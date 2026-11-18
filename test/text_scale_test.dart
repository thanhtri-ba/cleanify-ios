import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cleanify/features/home/home_page.dart';
import 'package:cleanify/features/onboarding/onboarding_flow.dart';
import 'package:cleanify/features/scan/scan_complete_page.dart';
import 'package:cleanify/features/scan/scan_controller.dart';
import 'package:cleanify/features/scan/scan_error_page.dart';
import 'package:cleanify/features/scan/smart_scan_page.dart';
import 'package:cleanify/features/storage/storage_page.dart';
import 'package:cleanify/theme/appearance.dart';

/// Chữ lớn (Dynamic Type) ở mức tối đa app cho phép (1,4x): các trang phải dựng được
/// và không tràn ở cả hai chế độ sáng/tối.
Future<void> pumpScaled(
    WidgetTester tester, Widget page, Size size, double scale) async {
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: page,
  ));
  await tester.pump(const Duration(seconds: 2));
}

void main() {
  const sizes = [Size(390, 844), Size(375, 667)];
  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    for (final size in sizes) {
      final tag =
          '${mode.name} ${size.width.toInt()}x${size.height.toInt()} x1.4';

      void run(String name, Widget Function(ScanController c) make) {
        testWidgets('$name chữ lớn không tràn ($tag)', (tester) async {
          Appearance.mode.value = mode;
          addTearDown(() => Appearance.mode.value = ThemeMode.system);
          final c = ScanController();
          addTearDown(c.dispose);
          await pumpScaled(tester, make(c), size, 1.4);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        });
      }

      run('Trang chủ', (c) => HomePage(controller: c));
      run(
          'Bộ nhớ',
          (c) => StoragePage(
                total: 58100000000,
                free: 16300000000,
                photoBytes: 24600000000,
                videoBytes: 11300000000,
                photos: 3340,
                videos: 182,
                onLargeVideos: () {},
                onScreenshots: () {},
              ));
      run('Kết quả quét', (c) => ScanCompletePage(controller: c));
      run('Quét lỗi', (c) => ScanErrorPage(controller: c));
      run('Đang quét', (c) => SmartScanPage(controller: c));
      run('Hướng dẫn', (c) => OnboardingFlow(onFinished: () {}));
    }
  }
}
