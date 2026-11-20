// What Settings does with passkeys, as the web's `livePasskeys` and `addPasskey` do
// (apps/web/app/features/settings/passkeys.ts, apps/web/app/auth/passkey.ts): list, add, delete.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/api/auth_api.dart';
import 'package:wambito/local/prf.dart' show PasskeyPrf;
import 'package:wambito/settings/passkeys_settings.dart';

import '../entry/fakes.dart';
import 'harness.dart';

void main() {
  testWidgets('lists the account\'s passkeys with the session\'s token, oldest first', (t) async {
    final auth = FakeAuthApi()
      ..passkeyItems.addAll([
        PasskeyItem(id: 'a', createdAt: DateTime.utc(2026, 10, 2, 9), synced: true),
        PasskeyItem(id: 'b', name: 'Pixel', createdAt: DateTime.utc(2026, 10, 5, 10)),
      ]);
    final env = await pumpSettingsApp(t, auth: auth);
    final passkeys = env.container.read(settingsPasskeysProvider);
    final items = await passkeys.list();
    expect(items.map((p) => p.id), ['a', 'b']);
    expect(auth.calls, contains('listPasskeys email-token-0'));
  });

  testWidgets('says whether this phone can make one', (t) async {
    final env = await pumpSettingsApp(t, passkeysSupported: true);
    expect(await env.container.read(settingsPasskeysProvider).supported(), isTrue);
    env.passkeys.isSupported = false;
    expect(await env.container.read(settingsPasskeysProvider).supported(), isFalse);
  });

  group('adding one', () {
    testWidgets('asks the phone and tells the server: it is added', (t) async {
      final env = await pumpSettingsApp(t, passkeysSupported: true);
      final outcome = await env.container.read(settingsPasskeysProvider).add();
      expect(outcome, PasskeyOutcome.added);
      expect(env.auth.calls, contains('passkeyRegisterOptions email-token-0'));
      expect(env.auth.calls.any((c) => c.startsWith('passkeyRegister email-token-0')), isTrue);
      expect(env.auth.passkeyItems, hasLength(1));
    });

    testWidgets('closing the phone\'s prompt is silent: cancelled, nothing sent', (t) async {
      final env = await pumpSettingsApp(t, passkeysSupported: true);
      env.passkeys.failure = const AuthFailure(code: 'AUTH_CANCELLED', status: 400);
      final outcome = await env.container.read(settingsPasskeysProvider).add();
      expect(outcome, PasskeyOutcome.cancelled);
      expect(env.auth.passkeyItems, isEmpty);
    });

    testWidgets('a passkey this phone already has counts as added', (t) async {
      final env = await pumpSettingsApp(t, passkeysSupported: true);
      env.passkeys.failure = const AuthFailure(
        code: 'ERROR_AUTHENTICATOR_PREVIOUSLY_REGISTERED',
        status: 400,
      );
      expect(await env.container.read(settingsPasskeysProvider).add(), PasskeyOutcome.added);
    });

    testWidgets('anything else that goes wrong is a failure, never a crash', (t) async {
      final env = await pumpSettingsApp(t, passkeysSupported: true);
      final passkeys = env.container.read(settingsPasskeysProvider);
      env.passkeys.failure = const AuthFailure(code: 'PASSKEY_FAILED', status: 400);
      expect(await passkeys.add(), PasskeyOutcome.failed);
      env.auth.failures['passkeyRegister'] = const AuthFailure(status: 0);
      expect(await passkeys.add(), PasskeyOutcome.failed);
      env.auth.failures['passkeyRegisterOptions'] = StateError('a bug');
      expect(await passkeys.add(), PasskeyOutcome.failed);
    });
  });

  group('adding one that opens the data too (an encrypted account)', () {
    // 32 bytes of 7, base64url
    final prfBytes = List.filled(32, 7);
    final prfText = base64Url.encode(prfBytes).replaceAll('=', '');

    Future<(SettingsEnv, List<PasskeyPrf>, List<String>)> run(
      WidgetTester t, {
      required String attestation,
      String? assertion,
    }) async {
      final env = await pumpSettingsApp(t, passkeysSupported: true);
      env.passkeys.createJson = attestation;
      if (assertion != null) env.passkeys.getJson = assertion;
      final kept = <PasskeyPrf>[];
      final told = <String>[];
      final copies = <List<int>>[];
      final outcome = await env.container
          .read(settingsPasskeysProvider)
          .add(
            prf: PasskeyPrfUse(
              explainSecondTouch: () => told.add('second touch'),
              keep: (p) async {
                kept.add(p);
                copies.add(List.of(p.prf));
              },
              onNoPrf: () => told.add('no prf'),
            ),
          );
      expect(outcome, PasskeyOutcome.added);
      // what keep saw, before the bytes were zeroed
      for (final (i, k) in kept.indexed) {
        expect(copies[i], isNot(everyElement(0)));
        expect(k.prf, everyElement(0));
      }
      return (env, kept, told);
    }

    testWidgets('the registration asks for the PRF, and its output goes to keep', (t) async {
      final (env, kept, told) = await run(
        t,
        attestation:
            '{"id":"cred-1","clientExtensionResults":{"prf":{"enabled":true,"results":{"first":"$prfText"}}}}',
      );
      expect(kept.single.credentialId, 'cred-1');
      expect(told, isEmpty);
      final create = env.passkeys.calls.firstWhere((c) => c.startsWith('create '));
      expect(create, contains('"prf":{"eval":{"first"'));
    });

    testWidgets('prf enabled without an output: explained, then a second touch of that passkey', (
      t,
    ) async {
      final (env, kept, told) = await run(
        t,
        attestation: '{"id":"cred-1","clientExtensionResults":{"prf":{"enabled":true}}}',
        assertion:
            '{"id":"cred-1","clientExtensionResults":{"prf":{"results":{"first":"$prfText"}}}}',
      );
      expect(told, ['second touch']);
      expect(kept.single.credentialId, 'cred-1');
      final get = env.passkeys.calls.firstWhere((c) => c.startsWith('get '));
      expect(get, contains('"id":"cred-1"'));
    });

    testWidgets('a passkey with no PRF at all is added, nothing is kept, and it is told', (
      t,
    ) async {
      final (_, kept, told) = await run(
        t,
        attestation: '{"id":"cred-1","clientExtensionResults":{}}',
      );
      expect(kept, isEmpty);
      expect(told, ['no prf']);
    });

    testWidgets('prf enabled, and the second touch gives none: told after the second touch', (
      t,
    ) async {
      final (_, kept, told) = await run(
        t,
        attestation: '{"id":"cred-1","clientExtensionResults":{"prf":{"enabled":true}}}',
        assertion: '{"id":"cred-1","clientExtensionResults":{}}',
      );
      expect(kept, isEmpty);
      expect(told, ['second touch', 'no prf']);
    });

    testWidgets('a PRF whose wrap cannot be saved is not a passkey without PRF', (t) async {
      final env = await pumpSettingsApp(t, passkeysSupported: true);
      env.passkeys.createJson =
          '{"id":"cred-1","clientExtensionResults":{"prf":{"enabled":true,"results":{"first":"$prfText"}}}}';
      final told = <String>[];
      final outcome = await env.container
          .read(settingsPasskeysProvider)
          .add(
            prf: PasskeyPrfUse(
              explainSecondTouch: () {},
              keep: (p) async => throw StateError('the wrap was refused'),
              onNoPrf: () => told.add('no prf'),
            ),
          );
      expect(outcome, PasskeyOutcome.added);
      expect(told, isEmpty);
    });

    testWidgets('a cancelled second touch leaves the passkey without a wrap, still added', (
      t,
    ) async {
      final env = await pumpSettingsApp(t, passkeysSupported: true);
      env.passkeys.createJson = '{"id":"cred-1","clientExtensionResults":{"prf":{"enabled":true}}}';
      final kept = <PasskeyPrf>[];
      final told = <String>[];
      // the second touch (a `get`) is cancelled: the first `create` has already answered
      env.passkeys.getFailure = const AuthFailure(code: 'AUTH_CANCELLED', status: 400);
      final outcome = await env.container
          .read(settingsPasskeysProvider)
          .add(
            prf: PasskeyPrfUse(
              explainSecondTouch: () {},
              keep: (p) async => kept.add(p),
              onNoPrf: () => told.add('no prf'),
            ),
          );
      expect(outcome, PasskeyOutcome.added);
      expect(kept, isEmpty);
      // Cancelled is not "gives no PRF": nothing is said.
      expect(told, isEmpty);
    });

    testWidgets('closing the prompt is cancelled, as without a wrap', (t) async {
      final env = await pumpSettingsApp(t, passkeysSupported: true);
      env.passkeys.failure = const AuthFailure(code: 'AUTH_CANCELLED', status: 400);
      final outcome = await env.container
          .read(settingsPasskeysProvider)
          .add(
            prf: PasskeyPrfUse(explainSecondTouch: () {}, keep: (p) async {}),
          );
      expect(outcome, PasskeyOutcome.cancelled);
      expect(env.auth.passkeyItems, isEmpty);
    });
  });

  testWidgets('deletes one by its id', (t) async {
    final auth = FakeAuthApi()
      ..passkeyItems.add(PasskeyItem(id: 'a', createdAt: DateTime.utc(2026, 10, 2)));
    final env = await pumpSettingsApp(t, auth: auth);
    await env.container.read(settingsPasskeysProvider).remove('a');
    expect(auth.calls, contains('deletePasskey a'));
    expect(auth.passkeyItems, isEmpty);
  });
}
