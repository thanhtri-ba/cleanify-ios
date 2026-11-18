import 'dart:async';
import 'dart:typed_data';

import 'package:photo_manager/photo_manager.dart';

import 'regroup.dart';
import 'scan_diagnostics.dart';

class DuplicateItem {
  DuplicateItem(
    this.asset, {
    required this.exact,
    this.similarity,
    this.byModel = false,
    this.viaOriginal = false,
    this.modelCosine,
    this.pdqHamming,
  });
  final AssetEntity asset;

  /// Trùng SHA-256 với ảnh đại diện của nhóm.
  final bool exact;

  /// Độ giống so với ảnh đại diện (0–100): bit-hash PDQ, hoặc cosine DINO x 100
  /// khi [byModel]. Null nếu không tính được.
  final double? similarity;

  /// Được nhóm bởi mô hình AI (DINO), không phải bởi SHA-256/PDQ.
  final bool byModel;

  /// Ảnh đã chỉnh sửa (iOS): hash của BẢN GỐC khớp ảnh đại diện. Ảnh đang hiển thị
  /// khác ảnh đại diện (có thể có nét vẽ, crop), nên [similarity] là null và
  /// "Dọn nhanh" không tự xóa.
  final bool viaOriginal;

  /// Chỉ cho nhóm tương tự: cosine embedding (đã trừ trung bình) với ảnh đại diện,
  /// khi ảnh được nhóm CHỈ nhờ mô hình. [similarity] là null nên không bị tự xóa.
  /// Giao diện lọc theo giá trị này (thanh "Độ nhạy").
  final double? modelCosine;

  /// Khoảng cách Hamming PDQ (0–256) tới ảnh đại diện, chỉ cho ảnh nhóm tương tự.
  /// Mô hình AI nhìn theo ngữ nghĩa (vd. mọi ảnh "trời" gần nhau) nên cần thêm bằng
  /// chứng hình dạng/độ sáng: hai ảnh ngẫu nhiên có Hamming ~128 ± 8.
  final int? pdqHamming;
}

enum GroupKind { duplicate, similar }

/// Ảnh này là ảnh CHỤP MÀN HÌNH chứ không phải chụp từ camera.
///
/// iOS đánh dấu bằng bit 4 của subtype (PHAssetMediaSubtypePhotoScreenshot).
/// Android không có cờ nào, nên dựa vào thư mục hệ thống luôn lưu ảnh chụp
/// màn hình vào. Đoán thừa an toàn hơn đoán thiếu: nhận nhầm một ảnh camera
/// thành ảnh màn hình chỉ làm nó nằm sang nhóm khác, không mất ảnh.
bool isScreenshotAsset(AssetEntity a) =>
    (a.subtype & 4) != 0 ||
    (a.relativePath ?? '').toLowerCase().contains('screenshot');

/// Nhóm "tương tự" sau khi bỏ các ảnh đã nằm trong một nhóm "trùng" trong [groups]:
/// một ảnh chỉ thuộc một loại (trùng được ưu tiên) để hai loại không lẫn vào nhau.
/// Nhóm còn dưới 2 ảnh thì bỏ. Chỉ trả về nhóm tương tự.
///
/// [level] là mức "độ lệch cho phép" người dùng chọn lúc xem: bỏ ảnh có cosine với ảnh
/// đại diện thấp hơn mức đó (không quét lại; quét luôn dùng mức rộng nhất).
List<DuplicateGroup> similarExcludingDuplicates(
  List<DuplicateGroup> groups, {
  SimilarLevel level = kDefaultSimilarLevel,
  double? minCosine,
}) {
  // [minCosine] (thanh kéo độ lệch) thay cho mức cố định; Hamming PDQ nội suy theo đó.
  final cosLimit = minCosine ?? level.cosine;
  final hamLimit = minCosine == null
      ? level.maxHamming
      : hammingForCosine(minCosine);
  final dup = <String>{
    for (final g in groups)
      if (g.kind == GroupKind.duplicate)
        for (final e in g.items) e.asset.id,
  };
  final out = <DuplicateGroup>[];
  for (final g in groups) {
    if (g.kind != GroupKind.similar) continue;
    final items = [
      for (final e in g.items)
        if (!dup.contains(e.asset.id) &&
            (e.modelCosine == null || e.modelCosine! >= cosLimit) &&
            (e.pdqHamming == null ||
                e.pdqHamming! <= hamLimit ||
                // Cosine AI đã cao (>= mức Chặt) thì Hamming PDQ không được loại ảnh khỏi nhóm.
                (e.modelCosine ?? 0) >= SimilarLevel.strict.cosine))
          e,
    ];
    if (items.length > 1) {
      out.add(DuplicateGroup(items, kind: GroupKind.similar));
    }
  }
  return out;
}

/// Hai ngưỡng cosine (MobileNet, ĐÃ trừ vector trung bình) chia ảnh làm 3 loại:
///   cosine >= [kCosineDuplicate]                    -> trùng / gần như y hệt
///   [kCosineSimilar] <= cosine < [kCosineDuplicate] -> giống (cùng cảnh, lệch nhẹ)
///   cosine < [kCosineSimilar]                       -> khác
/// Cả hai là giá trị TẠM, đo trên 50 ảnh thật (không phải tập calibrate). Thang này
/// phụ thuộc vector trung bình của thư viện nên KHÔNG ổn định giữa các thư viện;
/// thay bằng ngưỡng calibrate khi có.
const double kCosineSimilar = 0.85;
const double kCosineDuplicate = 0.93;

/// Mức "độ lệch cho phép" của tab Giống nhau (chọn ở bộ lọc, áp dụng ngay không quét
/// lại). Quét luôn gom ở mức [SimilarLevel.wide]; các mức chặt hơn chỉ ẩn bớt ảnh.
enum SimilarLevel {
  strict('Chặt', 0.80, 96, 'Cùng cảnh, lệch nhẹ.'),
  normal('Vừa', 0.65, 108, 'Cùng cảnh, lệch vừa.'),
  wide('Rộng', 0.50, 120, 'Gồm cả ảnh cùng bối cảnh, lệch nhiều.');

  const SimilarLevel(this.label, this.cosine, this.maxHamming, this.hint);
  final String label;
  final double cosine;

  /// Hamming PDQ tối đa tới ảnh đại diện (104 ≈ 3σ dưới mức ngẫu nhiên 128).
  final int maxHamming;
  final String hint;

  /// Số hiển thị (cosine x 100, làm tròn) trên thẻ chọn mức.
  int get percent => (cosine * 100).round();
}

const SimilarLevel kDefaultSimilarLevel = SimilarLevel.normal;

/// Mặc định của bộ lọc khi mở màn xem kết quả (người dùng vẫn chỉnh được):
/// tab Trùng theo độ giống PDQ (%), tab Giống nhau theo cosine.
const double kDefaultDupSim = 78.0;

/// Ngưỡng cosine để XÁC NHẬN hai ảnh là tương tự, lúc xem kết quả.
///
/// PHẢI bằng `kDefaultSimilarLevel.cosine` (mức "Vừa" = 0,65). Trước đây là
/// 0,63: không trùng mức nào có tên, nên mở bảng Lọc ra thì cả ba nút Chặt /
/// Vừa / Rộng đều không sáng (nút chỉ sáng khi lệch dưới 0,005) và người dùng
/// không biết mình đang đứng ở đâu. Dart không cho đọc trường của hằng enum
/// trong biểu thức hằng, nên con số phải chép tay — đổi mức mặc định thì sửa
/// cả hai chỗ.
///
/// Đây là ngưỡng LỌC LÚC XEM, không phải ngưỡng quét: bộ quét luôn gom ở mức
/// rộng nhất ([ScanConfig.similarModelFloor] = 0,50) rồi lọc lại ở đây, nên
/// kéo thanh trượt là thấy kết quả ngay, không phải quét lại.
const double kDefaultSimilarTol = 0.65;

/// Hamming PDQ tối đa ứng với một ngưỡng cosine bất kỳ: nội suy tuyến tính giữa mức Rộng
/// (cosine thấp, Hamming lớn) và mức Chặt, kẹp ở hai đầu.
int hammingForCosine(double cos) {
  final lo = SimilarLevel.wide.cosine, hi = SimilarLevel.strict.cosine;
  if (cos <= lo) return SimilarLevel.wide.maxHamming;
  if (cos >= hi) return SimilarLevel.strict.maxHamming;
  final t = (cos - lo) / (hi - lo);
  return (SimilarLevel.wide.maxHamming +
          t * (SimilarLevel.strict.maxHamming - SimilarLevel.wide.maxHamming))
      .round();
}

/// Nhãn mức giống theo cosine embedding. Cosine KHÔNG phải xác suất/%: dùng để người
/// xem nhìn nhanh theo 3 loại ở trên.
String cosineBand(double c) {
  if (c >= kCosineDuplicate) return 'Rất giống';
  if (c >= kCosineSimilar) return 'Giống';
  if (c >= SimilarLevel.strict.cosine) return 'Khá giống';
  if (c >= SimilarLevel.normal.cosine) return 'Hơi giống';
  return 'Khác biệt';
}

class DuplicateGroup {
  DuplicateGroup(this.items, {this.kind = GroupKind.duplicate});

  /// duplicate: trùng hoặc gần trùng (SHA-256/PDQ).
  final GroupKind kind;

  /// items.first là ảnh đề xuất giữ lại (độ phân giải cao nhất, cũ nhất).
  final List<DuplicateItem> items;

  bool get allExact => items.every((e) => e.exact);

  /// Bản lọc theo độ nhạy: bỏ ảnh chỉ được nhóm nhờ mô hình mà cosine < [t].
  /// Trả về chính nhóm này nếu không ảnh nào bị bỏ, null nếu còn dưới 2 ảnh.
  DuplicateGroup? withMinModelCosine(double t) {
    bool ok(DuplicateItem e) => e.modelCosine == null || e.modelCosine! >= t;
    if (items.every(ok)) return this;
    final kept = [
      for (final e in items)
        if (ok(e)) e,
    ];
    return kept.length < 2 ? null : DuplicateGroup(kept, kind: kind);
  }

  double? get minSimilarity {
    double? m;
    for (final e in items) {
      final s = e.exact ? 100.0 : e.similarity;
      if (s != null && (m == null || s < m)) m = s;
    }
    return m;
  }
}

class ScanCancelled implements Exception {
  const ScanCancelled();
}

class PermissionDeniedException implements Exception {
  const PermissionDeniedException();
}

/// Toàn bộ kết quả quét chỉ sống trong RAM của session này.
/// Không ghi database/file. [dispose] xóa mọi tham chiếu.
class ScanSession {
  ScanSession({this.diag});

  /// Chẩn đoán (chỉ khi bật). Null nghĩa là không ghi gì thêm.
  final ScanDiagnostics? diag;

  bool cancelled = false;
  bool _paused = false;
  Completer<void>? _resumeSignal;

  final List<DuplicateGroup> groups = [];

  /// Path of the automatically generated CSV for this scan, if saving worked.
  /// A refinement pass rewrites this same file with the final group results.
  String? reportPath;
  String? reportError;

  /// Dữ liệu PDQ để gom lại nhóm trùng theo ngưỡng người dùng chọn. Null nếu chưa quét
  /// kiểu "trùng". Chỉ trong RAM, xóa khi [dispose].
  PdqIndex? pdqIndex;

  /// Mọi ảnh đã quét (đúng thứ tự quét) để màn hình "Xem ảnh" duyệt.
  List<AssetEntity> assets = const [];

  /// Embedding (đã trừ trung bình, L2-normalize) theo asset id; chỉ trong RAM.
  /// Rỗng nếu bước AI bị bỏ qua. Dùng cho [neighborsOf].
  final Map<String, Float32List> embeddings = {};

  /// [k] ảnh giống [id] nhất theo cosine embedding, giảm dần. Rỗng nếu thiếu embedding.
  List<({AssetEntity asset, double cosine})> neighborsOf(
    String id, {
    int k = 30,
  }) {
    final q = embeddings[id];
    if (q == null) return const [];
    final byId = {for (final a in assets) a.id: a};
    final res = <({AssetEntity asset, double cosine})>[];
    embeddings.forEach((other, v) {
      final a = byId[other];
      if (other == id || a == null || v.length != q.length) return;
      var c = 0.0;
      for (var i = 0; i < q.length; i++) {
        c += q[i] * v[i];
      }
      res.add((asset: a, cosine: c));
    });
    res.sort((x, y) => y.cosine.compareTo(x.cosine));
    return res.length > k ? res.sublist(0, k) : res;
  }

  /// Thời gian từng giai đoạn của lần quét này (hiện trên màn hình kết quả).
  final List<String> timings = [];

  /// Các bước dừng theo ngân sách nên kết quả của chúng chưa bao phủ toàn thư viện.
  final Set<String> incompleteStages = {};
  final Map<String, int> remainingForStage = {};
  int scanned = 0;
  int libraryTotal = 0;
  int hashFailures = 0;

  /// Số nhóm trùng ước tính ngay sau bước so khớp, để màn quét hiện số tăng dần thay vì 0.
  int liveGroups = 0;
  Duration elapsed = Duration.zero;

  bool get paused => _paused;

  void pause() {
    if (_paused) return;
    _paused = true;
    _resumeSignal = Completer<void>();
  }

  void resume() {
    if (!_paused) return;
    _paused = false;
    _resumeSignal?.complete();
    _resumeSignal = null;
  }

  /// Dừng tại ranh giới batch khi đang pause.
  Future<void> waitIfPaused() async {
    final signal = _resumeSignal;
    if (_paused && signal != null) await signal.future;
  }

  List<DuplicateGroup> get duplicateGroups =>
      groups.where((g) => g.kind == GroupKind.duplicate).toList();

  List<DuplicateGroup> get similarGroups =>
      groups.where((g) => g.kind == GroupKind.similar).toList();

  int get reclaimable =>
      duplicateGroups.fold(0, (sum, g) => sum + (g.items.length - 1));

  void removeAssets(Set<String> ids) {
    pdqIndex?.removed.addAll(ids);
    assets = [
      for (final a in assets)
        if (!ids.contains(a.id)) a,
    ];
    for (final id in ids) {
      embeddings.remove(id);
    }
    for (final g in groups) {
      g.items.removeWhere((e) => ids.contains(e.asset.id));
    }
    groups.removeWhere((g) => g.items.length < 2);
  }

  Future<void> dispose() async {
    cancelled = true;
    resume();
    groups.clear();
    embeddings.clear();
    pdqIndex = null;
    assets = const [];
    diag?.clear();
  }
}
