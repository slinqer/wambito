// The settings menu: six rows that each open their own route, then "Cerrar sesión" and the version.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/l10n/app_localizations.dart';
import 'package:wambito/settings/settings_screen.dart';
import 'package:wambito/theme/theme.dart';
import 'package:wambito/ui/app_shell.dart';
import 'package:wambito/settings/feedback.dart' show appVersionProvider;
import 'package:wambito/settings/settings_categories.dart';
import 'package:wambito/ui/lk_icons.dart';

import '../support/icons.dart';
import 'harness.dart';

const _lines = [
  ('Mis agentes', 'ChatGPT · Claude · Lumo+ · Grok'),
  ('Cuenta y seguridad', 'Passkeys, dispositivos, clave'),
  ('Preferencias', 'Español · Noche · COP'),
  ('Captura', 'Automática, voz, avisos'),
  ('Tus datos', 'Importar, exportar'),
  ('Más', 'Comentarios, servidor, acerca de'),
];

final _version = appVersionProvider.overrideWith((ref) async => '1.0.4');

Future<SettingsEnv> _pump(WidgetTester tester, {bool guest = false}) async {
  final env = await pumpSettingsApp(
    tester,
    guest: guest,
    location: '/settings',
    overrides: [_version],
  );
  return env;
}

void main() {
  testWidgets('six rows in order, each with its line', (tester) async {
    await _pump(tester);
    var last = -1.0;
    for (final (title, line) in _lines) {
      expect(find.text(title), findsOneWidget, reason: title);
      expect(find.text(line), findsOneWidget, reason: line);
      final y = tester.getTopLeft(find.text(title)).dy;
      expect(y, greaterThan(last), reason: title);
      last = y;
    }
    expect(find.byKey(const Key('settings.menu.agents')), findsOneWidget);
  });

  testWidgets('each row pushes its category route', (tester) async {
    final env = await _pump(tester);
    for (final category in SettingsCategory.values) {
      await tester.tap(find.byKey(Key('settings.menu.${category.name}')));
      await tester.pumpAndSettle();
      expect(env.router.state.uri.path, category.path);
      env.router.pop();
      await tester.pumpAndSettle();
      expect(env.router.state.uri.path, '/settings');
    }
  });

  testWidgets('sign out then the version sit under the rows', (tester) async {
    await _pump(tester);
    final more = tester.getBottomLeft(find.byKey(const Key('settings.menu.more'))).dy;
    final signOut = tester.getTopLeft(find.byKey(const Key('settings.signOut'))).dy;
    final version = tester.getTopLeft(find.text('Wambito 1.0.4')).dy;
    expect(signOut, greaterThan(more));
    expect(version, greaterThan(signOut));
  });

  testWidgets('at 360 x 740 the last row and the version show without scrolling', (tester) async {
    await _pump(tester);
    tester.view.physicalSize = const Size(360, 740);
    await tester.pumpAndSettle();
    final more = tester.getBottomLeft(find.byKey(const Key('settings.menu.more'))).dy;
    final version = tester.getBottomLeft(find.text('Wambito 1.0.4')).dy;
    expect(more, lessThan(740));
    expect(version, lessThan(740));
  });

  testWidgets('a row is one pressable with a chevron', (tester) async {
    await _pump(tester);
    expect(findIcon(LkIconName.chevronRight), findsNWidgets(6));
  });

  testWidgets('a guest sees "Guarda tu progreso" above the first row', (tester) async {
    await _pump(tester, guest: true);
    final save = tester.getTopLeft(find.byKey(const Key('settings.saveProgress'))).dy;
    final first = tester.getTopLeft(find.byKey(const Key('settings.menu.agents'))).dy;
    expect(save, lessThan(first));
  });

  testWidgets('webSectionsOnly hides Captura and signing out', (tester) async {
    final env = await _pump(tester);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: env.container,
        child: MaterialApp(
          theme: dayTheme,
          locale: const Locale('es'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const ShellFrame(
            padding: EdgeInsets.all(16),
            showMic: false,
            child: SettingsScreen(webSectionsOnly: true),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Captura'), findsNothing);
    expect(find.text('Tus datos'), findsOneWidget);
    expect(find.byKey(const Key('settings.signOut')), findsNothing);
  });
}
