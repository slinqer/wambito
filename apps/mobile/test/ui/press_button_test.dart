import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/theme/tokens.g.dart';
import 'package:wambito/ui/press_button.dart';
import 'package:wambito/ui/pressable.dart';
import 'package:wambito/ui/press_link.dart';

import '../support/fonts.dart';
import '../support/ui_app.dart';

/// `PressButton` and `PressLink`'s behaviour, as apps/web/app/ui/PressButton.tsx, PressLink.tsx and
/// their stories define it (the pressed offsets are app.css `.lk-btn-*:active`). How they look is
/// test/parity/press_button_parity_test.dart's job.
/// Lets a held finger count as a press (Flutter tells a tap from a scroll for 100 ms first), then
/// lets the 80 ms transition run for [after].
Future<void> _holdFor(WidgetTester t, Duration after) async {
  await t.pump(const Duration(milliseconds: 101));
  await t.pump();
  await t.pump(after);
}

void main() {
  setUpAll(loadAppFonts);

  testWidgets('a tap calls onPressed; a disabled button does nothing', (t) async {
    var taps = 0;
    await t.pumpWidget(
      uiApp(
        Column(
          children: [
            PressButton.text('Guardar', onPressed: () => taps++),
            PressButton.text('Cancelar'),
          ],
        ),
      ),
    );
    await t.tap(find.text('GUARDAR'));
    await t.pumpAndSettle();
    expect(taps, 1);
    await t.tap(find.text('CANCELAR'));
    await t.pumpAndSettle();
    expect(taps, 1);
  });

  testWidgets('Enter and Space press the focused button', (t) async {
    var taps = 0;
    await t.pumpWidget(
      uiApp(PressButton.text('Guardar', onPressed: () => taps++, autofocus: true)),
    );
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.sendKeyEvent(LogicalKeyboardKey.space);
    expect(taps, 2);
  });

  testWidgets('the label is upper case, as the web writes it', (t) async {
    await t.pumpWidget(uiApp(PressButton.text('Agregar gasto', onPressed: () {})));
    expect(find.text('AGREGAR GASTO'), findsOneWidget);
  });

  testWidgets('it is at least 44 x 44, even with a one-letter label', (t) async {
    await t.pumpWidget(
      uiApp(
        Row(
          children: [
            PressButton.text('x', size: PressSize.sm, tone: PressTone.ghost, onPressed: () {}),
          ],
        ),
      ),
    );
    final size = t.getSize(find.byType(PressButton));
    expect(size.width, greaterThanOrEqualTo(44));
    expect(size.height, greaterThanOrEqualTo(44));
  });

  group('pressed: the button sinks by its edge', () {
    Future<double> sunk(WidgetTester t, PressTone tone) async {
      await t.pumpWidget(
        uiApp(
          Row(
            children: [PressButton.text('Ok', tone: tone, onPressed: () {})],
          ),
        ),
      );
      final before = t.getTopLeft(find.text('OK')).dy;
      final finger = await t.startGesture(t.getCenter(find.byType(PressButton)));
      await _holdFor(t, const Duration(milliseconds: 200));
      final down = t.getTopLeft(find.text('OK')).dy - before;
      await finger.up();
      await t.pumpAndSettle();
      expect(t.getTopLeft(find.text('OK')).dy, before, reason: 'it comes back up');
      return down;
    }

    // app.css: .lk-btn-primary:active translateY(5px); secondary 3px; ghost 2px.
    testWidgets('primary 5px', (t) async => expect(await sunk(t, PressTone.primary), 5));
    testWidgets('secondary 3px', (t) async => expect(await sunk(t, PressTone.secondary), 3));
    testWidgets('ghost 2px', (t) async => expect(await sunk(t, PressTone.ghost), 2));

    testWidgets('over 80 ms, not at once', (t) async {
      await t.pumpWidget(uiApp(Row(children: [PressButton.text('Ok', onPressed: () {})])));
      final before = t.getTopLeft(find.text('OK')).dy;
      final finger = await t.startGesture(t.getCenter(find.byType(PressButton)));
      await _holdFor(t, const Duration(milliseconds: 40));
      final midway = t.getTopLeft(find.text('OK')).dy - before;
      expect(midway, inExclusiveRange(0, 5));
      await finger.up();
      await t.pumpAndSettle();
    });

    testWidgets('at once with "remove animations"', (t) async {
      await t.pumpWidget(
        uiApp(Row(children: [PressButton.text('Ok', onPressed: () {})]), disableAnimations: true),
      );
      final before = t.getTopLeft(find.text('OK')).dy;
      final finger = await t.startGesture(t.getCenter(find.byType(PressButton)));
      await t.pump(const Duration(milliseconds: 101));
      await t.pump();
      await t.pump();
      expect(t.getTopLeft(find.text('OK')).dy - before, 5);
      await finger.up();
      await t.pumpAndSettle();
    });

    testWidgets('a quick tap still shows it sinking for the press time', (t) async {
      await t.pumpWidget(uiApp(Row(children: [PressButton.text('Ok', onPressed: () {})])));
      final before = t.getTopLeft(find.text('OK')).dy;
      await t.tap(find.byType(PressButton));
      await t.pump();
      await t.pump(const Duration(milliseconds: 60));
      expect(t.getTopLeft(find.text('OK')).dy, greaterThan(before));
      await t.pumpAndSettle();
      expect(t.getTopLeft(find.text('OK')).dy, before);
    });

    testWidgets('a disabled button does not move and is half as opaque', (t) async {
      await t.pumpWidget(uiApp(Row(children: [PressButton.text('Ok')])));
      final before = t.getTopLeft(find.text('OK')).dy;
      final finger = await t.startGesture(t.getCenter(find.byType(PressButton)));
      await _holdFor(t, const Duration(milliseconds: 200));
      expect(t.getTopLeft(find.text('OK')).dy, before);
      await finger.up();
      expect(
        t
            .widget<Opacity>(
              find.descendant(of: find.byType(PressButton), matching: find.byType(Opacity)),
            )
            .opacity,
        0.5,
      );
    });
  });

  group('semantics', () {
    testWidgets('a button is a button, named by its label, and disabled without onPressed', (
      t,
    ) async {
      final handle = t.ensureSemantics();
      await t.pumpWidget(
        uiApp(
          Column(
            children: [
              PressButton.text('Guardar', onPressed: () {}),
              PressButton.text('Cancelar'),
            ],
          ),
        ),
      );
      expect(
        t.getSemantics(find.text('GUARDAR')),
        matchesSemantics(
          label: 'GUARDAR',
          isButton: true,
          isEnabled: true,
          hasEnabledState: true,
          isFocusable: true,
          hasTapAction: true,
          hasFocusAction: true,
        ),
      );
      expect(
        t.getSemantics(find.text('CANCELAR')),
        matchesSemantics(label: 'CANCELAR', isButton: true, hasEnabledState: true),
      );
      handle.dispose();
    });

    testWidgets('a link is a link', (t) async {
      final handle = t.ensureSemantics();
      var went = 0;
      await t.pumpWidget(
        uiApp(Row(children: [PressLink.text('Empieza ahora', onPressed: () => went++)])),
      );
      expect(
        t.getSemantics(find.text('EMPIEZA AHORA')),
        isSemantics(isLink: true, label: 'EMPIEZA AHORA'),
      );
      await t.tap(find.text('EMPIEZA AHORA'));
      expect(went, 1);
      handle.dispose();
    });
  });

  testWidgets('the danger tone is the delete colour, its words on it in bg', (t) async {
    await t.pumpWidget(
      uiApp(PressButton.text('Eliminar', tone: PressTone.danger, onPressed: () {})),
    );
    final colors = WambitoColors.night;
    final box = t.widget<PressSurface>(find.byType(PressSurface)).decoration;
    expect(box.color, colors.over);
    final label = t.widget<RichText>(
      find.descendant(of: find.byType(PressButton), matching: find.byType(RichText)),
    );
    expect(label.text.style?.color, colors.bg);
  });
}
