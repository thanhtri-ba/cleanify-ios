import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cleanify/features/scan/cleaning_page.dart';
import 'package:cleanify/features/scan/scan_error_page.dart';
import 'package:cleanify/features/scan/scan_options_sheet.dart';
import 'package:cleanify/features/scan/smart_scan_page.dart';
import 'package:cleanify/features/shell/app_dock.dart';
import 'package:cleanify/features/shell/page_kit.dart';
import 'package:cleanify/features/scan/scan_complete_page.dart';
import 'package:cleanify/features/scan/scan_controller.dart';
import 'package:cleanify/features/storage/storage_page.dart';
import 'package:cleanify/theme/appearance.dart';

Future<void> show(WidgetTester tester, Widget page, Size size) async {
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: page));
  await tester.pump(const Duration(seconds: 2));
}

void main() {
  const sizes = [Size(390, 844), Size(375, 667), Size(320, 568)];
  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    for (final size in sizes) {
      final tag = '${mode.name} ${size.width.toInt()}x${size.height.toInt()}';

      testWidgets('Bộ nhớ dựng được, không tràn ($tag)', (tester) async {
        Appearance.mode.value = mode;
        addTearDown(() => Appearance.mode.value = ThemeMode.system);
        await show(
            tester,
            StoragePage(
              total: 58100000000,
              free: 16300000000,
              photoBytes: 24600000000,
              videoBytes: 11300000000,
              photos: 3340,
              videos: 182,
              onLargeVideos: () {},
              onScreenshots: () {},
            ),
            size);
        expect(find.text('Bộ nhớ'), findsWidgets);
        expect(find.text('Video lớn'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('Kết quả quét dựng được, không tràn ($tag)', (tester) async {
        Appearance.mode.value = mode;
        addTearDown(() => Appearance.mode.value = ThemeMode.system);
        final c = ScanController();
        addTearDown(c.dispose);
        await show(tester, ScanCompletePage(controller: c), size);
        expect(find.text('Kết quả quét'), findsWidgets);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('Đang dọn: xong ngay khi không có ảnh nào', (tester) async {
    final c = ScanController();
    addTearDown(c.dispose);
    await show(tester, CleaningPage(controller: c, assets: const []),
        const Size(390, 844));
    expect(find.text('Đã dọn xong'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Quét lỗi: có Thử lại và nói rõ không xóa gì', (tester) async {
    final c = ScanController();
    addTearDown(c.dispose);
    await show(tester, ScanErrorPage(controller: c), const Size(390, 844));
    expect(find.text('Quét chưa hoàn tất'), findsOneWidget);
    expect(find.text('Thử lại'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Bảng chọn chế độ quét mở được và ẩn dock', (tester) async {
    await tester.pumpWidget(MaterialApp(
      navigatorKey: AppDock.navigatorKey,
      navigatorObservers: [AppDock.observer],
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => showScanOptions(context, photos: 2000),
              child: const Text('mo'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('mo'));
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.text('Chọn chế độ quét'), findsOneWidget);
    expect(find.text('Bắt đầu quét'), findsOneWidget);
    expect(AppDock.pageHidden.value, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Hộp thoại xác nhận xóa: cần tick mới xóa được', (tester) async {
    bool? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () async {
                result = await showConfirmDialog(context,
                    title: 'Xóa 4 ảnh?',
                    message: 'Mỗi nhóm giữ lại ít nhất 1 ảnh.',
                    warning: '2 ảnh yêu thích nằm trong lựa chọn.',
                    tickLabel: 'Tôi đã xem lại các ảnh này',
                    confirmLabel: 'Xóa 4 ảnh');
              },
              child: const Text('mo'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('mo'));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Xóa 4 ảnh?'), findsOneWidget);
    // Chưa tick: bấm Xóa không đóng hộp thoại.
    await tester.tap(find.text('Xóa 4 ảnh'));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Xóa 4 ảnh?'), findsOneWidget);
    await tester.tap(find.text('Tôi đã xem lại các ảnh này'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Xóa 4 ảnh'));
    await tester.pump(const Duration(milliseconds: 600));
    expect(result, isTrue);
  });

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    for (final size in const [Size(390, 844), Size(375, 667), Size(320, 568)]) {
      testWidgets(
          'Trang quét dựng được, không tràn (${mode.name} ${size.width.toInt()}x${size.height.toInt()})',
          (tester) async {
        Appearance.mode.value = mode;
        addTearDown(() => Appearance.mode.value = ThemeMode.system);
        final c = ScanController();
        addTearDown(c.dispose);
        tester.view.physicalSize = size * 2;
        tester.view.devicePixelRatio = 2;
        addTearDown(tester.view.reset);
        await tester
            .pumpWidget(MaterialApp(home: SmartScanPage(controller: c)));
        await tester.pump(const Duration(milliseconds: 800));
        expect(find.text('Báo khi quét xong'), findsNothing);
        expect(find.text('Ảnh đã đọc'), findsOneWidget);
        expect(find.text('Nhóm tìm thấy'), findsOneWidget);
        expect(find.text('Tạm dừng'), findsOneWidget);
        expect(tester.takeException(), isNull);
        // Gỡ trang để hủy Timer định kỳ trước khi test kết thúc.
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}
