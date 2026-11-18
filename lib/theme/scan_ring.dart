import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'app_theme.dart';

/// Vòng tiến độ nền tối: phần đã chạy tô gradient lime sang xanh, đầu nét tròn.
class ScanRingPainter extends CustomPainter {
  ScanRingPainter(this.f,
      {this.width = 12,
      this.track = Pastel.night3,
      this.from = Colors.white,
      this.to = const Color(0xFFBDBDBD)});
  final double f;
  final double width;
  final Color track;
  final Color from;
  final Color to;

  @override
  void paint(Canvas canvas, Size size) {
    final w = width;
    final rect = Rect.fromLTWH(w / 2, w / 2, size.width - w, size.height - w);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..strokeCap = StrokeCap.round
      ..color = track;
    canvas.drawArc(rect, 0, math.pi * 2, false, base);
    if (f > 0) {
      final sweep = math.pi * 2 * f.clamp(0.0, 1.0);
      final p = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          startAngle: 0,
          endAngle: math.pi * 2,
          colors: [from, to],
          transform: const GradientRotation(-math.pi / 2),
        ).createShader(rect);
      canvas.drawArc(rect, -math.pi / 2, sweep, false, p);
    }
  }

  @override
  bool shouldRepaint(ScanRingPainter o) =>
      o.f != f ||
      o.width != width ||
      o.track != track ||
      o.from != from ||
      o.to != to;
}
