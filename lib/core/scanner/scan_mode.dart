import 'dart:math' as math;

/// Kiểu quét người dùng chọn trước khi bắt đầu. Chỉ phần được chọn mới chạy.
class ScanMode {
  const ScanMode({this.duplicates = true, this.similar = false});

  /// Ảnh trùng / gần trùng: PDQ tìm ứng viên, SHA-256 xác nhận bản y hệt.
  final bool duplicates;

  /// Ảnh tương tự (cùng cảnh): embedding AI MobileNetV3 (chậm hơn nhiều).
  final bool similar;

  bool get any => duplicates || similar;
}

// Ngân sách hiển thị là mục tiêu, không phải cam kết thời gian hoặc cam kết
// xử lý đủ toàn thư viện. Máy chậm có thể phải trả kết quả một phần.
const double _readMsPerPhoto = 6.3;
const double _pairUs = 6.0;
const double _shaFraction =
    0.10; // tỷ lệ ảnh nghi trùng khít cần export file gốc
const double _shaMsPerPhoto = 15.0;
const double _largeIndexMs = 8000.0;
const double _aiBudgetMs = 45000.0;
const double _scanBudgetMs = 110000.0;
const int _exactPairsBelow = 6000;

/// Thời gian quét dự kiến cho [photos] ảnh theo [mode].
Duration estimateScan(int photos, ScanMode mode) {
  if (photos <= 0 || !mode.any) return Duration.zero;
  var ms = 0.0;
  // Quét tương tự vẫn phải chạy bước trùng để loại ảnh trùng khỏi kết quả.
  if (mode.any) {
    if (photos <= _exactPairsBelow) {
      final pairs = photos * (photos - 1) / 2;
      ms +=
          photos * _readMsPerPhoto +
          pairs * _pairUs / 1000 +
          photos * _shaFraction * _shaMsPerPhoto;
    } else {
      ms +=
          photos * _readMsPerPhoto +
          photos * _shaFraction * _shaMsPerPhoto +
          _largeIndexMs;
    }
  }
  if (mode.similar) ms += _aiBudgetMs;
  ms = math.min(ms, _scanBudgetMs);
  return Duration(milliseconds: ms.round());
}

/// Ngân sách mục tiêu riêng từng phần, để hiện cạnh mỗi lựa chọn.
Duration estimateDuplicates(int photos) =>
    estimateScan(photos, const ScanMode(duplicates: true, similar: false));
Duration estimateSimilar(int photos) =>
    estimateScan(photos, const ScanMode(duplicates: false, similar: true));
