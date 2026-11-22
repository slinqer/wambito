// Tus datos, the light version (spec 2026-11-22): "Importar movimientos" (a chevron to the import;
// "Próximamente" and no chevron on an encrypted account) and "Descargar tus datos" (today's export
// choices in a sheet; the same file names and the same save or share question).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/settings/account_repository.dart';
import 'package:wambito/settings/settings_parts.dart' show RowChevron, SettingsRow;

import '../support/preview_account.dart';
import 'account_harness.dart';
import 'harness.dart';

Finder _row(String key) => find.byKey(Key(key));

void main() {
  testWidgets('the two rows, with their one line each', (t) async {
    await pumpAccount(t, location: '/settings/data');
    expect(find.text('Importar movimientos'), findsOneWidget);
    expect(find.text('Desde Budge'), findsOneWidget);
    expect(find.text('Descargar tus datos'), findsOneWidget);
    expect(find.text('En JSON o CSV'), findsOneWidget);
    // The choices are not on the page: they are in the sheet.
    expect(_row('settings.export.json'), findsNothing);
    final import = t.widget<SettingsRow>(_row('settings.import'));
    expect(import.trailing, isA<RowChevron>());
  });

  testWidgets('Importar leads to the import page', (t) async {
    final env = await pumpAccount(t, location: '/settings/data');
    await t.tap(_row('settings.import'));
    await t.pumpAndSettle();
    expect(env.app.router.state.uri.path, '/import');
  });

  testWidgets('an encrypted account: "Próximamente" and no chevron on the import', (t) async {
    final handle = t.ensureSemantics();
    await pumpSettingsApp(t, location: '/settings/data', overrides: previewOpen());
    final import = t.widget<SettingsRow>(_row('settings.import.comingSoon'));
    expect(import.trailing, isNot(isA<RowChevron>()));
    expect(find.text('Próximamente'), findsWidgets);
    expect(_row('settings.import'), findsNothing);
    // The full wording stays for a screen reader.
    expect(t.getSemantics(_row('settings.import.comingSoon')).hint, 'Próximamente con cifrado');
    handle.dispose();
  });

  testWidgets('Descargar opens the choices in a sheet; JSON downloads as before', (t) async {
    final env = await pumpAccount(t, location: '/settings/data');
    await t.tap(_row('settings.export'));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('settings.export.json')), findsOneWidget);
    expect(find.byKey(const Key('settings.export.csv')), findsOneWidget);
    expect(
      find.bySemanticsLabel(
        'Todo en JSON, o tus movimientos en CSV para abrirlos en Excel o Google Sheets.',
      ),
      findsOneWidget,
    );
    await t.tap(_row('settings.export.json'));
    await t.pumpAndSettle();
    expect(env.accounts.exports, [ExportFormat.json]);
    expect(find.text('¿Qué hacemos con wambito-export-2026-10-21.json?'), findsOneWidget);
  });

  testWidgets('a guest finds both buttons off, with the line that says why', (t) async {
    final env = await pumpAccount(t, location: '/settings/data', guest: true);
    await t.tap(_row('settings.export'));
    await t.pumpAndSettle();
    expect(
      find.bySemanticsLabel(
        'Primero guarda tu progreso con un correo; después podrás descargar tus datos.',
      ),
      findsOneWidget,
    );
    await t.tap(_row('settings.export.json'), warnIfMissed: false);
    await t.pumpAndSettle();
    expect(env.accounts.exports, isEmpty);
  });
}
