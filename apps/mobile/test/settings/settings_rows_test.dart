// The light group and row of the settings categories (`SettingsGroup`, `SettingsRow`).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/settings/settings_parts.dart';
import 'package:wambito/theme/tokens.g.dart';
import 'package:wambito/ui/lk_icons.dart';
import 'package:wambito/ui/lk_theme.dart';

import '../support/fonts.dart';
import '../support/ui_app.dart';

const _icon = LkIcon(LkIconName.shield, size: 20);

void main() {
  setUpAll(loadAppFonts);

  testWidgets('a switch row is one switch named by its title and toggles on tap', (t) async {
    final handle = t.ensureSemantics();
    var value = false;
    await t.pumpWidget(
      uiApp(
        StatefulBuilder(
          builder: (context, setState) => SettingsRow(
            icon: _icon,
            title: 'Sonido',
            line: 'Al guardar',
            trailing: RowSwitch(value: value, onChanged: (v) => setState(() => value = v)),
          ),
        ),
      ),
    );
    final named = find.bySemanticsLabel('Sonido');
    expect(
      t.getSemantics(named),
      isSemantics(label: 'Sonido', hasToggledState: true, isToggled: false),
    );
    await t.tap(find.text('Sonido'));
    await t.pump(const Duration(milliseconds: 200));
    expect(value, isTrue);
    expect(t.getSemantics(named), isSemantics(label: 'Sonido', isToggled: true));
    handle.dispose();
  });

  testWidgets('a chevron row shows its value', (t) async {
    await t.pumpWidget(
      uiApp(
        const SettingsRow(
          icon: _icon,
          title: 'Idioma',
          trailing: RowChevron(value: 'Español'),
        ),
      ),
    );
    expect(find.text('Español'), findsOneWidget);
    expect(find.byType(LkIcon), findsNWidgets(2));
  });

  testWidgets('a chip row shows its text', (t) async {
    await t.pumpWidget(
      uiApp(const SettingsRow(icon: _icon, title: 'Este', trailing: RowChip('este dispositivo'))),
    );
    expect(find.text('este dispositivo'), findsOneWidget);
  });

  testWidgets('a trash row is a button named by its label', (t) async {
    final handle = t.ensureSemantics();
    var taps = 0;
    await t.pumpWidget(
      uiApp(
        SettingsRow(
          icon: _icon,
          title: 'Pixel 8',
          trailing: RowTrash(label: 'Quitar Pixel 8', onTap: () => taps++),
        ),
      ),
    );
    expect(find.bySemanticsLabel('Quitar Pixel 8'), findsOneWidget);
    expect(
      t.getSemantics(find.bySemanticsLabel('Quitar Pixel 8')),
      isSemantics(label: 'Quitar Pixel 8', isButton: true),
    );
    await t.tap(find.bySemanticsLabel('Quitar Pixel 8'));
    expect(taps, 1);
    handle.dispose();
  });

  testWidgets('a danger row has the over colour on its title', (t) async {
    await t.pumpWidget(
      uiApp(const SettingsRow(icon: _icon, title: 'Borrar', danger: true, trailing: RowNone())),
    );
    final context = t.element(find.byType(SettingsRow));
    final style = t.widget<Text>(find.text('Borrar')).style!;
    expect(style.color, context.lkColors.over);
    expect(style.fontSize, 14);
    expect(style.fontWeight, FontWeight.w800);
  });

  testWidgets('at 130 % and an Italian 40-character line, the row stays one line tall', (t) async {
    const line = 'Ultimo accesso tre settimane fa da Roma.';
    expect(line.length, 40);
    await t.pumpWidget(
      uiApp(
        const SettingsRow(
          icon: _icon,
          title: 'Portatile di casa',
          line: line,
          trailing: RowChevron(value: 'Italiano'),
        ),
        width: 360,
        textScale: 1.3,
      ),
    );
    expect(t.getSize(find.byType(SettingsRow)).height, lessThanOrEqualTo(76));
  });

  testWidgets('a long chevron value truncates and the row stays one line tall', (t) async {
    await t.pumpWidget(
      uiApp(
        const SettingsRow(
          icon: _icon,
          title: 'Lingua',
          line: 'Cambia la lingua dell app',
          trailing: RowChevron(value: 'Portoghese (Brasile) e altre lingue'),
        ),
        width: 360,
        textScale: 1.3,
      ),
    );
    expect(t.takeException(), isNull);
    expect(t.getSize(find.byType(SettingsRow)).height, lessThanOrEqualTo(76));
    final row = t.getRect(find.byType(SettingsRow));
    final value = t.getRect(find.text('Portoghese (Brasile) e altre lingue'));
    expect(value.right, lessThanOrEqualTo(row.right));
    expect(value.width, lessThanOrEqualTo(row.width * 0.5));
    expect(t.getSize(find.text('Lingua')).width, greaterThan(40));
  });

  testWidgets('a group shows its label and divides its rows', (t) async {
    await t.pumpWidget(
      uiApp(
        const SettingsGroup(
          label: 'Dispositivos',
          rows: [
            SettingsRow(icon: _icon, title: 'A', trailing: RowNone()),
            SettingsRow(icon: _icon, title: 'B', trailing: RowNone()),
          ],
        ),
      ),
    );
    expect(find.text('DISPOSITIVOS'), findsOneWidget);
    final dividers = find.byKey(const ValueKey('settings-row-divider'));
    expect(dividers, findsOneWidget);
    final context = t.element(find.byType(SettingsGroup));
    expect(t.getSize(dividers).height, 2);
    expect(WambitoTokens.radiusLg, isNotNull);
    expect(context.lkColors.stroke, isNotNull);
  });
}
