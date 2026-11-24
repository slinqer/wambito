import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/ui/tile_glyph.dart';

/// Apple Color Emoji leaves more room on the right of a glyph than on its left, and the tile's line
/// box is Nunito's, so on the iPhone a tile's emoji sat about 1.5pt left and 1pt low (measured on
/// the simulator at 17px). [TileGlyph] moves it back there, in proportion to its size.
void main() {
  Future<Offset> shiftOf(WidgetTester tester, {double size = 17}) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: TileGlyph('🛒', color: const Color(0xFFFFFFFF), size: size),
        ),
      ),
    );
    final moves = tester.widgetList<Transform>(
      find.descendant(of: find.byType(TileGlyph), matching: find.byType(Transform)),
    );
    if (moves.isEmpty) return Offset.zero;
    final m = moves.single.transform;
    return Offset(m.getTranslation().x, m.getTranslation().y);
  }

  testWidgets('on the iPhone the emoji moves right and up, in proportion to its size', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    final at17 = await shiftOf(tester);
    expect(at17.dx, closeTo(1.5, 0.1));
    expect(at17.dy, closeTo(-1.1, 0.1));
    final at24 = await shiftOf(tester, size: 24);
    expect(at24.dx / at17.dx, closeTo(24 / 17, 0.01));
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('on Android it stays where the text puts it', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    expect(await shiftOf(tester), Offset.zero);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('it is the glyph alone, at the size asked', (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: TileGlyph('🏠', color: Color(0xFFFFFFFF), size: 24),
      ),
    );
    expect(tester.widget<Text>(find.text('🏠')).style!.fontSize, 24);
  });
}
