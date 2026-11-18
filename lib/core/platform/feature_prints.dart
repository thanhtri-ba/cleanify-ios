import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart';

/// Vector đặc trưng của Vision (VNGenerateImageFeaturePrintRequest), chỉ iOS.
///
/// Đây là cách Apple đo độ giống nội dung của hai ảnh mà không cần file model:
/// hệ điều hành đã có sẵn. Khác PDQ, vector này vẫn gần nhau khi khung hình hơi
/// lệch, nên dùng cho nhóm "giống". Ngưỡng khoảng cách phải hiệu chỉnh bằng ảnh
/// thật trước khi dùng để gom nhóm.
class FeaturePrints {
  FeaturePrints._();

  static const _ch = MethodChannel('cleanify/photo_edits');

  static bool get supported => Platform.isIOS;

  /// Vector của từng ảnh theo id. Ảnh không lấy được thì không có trong kết quả.
  static Future<Map<String, Float32List>> of(List<String> ids) async {
    if (!supported || ids.isEmpty) return {};
    final r = await _ch.invokeMapMethod<String, Uint8List>(
        'featurePrints', {'ids': ids});
    final out = <String, Float32List>{};
    r?.forEach((id, bytes) {
      if (bytes.isEmpty || bytes.lengthInBytes % 4 != 0) return;
      // Sao chép sang Float32List mới: buffer từ kênh có thể không căn đúng 4 byte.
      final bd = ByteData.sublistView(bytes);
      final v = Float32List(bytes.lengthInBytes ~/ 4);
      for (var k = 0; k < v.length; k++) {
        v[k] = bd.getFloat32(k * 4, Endian.little);
      }
      out[id] = v;
    });
    return out;
  }
}

/// Khoảng cách Euclid giữa hai vector đặc trưng. Khác độ dài thì trả vô cực.
double featureDistance(Float32List a, Float32List b) {
  if (a.length != b.length) return double.infinity;
  var s = 0.0;
  for (var k = 0; k < a.length; k++) {
    final d = a[k] - b[k];
    s += d * d;
  }
  return math.sqrt(s);
}
