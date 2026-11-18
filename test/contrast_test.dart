import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cleanify/theme/pastel_scheme.dart';

double _lin(double c) =>
    c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
double _lum(Color c) =>
    0.2126 * _lin(c.r) + 0.7152 * _lin(c.g) + 0.0722 * _lin(c.b);
double contrast(Color a, Color b) {
  final la = _lum(a), lb = _lum(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// Chữ phải đạt WCAG AA (>= 4,5:1) trên nền của nó ở cả hai chế độ sáng và tối.
void main() {
  for (final (name, t) in [
    ('sáng', PastelScheme.light),
    ('tối', PastelScheme.darkScheme)
  ]) {
    test('chữ chính và chữ mờ đủ tương phản ($name)', () {
      for (final bg in [t.page, t.card, t.chip]) {
        expect(contrast(t.ink, bg), greaterThanOrEqualTo(7), reason: 'ink/$bg');
        expect(contrast(t.mute, bg), greaterThanOrEqualTo(4.5),
            reason: 'mute/$bg');
      }
    });

    test('chữ phụ trên các thẻ xám đủ tương phản ($name)', () {
      for (final (fg, bg) in [
        (t.limeSub, t.limeBg2),
        (t.blueSub, t.blueBg2),
        (t.amberSub, t.amberBg2),
        (t.lilacSub, t.lilacBg2),
        (t.limeText, t.limeBg),
        (t.dockIcon, t.dockTop),
      ]) {
        expect(contrast(fg, bg), greaterThanOrEqualTo(4.5), reason: '$fg/$bg');
      }
    });
  }
}
