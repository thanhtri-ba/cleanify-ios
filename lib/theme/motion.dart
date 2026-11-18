import 'package:flutter/material.dart';

/// Thời lượng và đường cong chuyển động dùng chung. Ngắn, tinh tế, không lặp vô hạn.
const Duration kMotionFast = Duration(milliseconds: 180);
const Duration kMotionMed = Duration(milliseconds: 280);
const Curve kMotionCurve = Curves.easeOutCubic;

/// Người dùng bật "Reduce Motion" (iOS) / tắt animation (Android).
bool reduceMotion(BuildContext context) => MediaQuery.disableAnimationsOf(context);

/// Chuyển trang cho Android: trang mới trượt vào từ phải, trang cũ lùi nhẹ sang
/// trái rồi dừng. iOS không dùng builder này (giữ chuyển trang Cupertino để còn
/// vuốt cạnh trái quay lại).
///
/// KHÔNG làm mờ dần cả trang. Mọi trang trong app đều có BackdropFilter (thanh
/// tiêu đề thu gọn khi cuộn) và ImageFiltered (ba blob nền); bọc chúng trong một
/// lớp opacity khiến chúng lấy mẫu nền sai và nháy đen/xám trên Android.
///
/// Dùng CurveTween thay CurvedAnimation vì buildTransitions chạy lại mỗi khung
/// hình: CurvedAnimation tạo ở đây sẽ không ai dispose.
class SlidePageTransitionsBuilder extends PageTransitionsBuilder {
  const SlidePageTransitionsBuilder();
  @override
  Widget buildTransitions<T>(PageRoute<T> route, BuildContext context,
      Animation<double> animation, Animation<double> secondaryAnimation, Widget child) {
    if (reduceMotion(context)) return child;
    final enter = Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
        .chain(CurveTween(curve: kMotionCurve))
        .animate(animation);
    final leave = Tween<Offset>(begin: Offset.zero, end: const Offset(-0.22, 0))
        .chain(CurveTween(curve: kMotionCurve))
        .animate(secondaryAnimation);
    return SlideTransition(
      position: leave,
      child: SlideTransition(position: enter, child: child),
    );
  }
}

/// Nhấn nút thì thu nhỏ nhẹ (0,97). Không chặn cử chỉ của nút bên trong.
class PressScale extends StatefulWidget {
  const PressScale({super.key, required this.child, this.enabled = true});
  final Widget child;
  final bool enabled;
  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _down = false;

  void _set(bool v) {
    if (widget.enabled && _down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) => Listener(
        onPointerDown: (_) => _set(true),
        onPointerUp: (_) => _set(false),
        onPointerCancel: (_) => _set(false),
        child: AnimatedScale(
          scale: _down && !reduceMotion(context) ? 0.97 : 1,
          duration: const Duration(milliseconds: 90),
          curve: Curves.easeOut,
          child: widget.child,
        ),
      );
}

/// Hiện lần lượt: fade + trượt lên 12px, trễ [index] x 60ms. Chỉ chạy lần đầu widget
/// được dựng; [index] từ [maxAnimated] trở đi hiện ngay (danh sách dài không bị trễ).
class Reveal extends StatelessWidget {
  const Reveal({super.key, required this.index, required this.child, this.maxAnimated = 8});
  final int index;
  final int maxAnimated;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (index >= maxAnimated || reduceMotion(context)) return child;
    final delay = index * 60;
    final total = 280 + delay;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: total),
      curve: Interval(delay / total, 1, curve: kMotionCurve),
      builder: (_, v, c) => Opacity(
        opacity: v,
        child: Transform.translate(offset: Offset(0, 12 * (1 - v)), child: c),
      ),
      child: child,
    );
  }
}

/// Số đếm từ 0 (lần đầu) hoặc từ giá trị cũ lên giá trị mới.
class CountUp extends StatelessWidget {
  const CountUp(
      {super.key, required this.value, required this.builder, this.duration = const Duration(milliseconds: 600), this.decimals = 0});
  final double value;
  final int decimals;
  final Duration duration;
  final Widget Function(String text) builder;

  @override
  Widget build(BuildContext context) {
    if (reduceMotion(context)) return builder(value.toStringAsFixed(decimals));
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value),
      duration: duration,
      curve: kMotionCurve,
      builder: (_, v, __) => builder(v.toStringAsFixed(decimals)),
    );
  }
}
