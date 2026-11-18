import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

/// Chế độ giao diện của trang chủ và màn quét: theo hệ thống, luôn sáng hoặc luôn tối.
/// Lưu bằng một file nhỏ trong thư mục dữ liệu app (không cần thêm thư viện mới).
class Appearance {
  Appearance._();
  static final ValueNotifier<ThemeMode> mode = ValueNotifier(ThemeMode.system);

  static Future<File?> _file() async {
    try {
      final d = await getApplicationSupportDirectory();
      return File('${d.path}/appearance.txt');
    } catch (_) {
      return null; // Môi trường test không có path_provider.
    }
  }

  static Future<void> load() async {
    try {
      final f = await _file();
      if (f == null || !await f.exists()) return;
      final v = (await f.readAsString()).trim();
      mode.value = ThemeMode.values
          .firstWhere((m) => m.name == v, orElse: () => ThemeMode.system);
    } catch (_) {}
  }

  static Future<void> set(ThemeMode m) async {
    mode.value = m;
    try {
      final f = await _file();
      await f?.writeAsString(m.name);
    } catch (_) {}
  }

  /// Tự động -> Sáng -> Tối -> Tự động.
  static ThemeMode next(ThemeMode m) => switch (m) {
        ThemeMode.system => ThemeMode.light,
        ThemeMode.light => ThemeMode.dark,
        ThemeMode.dark => ThemeMode.system,
      };

  static String label(ThemeMode m) => switch (m) {
        ThemeMode.system => 'Tự động',
        ThemeMode.light => 'Sáng',
        ThemeMode.dark => 'Tối',
      };
}
