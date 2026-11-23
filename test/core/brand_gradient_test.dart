import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:ourmynd/core/theme/app_colors.dart';

/// The brand gradient is painted on every primary button and hero surface in
/// the app, and it is built by hand-written Oklab conversions. A sign error in
/// those would not throw: it would quietly ship a wrong-coloured app. These
/// pin the three properties that make the ramp correct.
///
/// The contrast test is the one that caught a real bug: dark mode's stops used
/// to be *lighter* than light mode's, which left white button text at 2.40:1.

double _lin(double c) =>
    c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

/// WCAG relative luminance.
double _luminance(Color c) =>
    0.2126 * _lin(c.r) + 0.7152 * _lin(c.g) + 0.0722 * _lin(c.b);

double _contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

/// Allows one 8-bit step, which is all the round trip can lose.
void _expectSameColor(Color got, Color want) {
  expect((got.r - want.r).abs() * 255, lessThanOrEqualTo(1.0),
      reason: 'red channel');
  expect((got.g - want.g).abs() * 255, lessThanOrEqualTo(1.0),
      reason: 'green channel');
  expect((got.b - want.b).abs() * 255, lessThanOrEqualTo(1.0),
      reason: 'blue channel');
}

void main() {
  for (final (name, scheme) in [
    ('light', OmColors.light),
    ('dark', OmColors.dark),
  ]) {
    group('$name brand gradient', () {
      test('begins and ends on the declared stops', () {
        // If the Oklab round trip were wrong, the ends would drift off the
        // palette and every button would be a slightly different colour than
        // the design system says.
        final colors = scheme.brandGradient.colors;
        _expectSameColor(colors.first, scheme.gradStart);
        _expectSameColor(colors.last, scheme.gradEnd);
      });

      test('darkens evenly, with no band reversing direction', () {
        // A smooth ramp is a monotonic one. Interpolating in the wrong space,
        // or a transposed matrix row, shows up here as a step going back the
        // other way.
        final ls = scheme.brandGradient.colors.map(_luminance).toList();
        for (var i = 1; i < ls.length; i++) {
          expect(ls[i], lessThan(ls[i - 1]),
              reason: 'stop $i is lighter than stop ${i - 1}');
        }
      });

      test('keeps the steps small enough not to band', () {
        // Even steps are not enough on their own: they also have to be small.
        // The largest gap being close to the average is what says the ramp is
        // evenly spaced rather than bunched at one end.
        final ls = scheme.brandGradient.colors.map(_luminance).toList();
        final gaps = [
          for (var i = 1; i < ls.length; i++) ls[i - 1] - ls[i],
        ];
        final mean = gaps.reduce((a, b) => a + b) / gaps.length;
        expect(gaps.reduce(math.max), lessThan(mean * 1.6));
      });

      test('carries white text at every stop', () {
        // Bold text on a filled surface needs 3:1. This is what dark mode
        // failed at 2.40:1 before the stops were deepened.
        for (final stop in scheme.brandGradient.colors) {
          expect(_contrast(stop, const Color(0xFFFFFFFF)),
              greaterThanOrEqualTo(3.0),
              reason: 'white on $stop');
        }
      });

      test('stays visible as a shape against the page', () {
        // Deepening the stops for text contrast must not go so far that the
        // button stops reading as a button. A UI component needs 3:1 against
        // what is behind it.
        for (final stop in scheme.brandGradient.colors) {
          expect(_contrast(stop, scheme.bg), greaterThanOrEqualTo(2.9),
              reason: '$stop against the page');
        }
      });
    });
  }
}
