import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cleanify/features/home/home_page.dart';
import 'package:cleanify/features/scan/scan_controller.dart';
import 'package:cleanify/features/shell/app_dock.dart';
import 'package:cleanify/theme/appearance.dart';

Future<void> pumpHome(WidgetTester tester, ScanController c) async {
  await tester.pumpWidget(MaterialApp(home: HomePage(controller: c)));
  await tester.pump(const Duration(seconds: 2));
}

void main() {
  testWidgets('Home chưa quét: tiêu đề, bộ nhớ, gợi ý và nút quét',
      (tester) async {
    final c = ScanController();
    addTearDown(c.dispose);
    await pumpHome(tester, c);
    expect(find.textContaining('Cleanify'), findsWidgets);
    expect(find.text('Chưa quét'), findsWidgets);
    expect(find.textContaining('Bộ nhớ'), findsWidgets);
    await tester.drag(
        find.byType(SingleChildScrollView).first, const Offset(0, -1200));
    await tester.pump();
    expect(find.text('Quét ảnh & video'), findsOneWidget);
  });

  testWidgets(
      'Dock cố định ở mọi trang: có ở trang chủ và trang con, ẩn ở trang nodock',
      (tester) async {
    AppDock.forceHidden.value = false;
    addTearDown(() => AppDock.forceHidden.value = true);
    final c = ScanController();
    addTearDown(c.dispose);
    await tester.pumpWidget(MaterialApp(
      navigatorKey: AppDock.navigatorKey,
      navigatorObservers: [AppDock.observer],
      builder: (context, child) => DockShell(child: child!),
      home: HomePage(controller: c),
    ));
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Trang chủ'), findsOneWidget);
    expect(AppDock.pageHidden.value, isFalse);
    // VoiceOver: nút + và các tab có nhãn đọc được.
    final sem = tester.ensureSemantics();
    expect(find.bySemanticsLabel('Mở bảng công cụ'), findsOneWidget);
    expect(find.bySemanticsLabel('Cài đặt'), findsWidgets);
    sem.dispose();
    // Dock nằm ngoài Scaffold: chữ không được dính gạch chân vàng của kiểu mặc định.
    final style =
        DefaultTextStyle.of(tester.element(find.text('Trang chủ'))).style;
    expect(style.decoration == null || style.decoration == TextDecoration.none,
        isTrue);

    // Trang con thường: dock vẫn còn.
    AppDock.navigatorKey.currentState!.push(MaterialPageRoute(
        settings: const RouteSettings(name: 'tab:2'),
        builder: (_) => const Scaffold(body: Text('Trang con'))));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Trang con'), findsOneWidget);
    expect(AppDock.tab.value, 2);
    expect(find.text('Bộ nhớ'), findsWidgets);

    // Trang toàn màn hình: dock bị ẩn.
    AppDock.navigatorKey.currentState!.push(MaterialPageRoute(
        settings: const RouteSettings(name: 'nodock'),
        builder: (_) => const Scaffold(body: Text('Đang quét'))));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(AppDock.pageHidden.value, isTrue);

    // Về trang chủ: dock hiện lại, tab Trang chủ sáng.
    AppDock.navigatorKey.currentState!.popUntil((r) => r.isFirst);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(AppDock.pageHidden.value, isFalse);
    expect(AppDock.tab.value, 0);
  });

  testWidgets('Chuyển tab trực tiếp: trang cũ bị gỡ, không quay về trang chủ',
      (tester) async {
    AppDock.resetForTest();
    AppDock.forceHidden.value = false;
    addTearDown(() => AppDock.forceHidden.value = true);
    final c = ScanController();
    addTearDown(c.dispose);
    await tester.pumpWidget(MaterialApp(
      navigatorKey: AppDock.navigatorKey,
      navigatorObservers: [AppDock.observer],
      builder: (context, child) => DockShell(child: child!),
      home: const Scaffold(body: Text('Trang chủ gốc')),
    ));
    final nav = AppDock.navigatorKey.currentState!;
    nav.push(MaterialPageRoute(
        settings: const RouteSettings(name: 'tab:3'),
        builder: (_) => const Scaffold(body: Text('Cài đặt giả'))));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Cài đặt giả'), findsOneWidget);

    AppDock.goReplace(() => nav.push(MaterialPageRoute(
        settings: const RouteSettings(name: 'tab:2'),
        builder: (_) => const Scaffold(body: Text('Bộ nhớ giả')))));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    // Trang mới đã mở; sau đó trang Cài đặt cũ bị gỡ êm.
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Bộ nhớ giả'), findsOneWidget);
    expect(find.text('Cài đặt giả', skipOffstage: false), findsNothing);
    expect(AppDock.tab.value, 2);
    // Quay lại thì về trang chủ (ngăn xếp chỉ còn [gốc, Bộ nhớ]).
    expect(AppDock.routeNames, ['/', 'tab:2']);
    nav.pop();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Trang chủ gốc'), findsOneWidget);
  });

  testWidgets('Bấm + mở bảng công cụ', (tester) async {
    AppDock.forceHidden.value = false;
    addTearDown(() => AppDock.forceHidden.value = true);
    final c = ScanController();
    addTearDown(c.dispose);
    await tester.pumpWidget(MaterialApp(
      navigatorKey: AppDock.navigatorKey,
      navigatorObservers: [AppDock.observer],
      builder: (context, child) => DockShell(child: child!),
      home: HomePage(controller: c),
    ));
    await tester.pump(const Duration(seconds: 2));
    final plus = find
        .byWidgetPredicate((w) =>
            w is GestureDetector && w.onTap != null && w.behavior == null)
        .last;
    await tester.tap(plus);
    await tester.pump(const Duration(milliseconds: 900));
    expect(find.text('Video lớn'), findsOneWidget);
    expect(find.text('Riêng tư'), findsOneWidget);
  });

  testWidgets('Toast hiện ở đầu màn hình và tự biến mất', (tester) async {
    final c = ScanController();
    addTearDown(c.dispose);
    await tester.pumpWidget(MaterialApp(
      navigatorKey: AppDock.navigatorKey,
      navigatorObservers: [AppDock.observer],
      home: HomePage(controller: c),
    ));
    await tester.pump(const Duration(seconds: 2));
    AppDock.say('Hãy quét trước để xem ảnh trùng.', warn: true);
    await tester.pump(const Duration(milliseconds: 700));
    final f = find.text('Hãy quét trước để xem ảnh trùng.');
    expect(f, findsOneWidget);
    expect(tester.getTopLeft(f).dy < 200, isTrue);
    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(milliseconds: 400));
    expect(f, findsNothing);
  });

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('Home dựng được ở chế độ ${mode.name}', (tester) async {
      Appearance.mode.value = mode;
      addTearDown(() => Appearance.mode.value = ThemeMode.system);
      final c = ScanController();
      addTearDown(c.dispose);
      await pumpHome(tester, c);
      expect(tester.takeException(), isNull);
    });
  }

  for (final size in const [Size(390, 844), Size(375, 667), Size(320, 568)]) {
    testWidgets(
        'Home không tràn ở ${size.width.toInt()}x${size.height.toInt()}',
        (tester) async {
      tester.view.physicalSize = size * 2;
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final c = ScanController();
      addTearDown(c.dispose);
      await pumpHome(tester, c);
      expect(tester.takeException(), isNull);
    });
  }
}
