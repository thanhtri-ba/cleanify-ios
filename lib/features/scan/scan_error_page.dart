import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_icon.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_theme.dart';
import '../../theme/pastel_scheme.dart';
import 'scan_controller.dart';
import 'smart_scan_page.dart';

/// Màn "Quét chưa hoàn tất": nói rõ không có gì bị xóa và cho thử lại.
class ScanErrorPage extends StatelessWidget {
  const ScanErrorPage({super.key, required this.controller});
  final ScanController controller;

  void _home(BuildContext context) =>
      Navigator.of(context).popUntil((r) => r.isFirst);

  @override
  Widget build(BuildContext context) {
    final t = PastelScheme.of(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: t.dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: t.page,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, box) => SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: box.maxHeight),
                child: IntrinsicHeight(
                  child: Column(children: [
                    const Spacer(flex: 2),
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0.6, end: 1),
                      duration: const Duration(milliseconds: 700),
                      curve: Curves.easeOutBack,
                      builder: (_, v, child) =>
                          Transform.scale(scale: v, child: child),
                      child: Container(
                        width: 130,
                        height: 130,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                              colors: [t.amberBg, t.amberBg2],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight),
                          boxShadow: const [
                            BoxShadow(
                                color: Color(0x33808080), spreadRadius: 12)
                          ],
                        ),
                        child: Center(
                          child: AppIcon(AppIcons.warningAmberRounded,
                              size: 56,
                              color: t.amberText,
                              accent: t.amberText),
                        ),
                      ),
                    ),
                    const SizedBox(height: 30),
                    Text('Quét chưa hoàn tất',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w500,
                            letterSpacing: -0.4,
                            color: t.ink)),
                    const SizedBox(height: 8),
                    Text(
                        'Quá trình quét bị dừng giữa chừng. Ảnh của bạn vẫn nguyên vẹn, '
                        'không có gì bị xóa.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 14, height: 1.5, color: t.mute)),
                    const SizedBox(height: 22),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: t.glass,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: t.glassBorder),
                      ),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Chi tiết',
                                style: TextStyle(fontSize: 11, color: t.mute)),
                            const SizedBox(height: 4),
                            Text(
                                controller.error ??
                                    'Thư viện ảnh tạm thời không khả dụng. Hãy thử lại sau giây lát.',
                                style: TextStyle(
                                    fontSize: 13, height: 1.5, color: t.ink)),
                          ]),
                    ),
                    const Spacer(flex: 3),
                    GestureDetector(
                      onTap: () {
                        controller.start();
                        Navigator.of(context).pushReplacement(MaterialPageRoute(
                            settings: const RouteSettings(name: 'nodock'),
                            builder: (_) =>
                                SmartScanPage(controller: controller)));
                      },
                      child: Container(
                        height: 58,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: t.dark ? const Color(0xFFF2F2F2) : Pastel.ink,
                          borderRadius: BorderRadius.circular(29),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          AppIcon(AppIcons.refreshRounded,
                              size: 20,
                              color: t.dark ? Pastel.ink : Colors.white,
                              accent: t.dark ? Pastel.ink : Colors.white),
                          const SizedBox(width: 8),
                          Text('Thử lại',
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: t.dark ? Pastel.ink : Colors.white)),
                        ]),
                      ),
                    ),
                    TextButton(
                      onPressed: () => _home(context),
                      child: Text('Về trang chủ',
                          style: TextStyle(fontSize: 14, color: t.mute)),
                    ),
                    const SizedBox(height: 90),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
