import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:image/image.dart' as img;

/// Phân đoạn người: ảnh -> mặt nạ 256x256 (1 = người, 0 = nền).
///
/// Dùng để so hình dạng người giữa hai ảnh và bỏ qua nền. Chuyển động nhỏ của
/// người làm mặt nạ thay đổi ít, nên IoU vẫn cao. Model xuất bằng
/// tool/export_person_seg.py và đặt tại [personAsset].
///
/// Nếu chưa có file model, [load] trả false và mọi hàm khác trả null: app chạy
/// y như trước, không lỗi.
const String personAsset = 'assets/models/person_seg.onnx';
const int personSize = 256;

const _mean = [0.485, 0.456, 0.406];
const _std = [0.229, 0.224, 0.225];

class PersonSegmenter {
  OrtSession? _session;
  String _inName = '';
  String _outName = '';

  bool get available => _session != null;

  /// Trả true nếu model đã sẵn sàng. Thiếu file hoặc lỗi runtime đều trả false.
  Future<bool> load() async {
    if (_session != null) return true;
    try {
      await rootBundle.load(personAsset); // ném lỗi nếu thiếu file
      final s = await OnnxRuntime().createSessionFromAsset(personAsset);
      _session = s;
      _inName = s.inputNames.first;
      _outName = s.outputNames.first;
      return true;
    } catch (_) {
      _session = null;
      return false;
    }
  }

  /// Mặt nạ người của một ảnh JPEG/PNG; null nếu không có model hoặc lỗi.
  Future<Uint8List?> maskOf(Uint8List bytes) async {
    final s = _session;
    if (s == null) return null;
    OrtValue? tensor;
    Map<String, OrtValue>? outs;
    try {
      final input = _preprocess(bytes);
      if (input == null) return null;
      tensor = await OrtValue.fromList(
          input, [1, 3, personSize, personSize]);
      outs = await s.run({_inName: tensor});
      final values = <double>[];
      _flatten(await outs[_outName]!.asList(), values);
      const plane = personSize * personSize;
      if (values.length < plane) return null;
      // Đầu ra là logit; dương nghĩa là người.
      final mask = Uint8List(plane);
      for (var i = 0; i < plane; i++) {
        mask[i] = values[values.length - plane + i] > 0 ? 1 : 0;
      }
      return mask;
    } catch (_) {
      return null;
    } finally {
      await tensor?.dispose();
      if (outs != null) {
        for (final o in outs.values) {
          await o.dispose();
        }
      }
    }
  }

  Future<void> close() async {
    final s = _session;
    _session = null;
    await s?.close();
  }

  static Float32List? _preprocess(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    final rgb = decoded.numChannels == 3 ? decoded : decoded.convert(numChannels: 3);
    final small = img.copyResize(
      rgb,
      width: personSize,
      height: personSize,
      interpolation: img.Interpolation.average,
    );
    const plane = personSize * personSize;
    final out = Float32List(3 * plane);
    for (var y = 0; y < personSize; y++) {
      for (var x = 0; x < personSize; x++) {
        final p = small.getPixel(x, y);
        final i = y * personSize + x;
        out[i] = (p.r / 255.0 - _mean[0]) / _std[0];
        out[plane + i] = (p.g / 255.0 - _mean[1]) / _std[1];
        out[2 * plane + i] = (p.b / 255.0 - _mean[2]) / _std[2];
      }
    }
    return out;
  }

  static void _flatten(Object? v, List<double> out) {
    if (v is num) {
      out.add(v.toDouble());
    } else if (v is List) {
      for (final e in v) {
        _flatten(e, out);
      }
    }
  }
}

/// IoU của hai mặt nạ cùng kích thước: |A ∩ B| / |A ∪ B|. Mặt nạ rỗng cả hai
/// thì trả 0 (không có người để so).
double maskIou(Uint8List a, Uint8List b) {
  if (a.length != b.length) return 0;
  var inter = 0;
  var union = 0;
  for (var i = 0; i < a.length; i++) {
    final x = a[i] != 0;
    final y = b[i] != 0;
    if (x && y) inter++;
    if (x || y) union++;
  }
  return union == 0 ? 0 : inter / union;
}
