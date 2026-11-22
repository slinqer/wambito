// Más, the light version (spec 2026-11-22): "Comentarios e ideas" (today's form in a sheet), "Lo que
// viene" and "Abrir Wambito en la web" (the same pages as before), and a second group with
// "Servidor" (its status as the value, the address as its line, today's change-server form) and
// "Acerca de" (the version).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/settings/feedback.dart';
import 'package:wambito/settings/server_status.dart';
import 'package:wambito/settings/settings_parts.dart' show SettingsRow;

import 'harness.dart';

Finder _row(String key) => find.byKey(Key(key));

Future<SettingsEnv> _pump(
  WidgetTester t, {
  ServerHealth health = const ServerHealth(online: true, version: '0.0.0-dev.abc1234'),
}) => pumpSettingsApp(
  t,
  location: '/settings/more',
  overrides: [
    serverHealthCheckProvider.overrideWithValue((server) async => health),
    appVersionProvider.overrideWith((ref) async => '1.2.3'),
  ],
);

void main() {
  testWidgets('the two groups, one line per row', (t) async {
    await _pump(t);
    expect(find.text('Comentarios e ideas'), findsOneWidget);
    expect(find.text('Cuéntanos qué mejorar'), findsOneWidget);
    expect(find.text('Lo que viene'), findsOneWidget);
    expect(find.text('Abrir Wambito en la web'), findsOneWidget);
    expect(find.text('Servidor'), findsOneWidget);
    expect(find.text('https://app.wambito.com'), findsOneWidget);
    expect(find.text('Conectado'), findsOneWidget);
    expect(find.text('Acerca de'), findsOneWidget);
    expect(find.text('Versión 1.2.3'), findsOneWidget);
    for (final element in find.byType(SettingsRow).evaluate()) {
      final box = element.renderObject! as RenderBox;
      expect(box.size.height, lessThanOrEqualTo(76), reason: '${element.widget.key}');
    }
  });

  testWidgets('Comentarios opens today\'s form in a sheet', (t) async {
    final handle = t.ensureSemantics();
    final env = await _pump(t);
    await t.tap(_row('settings.card.feedback'));
    await t.pumpAndSettle();
    expect(
      find.bySemanticsLabel(
        '¿Algo no funciona, o quieres que Wambito haga algo más? Cuéntanos por correo.',
      ),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel('Si no se abre tu correo, escribe a hola@wambito.com.'),
      findsOneWidget,
    );
    await t.tap(_row('settings.feedback'));
    await t.pumpAndSettle();
    expect(env.opener.opened.single.toString(), startsWith('mailto:hola@wambito.com'));
    handle.dispose();
  });

  testWidgets('Lo que viene and Abrir Wambito en la web open the same pages as before', (t) async {
    final env = await _pump(t);
    await t.tap(_row('settings.web'));
    await t.pumpAndSettle();
    await t.tap(_row('settings.roadmap'));
    await t.pumpAndSettle();
    expect(env.opener.opened.map((u) => u.toString()), [
      'https://app.wambito.com',
      'https://app.wambito.com/roadmap',
    ]);
  });

  testWidgets('Servidor offline says today\'s offline text', (t) async {
    await _pump(t, health: const ServerHealth.offline());
    expect(find.text('No responde'), findsOneWidget);
    expect(find.text('Conectado'), findsNothing);
  });

  testWidgets('Servidor opens the change-server form', (t) async {
    await _pump(t);
    await t.tap(_row('settings.server'));
    await t.pumpAndSettle();
    expect(find.text('Cambiar de servidor'), findsOneWidget);
    expect(_row('settings.server.field'), findsOneWidget);
  });

  testWidgets('Acerca de opens /settings/about', (t) async {
    final env = await _pump(t);
    await t.tap(_row('settings.about'));
    await t.pumpAndSettle();
    expect(env.router.state.uri.path, '/settings/about');
  });
}
