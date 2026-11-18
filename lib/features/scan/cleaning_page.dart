import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show HapticFeedback, SystemUiOverlayStyle;
import 'package:photo_manager/photo_manager.dart';

import '../../theme/app_theme.dart';
import '../../theme/scan_ring.dart';
import 'scan_controller.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_icon.dart';

/// Màn "Đang dọn dung lượng" (Figma 1:629). Chỉ được mở sau khi người dùng đã
/// xác nhận ở [ScanCompletePage]. Xóa theo lô để có thể tạm dừng giữa các lô;
/// mỗi lô iOS hiện một hộp thoại xác nhận của hệ thống.
class CleaningPage extends StatefulWidget {
  const CleaningPage(
      {super.key, required this.controller, required this.assets});
  final ScanController controller;
  final List<AssetEntity> assets;
  @override
  State<CleaningPage> createState() => _CleaningPageState();
}

class _CleaningPageState extends State<CleaningPage> {
  static const _batch = 500;
  int _deleted = 0;
  bool _paused = false;
  bool _finished = false;
  bool _failed = false;

  int get _total => widget.assets.length;
  double get _frac => _total == 0 ? 1 : _deleted / _total;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    try {
      var i = _deleted;
      while (i < _total) {
        while (_paused && mounted) {
          await Future<void>.delayed(const Duration(milliseconds: 200));
        }
        if (!mounted) return;
        final chunk = widget.assets.sublist(i, math.min(i + _batch, _total));
        final n = await widget.controller.deleteAssets(chunk);
        if (n == 0) {
          // Người dùng từ chối hộp thoại hệ thống: dừng, không thử lại ngầm.
          setState(() => _failed = true);
          return;
        }
        i += chunk.length;
        if (mounted) setState(() => _deleted += n);
      }
      if (mounted) {
        HapticFeedback.mediumImpact();
        setState(() => _finished = true);
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final stopped = _finished || _failed;
    final pct = (_frac * 100).round();
    return PopScope(
      canPop: stopped,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Scaffold(
          backgroundColor: Pastel.night,
          body: Stack(children: [
            // Vầng sáng sau vòng tiến độ.
            Positioned(
              top: 100,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: Center(
                  child: Container(
                    width: 290,
                    height: 290,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(colors: [
                        const Color(0x33FFFFFF)
                            .withValues(alpha: _finished ? 0.5 : 0.35),
                        const Color(0x14FFFFFF),
                        const Color(0x00000000),
                      ], stops: const [
                        0,
                        0.55,
                        1
                      ]),
                    ),
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Column(children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  child: Row(children: [
                    Opacity(
                      opacity: stopped ? 1 : 0,
                      child: Material(
                        color: Pastel.night3,
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: stopped
                              ? () => Navigator.of(context)
                                  .popUntil((r) => r.isFirst)
                              : null,
                          child: const SizedBox(
                              width: 42,
                              height: 42,
                              child: AppIcon(AppIcons.close,
                                  label: 'Đóng',
                                  size: 18,
                                  color: Colors.white,
                                  accent: Colors.white)),
                        ),
                      ),
                    ),
                    const Expanded(
                      child: Text('Đang dọn dung lượng',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.1,
                              color: Colors.white)),
                    ),
                    const SizedBox(width: 42),
                  ]),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(22, 24, 22, 16),
                    children: [
                      Center(
                        child: SizedBox(
                          width: 220,
                          height: 220,
                          child: TweenAnimationBuilder<double>(
                            tween: Tween(end: _frac),
                            duration: const Duration(milliseconds: 400),
                            curve: Curves.easeOut,
                            builder: (context, f, _) => CustomPaint(
                              painter: ScanRingPainter(f, width: 14),
                              child: Center(
                                child: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 350),
                                  transitionBuilder: (child, a) =>
                                      FadeTransition(
                                    opacity: a,
                                    child: ScaleTransition(
                                        scale: CurvedAnimation(
                                            parent: a,
                                            curve: Curves.easeOutBack),
                                        child: child),
                                  ),
                                  child: _finished
                                      ? Container(
                                          key: const ValueKey('ok'),
                                          width: 120,
                                          height: 120,
                                          decoration: const BoxDecoration(
                                              shape: BoxShape.circle,
                                              gradient: LinearGradient(colors: [
                                                Color(0xFFFFFFFF),
                                                Color(0xFFBDBDBD)
                                              ])),
                                          child: const Center(
                                              child: AppIcon(
                                                  AppIcons.checkRounded,
                                                  size: 60,
                                                  color: Pastel.ink,
                                                  accent: Pastel.ink)),
                                        )
                                      : Column(
                                          key: const ValueKey('pct'),
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                              Text('${(f * 100).round()}%',
                                                  style: const TextStyle(
                                                      fontSize: 52,
                                                      height: 1.12,
                                                      fontWeight:
                                                          FontWeight.w400,
                                                      letterSpacing: -1.4,
                                                      color: Colors.white)),
                                              const SizedBox(height: 6),
                                              Text(
                                                  _failed
                                                      ? 'ĐÃ DỪNG'
                                                      : 'ĐANG DỌN',
                                                  style: const TextStyle(
                                                      fontSize: 11,
                                                      letterSpacing: 1.2,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      color: Pastel.nightMute)),
                                            ]),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 26),
                      Text(
                          _finished
                              ? 'Đã dọn xong'
                              : 'Dọn chỗ cho điều quan trọng',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.4,
                              color: Colors.white)),
                      const SizedBox(height: 6),
                      Text(
                          _failed
                              ? 'Bạn đã từ chối xác nhận hoặc có lỗi. Ảnh còn lại vẫn được giữ nguyên.'
                              : (_finished
                                  ? 'Các ảnh đã chọn đã được xóa.'
                                  : 'Đang xử lý ảnh đã xác nhận'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 14,
                              height: 1.4,
                              color: Pastel.nightMute)),
                      const SizedBox(height: 26),
                      Row(children: [
                        _stat('$_deleted', 'Đã xóa', Colors.white),
                        const SizedBox(width: 8),
                        _stat('$_total', 'Ảnh đã chọn', Colors.white),
                        const SizedBox(width: 8),
                        _stat('${_total - _deleted}', 'Còn lại',
                            const Color(0xFFBDBDBD)),
                      ]),
                      const SizedBox(height: 22),
                      Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Tiến độ dọn dẹp',
                                style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white)),
                            Text('$pct%',
                                style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white)),
                          ]),
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: _frac,
                          minHeight: 8,
                          color: Colors.white,
                          backgroundColor: Pastel.night3,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 0, 22, 18),
                  child: stopped
                      ? GestureDetector(
                          onTap: () =>
                              Navigator.of(context).popUntil((r) => r.isFirst),
                          child: Container(
                            height: 56,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                                gradient: const LinearGradient(colors: [
                                  Color(0xFFFFFFFF),
                                  Color(0xFFBDBDBD)
                                ]),
                                borderRadius: BorderRadius.circular(28)),
                            child: const Text('Về trang chủ',
                                style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: Pastel.ink)),
                          ),
                        )
                      : GestureDetector(
                          onTap: () => setState(() => _paused = !_paused),
                          child: Container(
                            height: 56,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                                color: Pastel.night3,
                                borderRadius: BorderRadius.circular(28)),
                            child:
                                Row(mainAxisSize: MainAxisSize.min, children: [
                              AppIcon(
                                  _paused
                                      ? AppIcons.playArrowRounded
                                      : AppIcons.pauseRounded,
                                  size: 18,
                                  color: Colors.white,
                                  accent: Colors.white),
                              const SizedBox(width: 8),
                              Text(_paused ? 'Tiếp tục dọn' : 'Tạm dừng dọn',
                                  style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white)),
                            ]),
                          ),
                        ),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _stat(String v, String l, Color c) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
              color: Pastel.night2, borderRadius: BorderRadius.circular(16)),
          child: Column(children: [
            Text(v,
                style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.3,
                    color: c)),
            const SizedBox(height: 2),
            Text(l,
                style: const TextStyle(fontSize: 11, color: Pastel.nightMute)),
          ]),
        ),
      );
}
