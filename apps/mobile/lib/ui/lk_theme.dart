import 'package:flutter/material.dart';

import '../theme/theme.dart';
import '../theme/tokens.g.dart';

/// The design tokens of the current theme, for the web's components ported to `lib/ui`.
extension LkThemeContext on BuildContext {
  /// The theme's colours and edge shadows (`Theme.of(context).extension<WambitoTheme>()!`).
  WambitoTheme get lk => Theme.of(this).extension<WambitoTheme>()!;

  /// The theme's colours.
  WambitoColors get lkColors => lk.colors;
}

/// Where Blink starts a text with a letter spacing of [spacing]: half the spacing in from the left
/// (it puts half of a letter spacing before a glyph and half after it; Flutter puts all of it
/// after, so Flutter's glyphs sit half a spacing to the left of the web's), cut to a quarter of a
/// device pixel, the grid Skia places glyphs on, and a hair under that step: a glyph exactly on
/// a step is drawn on the next one in Flutter's tests, a hair under it on the same one as in
/// Chrome. Translate the text by it.
double letterSpacingShift(BuildContext context, double spacing) {
  final ratio = MediaQuery.devicePixelRatioOf(context);
  return ((spacing / 2 * ratio * 4).floor() - 0.15) / 4 / ratio;
}

final _baselineShifts = <(String?, double?, FontWeight?, double?), double>{};

/// How far Flutter draws a line of [style] above or below where Blink does (positive: lower in
/// Blink): Blink rounds the font's ascent and descent to whole pixels and floors the half-leading
/// when it places the baseline in a line box taller than the text; Flutter keeps the fractions.
/// [style] needs a `height` and `leadingDistribution: even`, which the web's line heights are.
double cssBaselineShift(TextStyle style) {
  final key = (style.fontFamily, style.fontSize, style.fontWeight, style.height);
  return _baselineShifts.putIfAbsent(key, () {
    final painter = TextPainter(
      text: TextSpan(
        text: 'x',
        style: TextStyle(
          fontFamily: style.fontFamily,
          fontSize: style.fontSize,
          fontWeight: style.fontWeight,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final ascent = painter.computeDistanceToActualBaseline(TextBaseline.alphabetic);
    final descent = painter.height - ascent;
    painter.dispose();
    final lineHeight = style.fontSize! * style.height!;
    final blink =
        ascent.roundToDouble() +
        ((lineHeight - ascent.roundToDouble() - descent.roundToDouble()) / 2).floorToDouble();
    final flutter = (lineHeight - ascent - descent) / 2 + ascent;
    // A hair lower: a baseline exactly half a device pixel down is drawn on the pixel below in
    // Chrome and on the one above in Flutter's tests.
    return blink - flutter + 0.02;
  });
}

/// [child] (a line of text in [style]) moved to where Blink puts its baseline: see
/// [cssBaselineShift]. The move is a paint offset; the line keeps its place in the layout.
class BlinkLine extends StatelessWidget {
  const BlinkLine({super.key, required this.style, required this.child});

  final TextStyle style;
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Transform.translate(offset: Offset(0, cssBaselineShift(style)), child: child);
}

/// The widths of [count] equal columns [gap] apart in [width] px, as Chrome draws them: it rounds
/// the left and right edge of every box to a whole device pixel (at [ratio] device pixels per
/// logical one), so a column of 102.67px is 102.5 or 103px and every edge is sharp. Flutter keeps
/// the fractions and draws blurred edges. The first [count] values are the columns' widths, then
/// the [count] - 1 gaps between them, then how far each column's centre moved when its edges were
/// rounded (text is placed from the unrounded box: shift it back by that much). Lay a row out as
/// column, gap, column, gap, column.
List<double> snappedColumns(double width, int count, double gap, double ratio) {
  final column = (width - gap * (count - 1)) / count;
  double snap(double value) => (value * ratio).round() / ratio;
  final lefts = [for (var i = 0; i < count; i++) snap(i * (column + gap))];
  final rights = [for (var i = 0; i < count; i++) snap(i * (column + gap) + column)];
  // The last edge never passes the room: rounded up it would overflow by a fraction of a pixel
  // (0.178 px on a 2.8125 phone), so it goes down to the device pixel inside.
  final room = (width * ratio).floorToDouble() / ratio;
  if (rights[count - 1] > room) rights[count - 1] = room;
  return [
    for (var i = 0; i < count; i++) rights[i] - lefts[i],
    for (var i = 0; i < count - 1; i++) lefts[i + 1] - rights[i],
    for (var i = 0; i < count; i++) i * (column + gap) + column / 2 - (lefts[i] + rights[i]) / 2,
  ];
}
