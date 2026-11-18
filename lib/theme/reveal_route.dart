import 'package:flutter/material.dart';

import 'motion.dart';

/// Chuyển trang kiểu "mở rộng từ một điểm": trang mới lộ ra trong một hình tròn lớn dần
/// từ [center] (tọa độ toàn màn hình) cho tới khi phủ kín. Tắt hiệu ứng (chỉ hiện dần)
/// khi người dùng bật giảm chuyển động.
class CircleRevealRoute<T> extends PageRouteBuilder<T> {
  CircleRevealRoute(
      {required this.center, required WidgetBuilder builder, super.settings})
      : super(
          transitionDuration: const Duration(milliseconds: 750),
          reverseTransitionDuration: const Duration(milliseconds: 450),
          pageBuilder: (context, _, __) => builder(context),
        );

  final Offset center;

  @override
  Widget buildTransitions(BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation, Widget child) {
    if (reduceMotion(context)) {
      return FadeTransition(opacity: animation, child: child);
    }
    final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeInOutCubic,
        reverseCurve: Curves.easeInCubic);
    return AnimatedBuilder(
      animation: curved,
      child: child,
      builder: (context, child) {
        final size = MediaQuery.sizeOf(context);
        final far = [
          center.distance,
          (center - Offset(size.width, 0)).distance,
          (center - Offset(0, size.height)).distance,
          (center - Offset(size.width, size.height)).distance,
        ].reduce((a, b) => a > b ? a : b);
        return ClipPath(
          clipper: _CircleClipper(center, far * curved.value),
          // Khử răng cưa một đường tròn lớn trên toàn màn hình mỗi khung hình rất
          // tốn; cạnh đã được chuyển động che nên cắt cứng là đủ.
          clipBehavior: Clip.hardEdge,
          child: child,
        );
      },
    );
  }

  @override
  bool get opaque => true;
}

class _CircleClipper extends CustomClipper<Path> {
  _CircleClipper(this.center, this.radius);
  final Offset center;
  final double radius;
  @override
  Path getClip(Size size) =>
      Path()..addOval(Rect.fromCircle(center: center, radius: radius));
  @override
  bool shouldReclip(_CircleClipper o) =>
      o.radius != radius || o.center != center;
}
