import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Hash 256 bit kiểu PDQ: grayscale 64x64 -> DCT -> lấy 16x16 hệ số thấp
/// -> so với median -> 256 bit.
///
/// Lưu ý: đây là bản đơn giản hóa theo ý tưởng PDQ (không có Jarosz filter,
/// không có chuẩn hóa/quantize như bản gốc của Meta), nên KHÔNG tương thích
/// bit-by-bit với thư viện PDQ chính thức.
final List<Float64List> _cos = List.generate(
  16,
  (u) => Float64List.fromList(
    List.generate(64, (x) => math.cos(math.pi * (2 * x + 1) * u / 128)),
  ),
);

/// Điểm chất lượng tương ứng với ảnh "đủ chi tiết": độ dốc trung bình giữa các
/// điểm ảnh cạnh nhau, thang 0-255. Ảnh thường rơi vào 8-20; nền phẳng gần 0.
const double kPdqFullDetail = 12.0;

/// Hash kèm điểm chất lượng.
class PdqResult {
  const PdqResult(this.words, this.quality);

  final Uint64List words;

  /// 0-100. Thấp nghĩa là ảnh ít chi tiết (nền phẳng, ảnh tối, ảnh chụp màn
  /// hình gần như trắng) nên hash không ổn định: hai ảnh KHÁC nhau vẫn có thể
  /// ra bit gần giống nhau. Nơi gọi nên bỏ qua hash dưới ngưỡng khi so Hamming.
  final double quality;
}

/// Trả về 4 word 64-bit, hoặc null nếu không giải mã được ảnh.
Uint64List? pdqHash(Uint8List imageBytes) => pdqDecode(imageBytes)?.words;

/// Giải mã ảnh nén rồi băm. Đường dùng khi không có sẵn ma trận xám.
PdqResult? pdqDecode(Uint8List imageBytes) {
  final decoded = img.decodeImage(imageBytes);
  if (decoded == null) return null;
  final small = img.copyResize(
    decoded,
    width: 64,
    height: 64,
    interpolation: img.Interpolation.average,
  );

  final lum = Float64List(64 * 64);
  // Đọc thẳng buffer byte (nhanh hơn nhiều so với getPixel từng điểm); giá trị
  // luminance giống hệt đường getPixel nên hash không đổi.
  final rgb = small.format == img.Format.uint8
      ? small.getBytes(order: img.ChannelOrder.rgb)
      : null;
  if (rgb != null && rgb.length == 3 * 64 * 64) {
    for (var i = 0, j = 0; i < 64 * 64; i++, j += 3) {
      lum[i] = 0.299 * rgb[j] + 0.587 * rgb[j + 1] + 0.114 * rgb[j + 2];
    }
  } else {
    for (var y = 0; y < 64; y++) {
      for (var x = 0; x < 64; x++) {
        final p = small.getPixel(x, y);
        lum[y * 64 + x] = 0.299 * p.r + 0.587 * p.g + 0.114 * p.b;
      }
    }
  }

  return pdqFromLuma(lum);
}

/// Băm từ ma trận xám 64x64 đã có sẵn (0-255). Dùng cho đường băm ở tầng
/// native: nền tảng trả thẳng điểm ảnh nên khỏi mã hoá rồi giải mã lại JPEG.
PdqResult? pdqFromGray(Uint8List gray) {
  if (gray.length != 64 * 64) return null;
  final lum = Float64List(64 * 64);
  for (var i = 0; i < 64 * 64; i++) {
    lum[i] = gray[i].toDouble();
  }
  return pdqFromLuma(lum);
}

/// Độ dốc trung bình giữa các điểm ảnh cạnh nhau, quy về thang 0-100.
double _quality(Float64List lum) {
  var sum = 0.0;
  for (var y = 0; y < 64; y++) {
    final r = y * 64;
    for (var x = 0; x < 63; x++) {
      sum += (lum[r + x + 1] - lum[r + x]).abs();
    }
  }
  for (var y = 0; y < 63; y++) {
    final r = y * 64;
    for (var x = 0; x < 64; x++) {
      sum += (lum[r + 64 + x] - lum[r + x]).abs();
    }
  }
  final mean = sum / (64 * 63 * 2);
  final q = mean * 100 / kPdqFullDetail;
  return q > 100 ? 100 : q;
}

/// Làm mịn kiểu Jarosz (xấp xỉ): hai lượt box-filter 5 điểm, theo hàng rồi theo cột.
/// Bỏ răng cưa và nhiễu tần số cao do thu nhỏ, để hash ổn định hơn khi ảnh bị nén lại
/// hoặc đổi kích thước. Dùng chung cho mọi đường băm nên hai nền tảng cho cùng kết quả.
Float64List _jaroszSmooth(Float64List src) {
  const w = 2;
  final a = Float64List.fromList(src);
  final b = Float64List(64 * 64);
  for (var pass = 0; pass < 2; pass++) {
    for (var y = 0; y < 64; y++) {
      final r = y * 64;
      for (var x = 0; x < 64; x++) {
        var s = 0.0;
        var n = 0;
        for (var k = -w; k <= w; k++) {
          final xx = x + k;
          if (xx < 0 || xx >= 64) continue;
          s += a[r + xx];
          n++;
        }
        b[r + x] = s / n;
      }
    }
    for (var x = 0; x < 64; x++) {
      for (var y = 0; y < 64; y++) {
        var s = 0.0;
        var n = 0;
        for (var k = -w; k <= w; k++) {
          final yy = y + k;
          if (yy < 0 || yy >= 64) continue;
          s += b[yy * 64 + x];
          n++;
        }
        a[y * 64 + x] = s / n;
      }
    }
  }
  return a;
}

PdqResult pdqFromLuma(Float64List lum) {
  final quality = _quality(lum);
  final sm = _jaroszSmooth(lum);

  // DCT tách hàng/cột, chỉ tính 16 tần số thấp.
  final tmp = Float64List(64 * 16);
  for (var y = 0; y < 64; y++) {
    for (var u = 0; u < 16; u++) {
      var s = 0.0;
      final c = _cos[u];
      for (var x = 0; x < 64; x++) {
        s += sm[y * 64 + x] * c[x];
      }
      tmp[y * 16 + u] = s;
    }
  }
  final coeff = Float64List(256);
  for (var v = 0; v < 16; v++) {
    final c = _cos[v];
    for (var u = 0; u < 16; u++) {
      var s = 0.0;
      for (var y = 0; y < 64; y++) {
        s += tmp[y * 16 + u] * c[y];
      }
      coeff[v * 16 + u] = s;
    }
  }

  final sorted = Float64List.fromList(coeff)..sort();
  final median = (sorted[127] + sorted[128]) / 2;
  final words = Uint64List(4);
  for (var i = 0; i < 256; i++) {
    if (coeff[i] > median) {
      words[i >> 6] |= (1 << (i & 63));
    }
  }
  return PdqResult(words, quality);
}

int popcount64(int x) {
  x = x - ((x >>> 1) & 0x5555555555555555);
  x = (x & 0x3333333333333333) + ((x >>> 2) & 0x3333333333333333);
  x = (x + (x >>> 4)) & 0x0f0f0f0f0f0f0f0f;
  return (x * 0x0101010101010101) >>> 56;
}

/// Hamming distance giữa hash thứ [i] và [j] trong mảng phẳng (4 word/hash).
int hammingFlat(Uint64List flat, int i, int j) {
  var d = 0;
  for (var k = 0; k < 4; k++) {
    d += popcount64(flat[i * 4 + k] ^ flat[j * 4 + k]);
  }
  return d;
}

/// S_PDQ = 100 * (1 - D_H / 256). Là độ giống của bit hash, không phải % nội dung.
double pdqSimilarity(int hamming) => 100 * (1 - hamming / 256);
