import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import 'features/home/home_page.dart';
import 'features/onboarding/onboarding_flow.dart';
import 'core/platform/scan_notifier.dart';
import 'core/scanner/photo_store.dart';
import 'features/scan/scan_controller.dart';
import 'theme/app_theme.dart';
import 'theme/appearance.dart';
import 'features/shell/app_dock.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Bộ đệm ảnh mặc định của Flutter cho tới 100 MB / 1000 ảnh đã giải mã. Lưới
  // kết quả chỉ cần vài chục ô cùng lúc nên 40 MB là dư; phần còn lại là RAM
  // chết, và là lý do app bị hệ điều hành đóng khi chuyển sang app khác.
  PaintingBinding.instance.imageCache
    ..maximumSizeBytes = 40 << 20
    ..maximumSize = 200;
  await Appearance.load();
  await PhotoStore.loadFlag();
  ScanNotifier.instance.init();
  runApp(const CleanifyApp());
}

class CleanifyApp extends StatefulWidget {
  const CleanifyApp({super.key});

  @override
  State<CleanifyApp> createState() => _CleanifyAppState();
}

class _CleanifyAppState extends State<CleanifyApp> {
  /// null = đang kiểm tra quyền; true = chưa từng được hỏi quyền Ảnh.
  /// Không lưu cờ xuống đĩa: onboarding chỉ hiện khi quyền còn notDetermined.
  bool? _showOnboarding;
  final ScanController _scan = ScanController();

  @override
  void initState() {
    super.initState();
    _checkOnboarding();
  }

  Future<void> _checkOnboarding() async {
    var show = false;
    try {
      final s = await PhotoManager.getPermissionState(
          requestOption: const PermissionRequestOption());
      show = s == PermissionState.notDetermined;
    } catch (_) {}
    if (mounted) {
      setState(() => _showOnboarding = show);
      AppDock.forceHidden.value = show;
    }
  }

  @override
  void dispose() {
    _scan.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Chế độ sáng/tối phải đi qua MaterialApp, không chỉ qua PastelScheme.
    //
    // Trước đây dòng này ghim cứng ThemeMode.light, còn Appearance chỉ được đọc
    // trong PastelScheme. Nghĩa là ở chế độ tối, ThemeData vẫn là bản SÁNG:
    // nền nằm sau Navigator, màu vòng xoay, hộp thoại và bảng trượt mặc định
    // đều lấy màu sáng. Lúc chuyển trang, dải nền lộ ra sau trang đang trượt là
    // màu sáng trên giao diện tối — thấy rõ nhất ở đáy màn hình, quanh dock.
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: Appearance.mode,
      builder: (context, mode, _) => MaterialApp(
        navigatorKey: AppDock.navigatorKey,
        navigatorObservers: [AppDock.observer],
        // Giới hạn chữ lớn của iOS ở 1,4 lần: vẫn dễ đọc hơn nhưng bố cục không vỡ.
        builder: (context, child) => MediaQuery.withClampedTextScaling(
          minScaleFactor: 1.0,
          maxScaleFactor: 1.4,
          child: DockShell(child: child ?? const SizedBox.shrink()),
        ),
        title: 'Cleanify',
        debugShowCheckedModeBanner: false,
        themeMode: mode,
        theme: buildAppTheme(Brightness.light),
        darkTheme: buildAppTheme(Brightness.dark),
        home: switch (_showOnboarding) {
          null => const Scaffold(),
          true => OnboardingFlow(onFinished: () {
              setState(() => _showOnboarding = false);
              AppDock.forceHidden.value = false;
            }),
          false => HomePage(controller: _scan),
        },
      ),
    );
  }
}
