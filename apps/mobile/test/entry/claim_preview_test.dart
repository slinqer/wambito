// A `preview` guest adds an email (phone-first spec 7.1, ruling 20): the claim, then the recovery
// key with no way out until it is saved (unless one was saved already), then the passkey offer, once.
// An email that has an account already offers the merge (spec 7.2): yes holds the guest's vault and
// sends that email's code; no leaves everything as it was.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/api/auth_api.dart';
import 'package:wambito/api/session.dart';
import 'package:wambito/entry/passkey_offer_screen.dart';
import 'package:wambito/home/home_screen.dart';
import 'package:wambito/l10n/app_localizations.dart';
import 'package:wambito/merge/merge_controller.dart';
import 'package:wambito/local/prf.dart' show PasskeyPrf;
import 'package:wambito/protect/protect_actions.dart';
import 'package:wambito/protect/protect_status.dart';
import 'package:wambito/security/screen_lock.dart';
import 'package:wambito/settings/passkeys_settings.dart';
import 'package:wambito/settings/security/recovery_setup_page.dart';
import 'package:wambito/settings/security/security_api.dart';
import 'package:wambito/vault/preview.dart' show isPreviewProvider;
import 'package:wambito/vault/recovery_key_setup_view.dart';
import 'package:wambito/vault/vault_providers.dart' show vaultSessionProvider;

import '../protect/fakes.dart' show FakeVault;
import '../settings/harness.dart';
import '../settings/security/fake_security.dart';

/// A merge that only records what the email screen asks of it.
class _Merge extends MergeController {
  final asked = <String>[];

  @override
  MergeState build() => const MergeIdle();

  @override
  String? get guestUserId => asked.any((a) => a.startsWith('begin')) ? 'user-1' : null;

  @override
  Future<void> begin(String email) async {
    asked.add('begin $email');
    state = MergeSigningIn(email);
  }

  @override
  Future<void> cancel() async {
    asked.add('cancel');
    state = const MergeIdle();
  }

  @override
  Future<void> resume() async {}

  @override
  Future<void> run() async {}
}

/// The claim's owed keys, in memory, kept across a restart of the app.
class _Marks implements KeyAfterClaimMarks {
  final owing = <String>{};

  @override
  Future<bool> owed(String userId) async => owing.contains(userId);

  @override
  Future<void> owe(String userId) async => owing.add(userId);

  @override
  Future<void> clear(String userId) async => owing.remove(userId);
}

/// The account's passkeys: adding one gives its PRF to the wrap when [givesPrf].
class _PrfPasskeys implements SettingsPasskeys {
  _PrfPasskeys({required this.givesPrf});

  final bool givesPrf;
  var adds = 0;

  @override
  Future<bool> supported() async => true;

  @override
  Future<List<PasskeyItem>> list() async => [];

  @override
  Future<PasskeyOutcome> add({PasskeyPrfUse? prf}) async {
    adds += 1;
    if (givesPrf && prf != null) {
      await prf.keep(PasskeyPrf(credentialId: 'cred-1', prf: Uint8List(32)));
    }
    return PasskeyOutcome.added;
  }

  @override
  Future<void> remove(String id) async {}
}

class _Preview {
  _Preview(this.env, this.vault, this.security, this.merge, this.marks);

  final SettingsEnv env;
  final FakeVault vault;
  final FakeSecurity security;
  final _Merge merge;
  final _Marks marks;
}

/// A `preview` guest on `/progress`, its vault open, the phone with passkeys. With [guest] false
/// and [location] null, the same phone started again after the claim ([vault] and [marks] kept).
Future<_Preview> _pumpPreviewGuest(
  WidgetTester t, {
  String? recoveryKeySavedAt,
  bool guest = true,
  String? location = '/progress',
  FakeVault? vault,
  _Marks? marks,
  LockCheck lock = LockCheck.noLock,
  SettingsPasskeys? passkeys,
}) async {
  vault ??= FakeVault(recoveryKeySavedAt: recoveryKeySavedAt);
  await t.runAsync(() => vault!.seeded);
  marks ??= _Marks();
  final security = FakeSecurity();
  final merge = _Merge();
  final env = await pumpSettingsApp(
    t,
    guest: guest,
    passkeysSupported: true,
    location: location,
    overrides: [
      keyAfterClaimMarksProvider.overrideWithValue(marks),
      settingsPasskeysProvider.overrideWithValue(passkeys ?? _PrfPasskeys(givesPrf: true)),
      isPreviewProvider.overrideWithValue(true),
      vaultSessionProvider.overrideWithValue(vault),
      securityApiProvider.overrideWithValue(security),
      securitySnapshotProvider.overrideWith((ref) async => snapshotOf()),
      screenLockProvider.overrideWithValue(FakeLock(lock)),
      protectStatusProvider.overrideWith(
        (ref) async => const ProtectStatus(
          recoveryKey: false,
          passkey: false,
          passkeyOffered: true,
          passkeyWithoutPrf: false,
        ),
      ),
      mergeControllerProvider.overrideWith(() => merge),
    ],
  );
  // The vault's open at start: home's look for an owed key runs after a frame.
  await _settle(t);
  return _Preview(env, vault, security, merge, marks);
}

/// Lets the fake vault's queue (built in the real zone) and the screens answer.
Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 4; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await t.pumpAndSettle();
  }
}

Future<void> _claim(WidgetTester t, String email) async {
  await t.enterText(find.byKey(const Key('progress.email')), email);
  await t.tap(find.byKey(const Key('progress.save')));
  await t.pumpAndSettle();
}

Future<void> _enterCode(WidgetTester t, String code) async {
  await t.enterText(find.byKey(const Key('entry.code')), code);
  await t.pump();
  await t.tap(find.byKey(const Key('entry.submitCode')));
  await _settle(t);
}

/// Types back the four characters the page asks for (positions pinned to 1-4), then saves.
Future<void> _checkAndSave(WidgetTester t) async {
  final key = t
      .widget<RecoveryKeySetupView>(find.byType(RecoveryKeySetupView))
      .recoveryKey
      .replaceAll('-', '');
  await t.tap(find.byKey(const Key('vault.saved')));
  await t.pumpAndSettle();
  final boxes = find.byType(EditableText);
  for (var i = 0; i < 4; i++) {
    await t.enterText(boxes.at(i), key[i]);
  }
  await t.pump();
  await t.tap(find.byKey(const Key('vault.continue')));
  await _settle(t);
}

void main() {
  setUp(() => setupPositions = const [1, 2, 3, 4]);
  tearDown(() => setupPositions = null);

  group('a preview guest adds an email', () {
    testWidgets(
      'after the claim the recovery key page shows with no way out, then the passkey offer',
      (t) async {
        final p = await _pumpPreviewGuest(t);
        await _claim(t, 'ana@correo.com');
        await _enterCode(t, '123456');

        expect(p.env.auth.calls, contains('claimVerify guest-token-0 ana@correo.com 123456'));
        expect(p.env.stored?.guest, isFalse);
        expect(find.byType(RecoveryKeySetupView), findsOneWidget);
        // No Cancel, and back keeps the page.
        expect(find.text('CANCELAR'), findsNothing);
        await t.binding.handlePopRoute();
        await _settle(t);
        expect(find.byType(RecoveryKeySetupView), findsOneWidget);
        // Nothing else is offered while the key waits.
        expect(p.env.container.read(sessionProvider).offerPasskeyFor, isNull);

        await _checkAndSave(t);

        expect(p.security.calls, containsAllInOrder(['newRecoveryKey', 'commit']));
        expect(await t.runAsync(p.vault.savedAt), isA<String>());
        expect(find.byType(RecoveryKeySetupView), findsNothing);
        expect(find.byType(PasskeyOfferScreen), findsOneWidget);
      },
    );

    testWidgets('an account whose key was already saved goes straight to the passkey offer', (
      t,
    ) async {
      final p = await _pumpPreviewGuest(t, recoveryKeySavedAt: '2026-11-01T10:00:00.000Z');
      await _claim(t, 'ana@correo.com');
      await _enterCode(t, '123456');

      expect(find.byType(RecoveryKeySetupView), findsNothing);
      expect(p.security.calls, isNot(contains('newRecoveryKey')));
      expect(find.byType(PasskeyOfferScreen), findsOneWidget);
    });

    testWidgets('the passkey is offered exactly once', (t) async {
      final p = await _pumpPreviewGuest(t, recoveryKeySavedAt: '2026-11-01T10:00:00.000Z');
      await _claim(t, 'ana@correo.com');
      await _enterCode(t, '123456');
      expect(find.byType(PasskeyOfferScreen), findsOneWidget);
      // Asked once: by the step after the claim, not by the claim too.
      expect(p.env.auth.calls.where((c) => c.startsWith('passkeyCount')), hasLength(1));

      await t.tap(find.byKey(const Key('offer.notNow')));
      await _settle(t);
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(p.env.container.read(sessionProvider).offerPasskeyFor, isNull);

      // Asking again (another claim's end, say) offers nothing: the answer is kept for the account.
      await p.env.container.read(sessionProvider.notifier).offerPasskey();
      await _settle(t);
      expect(p.env.container.read(sessionProvider).offerPasskeyFor, isNull);
      expect(find.byType(PasskeyOfferScreen), findsNothing);
    });

    testWidgets('killed on the key page: on the next start the key page shows again', (t) async {
      final p = await _pumpPreviewGuest(t);
      await _claim(t, 'ana@correo.com');
      await _enterCode(t, '123456');
      expect(find.byType(RecoveryKeySetupView), findsOneWidget);
      expect(p.marks.owing, {'user-1'});

      // The process dies here; the phone starts again signed in to the account with its email.
      final again = await _pumpPreviewGuest(
        t,
        guest: false,
        location: null,
        vault: p.vault,
        marks: p.marks,
      );
      expect(find.byType(RecoveryKeySetupView), findsOneWidget);
      expect(find.text('CANCELAR'), findsNothing);
      await _checkAndSave(t);
      expect(again.marks.owing, isEmpty);
      expect(find.byType(PasskeyOfferScreen), findsOneWidget);
    });

    testWidgets('the screen lock refused: the key is still owed and no passkey offer', (t) async {
      final p = await _pumpPreviewGuest(t, lock: LockCheck.cancelled);
      await _claim(t, 'ana@correo.com');
      await _enterCode(t, '123456');

      expect(p.env.stored?.guest, isFalse);
      expect(find.byType(RecoveryKeySetupView), findsNothing);
      expect(find.byType(PasskeyOfferScreen), findsNothing);
      expect(p.env.container.read(sessionProvider).offerPasskeyFor, isNull);
      expect(p.marks.owing, {'user-1'});

      // The next time the vault opens, the key page comes back.
      await _pumpPreviewGuest(t, guest: false, location: null, vault: p.vault, marks: p.marks);
      expect(find.byType(RecoveryKeySetupView), findsOneWidget);
      await _checkAndSave(t);
      expect(p.marks.owing, isEmpty);
      expect(find.byType(PasskeyOfferScreen), findsOneWidget);
    });

    testWidgets('the passkey offered after the claim wraps the data key with its PRF', (t) async {
      final passkeys = _PrfPasskeys(givesPrf: true);
      final p = await _pumpPreviewGuest(
        t,
        recoveryKeySavedAt: '2026-11-01T10:00:00.000Z',
        passkeys: passkeys,
      );
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));
      await _claim(t, 'ana@correo.com');
      await _enterCode(t, '123456');
      await t.tap(find.byKey(const Key('offer.add')));
      await _settle(t);

      expect(passkeys.adds, 1);
      expect(p.security.calls, contains('addPasskeyWrap cred-1'));
      expect(p.env.auth.calls.where((c) => c.startsWith('passkeyRegister ')), isEmpty);
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.text(l10n.passkeyOfferAdded), findsOneWidget);
      expect(find.text(l10n.protectPasskeyNoPrf), findsNothing);
    });

    testWidgets('a passkey with no PRF says it cannot open the data', (t) async {
      final passkeys = _PrfPasskeys(givesPrf: false);
      final p = await _pumpPreviewGuest(
        t,
        recoveryKeySavedAt: '2026-11-01T10:00:00.000Z',
        passkeys: passkeys,
      );
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));
      await _claim(t, 'ana@correo.com');
      await _enterCode(t, '123456');
      await t.tap(find.byKey(const Key('offer.add')));
      await _settle(t);

      expect(passkeys.adds, 1);
      expect(p.security.calls.where((c) => c.startsWith('addPasskeyWrap')), isEmpty);
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.text(l10n.protectPasskeyNoPrf), findsOneWidget);
    });

    testWidgets('the preview /progress says what an email adds and has no passkey section', (
      t,
    ) async {
      await _pumpPreviewGuest(t);
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));

      expect(find.text(l10n.protectEmailTitle), findsWidgets);
      expect(find.text(l10n.protectEmailLead), findsOneWidget);
      expect(find.text(l10n.progressPreviewBody), findsOneWidget);
      // Not the plain guest's copy: an email alone opens nothing of an encrypted account.
      expect(find.text(l10n.progressLead), findsNothing);
      expect(find.byKey(const Key('progress.passkey')), findsNothing);
      expect(find.text(l10n.progressPasskeyTitle), findsNothing);
      expect(find.byKey(const Key('progress.email')), findsOneWidget);
    });
  });

  group('the email has an account already', () {
    testWidgets('email_taken offers the merge; yes starts it and sends the code for that email', (
      t,
    ) async {
      final p = await _pumpPreviewGuest(t);
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));
      p.env.auth.failures['claimSend'] = const AuthFailure(code: 'email_taken', status: 409);
      await _claim(t, 'ana@correo.com');

      expect(find.text(l10n.mergeOfferQuestion), findsOneWidget);
      expect(p.merge.asked, isEmpty);
      expect(p.env.auth.calls.where((c) => c.startsWith('sendCode')), isEmpty);

      await t.tap(find.byKey(const Key('merge.yes')));
      await t.pumpAndSettle();

      expect(p.merge.asked, ['begin ana@correo.com']);
      expect(p.env.auth.calls.last, 'sendCode ana@correo.com');
      expect(find.byKey(const Key('entry.code')), findsOneWidget);
      // The guest is still signed in until the code is used.
      expect(p.env.stored?.token, 'guest-token-0');

      await _enterCode(t, '123456');
      expect(p.env.auth.calls, contains('verifyCode ana@correo.com 123456'));
      expect(p.env.stored?.token, 'email-token-1');
      expect(p.merge.asked, ['begin ana@correo.com']);
    });

    testWidgets('backing out of the merge\'s code step calls the merge off', (t) async {
      final p = await _pumpPreviewGuest(t);
      p.env.auth.failures['claimSend'] = const AuthFailure(code: 'email_taken', status: 409);
      await _claim(t, 'ana@correo.com');
      await t.tap(find.byKey(const Key('merge.yes')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('entry.code')), findsOneWidget);

      await t.binding.handlePopRoute();
      await t.pumpAndSettle();

      expect(p.merge.asked, ['begin ana@correo.com', 'cancel']);
      expect(find.byKey(const Key('entry.email')), findsOneWidget);
      expect(p.env.stored?.token, 'guest-token-0');
    });

    testWidgets('no keeps the screen and changes nothing', (t) async {
      final p = await _pumpPreviewGuest(t);
      final l10n = await AppLocalizations.delegate.load(const Locale('es'));
      p.env.auth.failures['claimSend'] = const AuthFailure(code: 'email_taken', status: 409);
      await _claim(t, 'ana@correo.com');
      expect(find.text(l10n.mergeOfferQuestion), findsOneWidget);
      p.env.auth.calls.clear();

      await t.tap(find.text(l10n.cancel.toUpperCase()));
      await t.pumpAndSettle();

      expect(p.merge.asked, isEmpty);
      expect(p.env.auth.calls, isEmpty);
      expect(p.env.stored?.token, 'guest-token-0');
      expect(p.env.stored?.guest, isTrue);
      expect(find.byKey(const Key('entry.email')), findsOneWidget);
      expect(find.text('Ese correo ya tiene una cuenta. Entra con él.'), findsOneWidget);
    });
  });
}
