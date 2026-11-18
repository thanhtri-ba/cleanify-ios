import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Cầu nối tới thư viện ảnh của hệ điều hành: dung lượng máy, dung lượng từng
/// file, ảnh chụp màn hình, ảnh đã chỉnh sửa, và thumbnail của BẢN GỐC.
/// iOS dùng PhotoKit (AppDelegate.swift), Android dùng MediaStore + StatFs
/// (MainActivity.kt). Hai bên cùng một tên kênh và cùng hợp đồng.
///
/// Khác biệt duy nhất: Android không giữ bản gốc bên trong ảnh đã chỉnh, nên
/// [originalThumbs] luôn rỗng ở đó — xem [hasOriginalVersions].
class PhotoEdits {
  static const _ch = MethodChannel('cleanify/photo_edits');

  bool get supported => Platform.isIOS || Platform.isAndroid;

  /// Hệ điều hành có giữ BẢN GỐC của ảnh đã chỉnh sửa hay không. Chỉ iOS có:
  /// PhotoKit lưu bản gốc trong cùng asset. Android chỉnh là ghi đè, không
  /// lấy lại được, nên bỏ qua bước băm bản gốc cho nhanh.
  bool get hasOriginalVersions => Platform.isIOS;

  /// Trong [ids], những ảnh đã chỉnh sửa. iOS đọc cờ chỉnh sửa của PhotoKit nên
  /// chắc chắn; Android suy đoán theo ngày sửa file nên có thể thừa vài ảnh.
  Future<Set<String>> editedIds(List<String> ids) async {
    if (!supported || ids.isEmpty) return {};
    final r = await _ch.invokeListMethod<String>('editedIds', {'ids': ids});
    return {...?r};
  }

  /// Tổng và còn trống của bộ nhớ máy (byte); null nếu không đọc được.
  Future<({int total, int free})?> storage() async {
    if (!supported) return null;
    final r = await _ch.invokeMapMethod<String, int>('storage', {'ids': <String>[]});
    final t = r?['total'];
    final f = r?['free'];
    if (t == null || f == null) return null;
    return (total: t, free: f);
  }

  /// Id của mọi ảnh chụp màn hình, mới nhất trước.
  Future<List<String>> screenshotIds() async {
    if (!supported) return [];
    final r = await _ch
        .invokeListMethod<String>('screenshotIds', {'ids': <String>[]});
    return r ?? [];
  }

  /// Dung lượng file (byte) theo id, đọc từ metadata (không tải iCloud). Id không
  /// lấy được thì không có trong kết quả hoặc bằng 0.
  Future<Map<String, int>> fileSizes(List<String> ids) async {
    if (!supported || ids.isEmpty) return {};
    final r = await _ch.invokeMapMethod<String, int>('fileSizes', {'ids': ids});
    if (kDebugMode) {
      debugPrint('[sizes] hỏi ${ids.length}, nhận ${r?.length ?? -1}');
    }
    return r ?? {};
  }

  /// Chữ ký MediaStore của mọi ảnh: id -> (dung lượng, thế hệ).
  ///
  /// Thế hệ là GENERATION_MODIFIED của MediaStore (Android 11+), bằng 0 nếu máy
  /// không có. Một lần truy vấn cho cả thư viện, không mở file. Lỗi hoặc không
  /// phải Android thì trả map rỗng: người gọi lùi về so ngày sửa + kích thước.
  Future<Map<String, ({int size, int gen})>> signatures() async {
    if (!Platform.isAndroid) return {};
    final r = await _ch.invokeMapMethod<String, String>(
        'signatures', {'ids': <String>[]});
    final out = <String, ({int size, int gen})>{};
    r?.forEach((id, v) {
      final k = v.indexOf('|');
      if (k <= 0) return;
      final size = int.tryParse(v.substring(0, k)) ?? 0;
      final gen = int.tryParse(v.substring(k + 1)) ?? 0;
      if (size > 0) out[id] = (size: size, gen: gen);
    });
    return out;
  }

  /// SHA-256 (hex) của FILE GỐC theo id, băm thẳng trong hệ điều hành.
  ///
  /// Đường cũ là `AssetEntity.originFile`: photo_manager CHÉP ảnh ra thư mục
  /// cache rồi Dart mới đọc lại để băm, xong phải xoá bản chép. Một ảnh 10 MB
  /// vì thế tốn 10 MB đọc + 10 MB ghi + 10 MB đọc lại. Ở đây hệ điều hành mở
  /// thẳng luồng đọc và băm tại chỗ: cùng một con số SHA-256, một lượt đọc.
  ///
  /// Chỉ Android. iOS vẫn đi đường cũ (PhotoKit không cho đọc thẳng như vậy).
  /// Id nào không đọc được thì không có trong kết quả, và người gọi tự lùi về
  /// đường cũ cho những id đó.
  Future<Map<String, String>> sha256Of(List<String> ids) async {
    if (!Platform.isAndroid || ids.isEmpty) return {};
    final r = await _ch.invokeMapMethod<String, String>('sha256', {'ids': ids});
    return r ?? {};
  }

  /// JPEG thumbnail bản gốc theo id. Ảnh không lấy được (vd. còn trên iCloud)
  /// không có trong kết quả. Android luôn trả rỗng ([hasOriginalVersions]).
  Future<Map<String, Uint8List>> originalThumbs(List<String> ids,
      {int size = 128}) async {
    if (!hasOriginalVersions || ids.isEmpty) return {};
    final r = await _ch.invokeMapMethod<String, Uint8List>(
        'originalThumbs', {'ids': ids, 'size': size});
    return r ?? {};
  }
}
