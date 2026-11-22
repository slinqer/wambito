// Preferencias, the light version (spec 2026-11-22, "Preferencias, Tus datos and Más, inside"):
// "Apariencia" (Idioma and Tema as value rows that open a sheet of today's choices), "Sonido y
// tacto" (two switch rows whose full sentences stay as their hints for a screen reader) and "Hora
// y moneda" (Zona horaria and Moneda as value rows that open their pickers).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/feedback/feedback.dart';
import 'package:wambito/settings/preferences.dart';
import 'package:wambito/settings/settings_parts.dart' show SettingsRow;

import '../home/fakes.dart';
import '../home/fixtures.dart';
import 'harness.dart';

Future<SettingsEnv> _pump(
  WidgetTester t, {
  Locale locale = const Locale('es'),
  bool movements = false,
}) => pumpSettingsApp(
  t,
  locale: locale,
  location: '/settings/preferences',
  homeRepo: FakeHomeRepository(
    currency: 'EUR',
    timezone: 'Europe/Madrid',
    items: [if (movements) tx('t1', '2026-10-20', -1500, currency: 'EUR')],
  ),
);

Finder _row(String key) => find.byKey(Key(key));

void main() {
  testWidgets('the three groups, one row each, with their values', (t) async {
    await _pump(t, movements: true);
    for (final label in ['Apariencia', 'Sonido y tacto', 'Hora y moneda']) {
      expect(find.bySemanticsLabel(label), findsWidgets, reason: label);
    }
    expect(
      find.descendant(of: _row('settings.language'), matching: find.text('Automático')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: _row('settings.theme'), matching: find.text('Noche')),
      findsOneWidget,
    );
    expect(find.text('Un sonido corto al anotar'), findsOneWidget);
    expect(find.text('Un toque suave al anotar y deshacer'), findsOneWidget);
    expect(
      find.descendant(of: _row('settings.timezone.change'), matching: find.text('Madrid')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: _row('settings.currency.row'), matching: find.text('EUR')),
      findsOneWidget,
    );
    // No heavy card is left: the choices live in the sheets.
    expect(_row('settings.language.es'), findsNothing);
    expect(_row('settings.theme.day'), findsNothing);
  });

  testWidgets('Idioma opens a sheet of today\'s choices; a pick applies at once and closes it', (
    t,
  ) async {
    final env = await _pump(t);
    await t.tap(_row('settings.language'));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('settings.language.auto')), findsOneWidget);
    await t.tap(_row('settings.language.en'));
    await t.pumpAndSettle();
    expect(env.container.read(localeOverrideProvider), const Locale('en'));
    expect(find.text('Preferences'), findsWidgets, reason: 'the page speaks English now');
    expect(_row('settings.language.en'), findsNothing, reason: 'the sheet closed on the pick');
    expect(
      find.descendant(of: _row('settings.language'), matching: find.text('English')),
      findsOneWidget,
    );
    // Back to Spanish: the row names it in itself.
    await t.tap(_row('settings.language'));
    await t.pumpAndSettle();
    await t.tap(_row('settings.language.es'));
    await t.pumpAndSettle();
    expect(
      find.descendant(of: _row('settings.language'), matching: find.text('Español')),
      findsOneWidget,
    );
  });

  testWidgets('Tema opens its sheet with its hint; a pick applies at once', (t) async {
    final handle = t.ensureSemantics();
    final env = await _pump(t);
    await t.tap(_row('settings.theme'));
    await t.pumpAndSettle();
    expect(find.bySemanticsLabel(RegExp('Automático sigue el modo de tu teléfono')), findsWidgets);
    await t.tap(_row('settings.theme.day'));
    await t.pumpAndSettle();
    expect(env.container.read(themeModeProvider), ThemeMode.light);
    expect(_row('settings.theme.day'), findsNothing, reason: 'the sheet closed on the pick');
    expect(find.descendant(of: _row('settings.theme'), matching: find.text('Día')), findsOneWidget);
    handle.dispose();
  });

  testWidgets('the sound and vibration switches toggle, and say their full sentence', (t) async {
    final handle = t.ensureSemantics();
    final env = await _pump(t);
    expect(
      t.getSemantics(_row('settings.sound')).hint,
      'Suenan al anotar y al celebrar. La vibración sigue igual.',
    );
    expect(
      t.getSemantics(_row('settings.vibration')).hint,
      'Un toque suave al anotar, deslizar y deshacer.',
    );
    await t.tap(_row('settings.sound'));
    await t.tap(_row('settings.vibration'));
    await t.pumpAndSettle();
    expect(env.container.read(soundEnabledProvider), isFalse);
    expect(env.container.read(vibrationEnabledProvider), isFalse);
    handle.dispose();
  });

  testWidgets('Moneda with movements: its sheet says why it stays', (t) async {
    final handle = t.ensureSemantics();
    await _pump(t, movements: true);
    await t.tap(_row('settings.currency.row'));
    await t.pumpAndSettle();
    expect(
      find.bySemanticsLabel(
        'Tu moneda es EUR. Ya tienes movimientos o recurrentes, así que se queda así.',
      ),
      findsOneWidget,
    );
    expect(_row('settings.currency.COP'), findsNothing);
    handle.dispose();
  });

  testWidgets('Moneda with no movements: its sheet offers the currencies', (t) async {
    await _pump(t);
    await t.tap(_row('settings.currency.row'));
    await t.pumpAndSettle();
    expect(_row('settings.currency.COP'), findsOneWidget);
  });

  testWidgets('every row is one line, 76 px at the most', (t) async {
    await _pump(t, movements: true);
    for (final element in find.byType(SettingsRow).evaluate()) {
      final box = element.renderObject! as RenderBox;
      expect(box.size.height, lessThanOrEqualTo(76), reason: '${element.widget.key}');
    }
    expect(find.byType(SettingsRow), findsNWidgets(6));
  });
}
