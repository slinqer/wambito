// Settings → Security for an encrypted account (twin of SecuritySection.tsx, with the phone's screen
// lock for the web's passkey touch): the devices, removing one, a new recovery key, approving a
// new device.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/l10n/app_localizations.dart';
import 'package:wambito/security/screen_lock.dart';
import 'package:wambito/settings/security/connect_device_screen.dart';
import 'package:wambito/settings/security/recovery_setup_page.dart';
import 'package:wambito/settings/security/security_api.dart';
import 'package:wambito/settings/security/security_section.dart';
import 'package:wambito/vault/encryption_mode.dart' show currentVaultAccountProvider;
import 'package:wambito/vault/preview.dart' show isPreviewProvider;
import 'package:wambito/vault/vault_providers.dart' show vaultSessionProvider;

import '../../support/fonts.dart';
import '../../support/ui_app.dart';
import '../harness.dart';
import '../../protect/fakes.dart';
import 'fake_security.dart';

Future<void> pumpSection(
  WidgetTester t,
  FakeSecurity security,
  ScreenLock lock, {
  List<Override> overrides = const [],
}) async {
  t.view
    ..physicalSize = const Size(824, 3200)
    ..devicePixelRatio = 2;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        securityApiProvider.overrideWithValue(security),
        screenLockProvider.overrideWithValue(lock),
        // No account nor vault unless the test gives them: the section asks the key as for any account.
        if (!overrides.any((o) => o.origin == currentVaultAccountProvider))
          currentVaultAccountProvider.overrideWithValue(null),
        if (!overrides.any((o) => o.origin == vaultSessionProvider))
          vaultSessionProvider.overrideWithValue(null),
        ...overrides,
      ],
      child: uiApp(
        SingleChildScrollView(child: SecuritySection(timeZone: 'America/Bogota')),
        locale: const Locale('en'),
      ),
    ),
  );
  await t.pumpAndSettle();
}

Future<void> tapKey(WidgetTester t, String key) async {
  await t.ensureVisible(find.byKey(Key(key)));
  await t.tap(find.byKey(Key(key)));
  await t.pumpAndSettle();
}

/// Types the four characters the setup screen asks for (positions pinned to 1-4: A, B, C, D).
Future<void> typeCheck(WidgetTester t) async {
  await tapKey(t, 'vault.saved');
  final boxes = find.byType(EditableText);
  for (final (i, c) in ['a', 'b', 'c', 'd'].indexed) {
    await t.enterText(boxes.at(i), c);
  }
  await t.pump();
}

void main() {
  setUpAll(loadAppFonts);
  setUp(() => setupPositions = const [1, 2, 3, 4]);
  tearDown(() => setupPositions = null);

  testWidgets('lists this phone and the other devices; this phone has no Remove', (t) async {
    final security = FakeSecurity();
    await pumpSection(t, security, FakeLock(LockCheck.passed));
    expect(find.text('Pixel 9'), findsOneWidget);
    expect(find.text('This phone'), findsOneWidget);
    expect(find.text('Firefox on Linux'), findsOneWidget);
    // only the forged one is "Not verified"
    expect(find.text('Not verified'), findsOneWidget);
    expect(find.byKey(const Key('security.remove.$ownId')), findsNothing);
    expect(find.byKey(const Key('security.remove.$laptopId')), findsOneWidget);
    expect(find.byKey(const Key('security.remove.$forgedId')), findsOneWidget);
    expect(find.text('Added on Oct 3, 2026'), findsOneWidget);
  });

  testWidgets('"N records could not be read" shows when there are some', (t) async {
    final handle = t.ensureSemantics();
    await pumpSection(t, FakeSecurity(snapshotOf(unreadable: 3)), FakeLock(LockCheck.passed));
    expect(find.bySemanticsLabel('Could not read 3 items'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('no unreadable records: no line about them', (t) async {
    await pumpSection(t, FakeSecurity(), FakeLock(LockCheck.passed));
    expect(find.textContaining('Could not read'), findsNothing);
  });

  testWidgets('a preview guest sees devices, Remove, New recovery key and Change keys', (t) async {
    // Settings as a guest (no email) on an encrypted account: the full section, as with an email.
    final security = FakeSecurity();
    final env = await pumpSettingsApp(
      t,
      guest: true,
      locale: const Locale('en'),
      location: '/settings',
      overrides: [
        isPreviewProvider.overrideWithValue(true),
        securityApiProvider.overrideWithValue(security),
        screenLockProvider.overrideWithValue(FakeLock(LockCheck.passed)),
      ],
    );
    expect(env.stored?.guest, isTrue);
    await t.scrollUntilVisible(
      find.byKey(const Key('settings.card.security')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await t.pumpAndSettle();
    expect(security.loads, greaterThan(0));
    expect(find.text('Pixel 9'), findsOneWidget);
    expect(find.text('Firefox on Linux'), findsOneWidget);
    expect(find.byKey(const Key('security.remove.$laptopId')), findsOneWidget);
    expect(find.byKey(const Key('security.newKey')), findsOneWidget);
    expect(find.byKey(const Key('security.changeKeys')), findsOneWidget);
    expect(find.byKey(const Key('security.connect')), findsOneWidget);
  });

  testWidgets('one entry connects another device, instead of Approve and Sign in on the web', (
    t,
  ) async {
    await pumpSection(t, FakeSecurity(), FakeLock(LockCheck.passed));
    expect(find.text('CONNECT ANOTHER DEVICE'), findsOneWidget);
    expect(find.byKey(const Key('security.connect')), findsOneWidget);
    expect(find.byKey(const Key('security.approve')), findsNothing);
    expect(find.byKey(const Key('security.signinWeb')), findsNothing);
    expect(find.text('APPROVE A NEW DEVICE'), findsNothing);
    expect(find.text('SIGN IN ON THE WEB'), findsNothing);
  });

  test('the new device names this entry, in every language', () {
    for (final locale in AppLocalizations.supportedLocales) {
      final l10n = lookupAppLocalizations(locale);
      expect(l10n.vaultPairLead, contains('→ ${l10n.settingsSecurityConnect},'), reason: '$locale');
    }
  });

  for (final key in ['security.newKey', 'security.remove.$laptopId', 'security.changeKeys']) {
    testWidgets('a double tap on $key asks the lock once', (t) async {
      final lock = _SlowLock();
      await pumpSection(t, FakeSecurity(), lock);
      await t.ensureVisible(find.byKey(Key(key)));
      await t.tap(find.byKey(Key(key)));
      await t.tap(find.byKey(Key(key)));
      await t.pump();
      expect(lock.asked, 1);
    });
  }

  testWidgets('"Connect another device" opens its screen, which closes back', (t) async {
    final security = FakeSecurity();
    await pumpSection(t, security, FakeLock(LockCheck.passed));
    final loads = security.loads;
    await tapKey(t, 'security.connect');
    expect(find.byType(ConnectDeviceScreen), findsOneWidget);
    // nothing is looked up before a code or a scan
    expect(security.calls.where((c) => c.startsWith('find')), isEmpty);
    await tapKey(t, 'connect.cancel');
    expect(find.byType(ConnectDeviceScreen), findsNothing);
    // a browser or a phone may have joined as a device: the list is read again
    expect(security.loads, greaterThan(loads));
  });

  group('removing a device', () {
    testWidgets('a cancelled screen lock does nothing', (t) async {
      final security = FakeSecurity();
      final lock = FakeLock(LockCheck.cancelled);
      await pumpSection(t, security, lock);
      await tapKey(t, 'security.remove.$laptopId');
      expect(lock.reasons, ["Confirm it's you to remove a device"]);
      expect(security.calls, isEmpty);
      expect(find.byKey(const Key('security.remove.key')), findsNothing);
    });

    testWidgets('with the lock passed the sheet opens; Remove deletes the wrap only', (t) async {
      final security = FakeSecurity();
      await pumpSection(t, security, FakeLock(LockCheck.passed));
      await tapKey(t, 'security.remove.$laptopId');
      expect(find.byKey(const Key('security.remove.confirm')), findsOneWidget);
      expect(find.byKey(const Key('security.remove.key')), findsNothing);
      // asking is not removing
      expect(security.calls, isEmpty);
      final loads = security.loads;
      await tapKey(t, 'security.remove.confirm');
      expect(security.calls, ['removeDevice $laptopId']);
      expect(find.text('Firefox on Linux no longer has access.'), findsOneWidget);
      // a plain removal suggests nothing
      expect(find.byKey(const Key('security.remove.changeKeys')), findsNothing);
      // the list is read again
      expect(security.loads, greaterThan(loads));
    });

    testWidgets('a preview guest with no saved key and no lock reaches the sheet', (t) async {
      final vault = FakeVault();
      await t.runAsync(() => vault.seeded);
      final security = FakeSecurity();
      await pumpSection(
        t,
        security,
        FakeLock(LockCheck.noLock),
        overrides: [accountOf(), vaultSessionProvider.overrideWithValue(vault)],
      );
      await tapKey(t, 'security.remove.$laptopId');
      // never asked for a key they never saw
      expect(find.byKey(const Key('screenLock.key')), findsNothing);
      expect(find.byKey(const Key('security.remove.confirm')), findsOneWidget);
    });

    testWidgets('an email account with no lock is still asked for the key first', (t) async {
      await pumpSection(t, FakeSecurity(), FakeLock(LockCheck.noLock));
      await tapKey(t, 'security.remove.$laptopId');
      expect(find.byKey(const Key('screenLock.key')), findsOneWidget);
      expect(find.byKey(const Key('security.remove.confirm')), findsNothing);
    });
  });

  group('changing the keys', () {
    testWidgets('a cancelled screen lock does nothing', (t) async {
      final security = FakeSecurity();
      final lock = FakeLock(LockCheck.cancelled);
      await pumpSection(t, security, lock);
      await tapKey(t, 'security.changeKeys');
      expect(lock.reasons, ["Confirm it's you to change your keys"]);
      expect(security.calls, isEmpty);
      expect(find.byKey(const Key('security.changeKeys.key')), findsNothing);
    });

    testWidgets('with the lock passed it rotates with nothing removed', (t) async {
      final security = FakeSecurity();
      await pumpSection(t, security, FakeLock(LockCheck.passed));
      await tapKey(t, 'security.changeKeys');
      await t.enterText(find.byKey(const Key('security.changeKeys.key')), recoveryKeyText);
      await t.pump();
      await tapKey(t, 'security.changeKeys.confirm');
      expect(security.calls, ['rotate remove= typed:$recoveryKeyText', 'commit', 'reloadKeys']);
      expect(find.text('Your keys changed.'), findsOneWidget);
      final loads = security.loads;
      await t.tapAt(const Offset(10, 10));
      await t.pumpAndSettle();
      // the keys changed: the list is read again
      expect(security.loads, greaterThan(loads));
    });

    testWidgets('a preview guest with no saved key and no lock reaches the sheet', (t) async {
      final vault = FakeVault();
      await t.runAsync(() => vault.seeded);
      final security = FakeSecurity();
      await pumpSection(
        t,
        security,
        FakeLock(LockCheck.noLock),
        overrides: [accountOf(), vaultSessionProvider.overrideWithValue(vault)],
      );
      await tapKey(t, 'security.changeKeys');
      // no key to type for the lock: the sheet opens, and its new-key way is there
      expect(find.byKey(const Key('screenLock.key')), findsNothing);
      expect(find.byKey(const Key('security.changeKeys.newKey')), findsOneWidget);
    });

    testWidgets('an email account with no lock is still asked for the key first', (t) async {
      await pumpSection(t, FakeSecurity(), FakeLock(LockCheck.noLock));
      await tapKey(t, 'security.changeKeys');
      expect(find.byKey(const Key('screenLock.key')), findsOneWidget);
      expect(find.byKey(const Key('security.changeKeys.key')), findsNothing);
    });
  });

  group('a new recovery key', () {
    testWidgets('a cancelled screen lock does nothing', (t) async {
      final security = FakeSecurity();
      final lock = FakeLock(LockCheck.cancelled);
      await pumpSection(t, security, lock);
      await tapKey(t, 'security.newKey');
      expect(lock.reasons, ["Confirm it's you to make a new recovery key"]);
      expect(security.calls, isEmpty);
    });

    testWidgets('the key is not made nor shown before the lock passes (D17)', (t) async {
      final security = FakeSecurity();
      final lock = _SlowLock();
      await pumpSection(t, security, lock);
      await t.ensureVisible(find.byKey(const Key('security.newKey')));
      await t.tap(find.byKey(const Key('security.newKey')));
      await t.pump();
      expect(security.calls, isEmpty);
      expect(find.text(recoveryKeyText.split('-').first), findsNothing);
      lock.answer.complete(LockCheck.passed);
      await t.pumpAndSettle();
      expect(security.calls, ['newRecoveryKey']);
      expect(find.text(recoveryKeyText.split('-').first), findsOneWidget);
    });

    testWidgets('a preview guest with no saved key and no lock is not asked for a key', (t) async {
      final vault = FakeVault();
      await t.runAsync(() => vault.seeded);
      final security = FakeSecurity();
      await pumpSection(
        t,
        security,
        FakeLock(LockCheck.noLock),
        overrides: [accountOf(), vaultSessionProvider.overrideWithValue(vault)],
      );
      await tapKey(t, 'security.newKey');
      expect(find.byKey(const Key('screenLock.key')), findsNothing);
      expect(security.calls, ['newRecoveryKey']);
    });

    testWidgets('an email account with no saved-key mark and no lock is still asked', (t) async {
      final vault = FakeVault();
      await t.runAsync(() => vault.seeded);
      final security = FakeSecurity();
      await pumpSection(
        t,
        security,
        FakeLock(LockCheck.noLock),
        overrides: [accountOf(anonymous: false), vaultSessionProvider.overrideWithValue(vault)],
      );
      await tapKey(t, 'security.newKey');
      expect(find.byKey(const Key('screenLock.key')), findsOneWidget);
      expect(security.calls, isEmpty);
    });

    testWidgets('a preview guest with a saved key and no lock is asked for it', (t) async {
      final vault = FakeVault(recoveryKeySavedAt: '2026-11-18T10:00:00.000Z');
      await t.runAsync(() => vault.seeded);
      await pumpSection(
        t,
        FakeSecurity(),
        FakeLock(LockCheck.noLock),
        overrides: [accountOf(), vaultSessionProvider.overrideWithValue(vault)],
      );
      await tapKey(t, 'security.newKey');
      expect(find.byKey(const Key('screenLock.key')), findsOneWidget);
    });

    testWidgets('the key is committed only after the four characters are typed back', (t) async {
      final security = FakeSecurity();
      await pumpSection(t, security, FakeLock(LockCheck.passed));
      await tapKey(t, 'security.newKey');
      expect(security.calls, ['newRecoveryKey']);
      await typeCheck(t);
      await tapKey(t, 'vault.continue');
      expect(security.calls, ['newRecoveryKey', 'commit']);
      expect(
        find.text('Your new recovery key is saved. The old one no longer works.'),
        findsOneWidget,
      );
    });

    testWidgets('giving up drops the key without committing', (t) async {
      final security = FakeSecurity();
      await pumpSection(t, security, FakeLock(LockCheck.passed));
      await tapKey(t, 'security.newKey');
      await tapKey(t, 'vault.cancel');
      expect(security.calls, ['newRecoveryKey', 'forget']);
    });

    testWidgets('rotated_elsewhere starts over: the keys and the list are read again', (t) async {
      final security = FakeSecurity()..commitFailures.add(keysError('rotated_elsewhere'));
      await pumpSection(t, security, FakeLock(LockCheck.passed));
      await tapKey(t, 'security.newKey');
      await typeCheck(t);
      await tapKey(t, 'vault.continue');
      expect(
        find.text('Your keys changed on another device meanwhile. Make the new key again.'),
        findsOneWidget,
      );
      expect(security.calls, ['newRecoveryKey', 'commit', 'reloadKeys']);
      expect(security.loads, 2);
    });
  });
}

class _SlowLock implements ScreenLock {
  final answer = Completer<LockCheck>();
  int asked = 0;

  @override
  Future<LockCheck> confirm(String reason) {
    asked += 1;
    return answer.future;
  }
}
