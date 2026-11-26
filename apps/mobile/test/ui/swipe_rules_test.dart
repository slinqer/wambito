import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/ui/swipe_rules.dart';

// The web's gesture.test.ts (Stage 2 Task 12c), rule by rule.
void main() {
  group('lockAxis', () {
    test('waits until the finger has moved past the slop', () {
      expect(lockAxis(5, 3, 8), isNull);
      expect(lockAxis(-8, 0, 8), isNull);
    });

    test('is horizontal only when the move is more sideways than down', () {
      expect(lockAxis(12, 4, 8), Axis2.x);
      expect(lockAxis(-12, 11, 8), Axis2.x);
      expect(lockAxis(4, 12, 8), Axis2.y);
      expect(lockAxis(-3, -20, 8), Axis2.y);
    });

    test('gives a perfect diagonal to scrolling', () {
      expect(lockAxis(10, 10, 8), Axis2.y);
      expect(lockAxis(-10, -10, 8), Axis2.y);
    });
  });

  group('rubberBand', () {
    test('follows 1:1 inside the bounds', () {
      expect(rubberBand(0.4, 0, 1, 0.3), 0.4);
    });

    test('resists past either bound by the factor', () {
      expect(rubberBand(-100, 0, 1, 0.3), closeTo(-30, 1e-9));
      expect(rubberBand(2, 0, 1, 0.3), closeTo(1.3, 1e-9));
    });
  });

  group('rowOffset', () {
    double offset({double start = 0, required double dx, bool left = true, bool right = true}) =>
        rowOffset(start: start, dx: dx, width: 360, factor: 0.3, left: left, right: right);

    test('follows the finger 1:1 to either side with an action', () {
      expect(offset(dx: -100), -100);
      expect(offset(dx: 120), 120);
      expect(offset(start: -88, dx: 30), -58);
    });

    test('resists toward a side without an action', () {
      expect(offset(right: false, dx: 100), closeTo(30, 1e-9));
      expect(offset(left: false, dx: -100), closeTo(-30, 1e-9));
    });

    test("stops at the row's width", () {
      expect(offset(dx: -500), -360);
    });
  });

  group('armedSide', () {
    test('arms a side past the threshold (40 % of the row)', () {
      expect(armedSide(-143, 360, 0.4), isNull);
      expect(armedSide(-144, 360, 0.4), Side.left);
      expect(armedSide(150, 360, 0.4), Side.right);
    });
  });

  group('rowRelease', () {
    RowRelease release(double offset, double vx, {bool left = true, bool right = true}) =>
        rowRelease(
          offset: offset,
          vx: vx,
          width: 360,
          threshold: 0.4,
          flick: 500,
          openWidth: 88,
          left: left,
          right: right,
        );

    test('commits right past the threshold, or on a flick', () {
      expect(release(150, 0), RowRelease.commitRight);
      expect(release(30, 700), RowRelease.commitRight);
    });

    test('a long or fast swipe left only opens Borrar', () {
      expect(release(-150, 0), RowRelease.openLeft);
      expect(release(-300, 0), RowRelease.openLeft);
      expect(release(-30, -700), RowRelease.openLeft);
      expect(release(-120, -2000), RowRelease.openLeft);
    });

    test('leaves a short swipe open', () {
      expect(release(-60, 0), RowRelease.openLeft);
      expect(release(60, 0), RowRelease.openRight);
    });

    test('closes a tiny swipe, or one flung back', () {
      expect(release(-20, 0), RowRelease.close);
      expect(release(-80, 700), RowRelease.close);
    });

    test('never commits a side without an action', () {
      expect(release(200, 800, right: false), RowRelease.close);
    });
  });

  group('the crown', () {
    test('a notch every 20 px, either way', () {
      expect(SwipeFeel.detent, 20);
      expect(notchOf(0), 0);
      expect(notchOf(19.9), 0);
      expect(notchOf(20), 1);
      expect(notchOf(-41), -2);
    });

    test('light at rest, firm at the threshold, never past it', () {
      const width = 360.0;
      expect(detentScale(0, width), closeTo(0.25, 1e-9));
      expect(detentScale(width * SwipeFeel.rowThreshold, width), closeTo(0.6, 1e-9));
      expect(detentScale(-width, width), closeTo(0.6, 1e-9));
      expect(detentScale(width * SwipeFeel.rowThreshold / 2, width), closeTo(0.425, 1e-9));
    });

    test('a detent is one tick at its scale', () {
      final pattern = detentPattern(0.5);
      expect(pattern.waveform, [5]);
      expect(pattern.primitives.single.name, 'tick');
      expect(pattern.primitives.single.scale, 0.5);
    });

    test('the spring home is underdamped, so it bounces', () {
      expect(SwipeFeel.rowHomeDamping, lessThan(2 * math.sqrt(SwipeFeel.rowStiffness)));
      expect(SwipeFeel.detentGap, const Duration(milliseconds: 25));
    });
  });
}
