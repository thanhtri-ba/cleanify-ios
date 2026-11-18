import 'dart:io' show ProcessInfo;
import 'dart:isolate' show Isolate;
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart'
    show debugPrint, kDebugMode, kProfileMode, kReleaseMode;
import 'package:photo_manager/photo_manager.dart';

import '../../engines/dino/dino_engine.dart';
import '../../engines/dino/dino_matcher.dart';
import '../../engines/lsh/candidate_index.dart';
import '../../engines/pdq/pdq_engine.dart';
import '../platform/photo_edits.dart';
import 'active_clock.dart';
import 'core_v2.dart';
import 'cross_group_reconcile.dart';
import 'hash_worker.dart';
import 'regroup.dart';
import 'scan_diagnostics.dart';
import 'scan_mode.dart';
import 'scan_progress.dart';
import 'photo_store.dart';
import 'scan_session.dart';
import 'pixel_diff.dart';
import 'series_merge.dart';
import 'star_groups.dart';

class ScanConfig {
  const ScanConfig({
    this.batchSize = 128,
    this.ioConcurrency = 16,
    this.shaBatch = 32,
    this.fileConcurrency = 4,
    this.maxHamming = 32,
    this.exactPairsBelow = 6000,
    this.similarMaxHamming = 64,
    this.useModel = true,
    this.useSimilarModel = true,
    this.similarModelK = 10,
    this.similarMaxPixelDiff = 50,
    this.similarModelFloor = kCosineSimilar,
    this.modelBatch = 16,
    this.similarTimeBudget = const Duration(seconds: 45),
    this.totalScanBudget = const Duration(seconds: 110),
    this.readingBudget = const Duration(seconds: 70),
    this.shaBudgetEnd = const Duration(seconds: 95),
    this.modelMinCosine = kCosineDuplicate,
    this.modelMeanSample = 256,
    this.modelMaxPhotos = 1200,
    this.modelMinMeanCount = 32,
    this.minPdqQuality = 40,
    this.burstWindowMs = 15000,
    this.burstMinRawCos = 0.70,
    this.timeClusterMs = 0,
    this.timeClusterMax = 40,
    this.useOriginalVersion = true,
    this.reconcileSimilarGroups = kDebugMode,
  });

  /// Điểm chất lượng PDQ tối thiểu (0-100) để hash được đem so Hamming.
  ///
  /// Ảnh quá ít chi tiết — nền phẳng, ảnh tối, ảnh chụp màn hình gần như trắng
  /// — cho hash gần như ngẫu nhiên, nên hai ảnh KHÁC nhau vẫn ra bit giống
  /// nhau. Đây chính là thứ ghi chú ở [maxHamming] gọi là "ảnh khác nhau bị gom
  /// chung", và là lý do ngưỡng Hamming phải siết từ 40 xuống 32.
  ///
  /// Hash dưới ngưỡng KHÔNG bị vứt: ảnh vẫn đi tiếp qua SHA-256 nên bản sao y
  /// hệt vẫn tìm ra, chỉ là không được ghép theo độ giống nữa.
  ///
  /// 12 tương ứng độ dốc trung bình 1,44/255 — rất thấp, gần như chỉ loại ảnh
  /// thật sự phẳng. Ảnh thường rơi vào 60-100.
  final double minPdqQuality;

  /// Hai ảnh chụp cách nhau không quá ngần này (ms) được coi là một chuỗi chụp nhanh
  /// và được xét bằng AI dù khoảng cách PDQ vượt ngưỡng.
  final int burstWindowMs;

  /// Cosine THÔ tối thiểu giữa hai ảnh liền kề của một chuỗi chụp để nối chúng.
  final double burstMinRawCos;

  /// Ảnh chụp cách nhau không quá ngần này (ms) thì thuộc cùng một nhóm theo thời gian.
  final int timeClusterMs;

  /// Số ảnh tối đa của một nhóm theo thời gian; vượt quá thì mở nhóm mới.
  final int timeClusterMax;

  /// Số ảnh mỗi batch khi đọc thumbnail + băm PDQ.
  final int batchSize;

  /// Số thumbnail đọc song song (nhỏ, nhẹ).
  final int ioConcurrency;

  /// SHA-256 chỉ tính cho ảnh nghi trùng: số ảnh mỗi lượt và số file gốc
  /// được export song song (export file gốc nặng nên giữ thấp).
  final int shaBatch;
  final int fileConcurrency;

  /// Hai ảnh vào chung nhóm khi Hamming PDQ <= maxHamming trên 256 bit.
  /// 56 -> độ giống bit-hash >= 78,1% (100 * (1 - 56/256)).
  ///
  /// ĐÂY LÀ NGƯỠNG DUY NHẤT. App không còn tách "trùng" với "tương tự": mọi
  /// nhóm nằm trên cùng một thang phần trăm, và một lần quét dựng xong tất cả.
  ///
  /// CẢNH BÁO LỊCH SỬ: ngưỡng này từng là 40 (84,4%) và người dùng báo ảnh KHÁC
  /// NHAU bị gom chung, nên nó bị siết về 32. 56 lỏng hơn cả mức đã từng hỏng,
  /// và lỏng hơn nhiều so với mức 31 mà bản PDQ gốc của Meta khuyến nghị.
  /// Hai thứ đã đổi kể từ đó: PDQ ở đây nay có Jarosz filter, và ảnh ít chi
  /// tiết bị loại bằng [minPdqQuality]. Hai cái đó là lý do có thể thử lại mức
  /// lỏng, không phải bằng chứng là nó đúng.
  ///
  /// Rào chắn: [kBulkCleanupDefaultSimilarity] vẫn là 94%, nên nhóm 78-94% chỉ
  /// HIỆN RA cho người dùng xem, không bao giờ được tự chọn xoá. Muốn biết 78%
  /// có gom nhầm không thì chấm vài chục nhóm ở màn hình Số liệu đo.
  final int maxHamming;

  /// Số ảnh tối đa để so mọi cặp PDQ (chính xác). Trên 6000 ảnh dùng LSH để
  /// tránh số phép so tăng bậc hai.
  final int exactPairsBelow;

  /// Giới hạn ngoài của phép tìm cạnh PDQ. 64 = 75%: khoảng (56, 64] là vùng
  /// mà mô hình xác minh. Bằng [maxHamming] thì vùng đó rỗng và bước AI không
  /// có việc gì để làm.
  final int similarMaxHamming;

  /// Bước AI (embedding ONNX) chạy SAU PDQ/SHA: chỉ xác minh cặp PDQ có
  /// maxHamming < Hamming <= similarMaxHamming của ảnh chưa vào nhóm nào.
  ///
  /// ĐÃ BẬT, nhưng [modelMinCosine] vẫn CHƯA calibrate. Vì vậy ảnh do mô hình
  /// ghép vào nhóm (cờ [DuplicateItem.byModel]) chỉ để người dùng XEM và tự
  /// chọn — [planBulkCleanup] không bao giờ tự chọn xoá chúng. Chạy
  /// tool/calibrate.py (tool/EVAL.md) rồi mới gỡ rào đó.
  final bool useModel;

  /// Dùng embedding để tìm thêm ảnh "tương tự" (cùng cảnh/chủ thể) mà PDQ bỏ sót.
  /// Mỗi ảnh nối với [similarModelK] hàng xóm gần nhất có cosine (đã trừ trung bình)
  /// >= [similarModelFloor]; mức cao hơn do người dùng chọn lúc xem. Không bao giờ
  /// tự xóa. Lỗi/thiếu mô hình thì bỏ qua, không ảnh hưởng kết quả PDQ.
  final bool useSimilarModel;

  final int similarModelK;
  final double similarModelFloor;

  /// Ảnh tương tự khác ảnh đại diện quá ngần này % điểm ảnh (bản thu nhỏ) thì không tính.
  final double similarMaxPixelDiff;
  final int modelBatch;

  /// Giới hạn bước MobileNet tìm ảnh tương tự để thời gian chờ trên điện thoại
  /// không kéo dài vô hạn. Kết quả phải được đánh dấu là chưa đầy đủ nếu chạm mức.
  final Duration similarTimeBudget;

  /// Mục tiêu tổng thời gian của một lượt quét. Phần AI chỉ dùng phần còn lại
  /// sau PDQ/LSH/SHA, chừa thời gian dựng nhóm và trả kết quả.
  final Duration totalScanBudget;

  /// Dừng đọc ảnh ở ranh giới batch nếu đã tiêu gần hết ngân sách.
  final Duration readingBudget;

  /// Không bắt đầu thêm batch SHA sau mốc này; phần chưa xác minh được báo rõ.
  final Duration shaBudgetEnd;

  /// Cặp được nâng thành "trùng" khi cosine của embedding ĐÃ TRỪ TRUNG BÌNH
  /// (rồi L2-normalize) >= ngưỡng này. 0.80 chỉ là giá trị tạm, CHƯA calibrate:
  /// chạy tool/calibrate.py (xem tool/EVAL.md) trên tập có cặp khó rồi mới bật
  /// [useModel]. Thang cosine sau khi trừ trung bình khác thang cosine thô.
  final double modelMinCosine;

  /// Số ảnh mẫu rải đều thư viện để tính vector trung bình, và số embedding tối
  /// thiểu để trung bình có nghĩa (ít hơn thì bỏ qua bước AI).
  final int modelMeanSample;
  final int modelMinMeanCount;

  /// Số ảnh TỐI ĐA mà bước xác minh AI được nhúng trong một lần quét, chưa kể
  /// mẫu tính trung bình.
  ///
  /// Không có trần thì số ảnh phải nhúng tỉ lệ với số cặp PDQ lưng chừng, và
  /// số đó lớn tuỳ thư viện — một thư viện nhiều ảnh chụp liên tiếp có thể đẩy
  /// bước AI lên hàng phút. Cặp bị bỏ không mất đi: chúng giữ nguyên cách xếp
  /// loại như khi chưa có bước AI, nên trần này không bao giờ làm kết quả tệ
  /// hơn lúc tắt mô hình.
  final int modelMaxPhotos;

  /// iOS: với ảnh đã chỉnh sửa trong ứng dụng Ảnh, hash thêm BẢN GỐC và nối ảnh đó
  /// với ảnh khác khi hash gốc gần hash hiện tại của ảnh kia (Hamming <= maxHamming).
  /// Cặp này chỉ vào nhóm "tương tự", không bao giờ tự xóa. Android: bỏ qua.
  final bool useOriginalVersion;

  /// Reconcile DINO similarity stars in debug builds for device verification.
  /// Release builds keep this off until the affected originals are validated.
  final bool reconcileSimilarGroups;
}

class ScanOrchestrator {
  ScanOrchestrator({this.config = const ScanConfig(), CoreMode? coreMode})
    : coreMode =
          coreMode ??
          CoreMode.parse(const String.fromEnvironment('CLEANIFY_CORE'));

  final CoreMode coreMode;

  final ScanConfig config;

  /// Trạng thái giữa hai giai đoạn để [refineSimilar] dựng lại nhóm tương tự.
  _Pending? _pending;

  /// Còn bước AI chưa chạy cho kết quả vừa quét.
  bool get canRefine => _pending != null;

  /// Các cặp chuỗi chụp đã được AI xác nhận trong lần quét này (khoá: _pairKey).
  final Set<int> _burstKeys = {};

  static int _pairKey(int a, int b) =>
      a < b ? a * 2000003 + b : b * 2000003 + a;

  /// Điền kết quả vào [session]. Dữ liệu trung gian (hash, index) chỉ là biến
  /// cục bộ nên được giải phóng khi hàm kết thúc.
  Future<void> run(
    ScanSession session,
    void Function(ScanProgress) onProgress, {
    ActiveClock? clock,
    ScanMode mode = const ScanMode(),
  }) async {
    var usingV2 = false;
    // Luôn chạy bước trùng (PDQ/SHA) để ảnh trùng không lọt vào "tương tự";
    // nhóm trùng chỉ được GIỮ LẠI trong kết quả nếu người dùng chọn.
    final wantDup = mode.duplicates;
    // Quét tương tự cần biết chính xác ảnh nào là bản sao để loại khỏi nhóm,
    // nên vẫn chạy PDQ/SHA nhưng không giữ nhóm trùng nếu người dùng không chọn.
    mode = ScanMode(duplicates: true, similar: mode.similar);
    _burstKeys.clear();
    // Đồng hồ không tính lúc tạm dừng/ra nền nếu controller truyền vào.
    final sw = clock ?? (ActiveClock()..start());
    // Ghi thời gian từng giai đoạn để hiện trên màn hình kết quả.
    void mark(String tag) {
      _log(tag, sw.elapsed);
      session.timings.add('${sw.elapsed.inSeconds}s · $tag');
    }

    session.timings.add(
      kReleaseMode
          ? 'build: release'
          : kProfileMode
          ? 'build: profile'
          : 'build: DEBUG (Dart chạy chậm hơn nhiều)',
    );
    try {
      final perm = await PhotoManager.requestPermissionExtend();
      if (!perm.hasAccess) throw const PermissionDeniedException();

      final paths = await PhotoManager.getAssetPathList(
        onlyAll: true,
        type: RequestType.image,
      );
      if (paths.isEmpty) return;
      final all = paths.first;
      final total = await all.assetCountAsync;
      session.libraryTotal = total;

      final assets = <AssetEntity>[];
      // Chỉ cấp mảng lớn cho bước PDQ khi chế độ trùng cần dùng đến.
      final shas = List<String?>.filled(mode.duplicates ? total : 0, null);
      final flat = Uint64List(mode.duplicates ? total * 4 : 0);
      final has = Uint8List(mode.duplicates ? total : 0);
      final qual = Uint8List(mode.duplicates ? total : 0);

      // has = 0 cũng gồm ảnh BĂM ĐƯỢC nhưng điểm quá thấp. Cần mảng riêng để
      // biết ảnh nào thật sự có vân tay, nếu không ảnh ít chi tiết sẽ bị giải
      // mã lại mỗi lần quét — mà chúng khá nhiều (ảnh chụp màn hình, ảnh tối).
      final hashed = Uint8List(mode.duplicates ? total : 0);

      /// Số ảnh có hash nhưng quá ít chi tiết để đem so khớp.
      var lowQuality = 0;

      // Vân tay nhớ từ lần quét trước được đọc theo từng lô trong fetch(), không
      // nạp cả thư viện vào RAM.
      var reused = 0;
      // Đánh dấu ảnh dùng lại vân tay cũ: chỉ những ảnh này mới được dùng lại
      // SHA đã nhớ, và được giữ SHA đó khi ghi cache lần nữa.
      final reusedAt = Uint8List(mode.duplicates ? total : 0);

      // Chữ ký MediaStore (dung lượng + thế hệ) của cả thư viện, một truy vấn.
      // Ảnh nào chữ ký còn nguyên thì chắc chắn chưa bị sửa kể từ lần quét
      // trước, nên không đọc, không giải mã, không băm lại. Thiếu chữ ký thì
      // chỉ mất lớp kiểm tra thêm này, không đổi kết quả.
      var sigs = const <String, MediaSig>{};
      if (mode.duplicates) {
        try {
          sigs = await PhotoEdits().signatures();
        } catch (_) {}
        mark('MediaStore: ${sigs.length} chữ ký');
      }

      // Giai đoạn 1: thumbnail + PDQ theo batch. KHÔNG đụng tới file gốc.
      // Trong lúc isolate băm batch hiện tại, batch kế tiếp đã được đọc trước.
      Future<_Batch?> fetch(int start) async {
        if (start >= total) return null;
        try {
          final end = math.min(start + config.batchSize, total);
          final list = await all.getAssetListRange(start: start, end: end);
          if (list.isEmpty) return null;
          // Chỉ quét ảnh tương tự thì không cần thumbnail 128px/PDQ.
          if (!mode.duplicates) return _Batch(list, const [], const {});
          // Ảnh còn nguyên ngày sửa thì dùng lại vân tay cũ: khỏi đọc thumbnail,
          // khỏi giải mã, khỏi băm. Đây là chỗ lần quét thứ hai nhanh hẳn.
          final rows = await PhotoStore.pdqFor(list, sigs);
          final skip = <int>{};
          for (var k = 0; k < list.length; k++) {
            if (rows.containsKey(list[k].id)) skip.add(k);
          }
          return _Batch(list, await _thumbs(list, skip), skip, rows);
        } catch (_) {
          return null;
        }
      }

      var nextStart = config.batchSize;
      var next = fetch(0);
      // Chờ thumbnail (đọc ảnh) so với băm: khâu nào lớn hơn là khâu nghẽn.
      final waitSw = Stopwatch();
      final hashSw = Stopwatch();
      var readingLimited = false;
      while (true) {
        if (sw.elapsed >= config.readingBudget && nextStart < total) {
          readingLimited = true;
          break;
        }
        if (session.cancelled) throw const ScanCancelled();
        await session.waitIfPaused();
        if (session.cancelled) throw const ScanCancelled();

        waitSw.start();
        final cur = await next;
        waitSw.stop();
        if (cur == null) break;
        next = fetch(nextStart);
        nextStart += config.batchSize;

        final base = assets.length;
        assets.addAll(cur.assets);
        hashSw.start();
        final outputs = mode.duplicates
            ? await hashBatch(cur.inputs)
            : const <HashOutput>[];
        hashSw.stop();
        for (final o in outputs) {
          final p = o.pdq;
          if (p != null) {
            final gi = base + o.index;
            flat.setRange(gi * 4, gi * 4 + 4, p);
            // has = 0 nghĩa là "không có PDQ dùng được": ảnh bị loại khỏi so
            // khớp Hamming nhưng vẫn vào danh sách cần SHA-256, nên bản sao y
            // hệt của ảnh phẳng vẫn tìm ra bình thường.
            final q = (o.quality ?? 100).round().clamp(0, 100);
            qual[gi] = q;
            hashed[gi] = 1;
            final ok = q >= config.minPdqQuality;
            has[gi] = ok ? 1 : 0;
            if (!ok) lowQuality++;
          }
        }
        for (final k in cur.skip) {
          final e = cur.rows[cur.assets[k].id];
          if (e == null) continue;
          final gi = base + k;
          flat.setRange(gi * 4, gi * 4 + 4, e.pdq);
          qual[gi] = e.quality;
          hashed[gi] = 1;
          reusedAt[gi] = 1;
          final ok = e.quality >= config.minPdqQuality;
          has[gi] = ok ? 1 : 0;
          if (!ok) lowQuality++;
          reused++;
        }
        session.scanned = assets.length;
        session.assets = assets;
        onProgress(
          ScanProgress(
            ScanPhase.reading,
            assets.length,
            total,
            paused: session.paused,
          ),
        );
        if ((assets.length ~/ config.batchSize) % 10 == 0) {
          mark('đọc ${assets.length}/$total');
        }
      }

      final n = assets.length;
      if (readingLimited) {
        final remaining = total - n;
        session.incompleteStages.add('PDQ/LSH');
        session.remainingForStage['PDQ/LSH'] = remaining;
        mark(
          'đạt ngân sách đọc ${config.readingBudget.inSeconds}s: '
          'đã đọc $n/$total ảnh, còn $remaining',
        );
      }
      mark(
        'xong PDQ n=$n · chờ thumbnail ${waitSw.elapsed.inSeconds}s, '
        'băm ${hashSw.elapsed.inSeconds}s'
        '${reused > 0 ? ' · dùng lại $reused vân tay' : ''}'
        '${lowQuality > 0 ? ' · $lowQuality ảnh ít chi tiết không so khớp' : ''}',
      );
      if (mode.duplicates) {
        await PhotoStore.savePdq(assets, flat, qual, hashed, reusedAt, sigs);
        // Ảnh đã xoá khỏi máy: chỉ dọn khi đã đọc hết, để phần chưa đọc không bị xoá nhầm.
        if (!readingLimited) await PhotoStore.prune(assets);
      }

      // Giai đoạn 1b (iOS): hash bản gốc của ảnh đã chỉnh sửa trong ứng dụng Ảnh.
      final orig = config.useOriginalVersion && mode.duplicates
          ? await _originalHashes(session, assets, mark)
          : const _OrigHashes([], null);
      onProgress(ScanProgress(ScanPhase.matching, n, n));

      // Giai đoạn 2: ứng viên LSH + Hamming (chỉ cần PDQ).
      // Chạy ngoài isolate chính; thư viện lớn dùng LSH để tránh mọi-cặp.
      final maxH = config.similarMaxHamming;
      final exactBelow = config.exactPairsBelow;
      // Chỉ ghi để màn chẩn đoán đọc: số ảnh vào bước PDQ và chế độ tìm cặp.
      lastEligibleCount = n;
      lastCandidateMode = (n <= exactBelow && n <= 6000) ? 'EXACT' : 'LSH';
      final edges = !mode.duplicates
          ? <MatchEdge>[]
          : await Isolate.run(
              () => findNearEdges(
                flat: flat,
                has: has,
                n: n,
                maxHamming: maxH,
                exactBelow: exactBelow,
              ),
            );
      mark('so khớp PDQ xong: ${edges.length} cạnh');

      // SHA-256 chỉ cần cho ảnh nghi trùng: hai file giống hệt nhau luôn có
      // thumbnail và PDQ giống hệt nhau, nên ảnh không nằm trong cặp ứng viên
      // nào thì không thể là bản sao y hệt của ảnh khác.
      final needSha = Uint8List(n);
      // Hai file giống hệt nhau luôn có PDQ giống hệt (khoảng cách 0), nên chỉ cạnh
      // khoảng cách 0 cần SHA để xác nhận. Cạnh xa hơn đã chắc chắn là KHÁC file;
      // bỏ qua chúng tránh export file gốc hàng nghìn ảnh (rất chậm trên iOS).
      for (final e in edges) {
        if (e.distance != 0) continue;
        needSha[e.a] = 1;
        needSha[e.b] = 1;
      }
      // PDQ trùng khít (kể cả bucket lớn mà LSH bỏ qua) và ảnh không có PDQ.
      final firstByPdq = <String, int>{};
      for (var i = 0; i < n; i++) {
        if (has[i] == 0) {
          needSha[i] = 1;
          continue;
        }
        final k =
            '${flat[i * 4]}_${flat[i * 4 + 1]}_'
            '${flat[i * 4 + 2]}_${flat[i * 4 + 3]}';
        final first = firstByPdq[k];
        if (first == null) {
          firstByPdq[k] = i;
        } else {
          needSha[first] = 1;
          needSha[i] = 1;
        }
      }
      // Lọc ứng viên bằng metadata trước khi đụng tới file.
      //
      // Hai file chỉ có thể giống nhau TỪNG BYTE khi trùng cả dung lượng lẫn
      // kích thước điểm ảnh. Ứng viên nào mang bộ đôi đó một mình thì chắc
      // chắn không trùng khít với ai — băm SHA-256 nó là đọc trọn cả file để
      // nhận về một câu trả lời đã biết trước.
      //
      // Hay gặp nhất: một ảnh và bản nén lại của nó (gửi qua ứng dụng nhắn
      // tin, tải lại từ mạng). PDQ của chúng trùng khít nên cả hai đều lọt vào
      // danh sách cần SHA, nhưng dung lượng khác nhau nên SHA chẳng bao giờ
      // khớp. Trước đây cả hai đều bị đọc hết file.
      //
      // Phép lọc này KHÔNG đổi kết quả, chỉ bỏ việc thừa.
      final sizes = mode.duplicates
          ? await _fileSizes(session, assets, mark, sigs)
          : const <int>[];
      final metaOk = sizes.length == n;
      String metaKey(int i) =>
          '${sizes[i]}|${assets[i].width}x${assets[i].height}';
      final candidates = [
        for (var i = 0; i < n; i++)
          if (mode.duplicates && needSha[i] == 1) i,
      ];
      final metaCount = <String, int>{};
      if (metaOk) {
        for (final i in candidates) {
          metaCount[metaKey(i)] = (metaCount[metaKey(i)] ?? 0) + 1;
        }
      }
      // Ảnh chưa đổi kể từ lần quét trước đã có SHA nhớ sẵn: lấy luôn, khỏi mở
      // file. Đây là bước tốn nhất của lần quét thứ hai khi có nhiều ảnh trùng.
      var cachedSha = 0;
      final reusedIdx = [
        for (final i in candidates)
          if (reusedAt[i] == 1) i,
      ];
      if (reusedIdx.isNotEmpty) {
        final known = await PhotoStore.shaFor([
          for (final i in reusedIdx) assets[i],
        ], sigs);
        for (final i in reusedIdx) {
          final h = known[assets[i].id];
          if (h == null) continue;
          shas[i] = h;
          cachedSha++;
        }
      }
      final shaIdx = [
        for (final i in candidates)
          // Giữ lại khi: không đọc được metadata, ảnh không có PDQ (vẫn cần SHA
          // để không bị tính thành lỗi băm), hoặc còn ảnh khác cùng bộ metadata.
          if (shas[i] == null &&
              (!metaOk ||
                  sizes[i] == 0 ||
                  has[i] == 0 ||
                  (metaCount[metaKey(i)] ?? 0) > 1))
            i,
      ];
      var nativeSha = 0;
      final skipped = candidates.length - shaIdx.length - cachedSha;
      mark(
        'cần SHA ${shaIdx.length}/$n ảnh'
        '${skipped > 0 ? ' (metadata bỏ $skipped)' : ''}'
        '${cachedSha > 0 ? ' (nhớ sẵn $cachedSha)' : ''}'
        ', cạnh LSH=${edges.length}',
      );

      var shaLimited = false;
      for (var s0 = 0; s0 < shaIdx.length; s0 += config.shaBatch) {
        if (sw.elapsed >= config.shaBudgetEnd) {
          shaLimited = true;
          break;
        }
        if (session.cancelled) throw const ScanCancelled();
        await session.waitIfPaused();
        if (session.cancelled) throw const ScanCancelled();
        final part = shaIdx.sublist(
          s0,
          math.min(s0 + config.shaBatch, shaIdx.length),
        );
        // Android băm thẳng trong hệ điều hành, không xuất file ra cache.
        Map<String, String> native = const {};
        try {
          native = await PhotoEdits().sha256Of([
            for (final i in part) assets[i].id,
          ]);
        } catch (_) {
          // Thiếu kênh native thì lùi hết về đường xuất file bên dưới.
        }
        final rest = <int>[];
        for (final i in part) {
          final h = native[assets[i].id];
          if (h != null) {
            shas[i] = h;
          } else {
            rest.add(i);
          }
        }
        nativeSha += part.length - rest.length;
        if (rest.isNotEmpty) {
          final outs = await hashBatch(await _files(rest, assets));
          for (final o in outs) {
            shas[rest[o.index]] = o.sha256Hex;
          }
          // Xóa bản export file gốc ngay, không để dồn tới cuối phiên.
          try {
            await PhotoManager.clearFileCache();
          } catch (_) {}
        }
        onProgress(
          ScanProgress(
            ScanPhase.exact,
            math.min(s0 + config.shaBatch, shaIdx.length),
            shaIdx.length,
            paused: session.paused,
          ),
        );
      }
      if (shaLimited) {
        final checked = shaIdx.where((i) => shas[i] != null).length;
        final remaining = shaIdx.length - checked;
        session.incompleteStages.add('SHA-256');
        session.remainingForStage['SHA-256'] = remaining;
        mark(
          'đạt ngân sách SHA ${config.shaBudgetEnd.inSeconds}s: '
          'còn $remaining ảnh chưa xác minh',
        );
      }
      // Ghi lại SHA vừa tính để lần quét sau khỏi mở lại những file này.
      if (mode.duplicates && shaIdx.isNotEmpty) {
        await PhotoStore.saveSha(assets, shas, shaIdx);
      }
      for (var i = 0; i < n; i++) {
        if (mode.duplicates && has[i] == 0 && shas[i] == null) {
          session.hashFailures++;
        }
      }
      mark(
        'xong SHA${nativeSha > 0 ? ' · $nativeSha băm thẳng, '
                  '${shaIdx.length - nativeSha} phải xuất file' : ''}',
      );

      // Nhóm exact theo SHA-256.
      final uf = UnionFind(n);
      final bySha = <String, int>{};
      for (var i = 0; i < n; i++) {
        final s = shas[i];
        if (s == null) continue;
        final first = bySha[s];
        if (first == null) {
          bySha[s] = i;
        } else {
          uf.union(first, i);
        }
      }

      // Nhóm "tương tự" chỉ dựa vào AI (ufSim), độc lập với nhóm trùng, để kết quả
      // giống hệt dù quét riêng hay quét cùng ảnh trùng.
      final ufSim = UnionFind(n);
      for (final e in edges) {
        if (e.distance <= config.maxHamming) uf.union(e.a, e.b);
      }
      if (mode.duplicates) {
        final sizes = <int, int>{};
        for (var i = 0; i < n; i++) {
          final r = uf.find(i);
          sizes[r] = (sizes[r] ?? 0) + 1;
        }
        session.liveGroups = sizes.values.where((v) => v > 1).length;
        onProgress(ScanProgress(ScanPhase.exact, n, n, paused: session.paused));
      }

      // Liên kết "bản đã chỉnh <-> ảnh khác" qua hash BẢN GỐC; chỉ cho nhóm tương tự.
      final links = _originalLinks(orig, flat, has, n);
      if (orig.owners.isNotEmpty) {
        mark('bản gốc: ${links.length} liên kết ảnh đã chỉnh <-> ảnh khác');
      }

      // Giai đoạn 3: mô hình AI xác minh các cặp PDQ nằm giữa ngưỡng trùng và
      // ngưỡng tương tự (chỉ cho ảnh chưa vào nhóm nào).
      final emb = config.useModel
          ? await _modelStage(
              session,
              assets,
              uf,
              edges,
              onProgress,
              mark,
              sigs,
            )
          : <int, Float32List>{};

      Map<int, Float32List> simEmb = {};
      if (config.useSimilarModel && mode.similar) {
        final remaining =
            config.totalScanBudget - sw.elapsed - const Duration(seconds: 8);
        if (remaining <= Duration.zero) {
          mark(
            'AI tương tự: bỏ qua để giữ ngân sách tổng '
            '${config.totalScanBudget.inSeconds}s',
          );
          session.incompleteStages.add('Ảnh tương tự');
          session.remainingForStage['Ảnh tương tự'] = assets.length;
        } else {
          final budget = remaining < config.similarTimeBudget
              ? remaining
              : config.similarTimeBudget;
          simEmb = await _similarModelStage(
            session,
            assets,
            ufSim,
            onProgress,
            mark,
            sigs,
            timeBudget: budget,
          );
        }
      }

      // Giai đoạn 5: nhóm trùng (ngưỡng maxHamming), rồi nhóm tương tự
      // (ngưỡng similarMaxHamming) từ các ảnh chưa nằm trong nhóm trùng nào.
      final byRoot = <int, List<int>>{};
      for (var i = 0; i < n; i++) {
        (byRoot[uf.find(i)] ??= <int>[]).add(i);
      }
      final groups = <DuplicateGroup>[];
      final inDupIds = <String>{};
      // Chỉ _aiVeto cần bảng này, mà nó chỉ chạy khi có embedding.
      final idxOf = simEmb.isEmpty
          ? const <String, int>{}
          : {for (var i = 0; i < n; i++) assets[i].id: i};
      for (final root in byRoot.values) {
        if (root.length < 2) continue;
        for (final comp in _splitByCapture(assets, root)) {
          if (comp.length < 2) continue;
          // Chuỗi chụp liên tiếp: cả chuỗi nối bằng cạnh chụp nhanh thành MỘT nhóm,
          // không tách theo sao.
          final used = <int>{};
          for (final chain in _burstChains(comp)) {
            chain.sort((a, b) => _byRepRank(assets, a, b));
            used.addAll(chain);
            final g = _buildGroup(
              session,
              assets,
              chain,
              shas,
              flat,
              has,
              emb,
              GroupKind.duplicate,
              config.maxHamming,
              links: links,
              chain: true,
            );
            if (g == null) continue;
            groups.add(g);
            inDupIds.addAll(g.items.map((e) => e.asset.id));
          }
          comp.removeWhere(used.contains);
          if (comp.length < 2) continue;
          // Một thành phần liên thông là CHUỖI ảnh: A gần B, B gần C, nhưng A và
          // C có thể xa nhau. Một nhóm chỉ giữ ảnh gần TRỰC TIẾP đại diện (để
          // không gom ảnh rất khác nhau qua chuỗi), nên phần còn lại phải được
          // chia thành các nhóm tiếp theo. Trước đây chúng bị bỏ rơi — và khi
          // chế độ "tương tự" riêng còn tồn tại thì nó nhặt lại; nay chỉ còn một
          // lượt quét nên ảnh gần giống ở xa đại diện biến mất khỏi kết quả.
          comp.sort((a, b) => _byRepRank(assets, a, b));
          _medoidFirst(comp, shas, flat, has, emb);
          final parts = starPartition(comp, (a, b) {
            final sa = shas[a];
            if (sa != null && sa == shas[b]) return 1.0;
            if (isScreenshotAsset(assets[a]) != isScreenshotAsset(assets[b])) {
              return -1.0;
            }
            return _dupLinked(a, b, shas, flat, has, emb) ? 1.0 : -1.0;
          }, 0.5);
          for (final members in parts) {
            final g = _buildGroup(
              session,
              assets,
              members,
              shas,
              flat,
              has,
              emb,
              GroupKind.duplicate,
              config.maxHamming,
              links: links,
            );
            if (g == null) continue;
            final checked = _aiVeto(g, idxOf, simEmb);
            if (checked == null) continue;
            groups.add(checked);
            inDupIds.addAll(checked.items.map((e) => e.asset.id));
          }
        }
      }
      groups.sort((a, b) => b.items.length.compareTo(a.items.length));

      // Gộp có điều kiện các nhóm trùng bị tách (luật hai chiều, không nối qua ảnh trung gian).
      _reconcileGroups(assets, groups, edges, shas, flat, has, emb, mark);

      if (mode.duplicates &&
          (coreMode == CoreMode.v2Active || coreMode == CoreMode.v2Shadow)) {
        // V2 needs a comparable embedding for every scanned asset before
        // it can replace the V1 snapshot. Shadow mode can measure partial input.
        final canPublish =
            coreMode == CoreMode.v2Active &&
            session.incompleteStages.isEmpty &&
            simEmb.length == assets.length;
        try {
          final candidate = _buildV2Duplicates(
            session,
            assets,
            byRoot.values,
            shas,
            flat,
            has,
            emb,
            simEmb,
            recordDiagnostics: canPublish,
          );
          if (candidate == null) {
            mark('Core V2: hết giới hạn xác minh, dùng kết quả V1');
          } else {
            mark(
              'Core V2: V1 ${groups.length} nhóm, V2 ${candidate.length} nhóm',
            );
            if (coreMode == CoreMode.v2Active && !canPublish) {
              mark('Core V2: embedding chưa đầy đủ, giữ kết quả V1');
            }
            if (canPublish) {
              usingV2 = true;
              groups
                ..clear()
                ..addAll(candidate);
              inDupIds
                ..clear()
                ..addAll(
                  candidate.expand((g) => g.items.map((i) => i.asset.id)),
                );
            }
          }
        } catch (e) {
          mark('Core V2: lỗi phân nhóm, dùng kết quả V1 ($e)');
        }
      }

      // Nhóm theo thời gian: ảnh chụp liên tiếp trong một khoảng ngắn là một nhóm.
      // Đặt trước _Pending để nhánh AI nền không làm mất các nhóm này.
      for (final g
          in usingV2 ? <DuplicateGroup>[] : _timeClusters(assets, inDupIds)) {
        groups.add(g);
        inDupIds.addAll(g.items.map((e) => e.asset.id));
      }
      final pending = _Pending(
        assets: assets,
        shas: shas,
        flat: flat,
        has: has,
        uf: uf,
        ufSim: ufSim,
        links: links,
        emb: emb,
        inDupIds: inDupIds,
        dupGroups: List.of(groups),
        usingV2: usingV2,
      );
      // Không chọn "tương tự": chưa dựng nhóm tương tự; người dùng có thể chạy AI sau.
      final similar = mode.similar
          ? await _pixelVeto(
              session,
              _buildSimilarGroups(session, pending, simEmb),
              mark,
            )
          : <DuplicateGroup>[];
      if (wantDup && mode.similar && !usingV2) {
        _mergeSeries(groups, similar, assets, simEmb, mark);
      }
      _pending = config.useSimilarModel && !mode.similar && wantDup
          ? pending
          : null;
      if (!wantDup) groups.clear();
      groups.addAll(similar);
      if (coreMode == CoreMode.v2Shadow && assets.isNotEmpty) {
        // Keep experimental DINOv2 features separate from V1's cache.
        final features = await _embedIndices(
          session,
          assets,
          List.generate(assets.length, (i) => i),
          (_) {},
          mark,
          progressTotal: assets.length,
          timeBudget: config.similarTimeBudget,
          useDinoV2: true,
        );
        mark('DINOv2 thử nghiệm: ${features.length}/${assets.length} ảnh');
        if (features.length <= 2000) {
          final screenshots = [
            for (final asset in assets) isScreenshotAsset(asset),
          ];
          final candidates = await Isolate.run(
            () => findDinoCandidates(features, screenshots),
          );
          mark('DINOv2 thử nghiệm: ${candidates.length} cặp ứng viên');
        } else {
          mark('DINOv2 thử nghiệm: bỏ qua tìm cặp vì vượt giới hạn');
        }
      }
      session.groups
        ..clear()
        ..addAll(groups);
      session.pdqIndex = wantDup && !usingV2
          ? PdqIndex(
              assets: assets,
              shas: shas,
              flat: flat,
              has: has,
              edges: edges,
              maxEdgeHamming: maxH,
            )
          : null;

      mark('xong nhóm ảnh trùng');
    } finally {
      session.elapsed = sw.elapsed;
      // Xóa file tạm mà photo_manager có thể đã tạo (vd. iOS export file gốc).
      try {
        await PhotoManager.clearFileCache();
      } catch (_) {}
    }
  }

  List<DuplicateGroup>? _buildV2Duplicates(
    ScanSession session,
    List<AssetEntity> assets,
    Iterable<List<int>> components,
    List<String?> shas,
    Uint64List flat,
    Uint8List has,
    Map<int, Float32List> emb,
    Map<int, Float32List> simEmb, {
    required bool recordDiagnostics,
  }) {
    final partitions = <List<int>>[];
    var remainingChecks = 50000;
    for (final component in components) {
      if (component.length < 2) continue;
      for (final members in _splitByCapture(assets, component)) {
        members.sort((a, b) => _byRepRank(assets, a, b));
        final bySha = <String, List<int>>{};
        for (final member in members) {
          final sha = shas[member];
          if (sha != null) (bySha[sha] ??= []).add(member);
        }
        final exact = bySha.values.where((group) => group.length > 1);
        partitions.addAll(exact);
        final exactMembers = exact.expand((group) => group).toSet();
        final near = members.where((i) => !exactMembers.contains(i)).toList();
        final result = partitionConfirmed(near, (a, b) {
          remainingChecks--;
          final cosine =
              cosineOf(simEmb[a], simEmb[b]) ?? cosineOf(emb[a], emb[b]);
          return verifyNearPair(
            sameCaptureType: true,
            hamming: _hamming(flat, has, a, b),
            cosine: cosine,
            maxHamming: config.maxHamming,
            candidateHamming: config.similarMaxHamming,
            minCosine: config.modelMinCosine,
          );
        }, maxChecks: remainingChecks);
        if (result.exhausted) return null;
        partitions.addAll(result.groups.where((group) => group.length > 1));
      }
    }
    final result = <DuplicateGroup>[];
    for (final members in partitions) {
      final group = _buildGroup(
        session,
        assets,
        members,
        shas,
        flat,
        has,
        emb,
        GroupKind.duplicate,
        config.maxHamming,
        recordDiagnostics: recordDiagnostics,
      );
      if (group != null) result.add(group);
    }
    result.sort((a, b) => b.items.length.compareTo(a.items.length));
    return result;
  }

  /// Khi đã có embedding AI: ảnh (không phải SHA giống hệt) trong nhóm trùng mà cosine với
  /// ảnh đại diện < [ScanConfig.similarModelFloor] (độ giống AI dưới 50%, ví dụ cùng hình nhưng khác màu) thì bị loại khỏi nhóm.
  /// Không có embedding thì giữ nguyên. Null nếu nhóm còn dưới 2 ảnh.
  DuplicateGroup? _aiVeto(
    DuplicateGroup g,
    Map<String, int> idxOf,
    Map<int, Float32List> simEmb,
  ) {
    if (simEmb.isEmpty) return g;
    final rep = simEmb[idxOf[g.items.first.asset.id]];
    if (rep == null) return g;
    final kept = [
      for (final e in g.items)
        if (e == g.items.first ||
            e.exact ||
            (cosineOf(simEmb[idxOf[e.asset.id]], rep) ?? 1) >=
                config.similarModelFloor)
          e,
    ];
    if (kept.length == g.items.length) return g;
    return kept.length < 2 ? null : DuplicateGroup(kept, kind: g.kind);
  }

  /// Tách thành viên một nhóm thành ảnh chụp từ camera và ảnh chụp màn hình.
  ///
  /// Hai loại này trùng nhau theo kiểu khác hẳn nhau: ảnh chụp màn hình giống
  /// nhau vì cùng một giao diện, còn ảnh camera giống nhau vì cùng một cảnh.
  /// Gom chung một nhóm thì người dùng phải so hai thứ không so được với nhau.
  /// Nhóm nào chỉ có một loại thì trả về nguyên vẹn, không tốn gì.
  static List<List<int>> _splitByCapture(
    List<AssetEntity> assets,
    List<int> members,
  ) {
    final shot = <int>[];
    final cam = <int>[];
    for (final m in members) {
      (isScreenshotAsset(assets[m]) ? shot : cam).add(m);
    }
    if (shot.isEmpty || cam.isEmpty) return [members];
    return [cam, shot];
  }

  /// Nhóm "tương tự" từ ảnh chưa vào nhóm trùng, theo [_Pending.ufSim] (+ embedding
  /// [simEmb] nếu có).
  List<DuplicateGroup> _buildSimilarGroups(
    ScanSession session,
    _Pending p,
    Map<int, Float32List> simEmb,
  ) {
    final n = p.assets.length;
    final bySim = <int, List<int>>{};
    for (var i = 0; i < n; i++) {
      (bySim[p.ufSim.find(i)] ??= <int>[]).add(i);
    }
    final similar = <DuplicateGroup>[];
    for (final all in bySim.values) {
      // Ảnh đã thuộc nhóm trùng thì không đưa vào nhóm tương tự.
      final members = [
        for (final i in all)
          if (!p.inDupIds.contains(p.assets[i].id)) i,
      ];
      if (members.length < 2) continue;
      members.sort((a, b) => _byRepRank(p.assets, a, b));
      // Chia thành các "sao" liên tiếp để không mất khung ở xa đại diện đầu tiên.
      // Cosine AI chỉ tính khi hình dạng/độ sáng (PDQ) cũng không quá khác: tránh gom
      // ảnh chỉ giống về "loại" (trời, mặt người, giấy) nhưng khác nội dung.
      final parts = starPartition(members, (a, b) {
        // Ảnh chụp màn hình không bao giờ nối với ảnh chụp từ camera.
        if (isScreenshotAsset(p.assets[a]) != isScreenshotAsset(p.assets[b])) {
          return -1;
        }
        final h = _hamming(p.flat, p.has, a, b);
        final c = cosineOf(simEmb[a], simEmb[b]);
        // PDQ chỉ chặn khi cosine AI chưa đủ cao (< mức Chặt). Cùng một cảnh chụp lệch khung
        // thường có Hamming rất lớn nhưng cosine cao: không để PDQ tách chúng thành nhiều nhóm.
        if (h != null &&
            h > SimilarLevel.wide.maxHamming &&
            (c ?? -1) < SimilarLevel.strict.cosine) {
          return -1;
        }
        return c;
      }, config.similarModelFloor);
      final reconciledParts = config.reconcileSimilarGroups
          ? reconcileSimilarPartitions(
              partitions: parts,
              matches: (a, b) {
                if (isScreenshotAsset(p.assets[a]) !=
                    isScreenshotAsset(p.assets[b])) {
                  return false;
                }
                final cosine = cosineOf(simEmb[a], simEmb[b]);
                final hamming = _hamming(p.flat, p.has, a, b);
                return nearDuplicatePairEvidence(
                  hamming: hamming,
                  pdqQualityOk: p.has[a] == 1 && p.has[b] == 1,
                  centeredCosine: cosine,
                  maxHamming: config.maxHamming,
                  similarMaxHamming: config.similarMaxHamming,
                  modelMinCosine: config.modelMinCosine,
                );
              },
              gapMs: (a, b) => p.assets[a].createDateTime
                  .difference(p.assets[b].createDateTime)
                  .inMilliseconds,
            )
          : parts;
      for (final part in reconciledParts) {
        final g = _buildGroup(
          session,
          p.assets,
          part,
          p.shas,
          p.flat,
          p.has,
          p.emb,
          GroupKind.similar,
          config.similarMaxHamming,
          simEmb: simEmb,
        );
        if (g != null) similar.add(g);
      }
    }
    similar.sort((a, b) => b.items.length.compareTo(a.items.length));
    return similar;
  }

  /// Ảnh tương tự mà điểm ảnh khác ảnh đại diện quá [ScanConfig.similarMaxPixelDiff] (%)
  /// thì không tính, dù cosine AI cao. So trên bản thu nhỏ 96x96 (xem [pixelDiffPercent]).
  /// Ảnh không đọc được thì giữ. Nhóm còn dưới 2 ảnh thì bỏ.
  Future<List<DuplicateGroup>> _pixelVeto(
    ScanSession session,
    List<DuplicateGroup> groups,
    void Function(String) mark,
  ) async {
    final limit = config.similarMaxPixelDiff;
    if (limit >= 100 || groups.isEmpty) return groups;
    const side = ThumbnailSize.square(192);
    var removed = 0;
    final out = <DuplicateGroup>[];
    for (final g in groups) {
      if (session.cancelled) return groups;
      final repBytes = await g.items.first.asset.thumbnailDataWithSize(side);
      if (repBytes == null) {
        out.add(g);
        continue;
      }
      final keep = <DuplicateItem>[g.items.first];
      final rest = g.items.skip(1).toList();
      for (var i = 0; i < rest.length; i += 8) {
        final chunk = rest.skip(i).take(8).toList();
        final res = await Future.wait([
          for (final e in chunk)
            () async {
              final b = await e.asset.thumbnailDataWithSize(side);
              if (b == null) return 0.0;
              return Isolate.run(() => pixelDiffPercent([repBytes, b]));
            }(),
        ]);
        for (var k = 0; k < chunk.length; k++) {
          if (res[k] > limit) {
            removed++;
          } else {
            keep.add(chunk[k]);
          }
        }
      }
      if (keep.length == g.items.length) {
        out.add(g);
      } else if (keep.length > 1) {
        out.add(DuplicateGroup(keep, kind: g.kind));
      }
    }
    mark('loại ảnh tương tự khác điểm ảnh > ${limit.round()}%: $removed ảnh');
    out.sort((a, b) => b.items.length.compareTo(a.items.length));
    return out;
  }

  /// Giai đoạn 2 (chạy nền sau [run]): embedding AI cho mọi ảnh rồi dựng lại các
  /// nhóm "tương tự". Nhóm trùng không đổi. Lỗi/hủy: giữ nguyên kết quả hiện có.
  /// Gộp nhóm tương tự cùng chuỗi vào nhóm trùng (xem [mergeSimilarIntoDuplicates]).
  void _mergeSeries(
    List<DuplicateGroup> dups,
    List<DuplicateGroup> sims,
    List<AssetEntity> assets,
    Map<int, Float32List> simEmb,
    void Function(String) mark,
  ) {
    if (simEmb.isEmpty) return;
    final idx = {for (var i = 0; i < assets.length; i++) assets[i].id: i};
    final n = mergeSimilarIntoDuplicates(
      dups: dups,
      sims: sims,
      minCos: kCosineDuplicate,
      embOf: (it) {
        final i = idx[it.asset.id];
        return i == null ? null : simEmb[i];
      },
    );
    mark('gộp chuỗi: $n/${sims.length} nhóm tương tự vào nhóm trùng');
  }

  Future<void> refineSimilar(
    ScanSession session,
    void Function(ScanProgress) onProgress,
  ) async {
    final p = _pending;
    if (p == null) return;
    _pending = null;
    final sw = ActiveClock()..start();
    void mark(String tag) {
      _log('AI nền: $tag', sw.elapsed);
      session.timings.add('AI nền ${sw.elapsed.inSeconds}s · $tag');
    }

    try {
      // Nhánh này đã tắt cùng useSimilarModel; không có chữ ký nên so ngày sửa.
      final simEmb = await _similarModelStage(
        session,
        p.assets,
        p.ufSim,
        onProgress,
        mark,
        const {},
        timeBudget: config.similarTimeBudget,
      );
      if (session.cancelled || simEmb.isEmpty) return;
      final similar = await _pixelVeto(
        session,
        _buildSimilarGroups(session, p, simEmb),
        mark,
      );
      // Ảnh có thể đã bị xóa trong lúc AI chạy.
      final live = {for (final a in session.assets) a.id};
      for (final g in similar) {
        g.items.removeWhere((e) => !live.contains(e.asset.id));
      }
      similar.removeWhere((g) => g.items.length < 2);
      if (!p.usingV2) {
        _mergeSeries(
          p.dupGroups
              .where((g) => g.items.length > 1 && g.kind == GroupKind.duplicate)
              .toList(),
          similar,
          p.assets,
          simEmb,
          mark,
        );
      }
      session.groups
        ..clear()
        ..addAll(p.dupGroups.where((g) => g.items.length > 1))
        ..addAll(similar);
      mark('xong nhóm tương tự: ${similar.length} nhóm');
    } finally {
      sw.stop();
    }
  }

  /// Thứ tự chọn đại diện: nhiều điểm ảnh nhất, rồi cũ nhất, rồi chỉ số (ổn định).
  static int _byRepRank(List<AssetEntity> assets, int a, int b) {
    final pa = assets[a].width * assets[a].height;
    final pb = assets[b].width * assets[b].height;
    if (pa != pb) return pb.compareTo(pa);
    final d = assets[a].createDateTime.compareTo(assets[b].createDateTime);
    return d != 0 ? d : a.compareTo(b);
  }

  /// Dựng một nhóm: ảnh lớn nhất/cũ nhất làm đại diện. Chỉ giữ ảnh có độ giống
  /// trực tiếp với đại diện <= [limit] (hoặc SHA trùng). KHÔNG nối qua ảnh khác,
  /// để tránh chuỗi gom ảnh rất khác nhau. Trả về null nếu còn dưới 2 ảnh.
  DuplicateGroup? _buildGroup(
    ScanSession session,
    List<AssetEntity> assets,
    List<int> members,
    List<String?> shas,
    Uint64List flat,
    Uint8List has,
    Map<int, Float32List> emb,
    GroupKind kind,
    int limit, {
    Map<int, int> links = const {},
    Map<int, Float32List> simEmb = const {},
    bool chain = false,
    bool recordDiagnostics = true,
  }) {
    final n = assets.length;
    double? simCos(int m) => kind == GroupKind.similar
        ? cosineOf(simEmb[m], simEmb[members.first])
        : null;
    bool linked(int a, int b) => links.containsKey(_linkKey(a, b, n));
    // Đại diện là phần tử đầu tiên do bước tách sao chọn (ảnh trung tâm). KHÔNG sắp
    // lại theo độ phân giải: trước đây làm vậy khiến thành viên giống ảnh trung tâm
    // nhưng xa ảnh lớn nhất bị loại và tạo thành nhóm thứ hai sát nhóm đầu.
    final rep = members.first;
    // Nhóm tương tự xét embedding; nhóm trùng dùng SHA/PDQ để tìm ứng viên.
    final isSim = kind == GroupKind.similar;
    final kept = chain
        ? List<int>.of(members)
        : [
            for (final m in members)
              if (m == rep ||
                  (isSim
                      ? (simCos(m) ?? -1) >= config.similarModelFloor
                      : _dupLinked(m, rep, shas, flat, has, emb)))
                m,
          ];
    if (kept.length < 2) return null;
    final items = <DuplicateItem>[];
    final rows = <DiagRow>[];
    for (final m in kept) {
      final exact = !isSim && shas[m] != null && shas[m] == shas[rep];
      final h = isSim ? null : _hamming(flat, has, m, rep);
      final simH = isSim && m != rep ? _hamming(flat, has, m, rep) : null;
      final c = m == rep ? null : cosineOf(emb[m], emb[rep]);
      // Nhóm do mô hình: hai ảnh không gần nhau theo PDQ nhưng có cosine.
      final byModel = !exact && c != null && !(h != null && h <= limit);
      final viaOriginal =
          m != rep &&
          !exact &&
          !byModel &&
          !(h != null && h <= limit) &&
          linked(m, rep);
      final cs = m == rep ? null : simCos(m);
      final modelOnly =
          kind == GroupKind.similar &&
          m != rep &&
          !exact &&
          !byModel &&
          !viaOriginal &&
          !(h != null && h <= limit) &&
          cs != null &&
          cs >= config.similarModelFloor;
      double? sim;
      if (m == rep) {
        sim = 100;
      } else if (viaOriginal || modelOnly) {
        sim = null; // ảnh khác ảnh đại diện (đã chỉnh): không tự xóa
      } else if (byModel) {
        sim = c * 100;
      } else if (h != null) {
        sim = pdqSimilarity(h);
      }
      items.add(
        DuplicateItem(
          assets[m],
          exact: exact,
          similarity: sim,
          byModel: byModel,
          viaOriginal: viaOriginal,
          modelCosine: modelOnly ? cs : null,
          pdqHamming: simH,
        ),
      );
      if (recordDiagnostics && session.diag != null) {
        rows.add(
          _dupRow(
            assets[m],
            assets[rep],
            isAnchor: m == rep,
            exact: exact,
            hamming: h,
            cosine: c ?? cs,
            byModel: byModel,
            modelOnly: modelOnly,
            limit: limit,
            origDistance: viaOriginal ? links[_linkKey(m, rep, n)] : null,
          ),
        );
      }
    }
    final group = DuplicateGroup(items, kind: kind);
    if (recordDiagnostics) session.diag?.attach(group, rows);
    return group;
  }

  /// Hamming PDQ giữa hai ảnh theo chỉ số; null nếu một trong hai không có hash.
  /// Nhóm theo thời gian: ảnh chụp cách nhau không quá [ScanConfig.timeClusterMs] thành
  /// một nhóm, bỏ qua ảnh đã vào nhóm trùng và ảnh chụp màn hình. Ảnh trong nhóm này
  /// không được xác nhận giống nhau (exact = false) nên không tự chọn xóa.
  List<DuplicateGroup> _timeClusters(
    List<AssetEntity> assets,
    Set<String> inDupIds,
  ) {
    // Tắt nhóm theo thời gian đơn thuần (timeClusterMs <= 0): nhóm chụp liên tiếp
    // nay do luật chụp liên tiếp (burstWindowMs + cosine thô) đảm nhiệm.
    if (config.timeClusterMs <= 0) return const [];
    final idx =
        <int>[
          for (var i = 0; i < assets.length; i++)
            if (!inDupIds.contains(assets[i].id) &&
                !isScreenshotAsset(assets[i]))
              i,
        ]..sort(
          (x, y) =>
              assets[x].createDateTime.compareTo(assets[y].createDateTime),
        );
    final out = <DuplicateGroup>[];
    var cur = <int>[];
    void flush() {
      if (cur.length >= 2) {
        out.add(
          DuplicateGroup([
            for (final i in cur) DuplicateItem(assets[i], exact: false),
          ], kind: GroupKind.similar),
        );
      }
      cur = <int>[];
    }

    for (final i in idx) {
      if (cur.isNotEmpty) {
        final gap = assets[i].createDateTime
            .difference(assets[cur.last].createDateTime)
            .inMilliseconds;
        if (gap > config.timeClusterMs || cur.length >= config.timeClusterMax) {
          flush();
        }
      }
      cur.add(i);
    }
    flush();
    return out;
  }

  /// Cosine thô (không trừ trung bình) giữa hai vector, null nếu thiếu dữ liệu.
  static double? _rawCos(Float32List? a, Float32List? b) {
    if (a == null || b == null || a.length != b.length) return null;
    var dot = 0.0, na = 0.0, nb = 0.0;
    for (var i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      na += a[i] * a[i];
      nb += b[i] * b[i];
    }
    if (na == 0 || nb == 0) return null;
    return dot / (math.sqrt(na) * math.sqrt(nb));
  }

  /// Các chuỗi chụp liên tiếp trong một thành phần: liên thông CHỈ qua cạnh chụp nhanh,
  /// mỗi chuỗi ≥ 2 ảnh. Thành phần quá lớn thì bỏ qua để tránh O(m²).
  List<List<int>> _burstChains(List<int> comp) {
    if (_burstKeys.isEmpty || comp.length > 600) return const [];
    final parent = {for (final i in comp) i: i};
    int find(int x) {
      while (parent[x] != x) {
        parent[x] = parent[parent[x]]!;
        x = parent[x]!;
      }
      return x;
    }

    var any = false;
    for (var i = 0; i < comp.length; i++) {
      for (var j = i + 1; j < comp.length; j++) {
        final a = comp[i], b = comp[j];
        if (_burstKeys.contains(_pairKey(a, b))) {
          parent[find(a)] = find(b);
          any = true;
        }
      }
    }
    if (!any) return const [];
    final byRoot = <int, List<int>>{};
    for (final i in comp) {
      (byRoot[find(i)] ??= <int>[]).add(i);
    }
    return [
      for (final g in byRoot.values)
        if (g.length >= 2) g,
    ];
  }

  /// Luật nối DUY NHẤT của nhóm trùng: cùng SHA, hoặc PDQ trong ngưỡng, hoặc AI
  /// cosine >= ngưỡng. Mọi nơi (tách sao, chọn đại diện, kiểm tra thành viên) đều dùng
  /// hàm này để không còn chuyện cạnh đã nối nhưng nhóm lại loại bỏ nó.
  bool _dupLinked(
    int a,
    int b,
    List<String?> shas,
    Uint64List flat,
    Uint8List has,
    Map<int, Float32List> emb,
  ) {
    final sa = shas[a];
    if (sa != null && sa == shas[b]) return true;
    if (_burstKeys.contains(_pairKey(a, b))) return true;
    final h = _hamming(flat, has, a, b);
    if (h != null && h <= config.maxHamming) return true;
    return config.useModel &&
        (cosineOf(emb[a], emb[b]) ?? -1) >= config.modelMinCosine;
  }

  /// Gộp có điều kiện các nhóm trùng có cạnh PDQ chéo. Nhóm B chỉ được gộp vào A
  /// khi mọi ảnh của B giống TRỰC TIẾP đại diện A theo [_dupLinked], và ngược lại.
  /// Không nối qua ảnh trung gian. Thiếu dữ liệu thì không gộp.
  void _reconcileGroups(
    List<AssetEntity> assets,
    List<DuplicateGroup> groups,
    List<MatchEdge> edges,
    List<String?> shas,
    Uint64List flat,
    Uint8List has,
    Map<int, Float32List> emb,
    void Function(String) mark,
  ) {
    final idx = <String, int>{
      for (var i = 0; i < assets.length; i++) assets[i].id: i,
    };
    final gOf = <int, int>{};
    for (var gi = 0; gi < groups.length; gi++) {
      for (final it in groups[gi].items) {
        final ai = idx[it.asset.id];
        if (ai != null) gOf.putIfAbsent(ai, () => gi);
      }
    }
    final cross = <int, Set<int>>{};
    for (final e in edges) {
      final ga = gOf[e.a];
      final gb = gOf[e.b];
      if (ga == null || gb == null || ga == gb) continue;
      final int lo = math.min<int>(ga, gb);
      final int hi = math.max<int>(ga, gb);
      (cross[lo] ??= <int>{}).add(hi);
    }
    final dead = <int>{};
    var merged = 0;
    var candidates = 0;
    final keys = cross.keys.toList()..sort();
    for (final ga in keys) {
      for (final gb in (cross[ga]!.toList()..sort())) {
        if (dead.contains(ga) || dead.contains(gb)) continue;
        candidates++;
        final reason = _reconcileReason(
          groups[ga],
          groups[gb],
          idx,
          shas,
          flat,
          has,
          emb,
        );
        if (reason != null) {
          if (candidates <= 30) {
            mark('Gộp nhóm ${ga + 1} + ${gb + 1}: không đạt ($reason)');
          }
          continue;
        }
        final have = {for (final it in groups[ga].items) it.asset.id};
        var added = 0;
        for (final it in groups[gb].items) {
          if (have.add(it.asset.id)) {
            groups[ga].items.add(DuplicateItem(it.asset, exact: false));
            added++;
          }
        }
        dead.add(gb);
        merged++;
        mark('Gộp nhóm ${gb + 1} vào nhóm ${ga + 1}: +$added ảnh');
      }
    }
    if (dead.isNotEmpty) {
      final kept = [
        for (var i = 0; i < groups.length; i++)
          if (!dead.contains(i)) groups[i],
      ];
      groups
        ..clear()
        ..addAll(kept);
    }
    mark('Gộp nhóm: $merged nhóm đã gộp trên $candidates cặp có cạnh chéo');
  }

  /// null nếu đạt luật theo cả hai chiều; ngược lại trả lý do đầu tiên không đạt.
  String? _reconcileReason(
    DuplicateGroup a,
    DuplicateGroup b,
    Map<String, int> idx,
    List<String?> shas,
    Uint64List flat,
    Uint8List has,
    Map<int, Float32List> emb,
  ) {
    String? check(DuplicateGroup from, DuplicateGroup to, String label) {
      final rep = idx[to.items.first.asset.id];
      if (rep == null) return '$label: thiếu chỉ số đại diện';
      var fail = 0;
      var total = 0;
      for (final it in from.items) {
        final m = idx[it.asset.id];
        if (m == null) return '$label: thiếu chỉ số ảnh';
        total++;
        if (m == rep) continue;
        if (!_dupLinked(m, rep, shas, flat, has, emb)) fail++;
      }
      return fail == 0
          ? null
          : '$label: $fail/$total ảnh không giống trực tiếp đại diện';
    }

    return check(b, a, 'B→A') ?? check(a, b, 'A→B');
  }

  /// Đưa ảnh "trung tâm" của thành phần (nhiều ảnh giống nhất) lên đầu để làm đại diện
  /// sao. Hoà thì giữ thứ tự ưu tiên cũ. Bỏ qua thành phần quá lớn vì tính O(m²).
  void _medoidFirst(
    List<int> comp,
    List<String?> shas,
    Uint64List flat,
    Uint8List has,
    Map<int, Float32List> emb,
  ) {
    final m = comp.length;
    if (m < 3 || m > 400) return;
    final deg = <int, int>{};
    for (final a in comp) {
      var d = 0;
      for (final b in comp) {
        if (a != b && _dupLinked(a, b, shas, flat, has, emb)) d++;
      }
      deg[a] = d;
    }
    final order = {for (var i = 0; i < m; i++) comp[i]: i};
    comp.sort((x, y) {
      final c = deg[y]!.compareTo(deg[x]!);
      return c != 0 ? c : order[x]!.compareTo(order[y]!);
    });
  }

  int? _hamming(Uint64List flat, Uint8List has, int i, int j) =>
      has[i] == 1 && has[j] == 1 ? hammingFlat(flat, i, j) : null;

  DiagRow _dupRow(
    AssetEntity asset,
    AssetEntity anchor, {
    required bool isAnchor,
    required bool exact,
    required int? hamming,
    double? cosine,
    bool byModel = false,
    bool modelOnly = false,
    required int limit,
    int? origDistance,
  }) {
    final String reason;
    if (isAnchor) {
      reason = 'anchor';
    } else if (exact) {
      reason = 'sha256';
    } else if (origDistance != null) {
      reason = 'bản gốc đã chỉnh (Hamming gốc=$origDistance)';
    } else if (modelOnly) {
      reason = 'ai-tương-tự cosine>=${config.similarModelFloor}';
    } else if (byModel) {
      reason = 'dino-cosine>=${config.modelMinCosine}';
    } else if (hamming != null && hamming <= limit) {
      reason = 'hamming<=$limit';
    } else {
      reason = 'bắc cầu (union-find)';
    }
    return DiagRow(
      assetId: asset.id,
      anchorId: anchor.id,
      hamming: hamming,
      pdqPercent: hamming == null ? null : pdqSimilarity(hamming),
      cosDino: cosine,
      threshold: byModel ? 'cos>=${config.modelMinCosine}' : 'max<=$limit',
      reason: reason,
    );
  }

  /// Khóa không phân biệt thứ tự cho cặp ảnh (a, b) trong thư viện n ảnh.
  static int _linkKey(int a, int b, int n) => a < b ? a * n + b : b * n + a;

  /// Hash thumbnail BẢN GỐC của các ảnh đã chỉnh sửa trong ứng dụng Ảnh. Chỉ
  /// chạy trên nền tảng còn giữ bản gốc (iOS); Android bỏ qua vì chỉnh là ghi đè.
  /// Mọi lỗi (kênh nền tảng thiếu, ảnh trên iCloud...) chỉ ghi vào timings.
  Future<_OrigHashes> _originalHashes(
    ScanSession session,
    List<AssetEntity> assets,
    void Function(String) mark,
  ) async {
    final edits = PhotoEdits();
    if (!edits.hasOriginalVersions) return const _OrigHashes([], null);
    try {
      final idToIdx = {for (var i = 0; i < assets.length; i++) assets[i].id: i};
      final allIds = idToIdx.keys.toList();
      final edited = <int>[];
      for (var s = 0; s < allIds.length; s += 500) {
        if (session.cancelled) throw const ScanCancelled();
        final part = allIds.sublist(s, math.min(s + 500, allIds.length));
        for (final id in await edits.editedIds(part)) {
          final i = idToIdx[id];
          if (i != null) edited.add(i);
        }
      }
      edited.sort();
      final owners = <int>[];
      final words = <int>[];
      var missing = 0;
      for (var s = 0; s < edited.length; s += 32) {
        if (session.cancelled) throw const ScanCancelled();
        await session.waitIfPaused();
        final part = edited.sublist(s, math.min(s + 32, edited.length));
        final thumbs = await edits.originalThumbs([
          for (final i in part) assets[i].id,
        ]);
        final inputs = <HashInput>[];
        final idxs = <int>[];
        for (final i in part) {
          final t = thumbs[assets[i].id];
          if (t == null) {
            missing++;
            continue;
          }
          inputs.add(HashInput(index: idxs.length, thumb: t));
          idxs.add(i);
        }
        if (inputs.isEmpty) continue;
        for (final o in await hashBatch(inputs)) {
          final p = o.pdq;
          if (p == null) {
            missing++;
            continue;
          }
          owners.add(idxs[o.index]);
          words.addAll(p);
        }
      }
      mark(
        'bản gốc: ${edited.length} ảnh đã chỉnh, ${owners.length} có hash gốc'
        '${missing > 0 ? ', $missing không lấy được (iCloud/lỗi)' : ''}',
      );
      return _OrigHashes(owners, Uint64List.fromList(words));
    } on ScanCancelled {
      rethrow;
    } catch (e) {
      mark('bản gốc: BỎ QUA ($e)');
      return const _OrigHashes([], null);
    }
  }

  /// Cặp (ảnh đã chỉnh o, ảnh khác j): hash BẢN GỐC của o có Hamming <= maxHamming
  /// với hash hiện tại của j, và hash hiện tại của o thì không (cặp đó đã được
  /// tìm thấy ở bước PDQ thường). Giá trị là khoảng cách Hamming của hash gốc.
  Map<int, int> _originalLinks(
    _OrigHashes orig,
    Uint64List flat,
    Uint8List has,
    int n,
  ) {
    final out = <int, int>{};
    final of = orig.flat;
    if (of == null) return out;
    for (var k = 0; k < orig.owners.length; k++) {
      final o = orig.owners[k];
      for (var j = 0; j < n; j++) {
        if (j == o || has[j] == 0) continue;
        var d = 0;
        for (var w = 0; w < 4; w++) {
          d += popcount64(of[k * 4 + w] ^ flat[j * 4 + w]);
        }
        if (d > config.maxHamming) continue;
        if (has[o] == 1 && hammingFlat(flat, o, j) <= config.maxHamming) {
          continue;
        }
        final key = _linkKey(o, j, n);
        final prev = out[key];
        if (prev == null || d < prev) out[key] = d;
      }
    }
    return out;
  }

  /// Embedding (chưa trừ trung bình) cho các ảnh có chỉ số trong [todo]. Lỗi được
  /// ghi vào timings; trả về map rỗng/thiếu thay vì ném lỗi.
  Future<Map<int, Float32List>> _embedIndices(
    ScanSession session,
    List<AssetEntity> assets,
    List<int> todo,
    void Function(ScanProgress) onProgress,
    void Function(String) mark, {
    int progressOffset = 0,
    int? progressTotal,
    Duration? timeBudget,
    bool useDinoV2 = false,
  }) async {
    final embedder = DinoEmbedder(useDinoV2: useDinoV2);
    try {
      await embedder.load();
    } catch (e) {
      mark('AI: BỎ QUA, không tải được mô hình ($e)');
      return {};
    }

    final raw = <int, Float32List>{};
    try {
      var thumbFail = 0;
      var batchFail = 0;
      var consecutiveFail = 0;
      String? lastErr;

      // Tổng thời gian (cộng dồn, các batch chạy chồng nhau nên có thể > thời gian thật).
      var thumbMs = 0;
      var prepMs = 0;
      Future<_EmbBatch> prep(int start, int end) async {
        final idx = todo.sublist(
          start,
          math.min(start + config.modelBatch, end),
        );
        try {
          final sw = Stopwatch()..start();
          final bytes = await _thumbBytes([
            for (final i in idx) assets[i],
          ], dinoSize);
          thumbMs += sw.elapsedMilliseconds;
          sw.reset();
          final inputs = await dinoPreprocessBatch(bytes);
          prepMs += sw.elapsedMilliseconds;
          return _EmbBatch(idx, inputs);
        } catch (e) {
          return _EmbBatch(idx, const [], error: '$e');
        }
      }

      var done = 0;
      // Đo thời gian: waitSw = thời gian CHỜ batch kế tiếp chuẩn bị xong (thumbnail +
      // giải mã + chuẩn hóa); embedSw = thời gian chạy model. Chờ lâu => nghẽn ở
      // chuẩn bị ảnh, embed lâu => nghẽn ở model.
      final waitSw = Stopwatch();
      final embedSw = Stopwatch();
      final budgetSw = Stopwatch()..start();
      var timeLimited = false;
      // Chia toàn bộ thư viện thành checkpoint 1.000 ảnh. Mỗi checkpoint chỉ
      // giữ tối đa hai batch thumbnail/preprocess đang chờ, rồi nhường một nhịp
      // để UI cập nhật mốc trước khi nạp checkpoint tiếp theo.
      for (
        var checkpoint = 0;
        checkpoint < todo.length;
        checkpoint += scanModelCheckpointSize
      ) {
        final checkpointEnd = math.min(
          checkpoint + scanModelCheckpointSize,
          todo.length,
        );
        final queue = <Future<_EmbBatch>>[];
        var nextStart = checkpoint;
        while (nextStart <
            math.min(checkpoint + 2 * config.modelBatch, checkpointEnd)) {
          queue.add(prep(nextStart, checkpointEnd));
          nextStart += config.modelBatch;
        }
        while (done < checkpointEnd) {
          if (timeBudget != null && budgetSw.elapsed >= timeBudget) {
            timeLimited = true;
            break;
          }
          if (session.cancelled) throw const ScanCancelled();
          await session.waitIfPaused();
          if (session.cancelled) throw const ScanCancelled();

          waitSw.start();
          final cur = await queue.removeAt(0);
          waitSw.stop();
          if (nextStart < checkpointEnd) {
            queue.add(prep(nextStart, checkpointEnd));
            nextStart += config.modelBatch;
          }

          if (cur.error != null) {
            batchFail += cur.idx.length;
            lastErr = cur.error;
          } else {
            final ok = <int>[];
            final inputs = <Float32List>[];
            for (var k = 0; k < cur.idx.length; k++) {
              final t = cur.inputs[k];
              if (t == null) {
                thumbFail++;
              } else {
                ok.add(cur.idx[k]);
                inputs.add(t);
              }
            }
            if (inputs.isNotEmpty) {
              try {
                embedSw.start();
                final e = await embedder.embed(inputs);
                embedSw.stop();
                for (var k = 0; k < ok.length; k++) {
                  raw[ok[k]] = e[k];
                }
                consecutiveFail = 0;
              } catch (e) {
                embedSw.stop();
                batchFail += ok.length;
                lastErr = '$e';
                consecutiveFail++;
              }
            }
          }
          done += cur.idx.length;
          if (timeBudget != null && budgetSw.elapsed >= timeBudget) {
            timeLimited = true;
          }
          onProgress(
            ScanProgress(
              ScanPhase.embedding,
              done,
              todo.length,
              paused: session.paused,
              overallDone: progressOffset + done,
              overallTotal: progressTotal,
              libraryDone: todo.isEmpty
                  ? 0
                  : (progressOffset + done) * assets.length ~/ progressTotal!,
              libraryTotal: assets.length,
            ),
          );
          if (consecutiveFail >= 3 || timeLimited) {
            if (consecutiveFail >= 3) {
              mark('AI: DỪNG sớm sau 3 batch lỗi liên tiếp');
            }
            break;
          }
        }
        if (consecutiveFail >= 3 || timeLimited) break;
        // Nhường UI sau mỗi mốc lớn; kết quả vẫn được giữ đến khi so khớp xong.
        await Future<void>.delayed(Duration.zero);
        if (consecutiveFail >= 3 || timeLimited) break;
      }
      if (timeLimited) {
        final remaining = todo.length - done;
        mark(
          'AI: dừng theo giới hạn ${timeBudget!.inSeconds}s; '
          'đã xử lý $done/${todo.length}, còn $remaining ảnh',
        );
        if (!useDinoV2) {
          session.incompleteStages.add('Ảnh tương tự');
          session.remainingForStage['Ảnh tương tự'] = remaining;
        }
      }
      mark(
        'AI: lấy thumbnail ${(thumbMs / 1000).round()}s, giải mã+chuẩn hóa '
        '${(prepMs / 1000).round()}s (cộng dồn); '
        'thời gian chờ chuẩn bị ảnh ${waitSw.elapsed.inSeconds}s, '
        'chạy model ${embedSw.elapsed.inSeconds}s '
        '(${todo.length} ảnh, batch ${config.modelBatch})',
      );
      mark(
        'AI: ${raw.length}/${todo.length} ảnh có embedding'
        '${thumbFail > 0 ? ', $thumbFail ảnh không đọc được thumbnail' : ''}'
        '${batchFail > 0 ? ', $batchFail ảnh lỗi ($lastErr)' : ''}',
      );
    } finally {
      await embedder.close();
    }

    return raw;
  }

  /// Bước AI cho tab "Tương tự": embedding mọi ảnh chưa vào nhóm trùng, trừ trung
  /// bình toàn thư viện, rồi nối mỗi ảnh với [ScanConfig.similarModelK] hàng xóm gần
  /// nhất (cosine >= [ScanConfig.similarModelFloor]) vào [ufSim]. Ngưỡng cuối do
  /// người dùng chỉnh lúc xem (thanh "Độ nhạy"), nên không cần bộ dữ liệu cố định.
  /// Trả về embedding đã trừ trung bình; rỗng nếu bỏ qua.
  Future<Map<int, Float32List>> _similarModelStage(
    ScanSession session,
    List<AssetEntity> assets,
    UnionFind ufSim,
    void Function(ScanProgress) onProgress,
    void Function(String) mark,
    Map<String, MediaSig> sigs, {
    required Duration timeBudget,
  }) async {
    final n = assets.length;
    // Mọi ảnh đều được embedding: kết quả tương tự không phụ thuộc việc có quét
    // ảnh trùng hay không.
    if (n < config.modelMinMeanCount) {
      mark('AI tương tự: BỎ QUA, chỉ $n ảnh cần so');
      return {};
    }
    // Vector đã nhớ từ lần quét trước: chỉ nhúng lại ảnh mới hoặc ảnh đã đổi.
    // Đây là khoản đắt nhất của cả lần quét (~30 ms mỗi ảnh, chạy trên TOÀN BỘ
    // thư viện), nên bỏ được ảnh nào là bớt thẳng ngần ấy thời gian.
    final knownSim = await PhotoStore.embFor(assets, sigs);
    final remembered = <int, Float32List>{
      for (var i = 0; i < n; i++)
        if (knownSim[assets[i].id] != null) i: knownSim[assets[i].id]!,
    };
    final todo = [
      for (var i = 0; i < n; i++)
        if (!remembered.containsKey(i)) i,
    ];
    if (remembered.isNotEmpty) {
      mark('AI tương tự: dùng lại ${remembered.length}/$n vector đã nhớ');
    }
    final fresh = todo.isEmpty
        ? <int, Float32List>{}
        : await _embedIndices(
            session,
            assets,
            todo,
            onProgress,
            mark,
            progressTotal: todo.length,
            timeBudget: timeBudget,
          );
    await PhotoStore.saveEmb(assets, fresh);
    final raw = <int, Float32List>{...remembered, ...fresh};
    if (raw.length < config.modelMinMeanCount) {
      mark('AI tương tự: BỎ QUA, chỉ ${raw.length} embedding hợp lệ');
      return {};
    }
    final out = centerEmbeddings(raw);
    onProgress(const ScanProgress(ScanPhase.matching, 0, 1));
    final ids = out.keys.toList()..sort();
    final dim = out[ids.first]!.length;
    final flat = Float32List(ids.length * dim);
    for (var r = 0; r < ids.length; r++) {
      flat.setRange(r * dim, (r + 1) * dim, out[ids[r]]!);
    }
    final k = config.similarModelK;
    final floor = config.similarModelFloor;
    final edges = await Isolate.run(
      () => findTopKEdges(
        emb: flat,
        n: ids.length,
        dim: dim,
        k: k,
        minCos: floor,
        mutual: false,
      ),
    );
    for (final e in edges) {
      ufSim.union(ids[e.a], ids[e.b]);
    }
    session.embeddings
      ..clear()
      ..addAll({for (final i in ids) assets[i].id: out[i]!});
    mark(
      'AI tương tự: ${ids.length} ảnh, ${edges.length} cạnh top-$k '
      'cosine>=$floor',
    );
    return out;
  }

  /// Bước AI: xác minh các cặp ứng viên PDQ có Hamming nằm giữa [ScanConfig.maxHamming]
  /// và [ScanConfig.similarMaxHamming] (hash lệch một chút, ví dụ ảnh cháy sáng).
  /// Chỉ ảnh thuộc các cặp đó (và chưa vào nhóm nào) được embedding, cộng một mẫu
  /// nhỏ rải đều thư viện để tính vector trung bình. Embedding được trừ trung bình
  /// rồi L2-normalize lại (đặc trưng MobileNet đều dương nên cosine thô giữa ảnh
  /// bất kỳ đã cao). Cặp có cosine >= [ScanConfig.modelMinCosine] được nối vào [uf].
  /// Mọi lỗi đều được ghi vào timings. Trả về embedding (đã trừ trung bình) theo
  /// chỉ số ảnh; rỗng nếu không có cặp nào cần xác minh hoặc không đủ mẫu.
  /// Vector trung bình nhớ giữa các lần quét, kèm số ảnh lúc tính nó.
  static _MeanVector? _meanCache;

  /// Quên vector trung bình đang nhớ (đổi mô hình, hoặc muốn tính lại từ đầu).
  static void forgetMeanVector() => _meanCache = null;

  /// Vector trung bình đang nhớ trong phiên. Chỉ để màn chẩn đoán đọc, không đổi pipeline.
  static Float64List? get libraryMean => _meanCache?.mean;

  /// Số ảnh đưa vào bước so PDQ của lần quét gần nhất, và chế độ tìm cặp.
  static int? lastEligibleCount;
  static String? lastCandidateMode;

  Future<Map<int, Float32List>> _modelStage(
    ScanSession session,
    List<AssetEntity> assets,
    UnionFind uf,
    List<MatchEdge> edges,
    void Function(ScanProgress) onProgress,
    void Function(String) mark,
    Map<String, MediaSig> sigs,
  ) async {
    final n = assets.length;
    final groupSize = List<int>.filled(n, 0);
    for (var i = 0; i < n; i++) {
      groupSize[uf.find(i)]++;
    }
    final pairs = <MatchEdge>[
      for (final e in edges)
        if (e.distance > config.maxHamming &&
            groupSize[uf.find(e.a)] == 1 &&
            groupSize[uf.find(e.b)] == 1)
          e,
    ];
    // Chuỗi chụp liên tiếp: ảnh chụp cách nhau trong vài giây được đưa vào AI dù PDQ
    // vượt ngưỡng, vì khung hình của một chuỗi thường khác nhiều về hash.
    final burstIdx = <int>[for (var i = 0; i < n; i++) i]
      ..sort(
        (x, y) => assets[x].createDateTime.compareTo(assets[y].createDateTime),
      );
    final burstSet = <int>{};
    for (var k = 1; k < burstIdx.length; k++) {
      final a = burstIdx[k - 1];
      final b = burstIdx[k];
      final gap = assets[b].createDateTime
          .difference(assets[a].createDateTime)
          .inMilliseconds;
      if (gap > config.burstWindowMs) continue;
      if (burstSet.add(_pairKey(a, b))) {
        pairs.add(MatchEdge(a, b, config.maxHamming + 1));
      }
    }
    mark(
      'chuỗi chụp v2: ${burstSet.length} cặp trong ${config.burstWindowMs ~/ 1000}s, ngưỡng cosine thô ${config.burstMinRawCos}',
    );
    if (pairs.isEmpty) {
      mark('AI: bỏ qua, không có cặp PDQ nào cần xác minh');
      return {};
    }

    // Ảnh cần embedding = ảnh trong các cặp + mẫu rải đều để lấy trung bình.
    // Vector trung bình là đặc tính của CẢ THƯ VIỆN, không phải của mấy cặp
    // đang xét. Nhúng lại 256 ảnh mẫu mỗi lần quét là trả một khoản cố định
    // cho một con số gần như không đổi — và chỉ cần tồn tại một cặp lưng chừng
    // là phải trả đủ. Giữ lại trong RAM giữa các lần quét; chỉ tính lại khi số
    // ảnh trong máy đã đổi quá 10%. Không ghi xuống đĩa: app hứa không lưu gì,
    // nên đổi lại là mất khi đóng app.
    final cached = _meanCache;
    final reuse =
        cached != null && (n - cached.libCount).abs() <= cached.libCount * 0.10;

    // Cặp gần nhau nhất là cặp dễ đúng nhất, nên xác minh chúng trước rồi mới
    // tới cặp xa dần, và dừng khi chạm trần.
    pairs.sort((a, b) => a.distance.compareTo(b.distance));
    final need = <int>{};
    var skippedPairs = 0;
    for (final e in pairs) {
      if (need.length >= config.modelMaxPhotos &&
          !(need.contains(e.a) && need.contains(e.b))) {
        skippedPairs++;
        continue;
      }
      need
        ..add(e.a)
        ..add(e.b);
    }
    if (skippedPairs > 0) {
      mark(
        'AI: bỏ $skippedPairs cặp xa nhất, đã chạm trần '
        '${config.modelMaxPhotos} ảnh',
      );
    }
    if (!reuse) {
      final sampleStep = math.max(1, n ~/ config.modelMeanSample);
      for (var i = 0; i < n; i += sampleStep) {
        need.add(i);
      }
      if (need.length < config.modelMinMeanCount) {
        mark(
          'AI: BỎ QUA, chỉ ${need.length} ảnh '
          '(< ${config.modelMinMeanCount}) nên không đủ mẫu để trừ trung bình',
        );
        return {};
      }
    }
    final todo = need.toList()..sort();

    // Vector đã nhớ từ lần quét trước: chỉ nhúng ảnh mới hoặc ảnh đã đổi.
    final known = await PhotoStore.embFor([
      for (final i in todo) assets[i],
    ], sigs);
    final missing = [
      for (final i in todo)
        if (!known.containsKey(assets[i].id)) i,
    ];
    if (known.isNotEmpty) {
      mark('AI: dùng lại ${known.length}/${todo.length} vector đã nhớ');
    }
    final fresh = missing.isEmpty
        ? <int, Float32List>{}
        : await _embedIndices(
            session,
            assets,
            missing,
            onProgress,
            mark,
            progressTotal: missing.length,
          );
    await PhotoStore.saveEmb(assets, fresh);
    final raw = <int, Float32List>{
      for (final i in todo)
        if (known[assets[i].id] != null) i: known[assets[i].id]!,
      ...fresh,
    };
    if (raw.isEmpty) {
      mark('AI: BỎ QUA xác minh, không có embedding hợp lệ');
      return {};
    }
    Float64List? mean;
    if (reuse && cached.mean.length == raw.values.first.length) {
      mean = cached.mean;
      mark(
        'AI: dùng lại vector trung bình, bỏ qua '
        '${config.modelMeanSample} ảnh mẫu',
      );
    } else {
      // Không dùng lại được thì phải tự tính, và tính từ ít ảnh thì vô nghĩa.
      if (raw.length < config.modelMinMeanCount) {
        mark('AI: BỎ QUA xác minh, chỉ ${raw.length} embedding hợp lệ');
        return {};
      }
      mean = meanOf(raw);
      _meanCache = _MeanVector(mean, n);
    }
    final out = centerEmbeddingsWith(raw, mean);
    onProgress(ScanProgress(ScanPhase.matching, pairs.length, pairs.length));
    var checked = 0;
    var merged = 0;
    for (final e in pairs) {
      final c = cosineOf(out[e.a], out[e.b]);
      if (c == null) continue;
      checked++;
      if (c >= config.modelMinCosine) {
        uf.union(e.a, e.b);
        merged++;
      } else if (burstSet.contains(_pairKey(e.a, e.b)) &&
          burstLikePairEvidence(
            gapMs: assets[e.a].createDateTime
                .difference(assets[e.b].createDateTime)
                .inMilliseconds,
            rawCosine: _rawCos(raw[e.a], raw[e.b]),
            burstWindowMs: config.burstWindowMs,
            burstMinRawCosine: config.burstMinRawCos,
          )) {
        _burstKeys.add(_pairKey(e.a, e.b));
        uf.union(e.a, e.b);
        merged++;
      }
    }
    mark(
      'AI: $merged/$checked cặp PDQ (${config.maxHamming}<Hamming<='
      '${config.similarMaxHamming}) có cosine>=${config.modelMinCosine}; '
      'đã nối ${_burstKeys.length} cặp chuỗi chụp',
    );
    return out;
  }

  /// Thumbnail vuông [side]px cho từng ảnh; null nếu không đọc được.
  Future<List<Uint8List?>> _thumbBytes(
    List<AssetEntity> batch,
    int side,
  ) async {
    final res = <Uint8List?>[];
    final c = config.ioConcurrency;
    for (var i = 0; i < batch.length; i += c) {
      final slice = batch.sublist(i, math.min(i + c, batch.length));
      res.addAll(
        await Future.wait([
          for (final a in slice)
            () async {
              try {
                return await a.thumbnailDataWithSize(
                  ThumbnailSize(side, side),
                  quality: 85,
                );
              } catch (_) {
                return null;
              }
            }(),
        ]),
      );
    }
    return res;
  }

  /// Cỡ thumbnail giữ nguyên tỷ lệ ảnh gốc, cạnh dài bằng [side].
  ///
  /// KHÔNG xin ảnh vuông. Xin vuông thì nền tảng được quyền cắt giữa để lấp
  /// đầy khung, và hai mép ảnh biến mất khỏi hash — ảnh cùng cảnh nhưng khác
  /// tỷ lệ sẽ băm ra khác nhau, còn ảnh khác nhau mà trùng phần giữa lại băm
  /// giống nhau. PDQ vốn băm TOÀN khung ảnh bóp về 64x64, nên lấy đúng tỷ lệ
  /// rồi để bước sau bóp mới là đúng định nghĩa.
  static ThumbnailSize _fitSize(AssetEntity a, int side) {
    final w = a.width, h = a.height;
    if (w <= 0 || h <= 0) return ThumbnailSize(side, side);
    if (w >= h) {
      return ThumbnailSize(side, math.max(16, (side * h / w).round()));
    }
    return ThumbnailSize(math.max(16, (side * w / h).round()), side);
  }

  /// Chỉ thumbnail 128px; chỉ số là chỉ số trong batch. Ảnh có chỉ số nằm
  /// trong [skip] đã có vân tay nhớ sẵn nên không đọc.
  Future<List<HashInput>> _thumbs(
    List<AssetEntity> batch, [
    Set<int> skip = const {},
  ]) async {
    final inputs = <HashInput>[];
    final c = config.ioConcurrency;
    for (var i = 0; i < batch.length; i += c) {
      final slice = batch.sublist(i, math.min(i + c, batch.length));
      final got = await Future.wait(
        List.generate(slice.length, (k) async {
          if (skip.contains(i + k)) return null;
          Uint8List? thumb;
          try {
            // Ảnh nằm trên iCloud chưa tải có thể làm lời gọi này treo vô hạn:
            // quá hạn thì coi như không đọc được, quét tiếp ảnh sau.
            thumb = await slice[k]
                .thumbnailDataWithSize(_fitSize(slice[k], 128), quality: 70)
                .timeout(const Duration(seconds: 10));
          } catch (_) {}
          return HashInput(index: i + k, thumb: thumb);
        }),
      );
      for (final g in got) {
        if (g != null) inputs.add(g);
      }
    }
    return inputs;
  }

  /// Export file gốc cho các ảnh nghi trùng; chỉ số là chỉ số trong [idx].
  /// Dung lượng từng ảnh (byte), đọc từ metadata của hệ điều hành: MediaStore
  /// trên Android, PHAssetResource trên iOS. Không mở file, không tải iCloud,
  /// nên tốn vài chục mili giây cho cả thư viện.
  ///
  /// Trả về danh sách rỗng nếu nền tảng không có kênh này; phần tử bằng 0 nghĩa
  /// là không đọc được ảnh đó. Thiếu dung lượng chỉ làm mất phần lọc, không bao
  /// giờ làm sai kết quả.
  Future<List<int>> _fileSizes(
    ScanSession session,
    List<AssetEntity> assets,
    void Function(String) mark, [
    Map<String, MediaSig> sigs = const {},
  ]) async {
    final edits = PhotoEdits();
    if (!edits.supported) return const [];
    final out = List<int>.filled(assets.length, 0);
    // Đã có dung lượng trong chữ ký MediaStore thì khỏi hỏi lần nữa.
    if (sigs.isNotEmpty) {
      var have = 0;
      for (var i = 0; i < assets.length; i++) {
        final z = sigs[assets[i].id]?.size ?? 0;
        if (z > 0) {
          out[i] = z;
          have++;
        }
      }
      if (have > 0) {
        mark('dung lượng từ MediaStore: $have/${assets.length} ảnh');
        return out;
      }
    }
    final index = <String, int>{};
    for (var i = 0; i < assets.length; i++) {
      index[assets[i].id] = i;
    }
    final ids = index.keys.toList();
    var known = 0;
    for (var s = 0; s < ids.length; s += 400) {
      if (session.cancelled) throw const ScanCancelled();
      final part = ids.sublist(s, math.min(s + 400, ids.length));
      try {
        final got = await edits.fileSizes(part);
        got.forEach((id, bytes) {
          final i = index[id];
          if (i != null && bytes > 0) {
            out[i] = bytes;
            known++;
          }
        });
      } catch (_) {
        // Nuốt lỗi: mất phần lọc thì chỉ chậm như cũ.
      }
    }
    mark('dung lượng từ metadata: $known/${assets.length} ảnh');
    return out;
  }

  Future<List<HashInput>> _files(
    List<int> idx,
    List<AssetEntity> assets,
  ) async {
    final inputs = <HashInput>[];
    final c = config.fileConcurrency;
    for (var i = 0; i < idx.length; i += c) {
      final end = math.min(i + c, idx.length);
      inputs.addAll(
        await Future.wait([
          for (var k = i; k < end; k++)
            () async {
              String? path;
              try {
                path = (await assets[idx[k]].originFile.timeout(
                  const Duration(seconds: 30),
                ))?.path;
              } catch (_) {}
              return HashInput(index: k, filePath: path);
            }(),
        ]),
      );
    }
    return inputs;
  }
}

class _Pending {
  _Pending({
    required this.assets,
    required this.shas,
    required this.flat,
    required this.has,
    required this.uf,
    required this.ufSim,
    required this.links,
    required this.emb,
    required this.inDupIds,
    required this.dupGroups,
    required this.usingV2,
  });
  final List<AssetEntity> assets;
  final List<String?> shas;
  final Uint64List flat;
  final Uint8List has;
  final UnionFind uf;
  final UnionFind ufSim;
  final Map<int, int> links;
  final Map<int, Float32List> emb;
  final Set<String> inDupIds;
  final List<DuplicateGroup> dupGroups;
  final bool usingV2;
}

class _OrigHashes {
  const _OrigHashes(this.owners, this.flat);

  /// owners[k] = chỉ số ảnh (đã chỉnh) mà hash gốc thứ k thuộc về.
  final List<int> owners;

  /// 4 word 64-bit cho mỗi hash gốc; null nếu không có.
  final Uint64List? flat;
}

class _EmbBatch {
  const _EmbBatch(this.idx, this.inputs, {this.error});
  final List<int> idx;
  final List<Float32List?> inputs;
  final String? error;
}

class _Batch {
  const _Batch(this.assets, this.inputs, this.skip, [this.rows = const {}]);
  final List<AssetEntity> assets;
  final List<HashInput> inputs;

  /// Chỉ số trong batch của ảnh dùng lại vân tay cũ, không băm lại.
  final Set<int> skip;

  /// Vân tay đã nhớ của các ảnh trong [skip], theo id.
  final Map<String, PdqRow> rows;
}

void _log(String tag, Duration elapsed) {
  if (!kDebugMode) return;
  const mb = 1024 * 1024;
  debugPrint(
    '[scan] ${elapsed.inSeconds}s $tag '
    'rss=${ProcessInfo.currentRss ~/ mb}MB max=${ProcessInfo.maxRss ~/ mb}MB',
  );
}

/// Vector trung bình của thư viện và số ảnh lúc tính nó.
class _MeanVector {
  const _MeanVector(this.mean, this.libCount);
  final Float64List mean;
  final int libCount;
}
