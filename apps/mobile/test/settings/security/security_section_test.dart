// Settings → Security for an encrypted account (twin of SecuritySection.tsx, with the phone's screen
// lock for the web's passkey touch): the devices, removing one, a new recovery key, approving a
// new device.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/security/screen_lock.dart';
import 'package:wambito/settings/security/approve_device_screen.dart';
import 'package:wambito/settings/security/recovery_setup_page.dart';
import 'package:wambito/settings/security/security_api.dart';
import 'package:wambito/settings/security/security_section.dart';

import '../../support/fonts.dart';
import '../../support/ui_app.dart';
import 'fake_security.dart';

Future<void> pumpSection(
  WidgetTester t,
  FakeSecurity security,
  ScreenLock lock, {
  bool guest = false,
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
      ],
      child: uiApp(
        SingleChildScrollView(
          child: SecuritySection(timeZone: 'America/Bogota', guest: guest),
        ),
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

  testWidgets('a guest sees only "Approve a new device" and nothing is loaded', (t) async {
    final security = FakeSecurity();
    await pumpSection(t, security, FakeLock(LockCheck.passed), guest: true);
    expect(find.byKey(const Key('security.approve')), findsOneWidget);
    expect(find.byKey(const Key('security.newKey')), findsNothing);
    expect(security.loads, 0);
  });

  testWidgets(
    'the entry is named as the new phone says: Settings → Security → Approve a new device',
    (t) async {
      await pumpSection(t, FakeSecurity(), FakeLock(LockCheck.passed));
      expect(find.text('Security'), findsWidgets);
      expect(find.text('APPROVE A NEW DEVICE'), findsOneWidget);
    },
  );

  testWidgets('"Approve a new device" opens the approver screen', (t) async {
    await pumpSection(t, FakeSecurity(), FakeLock(LockCheck.passed));
    await tapKey(t, 'security.approve');
    expect(find.byType(ApproveDeviceScreen), findsOneWidget);
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

    testWidgets('with the lock passed the choice sheet opens', (t) async {
      final security = FakeSecurity();
      await pumpSection(t, security, FakeLock(LockCheck.passed));
      await tapKey(t, 'security.remove.$laptopId');
      expect(find.byKey(const Key('security.remove.key')), findsOneWidget);
      expect(find.byKey(const Key('security.remove.newKey')), findsOneWidget);
      // asking is not removing: nothing was prepared
      expect(security.calls, isEmpty);
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

    testWidgets('the key is committed only after the four characters are typed back', (t) async {
      final security = FakeSecurity();
      await pumpSection(t, security, FakeLock(LockCheck.passed));
      await tapKey(t, 'security.newKey');
      expect(security.calls, ['newRecoveryKey']);
      await typeCheck(t);
      await tapKey(t, 'vault.continue');
      expect(security.calls, ['newRecoveryKey', 'commit', 'forget']);
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
      expect(security.calls, ['newRecoveryKey', 'commit', 'forget', 'reloadKeys']);
      expect(security.loads, 2);
    });
  });
}

class _SlowLock implements ScreenLock {
  final answer = Completer<LockCheck>();

  @override
  Future<LockCheck> confirm(String reason) => answer.future;
}
