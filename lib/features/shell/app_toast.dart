import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_icon.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_theme.dart';
import '../../theme/motion.dart';
import '../../theme/pastel_scheme.dart';
import 'app_dock.dart';

/// Thông báo nhanh hiện ở ĐẦU màn hình (không phải đáy, nơi có dock). Trượt xuống, tự
/// biến mất sau vài giây, vuốt lên để tắt. Thay cho SnackBar trong toàn app.
class AppToast {
  AppToast._();

  static OverlayEntry? _entry;
  static Timer? _timer;
  static _ToastHandle? _handle;

  static void show(String message,
      {AppIconData icon = AppIcons.infoOutline, bool warn = false}) {
    final overlay = AppDock.navigatorKey.currentState?.overlay;
    if (overlay == null) return;
    dismiss(immediate: true);
    final handle = _ToastHandle();
    _handle = handle;
    final entry = OverlayEntry(
      builder: (_) =>
          _ToastView(message: message, icon: icon, warn: warn, handle: handle),
    );
    _entry = entry;
    overlay.insert(entry);
    HapticFeedback.selectionClick();
    _timer = Timer(const Duration(milliseconds: 3200), dismiss);
  }

  static void dismiss({bool immediate = false}) {
    _timer?.cancel();
    final entry = _entry;
    final handle = _handle;
    _entry = null;
    _handle = null;
    if (entry == null) return;
    if (immediate || handle?.state == null) {
      entry.remove();
    } else {
      handle!.state!.hide().then((_) => entry.remove());
    }
  }
}

class _ToastHandle {
  _ToastViewState? state;
}

class _ToastView extends StatefulWidget {
  const _ToastView(
      {required this.message,
      required this.icon,
      required this.warn,
      required this.handle});
  final String message;
  final AppIconData icon;
  final bool warn;
  final _ToastHandle handle;

  @override
  State<_ToastView> createState() => _ToastViewState();
}

class _ToastViewState extends State<_ToastView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 520));
  double _drag = 0;

  @override
  void initState() {
    super.initState();
    widget.handle.state = this;
    _c.forward();
  }

  Future<void> hide() async {
    if (mounted) {
      await _c.animateBack(0,
          duration: const Duration(milliseconds: 260), curve: Curves.easeIn);
    }
  }

  @override
  void dispose() {
    widget.handle.state = null;
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = PastelScheme.of(context);
    final top = MediaQuery.paddingOf(context).top + 8;
    final calm = reduceMotion(context);
    final bg = t.dark ? const Color(0xFF2A2A2A) : Pastel.ink;
    final accent = widget.warn ? const Color(0xFFBDBDBD) : Colors.white;
    return AnimatedBuilder(
      animation: _c,
      builder: (_, child) {
        final v = calm ? 1.0 : Curves.easeOutBack.transform(_c.value);
        return Positioned(
          left: 16,
          right: 16,
          top: top - 90 * (1 - v) + _drag,
          child: Opacity(opacity: _c.value.clamp(0.0, 1.0), child: child),
        );
      },
      child: GestureDetector(
        onVerticalDragUpdate: (d) =>
            setState(() => _drag = (_drag + d.delta.dy).clamp(-120.0, 0.0)),
        onVerticalDragEnd: (_) {
          if (_drag < -24) {
            AppToast.dismiss();
          } else {
            setState(() => _drag = 0);
          }
        },
        onTap: AppToast.dismiss,
        child: Semantics(
          liveRegion: true,
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 12, 18, 12),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0x1FFFFFFF)),
                boxShadow: const [
                  BoxShadow(
                      color: Color(0x66000000),
                      blurRadius: 18,
                      offset: Offset(0, 7),
                      spreadRadius: -6),
                ],
              ),
              child: Row(children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration:
                      BoxDecoration(color: accent, shape: BoxShape.circle),
                  child: Center(
                      child: AppIcon(
                          widget.warn
                              ? AppIcons.warningAmberRounded
                              : widget.icon,
                          size: 18,
                          color: Pastel.ink,
                          accent: Pastel.ink)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(widget.message,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 14,
                          height: 1.3,
                          fontWeight: FontWeight.w500,
                          color: Colors.white)),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
