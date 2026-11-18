import 'cross_group_reconcile.dart';

/// Pair evidence collected by the read-only split diagnostic.
class CrossGroupPairEvidence {
  const CrossGroupPairEvidence({
    required this.groupA,
    required this.groupB,
    required this.assetA,
    required this.assetB,
    required this.gapMs,
    this.hamming,
    this.qualityOk,
    this.centeredCosine,
    this.rawCosine,
  });

  final String groupA;
  final String groupB;
  final String assetA;
  final String assetB;
  final int gapMs;
  final int? hamming;
  final bool? qualityOk;
  final double? centeredCosine;
  final double? rawCosine;
}

/// Formats a conservative, read-only merge dry run for selected groups.
///
/// A suggestion needs at least two independent cross-group pairs and at least
/// two represented assets on each side. This deliberately does not merge or
/// alter clustering thresholds.
String crossGroupDryRun({
  required List<CrossGroupPairEvidence> pairs,
  required Map<String, int> groupSizes,
  required int maxHamming,
  required int similarMaxHamming,
  required double modelMinCosine,
  required int burstWindowMs,
  required double burstMinRawCosine,
}) {
  if (pairs.isEmpty) return 'DRY RUN: không có cặp ảnh khác nhóm để đánh giá.';

  final buckets = <String, List<CrossGroupPairEvidence>>{};
  final names = <String, (String, String)>{};
  for (final pair in pairs) {
    final a = pair.groupA.compareTo(pair.groupB) <= 0
        ? pair.groupA
        : pair.groupB;
    final b = a == pair.groupA ? pair.groupB : pair.groupA;
    final key = '$a\u0000$b';
    (buckets[key] ??= []).add(
      a == pair.groupA
          ? pair
          : CrossGroupPairEvidence(
              groupA: a,
              groupB: b,
              assetA: pair.assetB,
              assetB: pair.assetA,
              gapMs: pair.gapMs,
              hamming: pair.hamming,
              qualityOk: pair.qualityOk,
              centeredCosine: pair.centeredCosine,
              rawCosine: pair.rawCosine,
            ),
    );
    names[key] = (a, b);
  }

  final out = StringBuffer()
    ..writeln('DRY RUN reconciliation (chỉ đọc, không tự gộp)')
    ..writeln(
      'Near-duplicate: PDQ H ≤ $maxHamming; vùng xác minh H ≤ '
      '$similarMaxHamming + cosine ≥ ${modelMinCosine.toStringAsFixed(2)}.',
    )
    ..writeln(
      'Burst-like: cách ≤ $burstWindowMs ms + cosine thô ≥ '
      '${burstMinRawCosine.toStringAsFixed(2)}.',
    )
    ..writeln(
      'Điều kiện gợi ý: ≥2 cặp độc lập, phủ toàn bộ nhóm nhỏ hơn và ≥2 ảnh nhóm lớn.',
    )
    ..writeln();

  final sorted = buckets.keys.toList()..sort();
  for (final key in sorted) {
    final groupPairs = buckets[key]!;
    final (a, b) = names[key]!;
    final near = <CrossGroupPairEvidence>[];
    final burst = <CrossGroupPairEvidence>[];
    for (final p in groupPairs) {
      final h = p.hamming;
      final q = p.qualityOk;
      if (nearDuplicatePairEvidence(
        hamming: h,
        pdqQualityOk: q,
        centeredCosine: p.centeredCosine,
        maxHamming: maxHamming,
        similarMaxHamming: similarMaxHamming,
        modelMinCosine: modelMinCosine,
      )) {
        near.add(p);
      }
      if (burstLikePairEvidence(
        gapMs: p.gapMs,
        rawCosine: p.rawCosine,
        burstWindowMs: burstWindowMs,
        burstMinRawCosine: burstMinRawCosine,
      )) {
        burst.add(p);
      }
    }
    out.writeln('$a ↔ $b · ${groupPairs.length} cặp kiểm tra');
    _writeClass(
      out,
      'Near-duplicate',
      near,
      groupPairs,
      groupSizes[a] ?? 0,
      groupSizes[b] ?? 0,
      (p) => p.hamming,
      (p) => p.centeredCosine,
    );
    _writeClass(
      out,
      'Burst-like',
      burst,
      groupPairs,
      groupSizes[a] ?? 0,
      groupSizes[b] ?? 0,
      (p) => p.gapMs,
      (p) => p.rawCosine,
      distanceLabel: 'gap ms',
    );
    final gaps = groupPairs.map((p) => p.gapMs).toList()..sort();
    out.writeln(
      '  Ưu tiên thời gian: gần nhất ${gaps.first} ms; '
      'tối đa ${gaps.last} ms.',
    );
    out.writeln();
  }
  return out.toString();
}

void _writeClass(
  StringBuffer out,
  String label,
  List<CrossGroupPairEvidence> hits,
  List<CrossGroupPairEvidence> all,
  int sizeA,
  int sizeB,
  int? Function(CrossGroupPairEvidence) distance,
  double? Function(CrossGroupPairEvidence) cosine, {
  String distanceLabel = 'Hamming',
}) {
  final left = <String>{};
  final right = <String>{};
  for (final p in hits) {
    left.add(p.assetA);
    right.add(p.assetB);
  }
  final needLeft = sizeA <= sizeB ? sizeA : 2;
  final needRight = sizeB <= sizeA ? sizeB : 2;
  final enough =
      hits.length >= 2 && left.length >= needLeft && right.length >= needRight;
  final unknown =
      hits.isEmpty &&
      all.any(
        (p) => distance(p) == null || p.qualityOk == null || cosine(p) == null,
      );
  final verdict = enough
      ? 'PASS'
      : unknown
      ? 'UNKNOWN, thiếu đặc trưng'
      : 'FAIL';
  final distances = [for (final p in hits) distance(p)]
    ..removeWhere((v) => v == null);
  final cosines = [for (final p in hits) cosine(p)]
    ..removeWhere((v) => v == null);
  out.write(
    '  $label: $verdict · ${hits.length} cặp đạt, '
    'phủ ${left.length}/$sizeA + ${right.length}/$sizeB ảnh',
  );
  if (distances.isNotEmpty) {
    distances.sort();
    out.write(' · $distanceLabel ${distances.first}–${distances.last}');
  }
  if (cosines.isNotEmpty) {
    cosines.sort();
    out.write(
      ' · cosine ${cosines.first!.toStringAsFixed(3)}–'
      '${cosines.last!.toStringAsFixed(3)}',
    );
  }
  out.writeln();
}
