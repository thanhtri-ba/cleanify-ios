import 'scan_mode.dart';

enum ScanPhase { reading, matching, exact, embedding }

const int scanDisplayBatchSize = 1000;
const int scanModelCheckpointSize = 1000;

class ScanProgress {
  const ScanProgress(
    this.phase,
    this.done,
    this.total, {
    this.paused = false,
    this.overallDone,
    this.overallTotal,
    this.libraryDone,
    this.libraryTotal,
  });
  final ScanPhase phase;
  final int done;
  final int total;
  final bool paused;
  final int? overallDone;
  final int? overallTotal;
  final int? libraryDone;
  final int? libraryTotal;

  int get progressDone => overallDone ?? done;
  int get progressTotal => overallTotal ?? total;
  int get milestoneDone => libraryDone ?? progressDone;
  int get milestoneTotal => libraryTotal ?? progressTotal;

  double? get fraction => total == 0 ? null : done / total;

  String get label {
    switch (phase) {
      case ScanPhase.reading:
        return 'Đang băm ảnh $done/$total';
      case ScanPhase.matching:
        return 'Đang so khớp ứng viên…';
      case ScanPhase.exact:
        return 'Đang đối chiếu file gốc $done/$total';
      case ScanPhase.embedding:
        return 'Đang phân tích AI $done/$total';
    }
  }

  /// Tiến độ theo các mốc dễ đọc, độc lập với batch nội bộ của thuật toán.
  int get batchIndex =>
      milestoneDone == 0 ? 0 : (milestoneDone - 1) ~/ scanDisplayBatchSize + 1;
  int get batchCount => milestoneTotal == 0
      ? 0
      : (milestoneTotal - 1) ~/ scanDisplayBatchSize + 1;
  int get remaining => (progressTotal - progressDone).clamp(0, progressTotal);
  int get batchStart => milestoneDone == 0
      ? 0
      : ((milestoneDone - 1) ~/ scanDisplayBatchSize) * scanDisplayBatchSize +
            1;
  int get batchEnd => milestoneTotal < batchIndex * scanDisplayBatchSize
      ? milestoneTotal
      : batchIndex * scanDisplayBatchSize;

  String get milestoneLabel => batchCount == 0
      ? '${groupDigits(milestoneDone)}/${groupDigits(milestoneTotal)} ảnh'
      : 'Đợt $batchIndex/$batchCount · ${groupDigits(milestoneDone)}'
            '/${groupDigits(milestoneTotal)} ảnh';

  /// Mốc gọn cho một dòng chữ hẹp: "1.000/30.000 ảnh", không kèm số đợt.
  ///
  /// Vòng tiến độ đã cho thấy đã đi được bao xa rồi, nên số đợt chỉ là một con
  /// số nữa để đọc. Cái người dùng muốn biết là còn bao nhiêu ảnh.
  String get milestoneShort =>
      '${groupDigits(milestoneDone)}/${groupDigits(milestoneTotal)} ảnh';

  String get batchRangeLabel => milestoneTotal == 0
      ? 'Chưa có ảnh'
      : '${batchStart.clamp(1, milestoneTotal)}–${batchEnd.clamp(0, milestoneTotal)}';
}

/// Nhóm hàng nghìn bằng dấu chấm theo cách viết tiếng Việt: 30000 -> "30.000".
String groupDigits(int v) {
  final s = v.abs().toString();
  final out = StringBuffer(v < 0 ? '-' : '');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) out.write('.');
    out.write(s[i]);
  }
  return out.toString();
}

/// "03:25" khi dưới 1 giờ, "1:02:03" khi từ 1 giờ trở lên.
String formatElapsed(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '$m:$s';
}

/// Thứ tự các giai đoạn THEO THỜI GIAN trong một lần quét (khác thứ tự enum).
const List<ScanPhase> _phaseOrder = [
  ScanPhase.reading,
  ScanPhase.matching,
  ScanPhase.exact,
  ScanPhase.embedding,
];

/// Tỉ trọng thời gian của từng giai đoạn SẼ CHẠY theo [mode], cộng lại bằng 1.
/// Giai đoạn không chạy có trọng số 0 nên không chiếm phần nào của thanh tiến độ.
/// Con số lấy từ hệ số ước tính trong scan_mode.dart (đọc+băm ~6 ms/ảnh, AI ~30 ms/ảnh).
Map<ScanPhase, double> phaseWeights(ScanMode mode) {
  if (mode.duplicates && mode.similar) {
    return {
      ScanPhase.reading: .15,
      ScanPhase.matching: .05,
      ScanPhase.exact: .10,
      ScanPhase.embedding: .70,
    };
  }
  if (mode.similar) {
    return {
      ScanPhase.reading: .20,
      ScanPhase.matching: .02,
      ScanPhase.exact: 0,
      ScanPhase.embedding: .78,
    };
  }
  // Chỉ tìm ảnh trùng. Bước AI vẫn chạy (ScanConfig.useModel) để phân xử các
  // cặp PDQ lưng chừng, nên nó PHẢI có phần trong thanh tiến độ. Để 0 thì
  // thanh đứng ở 99% suốt lúc chạy AI, còn số phần trăm của giai đoạn thì tụt
  // về 0 rồi bò lên — người dùng thấy như máy quay lại từ đầu.
  return {
    ScanPhase.reading: .50,
    ScanPhase.matching: .10,
    ScanPhase.exact: .20,
    ScanPhase.embedding: .20,
  };
}

/// Tiến độ TỔNG (0..1) của lần quét. Chỉ tăng theo giai đoạn đã xong cộng phần đang
/// chạy; giai đoạn "so khớp" không có tiến độ con nên coi là 0 cho tới khi giai đoạn
/// sau bắt đầu. Không bao giờ trả về 1: 100% chỉ có khi quét thật sự xong.
double overallProgress(ScanMode mode, ScanProgress p) {
  final w = phaseWeights(mode);
  var before = 0.0;
  for (final ph in _phaseOrder) {
    if (ph == p.phase) break;
    before += w[ph] ?? 0;
  }
  final inPhase = p.phase == ScanPhase.matching
      ? 0.0
      : (p.fraction ?? 0.0).clamp(0.0, 1.0);
  return (before + (w[p.phase] ?? 0) * inPhase).clamp(0.0, 0.99);
}
