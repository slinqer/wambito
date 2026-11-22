// "Protect your data"'s step 1 against the fake `/v2/keys` (phone-first spec 5.2): a guest account
// set up with its hidden recovery wrap gets a shown one on the same key version, with no rotation.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/local/keys.dart';
import 'package:wambito/protect/protect_actions.dart';
import 'package:wambito/security/screen_lock.dart';
import 'package:wambito/settings/passkeys_settings.dart';
import 'package:wambito/settings/security/recovery_setup_page.dart';
import 'package:wambito/settings/security/security_api.dart';
import 'package:wambito/ui/press_button.dart';
import 'package:wambito/vault/recovery_key_setup_view.dart';
import 'package:wambito/vault/vault_providers.dart' show vaultSessionProvider;

import '../local/fake_keys.dart';
import '../settings/security/fake_security.dart' show FakeLock;
import '../support/fonts.dart';
import '../support/ui_app.dart';
import 'fakes.dart';

/// A guest account set up on this phone: the hidden recovery wrap and this phone's device wrap.
class Guest {
  Guest(this.api, this.options, this.vault, this.hiddenId);

  final FakeKeys api;
  final KeysOptions options;
  final FakeVault vault;
  final String hiddenId;
}

Future<Guest> guest(WidgetTester t, {String? recoveryKeySavedAt}) async {
  final api = FakeKeys();
  final storage = memoryKeyStorage();
  final userId = newUser();
  final options = KeysOptions(userId: userId, dio: api.dio(), storage: storage);
  final vault = FakeVault(userId: userId, recoveryKeySavedAt: recoveryKeySavedAt);
  await t.runAsync(() async {
    await vault.seeded;
    final prepared = await prepareAccount(options, guest: true);
    expect(prepared.recoveryKey, isNull);
    await prepared.commit();
  });
  final hidden = api.wraps.singleWhere((w) => w.kind == 'recovery');
  api.calls.clear();
  return Guest(api, options, vault, hidden.id);
}

class _Protect extends ConsumerWidget {
  const _Protect(this.results, {this.passkey = false});

  final List<Object> results;
  final bool passkey;

  @override
  Widget build(BuildContext context, WidgetRef ref) => PressButton.text(
    'Protect',
    onPressed: () async {
      results.add(
        passkey
            ? await protectWithPasskey(context, ref)
            : await protectWithRecoveryKey(context, ref),
      );
    },
  );
}

Future<List<Object>> pumpProtect(
  WidgetTester t,
  Guest g, {
  LockCheck lock = LockCheck.noLock,
  FakeSettingsPasskeys? passkeys,
  bool passkey = false,
}) async {
  t.view
    ..physicalSize = const Size(824, 2400)
    ..devicePixelRatio = 2;
  addTearDown(t.view.reset);
  final results = <Object>[];
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        securityApiProvider.overrideWithValue(liveSecurity(g.vault, g.options)),
        vaultSessionProvider.overrideWithValue(g.vault),
        screenLockProvider.overrideWithValue(FakeLock(lock)),
        settingsPasskeysProvider.overrideWithValue(passkeys ?? FakeSettingsPasskeys()),
      ],
      child: uiApp(_Protect(results, passkey: passkey), locale: const Locale('en')),
    ),
  );
  return results;
}

/// Lets the real crypto and the fake server answer, then draws.
Future<void> settle(WidgetTester t) async {
  for (var i = 0; i < 5; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await t.pumpAndSettle();
  }
}

String shownKey(WidgetTester t) =>
    t.widget<RecoveryKeySetupView>(find.byType(RecoveryKeySetupView)).recoveryKey;

/// Types back the four characters the page asks for (positions pinned to 1-4), then saves.
Future<void> checkAndSave(WidgetTester t) async {
  final key = shownKey(t).replaceAll('-', '');
  await t.tap(find.byKey(const Key('vault.saved')));
  await t.pumpAndSettle();
  final boxes = find.byType(EditableText);
  for (var i = 0; i < 4; i++) {
    await t.enterText(boxes.at(i), key[i]);
  }
  await t.pump();
  await t.tap(find.byKey(const Key('vault.continue')));
  await settle(t);
}

void main() {
  setUpAll(loadAppFonts);
  setUp(() => setupPositions = const [1, 2, 3, 4]);
  tearDown(() => setupPositions = null);

  testWidgets(
    'the hidden recovery wrap is replaced by a shown one on the same key version, with no rotation',
    (t) async {
      final g = await guest(t);
      final results = await pumpProtect(t, g);
      await t.tap(find.text('PROTECT'));
      await settle(t);
      expect(find.byType(RecoveryKeySetupView), findsOneWidget);
      await checkAndSave(t);

      expect(results, [true]);
      final recovery = g.api.wraps.where((w) => w.kind == 'recovery').toList();
      expect(recovery, hasLength(1));
      expect(recovery.single.id, isNot(g.hiddenId));
      expect(recovery.single.keyV, 1);
      expect(g.api.calls.where((c) => c.path == '/api/v2/keys/rotate'), isEmpty);
      expect(g.api.posts, isEmpty);
      expect(g.api.verifierPuts, hasLength(1));
      expect(g.api.verifier, isNotNull);
      expect(await t.runAsync(g.vault.savedAt), isA<String>());
      final at = DateTime.parse((await t.runAsync(g.vault.savedAt))! as String);
      expect(at.isUtc, isTrue);
      expect(g.vault.syncs, 1);
    },
  );

  testWidgets('rotated_elsewhere makes the key again', (t) async {
    final g = await guest(t);
    var refusals = 1;
    g.api.intercept = (call) {
      if (call.method == 'PUT' && call.path.startsWith('/api/v2/keys/') && refusals > 0) {
        refusals -= 1;
        return (409, {'code': 'key_version_mismatch'});
      }
      return null;
    };
    final results = await pumpProtect(t, g);
    await t.tap(find.text('PROTECT'));
    await settle(t);
    final first = shownKey(t);
    await checkAndSave(t);

    // refused for sure: the keys are reloaded and a new key is shown
    expect(g.vault.reloads, 1);
    expect(find.byType(RecoveryKeySetupView), findsOneWidget);
    final second = shownKey(t);
    expect(second, isNot(first));
    expect(results, isEmpty);
    await checkAndSave(t);

    expect(results, [true]);
    expect(g.api.wraps.where((w) => w.kind == 'recovery'), hasLength(1));
    expect(g.api.wraps.singleWhere((w) => w.kind == 'recovery').id, isNot(g.hiddenId));
    expect(g.api.verifierPuts, hasLength(1));
    expect(await t.runAsync(g.vault.savedAt), isA<String>());
  });

  testWidgets('with no screen lock and no saved key, no recovery key is asked', (t) async {
    final g = await guest(t);
    await pumpProtect(t, g);
    await t.tap(find.text('PROTECT'));
    await settle(t);
    expect(find.byKey(const Key('screenLock.key')), findsNothing);
    expect(find.byType(RecoveryKeySetupView), findsOneWidget);
  });

  testWidgets('with no screen lock and a saved key, the saved key is asked first', (t) async {
    final g = await guest(t, recoveryKeySavedAt: '2026-11-18T10:00:00.000Z');
    await pumpProtect(t, g);
    await t.tap(find.text('PROTECT'));
    await settle(t);
    expect(find.byKey(const Key('screenLock.key')), findsOneWidget);
    expect(find.byType(RecoveryKeySetupView), findsNothing);
  });

  testWidgets('a closed screen lock makes nothing', (t) async {
    final g = await guest(t);
    final results = await pumpProtect(t, g, lock: LockCheck.cancelled);
    await t.tap(find.text('PROTECT'));
    await settle(t);
    expect(results, [false]);
    expect(find.byType(RecoveryKeySetupView), findsNothing);
    expect(g.api.calls.where((c) => c.method == 'PUT'), isEmpty);
  });

  testWidgets('leaving the page before saving sends nothing and marks nothing', (t) async {
    final g = await guest(t);
    final results = await pumpProtect(t, g);
    await t.tap(find.text('PROTECT'));
    await settle(t);
    await t.tap(find.text('CANCEL'));
    await settle(t);
    expect(results, [false]);
    expect(g.api.calls.where((c) => c.method == 'PUT'), isEmpty);
    expect(await t.runAsync(g.vault.savedAt), isNull);
  });

  testWidgets('the passkey step adds a passkey whose PRF goes to a wrap', (t) async {
    final g = await guest(t);
    final passkeys = FakeSettingsPasskeys();
    final results = await pumpProtect(t, g, passkeys: passkeys, passkey: true);
    await t.tap(find.text('PROTECT'));
    await settle(t);
    expect(results, [PasskeyOutcome.added]);
    expect(passkeys.used, isNotNull);
  });

  testWidgets('canLeave false: no Cancel and no way back before the key is saved', (t) async {
    final g = await guest(t);
    t.view
      ..physicalSize = const Size(824, 2400)
      ..devicePixelRatio = 2;
    addTearDown(t.view.reset);
    final results = <bool>[];
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          securityApiProvider.overrideWithValue(liveSecurity(g.vault, g.options)),
          vaultSessionProvider.overrideWithValue(g.vault),
          screenLockProvider.overrideWithValue(FakeLock(LockCheck.noLock)),
        ],
        child: uiApp(
          Consumer(
            builder: (context, ref, _) => PressButton.text(
              'Protect',
              onPressed: () async =>
                  results.add(await protectWithRecoveryKey(context, ref, canLeave: false)),
            ),
          ),
          locale: const Locale('en'),
        ),
      ),
    );
    await t.tap(find.text('PROTECT'));
    await settle(t);
    expect(find.text('CANCEL'), findsNothing);
    final popped = await t.binding.handlePopRoute();
    await settle(t);
    expect(popped, isTrue);
    expect(find.byType(RecoveryKeySetupView), findsOneWidget);
    await checkAndSave(t);
    expect(results, [true]);
  });
}
