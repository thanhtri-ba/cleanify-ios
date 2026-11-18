import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'app_theme.dart';

/// Đồng hồ vạch nửa vòng. [parts] là các đoạn màu nối nhau từ trái (tỷ lệ 0..1 so với
/// toàn vòng); phần còn lại là vạch xám. [reveal] 0..1 để vạch hiện dần theo thứ tự.
class TickDial extends StatelessWidget {
  const TickDial(
      {super.key,
      required this.parts,
      this.reveal = 1,
      this.height = 88,
      this.track = Pastel.track});
  final List<(double, Color)> parts;
  final double reveal;
  final double height;
  final Color track;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(painter: _TickPainter(parts, reveal, track)),
      );
}

class _TickPainter extends CustomPainter {
  _TickPainter(this.parts, this.reveal, this.track);
  final List<(double, Color)> parts;
  final double reveal;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    const n = 51;
    // Cùng tỷ lệ với bản vẽ: bán kính ngoài 96 trên khung 280 x 104.
    final k = math.min(size.width / 280, size.height / 104);
    final cx = size.width / 2;
    final cy = size.height - 4 * k;
    final r2 = 96 * k;
    final r1 = 74 * k;
    final p = Paint()..strokeCap = StrokeCap.round;
    var edges = <double>[];
    var acc = 0.0;
    for (final e in parts) {
      acc += e.$1.clamp(0.0, 1.0);
      edges.add(acc);
    }
    for (var i = 0; i < n; i++) {
      final t = i / (n - 1);
      final a = math.pi * (1 - t);
      final big = i % 5 == 0;
      final ra = big ? r1 - 6 * k : r1;
      var color = track;
      if (t <= reveal * (edges.isEmpty ? 0 : edges.last) + 0.0001 &&
          edges.isNotEmpty) {
        for (var j = 0; j < edges.length; j++) {
          if (t <= edges[j]) {
            color = parts[j].$2;
            break;
          }
        }
      }
      p
        ..color = color
        ..strokeWidth = (big ? 2.6 : 1.7) * k.clamp(0.8, 1.4);
      canvas.drawLine(Offset(cx + ra * math.cos(a), cy - ra * math.sin(a)),
          Offset(cx + r2 * math.cos(a), cy - r2 * math.sin(a)), p);
    }
  }

  @override
  bool shouldRepaint(_TickPainter o) =>
      o.reveal != reveal || o.parts != parts || o.track != track;
}

/// Vòng 72 vạch đầy đủ, [child] nằm giữa. [parts] như [TickDial]: các đoạn màu nối nhau
/// từ đỉnh theo chiều kim đồng hồ (tỷ lệ 0..1 so với cả vòng), còn lại là vạch [track].
class TickRing extends StatelessWidget {
  const TickRing({
    super.key,
    required this.parts,
    required this.size,
    this.reveal = 1,
    this.track = Pastel.track,
    this.child,
  });
  final List<(double, Color)> parts;
  final double size;
  final double reveal;
  final Color track;
  final Widget? child;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _RingPainter(parts, reveal, track),
          child: child == null
              ? null
              : Padding(
                  padding: EdgeInsets.all(size * 0.22),
                  child: Center(
                      child: FittedBox(fit: BoxFit.scaleDown, child: child)),
                ),
        ),
      );
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.parts, this.reveal, this.track);
  final List<(double, Color)> parts;
  final double reveal;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    const n = 72;
    final c = size.center(Offset.zero);
    final ro = size.width / 2 - 3;
    final ri = ro - size.width * 0.17;
    final w = (size.width / 72).clamp(2.0, 3.4);
    final p = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = w;
    final edges = <double>[];
    var acc = 0.0;
    for (final e in parts) {
      acc += e.$1.clamp(0.0, 1.0);
      edges.add(acc);
    }
    final last = edges.isEmpty ? 0.0 : edges.last;
    for (var i = 0; i < n; i++) {
      final t = i / n;
      final a = -math.pi / 2 + t * math.pi * 2;
      final r1 = i % 6 == 0 ? ri - size.width * 0.04 : ri;
      var color = track;
      if (edges.isNotEmpty && t < reveal * last) {
        for (var j = 0; j < edges.length; j++) {
          if (t < edges[j]) {
            color = parts[j].$2;
            break;
          }
        }
      }
      p.color = color;
      canvas.drawLine(c + Offset(math.cos(a), math.sin(a)) * r1,
          c + Offset(math.cos(a), math.sin(a)) * ro, p);
    }
  }

  @override
  bool shouldRepaint(_RingPainter o) =>
      o.reveal != reveal || o.parts != parts || o.track != track;
}
