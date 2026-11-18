import 'dart:math' as math;
import 'dart:typed_data';

import 'package:photo_manager/photo_manager.dart';

import '../../engines/dino/dino_matcher.dart';
import '../../engines/pdq/pdq_engine.dart';
import 'cross_group_diagnostic.dart';
import '../platform/photo_edits.dart';
import 'photo_store.dart';
import 'scan_orchestrator.dart';

/// Chẩn đoán "tách nhóm" — CHỈ ĐỌC.
///
/// Lấy PDQ và embedding đang lưu trong cache cho các ảnh được chọn, tính đủ mọi
/// cặp, rồi đối chiếu từng điều kiện với [ScanConfig] đang dùng. Không ghi cache,
/// không đổi nhóm, không đổi ngưỡng, không chạy lại pipeline.
///
/// Kết quả chỉ cho biết cặp có đạt các điều kiện đo được hay không. Nó KHÔNG
/// chứng minh nguyên nhân thực tế trong lần quét production: các bước như trần
/// 1200 ảnh AI, bucket LSH và thứ tự gom nhóm không được tính ở đây.
class SplitDiagnostic {
  SplitDiagnostic._();

  /// [labels] và [groupLabels] song song với [assets]. [groupLabels] là nhóm
  /// hiện tại của ảnh (null nếu ảnh không thuộc nhóm nào).
  static Future<String> run({
    required List<AssetEntity> assets,
    required List<String> labels,
    required List<String?> groupLabels,
    ScanConfig? config,
  }) async {
    final cfg = config ?? const ScanConfig();
    final n = assets.length;

    Map<String, MediaSig> sigs = const {};
    try {
      sigs = await PhotoEdits().signatures();
    } catch (_) {}
    final pdq = await PhotoStore.pdqFor(assets, sigs);
    final emb = await PhotoStore.embFor(assets, sigs);

    final flat = Uint64List(n * 4);
    final hasPdq = List<bool>.filled(n, false);
    final quality = List<int?>.filled(n, null);
    for (var i = 0; i < n; i++) {
      final row = pdq[assets[i].id];
      if (row == null) continue;
      hasPdq[i] = true;
      quality[i] = row.quality;
      for (var k = 0; k < 4; k++) {
        flat[i * 4 + k] = row.pdq[k];
      }
    }

    final raw = <int, Float32List>{};
    for (var i = 0; i < n; i++) {
      final v = emb[assets[i].id];
      if (v != null) raw[i] = v;
    }

    // Cosine của pipeline dùng vector đã trừ trung bình thư viện. Chỉ tính được
    // khi phiên quét còn giữ vector đó; nếu không thì ghi UNKNOWN, không đoán.
    final mean = ScanOrchestrator.libraryMean;
    final centered = <int, Float32List>{};
    if (mean != null) {
      final usable = <int, Float32List>{
        for (final e in raw.entries)
          if (e.value.length == mean.length) e.key: e.value,
      };
      centered.addAll(centerEmbeddingsWith(usable, mean));
    }

    final out = StringBuffer()
      ..writeln('CHẨN ĐOÁN TÁCH NHÓM (chỉ đọc cache)')
      ..writeln('Số ảnh chọn: $n · số cặp: ${n * (n - 1) ~/ 2}')
      ..writeln(
        'Lần quét gần nhất: ${ScanOrchestrator.lastEligibleCount ?? 'chưa rõ'} ảnh vào bước PDQ · '
        'chế độ tìm cặp: ${ScanOrchestrator.lastCandidateMode ?? 'chưa rõ'}',
      )
      ..writeln(
        'Ngưỡng: maxHamming ${cfg.maxHamming} · '
        'similarMaxHamming ${cfg.similarMaxHamming} · '
        'modelMinCosine ${cfg.modelMinCosine.toStringAsFixed(2)} · '
        'minPdqQuality ${cfg.minPdqQuality}',
      )
      ..writeln(
        'Chụp liên tiếp: ${cfg.burstWindowMs ~/ 1000}s · '
        'raw cosine ≥ ${cfg.burstMinRawCos.toStringAsFixed(2)}',
      )
      ..writeln(
        mean == null
            ? 'Vector trung bình: chưa có trong phiên, cosine ghi UNKNOWN'
            : 'Vector trung bình: có trong phiên',
      )
      ..writeln();

    var cross = 0;
    var crossPass = 0;
    final crossEvidence = <CrossGroupPairEvidence>[];
    for (var i = 0; i < n; i++) {
      for (var j = i + 1; j < n; j++) {
        final gi = groupLabels[i];
        final gj = groupLabels[j];
        final isCross = gi != null && gj != null && gi != gj;
        if (isCross) cross++;

        // PDQ Hamming.
        int? h;
        final String pdqSt;
        if (!hasPdq[i] || !hasPdq[j]) {
          pdqSt = 'UNKNOWN (CACHE_MISSING)';
        } else {
          h = hammingFlat(flat, i, j);
          if (h <= cfg.maxHamming) {
            pdqSt =
                'PASS (H $h ≤ ${cfg.maxHamming}: nối thẳng, không cần cosine)';
          } else if (h <= cfg.similarMaxHamming) {
            pdqSt =
                'PASS (H $h trong vùng AI ${cfg.maxHamming}–'
                '${cfg.similarMaxHamming}, cần cosine)';
          } else {
            pdqSt = 'FAIL (H $h > ${cfg.similarMaxHamming})';
          }
        }

        // Chất lượng PDQ: ảnh dưới ngưỡng không đưa vào so PDQ.
        final qi = quality[i];
        final qj = quality[j];
        final String qSt;
        if (qi == null || qj == null) {
          qSt = 'UNKNOWN (CACHE_MISSING)';
        } else if (qi >= cfg.minPdqQuality && qj >= cfg.minPdqQuality) {
          qSt = 'PASS ($qi, $qj)';
        } else {
          qSt = 'FAIL ($qi, $qj; ngưỡng ${cfg.minPdqQuality})';
        }

        // Cosine MobileNet đã trừ trung bình.
        double? c;
        final String cosSt;
        if (!raw.containsKey(i) || !raw.containsKey(j)) {
          cosSt = 'UNKNOWN (EMBEDDING_MISSING)';
        } else if (mean == null) {
          cosSt = 'UNKNOWN (chưa có vector trung bình trong phiên)';
        } else if (!centered.containsKey(i) || !centered.containsKey(j)) {
          cosSt = 'UNKNOWN (EMBEDDING_MISSING: sai số chiều)';
        } else {
          c = cosineOf(centered[i], centered[j]);
          if (c == null) {
            cosSt = 'UNKNOWN';
          } else if (c >= cfg.modelMinCosine) {
            cosSt =
                'PASS (${c.toStringAsFixed(3)} ≥ '
                '${cfg.modelMinCosine.toStringAsFixed(2)})';
          } else {
            cosSt =
                'FAIL (${c.toStringAsFixed(3)} < '
                '${cfg.modelMinCosine.toStringAsFixed(2)})';
          }
        }

        // Chụp liên tiếp: khoảng cách thời gian và raw cosine.
        final gapMs = assets[j].createDateTime
            .difference(assets[i].createDateTime)
            .inMilliseconds
            .abs();
        double? rc;
        if (raw.containsKey(i) && raw.containsKey(j)) {
          rc = _rawCos(raw[i]!, raw[j]!);
        }
        final String burstSt;
        if (gapMs > cfg.burstWindowMs) {
          burstSt = 'FAIL (cách $gapMs ms > ${cfg.burstWindowMs} ms)';
        } else if (rc == null) {
          burstSt = 'UNKNOWN (EMBEDDING_MISSING)';
        } else if (rc >= cfg.burstMinRawCos) {
          burstSt = 'PASS (cách $gapMs ms, raw ${rc.toStringAsFixed(3)})';
        } else {
          burstSt =
              'FAIL (cách $gapMs ms, raw ${rc.toStringAsFixed(3)} < '
              '${cfg.burstMinRawCos.toStringAsFixed(2)})';
        }

        final qOk = qSt.startsWith('PASS');
        final pdqOk =
            qOk &&
            h != null &&
            h <= cfg.similarMaxHamming &&
            (h <= cfg.maxHamming || (c != null && c >= cfg.modelMinCosine));
        final burstOk = burstSt.startsWith('PASS');
        final hasUnknown = [
          pdqSt,
          qSt,
          cosSt,
          burstSt,
        ].any((s) => s.startsWith('UNKNOWN'));
        final String verdict;
        if (pdqOk || burstOk) {
          verdict = 'đạt các điều kiện đo được';
        } else if (hasUnknown) {
          verdict = 'chưa kết luận, thiếu dữ liệu';
        } else {
          verdict = 'không đạt điều kiện nối';
        }
        if (isCross && (pdqOk || burstOk)) crossPass++;
        if (isCross) {
          crossEvidence.add(
            CrossGroupPairEvidence(
              groupA: gi,
              groupB: gj,
              assetA: assets[i].id,
              assetB: assets[j].id,
              gapMs: gapMs,
              hamming: h,
              qualityOk: qi == null || qj == null
                  ? null
                  : qi >= cfg.minPdqQuality && qj >= cfg.minPdqQuality,
              centeredCosine: c,
              rawCosine: rc,
            ),
          );
        }

        final where = isCross
            ? '[khác nhóm: $gi / $gj]'
            : '[${gi ?? 'ngoài nhóm'} / ${gj ?? 'ngoài nhóm'}]';
        out
          ..writeln('${labels[i]} ↔ ${labels[j]}  $where')
          ..writeln('  PDQ: $pdqSt')
          ..writeln('  Chất lượng: $qSt')
          ..writeln('  Cosine: $cosSt')
          ..writeln('  Chụp liên tiếp: $burstSt')
          ..writeln('  Kết luận: $verdict')
          ..writeln();
      }
    }

    final groupSizes = <String, int>{};
    for (final label in groupLabels) {
      if (label != null) {
        groupSizes.update(label, (n) => n + 1, ifAbsent: () => 1);
      }
    }
    out
      ..writeln(
        crossGroupDryRun(
          pairs: crossEvidence,
          groupSizes: groupSizes,
          maxHamming: cfg.maxHamming,
          similarMaxHamming: cfg.similarMaxHamming,
          modelMinCosine: cfg.modelMinCosine,
          burstWindowMs: cfg.burstWindowMs,
          burstMinRawCosine: cfg.burstMinRawCos,
        ),
      )
      ..writeln('Cặp khác nhóm: $cross · đạt điều kiện đo được: $crossPass')
      ..writeln(
        'Lưu ý: chỉ dựa trên cache và ngưỡng hiện tại. Không tính trần '
        '1200 ảnh AI, bucket LSH, thứ tự gom nhóm, hay điều kiện liền kề '
        'trong toàn thư viện. Không khẳng định nguyên nhân thực tế của '
        'lần quét production nếu chưa có trace.',
      );
    return out.toString();
  }

  static double? _rawCos(Float32List a, Float32List b) {
    if (a.length != b.length) return null;
    var dot = 0.0;
    var na = 0.0;
    var nb = 0.0;
    for (var k = 0; k < a.length; k++) {
      dot += a[k] * b[k];
      na += a[k] * a[k];
      nb += b[k] * b[k];
    }
    if (na == 0 || nb == 0) return null;
    return dot / (math.sqrt(na) * math.sqrt(nb));
  }
}
