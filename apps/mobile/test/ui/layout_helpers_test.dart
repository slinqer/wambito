import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/ui/confirm_sheet.dart' show flexOneRow;
import 'package:wambito/ui/css_text.dart';
import 'package:wambito/ui/lk_theme.dart';
import 'package:wambito/ui/outset_box.dart';
import 'package:wambito/ui/pixel_snap.dart';

import '../support/fonts.dart';
import '../support/ui_app.dart';

/// The helpers that make Flutter lay out and draw as Chrome does (docs/mobile/parity.md, "What
/// Chrome does that Flutter does not").
void main() {
  setUpAll(loadAppFonts);

  test('snappedColumns: three columns of 102.67px have their edges on whole device pixels', () {
    final track = snappedColumns(320, 3, 6, 2);
    final widths = track.sublist(0, 3);
    final gaps = track.sublist(3, 5);
    expect(widths, [102.5, 103.0, 102.5]);
    expect(widths[0] + gaps[0] + widths[1] + gaps[1] + widths[2], closeTo(320, 1e-9));
    for (final w in [...widths, ...gaps]) {
      expect((w * 2) % 1, 0, reason: 'a whole number of device pixels');
    }
    // A column's centre moves by the half-pixel its edges moved; text stays on the unrounded one.
    final shifts = track.sublist(5);
    expect(shifts[1], 0);
    expect(shifts[0], closeTo(-shifts[2], 1e-9));
  });

  testWidgets('CssText: a line is as wide as its words and spaces, each rounded up to 1/64', (
    t,
  ) async {
    late BuildContext context;
    await t.pumpWidget(
      uiApp(
        Builder(
          builder: (c) {
            context = c;
            return const SizedBox();
          },
        ),
      ),
    );
    const style = TextStyle(fontFamily: 'Nunito', fontWeight: FontWeight.w800, fontSize: 11);
    final whole = CssText.widthOf(context, const TextSpan(text: 'pingo doce', style: style));
    final parts = [
      for (final word in ['pingo', ' ', 'doce'])
        CssText.widthOf(context, TextSpan(text: word, style: style)),
    ].fold(0.0, (a, b) => a + b);
    expect(whole, parts);
    expect((whole * 64) % 1, 0, reason: 'in 64ths of a pixel');
  });

  testWidgets('CssText draws the line at that width, with no overflow', (t) async {
    await t.pumpWidget(
      uiApp(
        const CssText(
          TextSpan(
            text: 'Supermercado · ',
            style: TextStyle(fontFamily: 'Nunito', fontSize: 12),
            children: [
              TextSpan(
                text: 'x',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ],
          ),
        ),
      ),
    );
    expect(t.takeException(), isNull);
    expect(find.text('Supermercado'), findsOneWidget);
  });

  testWidgets('OutsetBox takes less room than its child and answers touches over all of it', (
    t,
  ) async {
    var taps = 0;
    await t.pumpWidget(
      uiApp(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: OutsetBox(
            vertical: 12,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => taps++,
              child: const SizedBox(width: 44, height: 44),
            ),
          ),
        ),
      ),
    );
    final box = t.getRect(find.byType(OutsetBox));
    expect(box.height, 20);
    await t.tapAt(Offset(box.left + 10, box.top - 10));
    await t.tapAt(Offset(box.left + 10, box.bottom + 10));
    expect(taps, 2);
    await t.tapAt(Offset(box.left + 10, box.top - 14));
    expect(taps, 2);
  });

  testWidgets('SnappedDecoratedBox lays out as it is and paints on whole device pixels', (t) async {
    t.view
      ..physicalSize = const Size(200, 200)
      ..devicePixelRatio = 2;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
          data: MediaQueryData(devicePixelRatio: 2),
          child: Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding: EdgeInsets.only(left: 10.3, top: 10.3),
              child: SnappedDecoratedBox(
                decoration: BoxDecoration(color: Color(0xFFFFFFFF)),
                child: SizedBox(width: 20.4, height: 20.4),
              ),
            ),
          ),
        ),
      ),
    );
    expect(
      t.getRect(find.byType(SnappedDecoratedBox)),
      const Rect.fromLTWH(10.3, 10.3, 20.4, 20.4),
    );
  });

  testWidgets('CssParagraph: breaks where Blink does, reads as one text, and is as tall as CSS', (
    t,
  ) async {
    final handle = t.ensureSemantics();
    const style = TextStyle(
      fontFamily: 'Nunito',
      fontSize: 13,
      fontWeight: FontWeight.w600,
      height: 1.5,
    );
    const text = 'Suenan al anotar y al celebrar. La vibración sigue igual.';
    late BuildContext context;
    // As wide as the first line takes, to the hundredth: the words' own widths, each rounded up.
    Future<void> pump(double width) => t.pumpWidget(
      uiApp(
        Builder(
          builder: (c) {
            context = c;
            return Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: width,
                child: const CssParagraph(text, style: style),
              ),
            );
          },
        ),
        width: 600,
      ),
    );
    await pump(500);
    final line = CssText.widthOf(context, const TextSpan(text: text, style: style));
    expect(
      t.getSize(find.byType(CssParagraph)).height,
      closeTo(13 * 1.5, 1e-9),
      reason: 'one line',
    );

    // A hair narrower than the first words need: the last word goes down.
    const firstLine = 'Suenan al anotar y al celebrar. La vibración';
    final first = CssText.widthOf(context, const TextSpan(text: firstLine, style: style));
    await pump(first - 0.01);
    expect(t.getSize(find.byType(CssParagraph)).height, closeTo(2 * 13 * 1.5, 1e-9));
    expect(find.bySemanticsLabel(text), findsOneWidget);
    expect(line, greaterThan(first));
    handle.dispose();
  });

  testWidgets('flexOneRow: each item is its own padding and an equal share of what is left', (
    t,
  ) async {
    await t.pumpWidget(
      uiApp(
        flexOneRow(
          gap: 8,
          items: [
            (16, Container(key: const Key('a'), height: 10)),
            (52, Container(key: const Key('b'), height: 10)),
          ],
        ),
        width: 412,
      ),
    );
    // 412 − 8 − 16 − 52 = 336 left: 168 each.
    expect(t.getSize(find.byKey(const Key('a'))).width, 16 + 168);
    expect(t.getSize(find.byKey(const Key('b'))).width, 52 + 168);
    expect(t.getTopLeft(find.byKey(const Key('b'))).dx, 16 + 168 + 8);
  });

  test('snapped columns never come out wider than their room, at any width and density', () {
    // A Galaxy S25 at its default zoom is 2.8125: the keypad overflowed by 0.178 px there.
    for (final ratio in [1.0, 2.0, 2.625, 2.75, 2.8125, 3.0, 3.5]) {
      for (var w = 280.0; w < 460; w += 0.07) {
        final track = snappedColumns(w, 3, 8, ratio);
        final total = track[0] + track[1] + track[2] + track[3] + track[4];
        expect(total, lessThanOrEqualTo(w + 1e-9), reason: 'width $w at $ratio');
      }
    }
  });
}
