// "Entrar con tu huella" in Settings (apps/web/app/features/settings/PasskeysSection.tsx): the
// passkeys listed with their name and when they were made, one added through the phone's prompt, one
// deleted after asking. A guest cannot add one from here.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/api/auth_api.dart';
import 'package:wambito/home/home_controller.dart';
import 'package:wambito/router.dart';
import 'package:wambito/vault/preview.dart' show isPreviewProvider;

import '../entry/fakes.dart';
import '../home/fakes.dart';
import 'harness.dart';

final _now = DateTime.utc(2026, 10, 21, 15);

PasskeyItem _key(String id, {String? name, DateTime? at, bool synced = false}) =>
    PasskeyItem(id: id, name: name, createdAt: at ?? DateTime.utc(2026, 10, 2, 14), synced: synced);

Future<SettingsEnv> _pump(
  WidgetTester t, {
  List<PasskeyItem> keys = const [],
  bool supported = true,
  bool guest = false,
  Locale locale = const Locale('es'),
  Object? listFailure,
  List<Override> overrides = const [],
}) async {
  final auth = FakeAuthApi()..passkeyItems.addAll(keys);
  if (listFailure != null) auth.failures['listPasskeys'] = listFailure;
  final env = await pumpSettingsApp(
    t,
    auth: auth,
    guest: guest,
    locale: locale,
    passkeysSupported: supported,
    homeRepo: FakeHomeRepository(timezone: 'America/Bogota'),
    overrides: [clockProvider.overrideWithValue(() => _now), ...overrides],
  );
  env.container.read(routerProvider).go('/settings/account');
  await t.pumpAndSettle();
  return env;
}

/// A test with the screen reader's tree on, for the texts [said] finds.
void testPage(String name, Future<void> Function(WidgetTester t) body) =>
    testWidgets(name, (t) async {
      final handle = t.ensureSemantics();
      await body(t);
      handle.dispose();
    });

/// A text drawn by `CssParagraph`: found by what a screen reader reads.
Finder said(String text) => find.bySemanticsLabel(text);

Future<void> _scrollTo(WidgetTester t, String key) async {
  await t.scrollUntilVisible(find.byKey(Key(key)), 200, scrollable: find.byType(Scrollable).first);
  await t.pumpAndSettle();
}

void main() {
  group('the list', () {
    testPage('shows each passkey: its name or "Huella", when it was made, and whether it syncs', (
      t,
    ) async {
      await _pump(
        t,
        keys: [
          _key('a', synced: true),
          _key('b', name: 'Pixel', at: DateTime.utc(2026, 10, 5, 10)),
        ],
      );
      await _scrollTo(t, 'settings.passkeys.add');
      expect(said('Entrar con tu huella'), findsWidgets);
      expect(
        said(
          'Una passkey es una llave guardada en tu teléfono o en tu gestor de contraseñas. Tu huella o tu cara solo la desbloquean, y tu correo sigue funcionando.',
        ),
        findsOneWidget,
      );
      expect(find.text('Huella'), findsOneWidget);
      expect(find.text('Pixel'), findsOneWidget);
      expect(find.text('Creada el 2 oct 2026'), findsOneWidget);
      expect(find.text('Creada el 5 oct 2026'), findsOneWidget);
      expect(find.text('Sincronizada'), findsOneWidget, reason: 'only the synced one');
    });

    testPage(
      'dates a passkey in the profile\'s zone: 02:00 UTC is still the day before in Bogota',
      (t) async {
        await _pump(t, keys: [_key('a', at: DateTime.utc(2026, 10, 3, 2))]);
        await _scrollTo(t, 'settings.passkeys.add');
        expect(find.text('Creada el 2 oct 2026'), findsOneWidget);
      },
    );

    testPage('names each delete button by the passkey, for a screen reader', (t) async {
      final handle = t.ensureSemantics();
      await _pump(
        t,
        keys: [
          _key('a'),
          _key('b', name: 'Pixel', at: DateTime.utc(2026, 10, 5, 10)),
        ],
      );
      await _scrollTo(t, 'settings.passkeys.add');
      expect(find.bySemanticsLabel('Eliminar la huella creada el 2 oct 2026'), findsOneWidget);
      expect(find.bySemanticsLabel('Eliminar Pixel, creada el 5 oct 2026'), findsOneWidget);
      handle.dispose();
    });

    testPage('says there are none, and that the email keeps working', (t) async {
      await _pump(t);
      await _scrollTo(t, 'settings.passkeys.add');
      expect(said('Aún no tienes ninguna: entras con el código de tu correo.'), findsOneWidget);
    });

    testPage('says when the list cannot be read', (t) async {
      await _pump(t, listFailure: const AuthFailure(status: 0));
      await _scrollTo(t, 'settings.passkeys.add');
      expect(
        said('No pudimos cargar tus huellas. Inténtalo de nuevo en un momento.'),
        findsOneWidget,
      );
    });

    testPage('in English, with the web\'s English words', (t) async {
      await _pump(t, locale: const Locale('en'), keys: [_key('a', synced: true)]);
      await _scrollTo(t, 'settings.passkeys.add');
      expect(said('Sign in with your fingerprint'), findsWidgets);
      expect(find.text('Fingerprint'), findsOneWidget);
      expect(find.text('Created on Oct 2, 2026'), findsOneWidget);
      expect(find.text('Synced'), findsOneWidget);
      expect(find.text('ADD A FINGERPRINT'), findsOneWidget);
    });
  });

  group('adding one', () {
    testPage('asks the phone, then lists the new one and says so', (t) async {
      final env = await _pump(t, keys: [_key('a')]);
      await _scrollTo(t, 'settings.passkeys.add');
      await t.tap(find.byKey(const Key('settings.passkeys.add')));
      await t.pumpAndSettle();
      expect(env.passkeys.calls.where((c) => c.startsWith('create')), hasLength(1));
      expect(find.text('Listo: ya puedes entrar con tu huella.'), findsOneWidget);
      expect(find.textContaining('Creada el'), findsNWidgets(2));
      await t.pump(const Duration(seconds: 10));
    });

    testPage('while the prompt is open it says so and cannot be pressed again', (t) async {
      final env = await _pump(t);
      final gate = Completer<void>();
      env.passkeys.holdCreate = gate;
      await _scrollTo(t, 'settings.passkeys.add');
      await t.tap(find.byKey(const Key('settings.passkeys.add')));
      await t.pump();
      expect(find.text('ESPERANDO TU HUELLA…'), findsOneWidget);
      await t.tap(find.byKey(const Key('settings.passkeys.add')), warnIfMissed: false);
      await t.pump();
      gate.complete();
      await t.pumpAndSettle();
      expect(env.passkeys.calls.where((c) => c.startsWith('create')), hasLength(1));
      expect(find.text('AGREGAR UNA HUELLA'), findsOneWidget);
      await t.pump(const Duration(seconds: 10));
    });

    testPage('closing the prompt is silent', (t) async {
      final env = await _pump(t);
      env.passkeys.failure = const AuthFailure(code: 'AUTH_CANCELLED', status: 400);
      await _scrollTo(t, 'settings.passkeys.add');
      await t.tap(find.byKey(const Key('settings.passkeys.add')));
      await t.pumpAndSettle();
      expect(find.textContaining('Listo'), findsNothing);
      expect(find.textContaining('No pudimos'), findsNothing);
      expect(find.text('AGREGAR UNA HUELLA'), findsOneWidget);
    });

    testPage('a failure says so and can be tried again', (t) async {
      final env = await _pump(t);
      env.passkeys.failure = const AuthFailure(code: 'PASSKEY_FAILED', status: 400);
      await _scrollTo(t, 'settings.passkeys.add');
      await t.tap(find.byKey(const Key('settings.passkeys.add')));
      await t.pumpAndSettle();
      expect(find.text('No pudimos guardar tu huella. Inténtalo otra vez.'), findsOneWidget);
      await t.pump(const Duration(seconds: 10));
      await t.tap(find.byKey(const Key('settings.passkeys.add')));
      await t.pumpAndSettle();
      expect(find.text('Listo: ya puedes entrar con tu huella.'), findsOneWidget);
      await t.pump(const Duration(seconds: 10));
    });

    testPage('a phone that cannot make one says so, and still lists and deletes', (t) async {
      await _pump(t, supported: false, keys: [_key('a')]);
      await _scrollTo(t, 'settings.passkeys.remove.a');
      expect(
        said('Este teléfono no permite crear huellas. Sigue entrando con tu correo.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('settings.passkeys.add')), findsNothing);
      expect(find.byKey(const Key('settings.passkeys.remove.a')), findsOneWidget);
    });

    testPage('is refused for a guest: the button is off, and the line says what to do first', (
      t,
    ) async {
      final env = await _pump(t, guest: true);
      await _scrollTo(t, 'settings.passkeys.add');
      expect(
        said('Primero guarda tu progreso con un correo; después podrás agregar una huella.'),
        findsOneWidget,
      );
      await t.tap(find.byKey(const Key('settings.passkeys.add')), warnIfMissed: false);
      await t.pumpAndSettle();
      expect(env.passkeys.calls.where((c) => c.startsWith('create')), isEmpty);
      expect(env.auth.calls.where((c) => c.startsWith('passkeyRegister')), isEmpty);
    });

    testPage('a preview guest may add one: no line, and the button works', (t) async {
      // "Protect your data" step 2 offers a passkey to a guest of an encrypted account.
      final env = await _pump(
        t,
        guest: true,
        overrides: [isPreviewProvider.overrideWithValue(true)],
      );
      await _scrollTo(t, 'settings.passkeys.add');
      expect(
        said('Primero guarda tu progreso con un correo; después podrás agregar una huella.'),
        findsNothing,
      );
      await t.tap(find.byKey(const Key('settings.passkeys.add')));
      await t.pumpAndSettle();
      expect(env.auth.calls.where((c) => c.startsWith('passkeyRegister')), isNotEmpty);
    });

    testPage('a guest still sees the passkeys already made on the account', (t) async {
      await _pump(t, guest: true, keys: [_key('a', name: 'Pixel')]);
      await _scrollTo(t, 'settings.passkeys.add');
      expect(find.text('Pixel'), findsOneWidget);
    });
  });

  group('deleting one', () {
    testPage('asks first, in the web\'s words; "Cancelar" leaves it', (t) async {
      final env = await _pump(t, keys: [_key('a')]);
      await _scrollTo(t, 'settings.passkeys.remove.a');
      await t.tap(find.byKey(const Key('settings.passkeys.remove.a')));
      await t.pumpAndSettle();
      expect(find.text('¿Eliminar esta huella?'), findsOneWidget);
      expect(
        find.text('Ya no podrás entrar con ella. Tu correo sigue funcionando.'),
        findsOneWidget,
      );
      await t.tap(find.text('CANCELAR'));
      await t.pumpAndSettle();
      expect(find.text('¿Eliminar esta huella?'), findsNothing);
      expect(env.auth.passkeyItems, hasLength(1));
      expect(env.auth.calls.where((c) => c.startsWith('deletePasskey')), isEmpty);
    });

    testPage('"Sí, eliminar" deletes it, and says so', (t) async {
      final env = await _pump(
        t,
        keys: [
          _key('a'),
          _key('b', name: 'Pixel'),
        ],
      );
      await _scrollTo(t, 'settings.passkeys.remove.a');
      await t.tap(find.byKey(const Key('settings.passkeys.remove.a')));
      await t.pumpAndSettle();
      await t.tap(find.text('SÍ, ELIMINAR'));
      await t.pumpAndSettle();
      expect(env.auth.calls, contains('deletePasskey a'));
      expect(find.text('¿Eliminar esta huella?'), findsNothing);
      expect(find.text('Eliminamos la huella.'), findsOneWidget);
      expect(find.byKey(const Key('settings.passkeys.remove.a')), findsNothing);
      expect(find.text('Pixel'), findsOneWidget);
      await t.pump(const Duration(seconds: 10));
    });

    testPage('a refusal says why and keeps the sheet for another try', (t) async {
      final env = await _pump(t, keys: [_key('a')]);
      env.auth.failures['deletePasskey'] = const AuthFailure(status: 503);
      await _scrollTo(t, 'settings.passkeys.remove.a');
      await t.tap(find.byKey(const Key('settings.passkeys.remove.a')));
      await t.pumpAndSettle();
      await t.tap(find.text('SÍ, ELIMINAR'));
      await t.pumpAndSettle();
      expect(find.text('No pudimos eliminar la huella. Inténtalo otra vez.'), findsOneWidget);
      expect(find.text('¿Eliminar esta huella?'), findsOneWidget);
      expect(env.auth.passkeyItems, hasLength(1));
      await t.pump(const Duration(seconds: 10));
    });
  });
}
