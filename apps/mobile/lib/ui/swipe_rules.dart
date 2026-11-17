// The math behind the row swipes, pure so every rule is unit-tested. A port of the web's
// apps/web/app/ui/gesture.ts (Stage 2 Task 12c), with the feel values of its `GESTURE` table.

import 'dart:math' as math;

import '../theme/tokens.g.dart';

/// The feel of the swipes, tuned on the web by hand on a 390 px phone (Task 12c). Durations are
/// the design tokens ([WambitoTokens]); these are the rest: distances, speeds and springs.
abstract final class SwipeFeel {
  /// px the finger moves before a gesture picks an axis (sideways, or the list's scroll).
  static const axisSlop = 8.0;

  /// px/s: a release faster than this is a flick: to the right it runs the action whatever the
  /// distance, to the left it opens Borrar.
  static const flickVelocity = 500.0;

  /// Toward a side with no action, content moves 0.3x the finger.
  static const rubberBand = 0.3;

  /// A row swiped right runs its action when let go past this fraction of its width; swiped left it
  /// opens Borrar instead.
  static const rowThreshold = 0.4;

  /// px: how much of an action a short swipe leaves open.
  static const rowActionWidth = 88.0;

  /// A sheet dragged down past this fraction of its height closes when let go.
  static const sheetCloseAt = 0.25;

  /// A sheet let go short of closing springs back: stiffness, damping.
  static const sheetBackStiffness = 500.0;
  static const sheetBackDamping = 40.0;

  /// px: a toast dragged this far down or sideways is dismissed.
  static const toastDismiss = 48.0;

  /// A deleted row starts folding away once this much of it has left the screen.
  static const rowGoneAt = 0.9;

  /// The spring of a row snapping open, shut, or back after its action: stiffness, damping.
  static const rowStiffness = 520.0;
  static const rowDamping = 38.0;

  /// The spring of a row flying off the screen when deleted (or back in after Deshacer).
  static const rowOutStiffness = 600.0;
  static const rowOutDamping = 48.0;

  /// How long the row folds away after it left (the web's `--collapse`).
  static const collapse = WambitoTokens.durationCollapse;

  /// The fade a reduced-motion row uses instead of moving (the web's `--fade`).
  static const fade = WambitoTokens.durationFade;
}

/// An axis. Named apart from Flutter's own `Axis`, which has no diagonal-free "undecided".
enum Axis2 { x, y }

/// Which way a gesture goes, decided once the finger has moved more than [slop] px: sideways only
/// when the move is more sideways than down (a perfect diagonal scrolls). Null until then. Once a
/// gesture is vertical it stays the list's.
Axis2? lockAxis(double dx, double dy, double slop) {
  final ax = dx.abs();
  final ay = dy.abs();
  if (math.max(ax, ay) <= slop) return null;
  return ax > ay ? Axis2.x : Axis2.y;
}

/// [value] inside [min, max]; past either bound it moves only [factor] as much (the rubber band).
double rubberBand(double value, double min, double max, double factor) {
  if (value < min) return min + (value - min) * factor;
  if (value > max) return max + (value - max) * factor;
  return value;
}

/// Where a dragged row sits: from where it started ([start]: 0, or open at plus or minus the
/// action's width) plus the finger's move, 1:1 toward a side that has an action (up to the row's
/// [width]), with the rubber band toward a side that has none. Negative is left (the delete side).
double rowOffset({
  required double start,
  required double dx,
  required double width,
  required double factor,
  required bool left,
  required bool right,
}) {
  final min = left ? -width : 0.0;
  final max = right ? width : 0.0;
  return rubberBand(start + dx, min, max, factor).clamp(-width, width);
}

enum Side { left, right }

/// The side whose action a release would run: past [threshold] (a fraction of the row's [width]).
Side? armedSide(double offset, double width, double threshold) {
  if (offset.abs() < threshold * width) return null;
  return offset < 0 ? Side.left : Side.right;
}

enum RowRelease { commitLeft, commitRight, openLeft, openRight, close }

/// What a released row does. To the right (Editar / Pagado), past the threshold or flicked toward
/// it, it runs the action. To the left it never deletes by itself: a long or fast swipe, like a
/// short one past half the action's width, leaves Borrar open and only a tap on it deletes.
/// Anything less, or a flick back, closes the row.
RowRelease rowRelease({
  required double offset,
  required double vx,
  required double width,
  required double threshold,
  required double flick,
  required double openWidth,
  required bool left,
  required bool right,
}) {
  final side = offset < 0
      ? Side.left
      : offset > 0
      ? Side.right
      : null;
  if (side == null) return RowRelease.close;
  if (!(side == Side.left ? left : right)) return RowRelease.close;
  final toward = side == Side.left ? vx <= -flick : vx >= flick;
  final back = side == Side.left ? vx >= flick : vx <= -flick;
  if (side == Side.left) {
    if (toward || armedSide(offset, width, threshold) == side) return RowRelease.openLeft;
  } else if (toward || armedSide(offset, width, threshold) == side) {
    return RowRelease.commitRight;
  }
  if (back) return RowRelease.close;
  if (offset.abs() >= openWidth / 2) {
    return side == Side.left ? RowRelease.openLeft : RowRelease.openRight;
  }
  return RowRelease.close;
}
