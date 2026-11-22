// Cuenta y seguridad, the light version (spec 2026-11-22; twin of AccountScreen.stories.tsx): the
// email, a group of passkeys, (encrypted accounts) a group of devices and the recovery key rows,
// and the delete row in red. A plain account has only the passkeys and the delete row; the trash
// buttons and the delete row open the existing confirmation and sheet.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/api/auth_api.dart';
import 'package:wambito/home/home_controller.dart';
import 'package:wambito/security/screen_lock.dart';
import 'package:wambito/settings/security/security_api.dart';
import 'package:wambito/vault/preview.dart' show isPreviewProvider;

import '../entry/fakes.dart';
import '../home/fakes.dart';
import 'harness.dart';
import 'security/fake_security.dart';

final _now = DateTime.utc(2026, 11, 22, 15);

final _passkeys = [
  PasskeyItem(id: 'pk-1', name: 'Pixel 8', createdAt: DateTime.utc(2026, 11, 3, 14), synced: true),
  PasskeyItem(id: 'pk-2', name: 'MacBook', createdAt: DateTime.utc(2026, 11, 18, 14)),
];

Future<SettingsEnv> _pump(WidgetTester t, {bool encrypted = false, FakeSecurity? security}) async {
  final auth = FakeAuthApi()..passkeyItems.addAll(_passkeys);
  final env = await pumpSettingsApp(
    t,
    auth: auth,
    passkeysSupported: true,
    locale: const Locale('es'),
    homeRepo: FakeHomeRepository(timezone: 'America/Bogota', email: 'ana@example.com'),
    overrides: [
      clockProvider.overrideWithValue(() => _now),
      if (encrypted) ...[
        isPreviewProvider.overrideWithValue(true),
        securityApiProvider.overrideWithValue(security ?? FakeSecurity()),
        screenLockProvider.overrideWithValue(FakeLock(LockCheck.passed)),
      ],
    ],
    location: '/settings/account',
  );
  return env;
}

Finder _said(String text) => find.bySemanticsLabel(text);

void main() {
  testWidgets('a plain account: the email, the passkeys group and the delete row only', (t) async {
    final handle = t.ensureSemantics();
    await _pump(t);
    expect(find.text('Cuenta y seguridad'), findsWidgets);
    expect(find.text('ana@example.com'), findsOneWidget);
    expect(find.text('Entrar con tu huella'), findsOneWidget);
    expect(find.text('Sin código, con tu huella o tu cara'), findsOneWidget);
    expect(find.text('Pixel 8'), findsOneWidget);
    expect(find.text('Desde el 3 nov 2026 · sincronizada'), findsOneWidget);
    expect(find.text('Desde el 18 nov 2026'), findsOneWidget);
    expect(find.byKey(const Key('settings.passkeys.remove.pk-1')), findsOneWidget);
    expect(find.bySemanticsLabel('Eliminar Pixel 8'), findsOneWidget);
    expect(find.text('Agregar una huella'), findsOneWidget);
    expect(find.byKey(const Key('settings.passkeys.add')), findsOneWidget);
    await t.scrollUntilVisible(
      find.byKey(const Key('settings.delete')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Eliminar tu cuenta'), findsOneWidget);
    expect(find.text('Borra tu cuenta y tus movimientos'), findsOneWidget);
    expect(find.text('Tus dispositivos'), findsNothing);
    expect(find.text('Clave de recuperación'), findsNothing);
    expect(find.byKey(const Key('security.newKey')), findsNothing);
    handle.dispose();
  });

  testWidgets('an encrypted account has all four, this phone marked "Este" with no trash', (
    t,
  ) async {
    await _pump(t, encrypted: true);
    await t.scrollUntilVisible(
      find.byKey(const Key('security.connect')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Tus dispositivos'), findsOneWidget);
    expect(find.text('Pueden abrir tus datos cifrados'), findsOneWidget);
    expect(find.text('Pixel 9'), findsOneWidget);
    expect(find.text('Este'), findsOneWidget);
    expect(find.byKey(const Key('security.remove.$ownId')), findsNothing);
    expect(find.byKey(const Key('security.remove.$laptopId')), findsOneWidget);
    expect(find.text('Conectar otro dispositivo'), findsOneWidget);
    await t.scrollUntilVisible(
      find.byKey(const Key('security.newKey')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Clave de recuperación'), findsOneWidget);
    expect(find.text('Crea una nueva si la perdiste'), findsOneWidget);
    expect(find.byKey(const Key('settings.delete')), findsOneWidget);
  });

  testWidgets('a passkey\'s trash asks the existing confirmation first', (t) async {
    await _pump(t);
    await t.tap(find.byKey(const Key('settings.passkeys.remove.pk-2')));
    await t.pumpAndSettle();
    expect(_said('¿Eliminar esta huella?'), findsWidgets);
    expect(find.byKey(const Key('settings.passkeys.remove.confirm')), findsOneWidget);
  });

  testWidgets('the delete row opens the sheet with its full text and the export-first button', (
    t,
  ) async {
    final handle = t.ensureSemantics();
    await _pump(t);
    await t.scrollUntilVisible(
      find.byKey(const Key('settings.delete')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await t.tap(find.byKey(const Key('settings.delete')));
    await t.pumpAndSettle();
    expect(
      _said(
        'Se borran de inmediato tus movimientos, categorías, presupuestos, recurrentes y huellas. Las copias de seguridad que los incluyan se borran solas en 14 días.',
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('settings.delete.export')), findsOneWidget);
    expect(find.text('DESCARGA TUS DATOS ANTES'), findsOneWidget);
    handle.dispose();
  });
}
