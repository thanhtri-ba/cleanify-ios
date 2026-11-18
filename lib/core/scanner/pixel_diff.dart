import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Kết quả so sánh pixel hai ảnh (thu nhỏ). [differentPercent] là tỉ lệ điểm ảnh
/// khác nhau rõ rệt, KHÔNG phải độ giống PDQ; heatmap là PNG RGBA trong suốt, chỗ
/// sáng là chỗ khác.
class PixelDiff {
  const PixelDiff(this.differentPercent, this.heatmapPng);
  final double differentPercent;
  final Uint8List heatmapPng;
  double get samePercent => 100 - differentPercent;
}

const int _diffSide = 96;
const int _diffThreshold = 32; // chênh luminance (0-255) coi là "khác"

/// Chạy trong isolate qua [compute]: nhận bytes ảnh đã thu nhỏ của hai ảnh.
PixelDiff computePixelDiff(List<Uint8List> pair, {bool heatmap = true}) {
  Uint8List lum(Uint8List bytes) {
    final d = img.decodeImage(bytes);
    if (d == null) return Uint8List(_diffSide * _diffSide);
    final s = img.copyResize(d,
        width: _diffSide,
        height: _diffSide,
        interpolation: img.Interpolation.average);
    final out = Uint8List(_diffSide * _diffSide);
    for (var y = 0; y < _diffSide; y++) {
      for (var x = 0; x < _diffSide; x++) {
        final p = s.getPixel(x, y);
        out[y * _diffSide + x] =
            (0.299 * p.r + 0.587 * p.g + 0.114 * p.b).round().clamp(0, 255);
      }
    }
    return out;
  }

  final a = lum(pair[0]);
  final b = lum(pair[1]);
  final heat = img.Image(width: _diffSide, height: _diffSide, numChannels: 4);
  var diff = 0;
  for (var y = 0; y < _diffSide; y++) {
    for (var x = 0; x < _diffSide; x++) {
      final i = y * _diffSide + x;
      final d = (a[i] - b[i]).abs();
      if (d > _diffThreshold) {
        diff++;
        heat.setPixelRgba(x, y, 255, 255, 255, math.min(220, 90 + d));
      } else {
        heat.setPixelRgba(x, y, 0, 0, 0, 0);
      }
    }
  }
  return PixelDiff(100 * diff / (_diffSide * _diffSide),
      heatmap ? Uint8List.fromList(img.encodePng(heat)) : Uint8List(0));
}

/// Phần trăm điểm ảnh khác của hai ảnh (không dựng heatmap). Chạy trong isolate.
double pixelDiffPercent(List<Uint8List> pair) =>
    computePixelDiff(pair, heatmap: false).differentPercent;
