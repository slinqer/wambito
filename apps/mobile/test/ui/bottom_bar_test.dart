import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/ui/bottom_bar.dart';
import 'package:wambito/ui/lk_icons.dart';

import '../support/fonts.dart';
import '../support/ui_app.dart';

/// `BottomBar`'s behaviour, as apps/web/app/ui/BottomBar.tsx and its stories define it (and the
/// 🎤 beside the ＋, spec decision 3). How it looks is test/parity/bottom_bar_parity_test.dart's
/// job, and test/ui/bottom_bar_golden_test.dart's for the 🎤.
Widget _bar({
  String current = 'home',
  List<String>? taps,
  VoidCallback? onAdd,
  VoidCallback? onMic,
  bool showMic = true,
  double width = 380,
}) => uiApp(
  BottomBar(
    current: current,
    showMic: showMic,
    onAdd: onAdd ?? () {},
    onMic: onMic ?? () {},
    onNavigate: (key) => taps?.add(key),
  ),
  width: width,
);

/// The icon [name] in the bar (the ＋, the 🎤, a tab's).
Finder _icon(LkIconName name) => find.byWidgetPredicate((w) => w is LkIcon && w.name == name);

void main() {
  setUpAll(loadAppFonts);

  testWidgets('the current tab\'s icon is filled, the other\'s outlined', (t) async {
    await t.pumpWidget(_bar(current: 'insights'));
    LkIconVariant variant(LkIconName name) => t.widget<LkIcon>(_icon(name)).variant;
    expect(variant(LkIconName.chart), LkIconVariant.filled);
    expect(variant(LkIconName.home), LkIconVariant.outline);
    await t.pumpWidget(_bar(current: 'categories'));
    expect(variant(LkIconName.chart), LkIconVariant.outline);
    expect(variant(LkIconName.home), LkIconVariant.outline);
  });

  testWidgets('Inicio and Análisis navigate; the ＋ adds; the 🎤 listens', (t) async {
    final taps = <String>[];
    var added = 0, mic = 0;
    await t.pumpWidget(_bar(taps: taps, onAdd: () => added++, onMic: () => mic++));
    await t.tap(find.text('Inicio'));
    await t.tap(find.text('Análisis'));
    await t.tap(_icon(LkIconName.plus));
    await t.tap(_icon(LkIconName.mic));
    expect(taps, ['home', 'insights']);
    expect(added, 1);
    expect(mic, 1);
  });

  testWidgets('the current tab is marked; the others are not', (t) async {
    final handle = t.ensureSemantics();
    await t.pumpWidget(_bar(current: 'insights'));
    expect(t.getSemantics(find.text('Análisis')).flagsCollection.isSelected.name, 'isTrue');
    expect(t.getSemantics(find.text('Inicio')).flagsCollection.isSelected.name, isNot('isTrue'));
    handle.dispose();
  });

  testWidgets('a section the bar has no tab for marks none', (t) async {
    final handle = t.ensureSemantics();
    await t.pumpWidget(_bar(current: 'categories'));
    for (final name in ['Inicio', 'Análisis']) {
      expect(t.getSemantics(find.text(name)).flagsCollection.isSelected.name, isNot('isTrue'));
    }
    handle.dispose();
  });

  testWidgets('the bar, the ＋ and the 🎤 are named for screen readers', (t) async {
    final handle = t.ensureSemantics();
    await t.pumpWidget(_bar());
    expect(find.bySemanticsLabel('Navegación principal'), findsOneWidget);
    expect(find.bySemanticsLabel('Agregar'), findsOneWidget);
    expect(find.bySemanticsLabel('Decir o escribir un gasto'), findsOneWidget);
    handle.dispose();
  });

  testWidgets(
    'the ＋ is 58px, rises 14px above the tabs and shares their bottom; the 🎤 is smaller, beside it',
    (t) async {
      await t.pumpWidget(_bar());
      final plus = t.getRect(
        find.ancestor(of: _icon(LkIconName.plus), matching: find.byType(SizedBox)).first,
      );
      final mic = t.getRect(
        find.ancestor(of: _icon(LkIconName.mic), matching: find.byType(SizedBox)).first,
      );
      final home = t.getRect(
        find.ancestor(of: find.text('Inicio'), matching: find.byType(AnimatedContainer)).first,
      );
      expect(plus.size, const Size(58, 58));
      expect(home.top - plus.top, 14);
      expect(plus.bottom, home.bottom);
      expect(mic.size, const Size(44, 44));
      expect(mic.left - plus.right, 8);
      expect(mic.bottom, plus.bottom);
      // The ＋ is in the middle of the bar, where the web puts it.
      expect(plus.center.dx, 190);
    },
  );

  testWidgets('the tabs are 76 × 44 and the bar is 66px under its 4px of reach', (t) async {
    await t.pumpWidget(_bar());
    final home = t.getRect(
      find.ancestor(of: find.text('Inicio'), matching: find.byType(AnimatedContainer)).first,
    );
    expect(home.size, const Size(76, 44));
    expect(t.getSize(find.byType(BottomBar)).height, 70);
  });

  for (final width in [412.0, 380.0, 360.0, 320.0]) {
    testWidgets('at $width px wide the 🎤 overlaps neither the ＋ nor a tab, nor the tab\'s label', (
      t,
    ) async {
      await t.pumpWidget(_bar(width: width));
      Rect box(Finder of, Type type) =>
          t.getRect(find.ancestor(of: of, matching: find.byType(type)).first);
      final plus = box(_icon(LkIconName.plus), SizedBox);
      final mic = box(_icon(LkIconName.mic), SizedBox);
      final insights = box(find.text('Análisis'), AnimatedContainer);
      final home = box(find.text('Inicio'), AnimatedContainer);
      expect(
        mic.left,
        greaterThanOrEqualTo(plus.right + (width >= 360 ? 4 : 0)),
        reason: 'clear of the ＋ (4px to spare from 360px; at 320px the tabs give up all they can and 1px is left)',
      );
      expect(mic.right, lessThanOrEqualTo(insights.left), reason: 'clear of the Análisis tab');
      expect(
        mic.right,
        lessThanOrEqualTo(insights.left - 0),
        reason: 'not on its empty margin either',
      );
      expect(mic.overlaps(home), isFalse);
      expect(mic.size, const Size(44, 44), reason: 'still a 44px target');
      expect(t.getRect(find.text('Análisis')).overlaps(mic), isFalse);
      // The ＋ is where the web puts it: in the middle.
      expect(plus.center.dx, closeTo(width / 2, 0.5));
      // The tabs keep the web's 76px wherever there is room for the 🎤 beside the ＋.
      if (width >= 380) expect(insights.width, 76);
      expect(insights.width, greaterThanOrEqualTo(56));
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('without the 🎤 (the parity pair) it is not there', (t) async {
    await t.pumpWidget(_bar(showMic: false));
    expect(_icon(LkIconName.mic), findsNothing);
  });

  testWidgets('a touch on the top of the ＋, above the bar\'s drawn box, still adds', (t) async {
    var added = 0;
    await t.pumpWidget(_bar(onAdd: () => added++));
    final plus = t.getRect(
      find.ancestor(of: _icon(LkIconName.plus), matching: find.byType(SizedBox)).first,
    );
    await t.tapAt(Offset(plus.center.dx, plus.top + 2));
    expect(added, 1);
  });

  testWidgets('Tab goes Inicio, ＋, 🎤, Análisis; Enter presses', (t) async {
    final taps = <String>[];
    var added = 0, mic = 0;
    await t.pumpWidget(_bar(taps: taps, onAdd: () => added++, onMic: () => mic++));
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(taps, ['home', 'insights']);
    expect(added, 1);
    expect(mic, 1);
  });

  testWidgets('at 130% on a 320px phone the labels still fit their 56px tabs', (t) async {
    await t.pumpWidget(
      uiApp(
        BottomBar(current: 'home', onAdd: () {}, onMic: () {}, onNavigate: (_) {}),
        width: 320,
        textScale: 1.3,
      ),
    );
    expect(t.takeException(), isNull);
  });

  testWidgets('at 130% on a 360px phone the labels do not overflow', (t) async {
    await t.pumpWidget(
      uiApp(
        BottomBar(current: 'home', onAdd: () {}, onMic: () {}, onNavigate: (_) {}),
        width: 360,
        textScale: 1.3,
      ),
    );
    expect(t.takeException(), isNull);
  });

  // Italian and European Portuguese run longer than Spanish (spec §3): the two tab labels still
  // draw whole, on one line each, on a 360px phone at 130% (and on a 320px one).
  for (final (code, labels) in [
    ('it', ['Home', 'Analisi']),
    ('pt', ['Início', 'Análise']),
  ]) {
    for (final width in [360.0, 320.0]) {
      testWidgets(
        '$code: the labels ${labels.join(' and ')} are not cut off at 130% on ${width}px',
        (t) async {
          await t.pumpWidget(
            uiApp(
              BottomBar(current: 'home', onAdd: () {}, onMic: () {}, onNavigate: (_) {}),
              locale: Locale(code),
              width: width,
              textScale: 1.3,
            ),
          );
          expect(t.takeException(), isNull);
          for (final label in labels) {
            final paragraph = t.renderObject<RenderParagraph>(find.text(label));
            expect(paragraph.didExceedMaxLines, isFalse, reason: label);
          }
        },
      );
    }
  }
}
