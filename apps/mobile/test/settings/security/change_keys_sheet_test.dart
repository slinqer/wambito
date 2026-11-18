// "Change keys" (the twin of the web's ChangeKeysSheet in SecuritySection.tsx): a rotation that
// removes no device, with the typed recovery key or a new one shown and checked first; plus what the
// web leaves to its caller (3b tasks 11 and 12): reloadKeys after a commit, a retry on the same
// prepared rotation, and forgetting one that is given up.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/local/rotate.dart' show DroppedWrap, RotateResult;
import 'package:wambito/settings/security/change_keys_sheet.dart';
import 'package:wambito/settings/security/recovery_setup_page.dart';

import '../../support/fonts.dart';
import '../../support/ui_app.dart';
import 'fake_security.dart';

RotateResult? result;
var closed = false;

Future<void> pumpSheet(WidgetTester t, FakeSecurity security, {bool hasPasskeys = false}) async {
  t.view
    ..physicalSize = const Size(824, 2400)
    ..devicePixelRatio = 2;
  addTearDown(t.view.reset);
  result = null;
  closed = false;
  await t.pumpWidget(
    ProviderScope(
      child: uiApp(
        Builder(
          builder: (context) => TextButton(
            key: const Key('open'),
            onPressed: () async {
              result = await ChangeKeysSheet.open(
                context,
                security: security,
                hasPasskeys: hasPasskeys,
              );
              closed = true;
            },
            child: const Text('open'),
          ),
        ),
        locale: const Locale('en'),
      ),
    ),
  );
  await t.tap(find.byKey(const Key('open')));
  await t.pumpAndSettle();
}

Future<void> tapKey(WidgetTester t, String key) async {
  await t.ensureVisible(find.byKey(Key(key)));
  await t.tap(find.byKey(Key(key)));
  await t.pumpAndSettle();
}

Future<void> typeKey(WidgetTester t) async {
  await t.enterText(find.byKey(const Key('security.changeKeys.key')), recoveryKeyText);
  await t.pump();
}

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

  testWidgets(
    'the typed key rotates, commits and reloads the keys; the sheet lists what was left out',
    (t) async {
      final handle = t.ensureSemantics();
      final security = FakeSecurity()
        ..dropped = const [DroppedWrap(id: 'x', label: 'Old tablet', reason: 'revoked')];
      await pumpSheet(t, security, hasPasskeys: true);
      await typeKey(t);
      await tapKey(t, 'security.changeKeys.confirm');
      expect(security.calls, ['rotate remove= typed:$recoveryKeyText', 'commit', 'reloadKeys']);
      expect(find.text('Your keys changed.'), findsOneWidget);
      expect(find.bySemanticsLabel('Old tablet (removed earlier)'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp("Fingerprints you didn't use just now")), findsOneWidget);
      await t.tapAt(const Offset(10, 10));
      await t.pumpAndSettle();
      expect(closed, isTrue);
      expect(result?.keyV, 3);
      handle.dispose();
    },
  );

  testWidgets('the body says that connected assistants are disconnected', (t) async {
    final handle = t.ensureSemantics();
    await pumpSheet(t, FakeSecurity(), hasPasskeys: true);
    expect(
      find.bySemanticsLabel(
        RegExp('Your devices keep working; connected assistants are disconnected'),
      ),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('without passkey wraps there is no note about fingerprints', (t) async {
    final security = FakeSecurity();
    await pumpSheet(t, security);
    await typeKey(t);
    await tapKey(t, 'security.changeKeys.confirm');
    expect(find.text('Your keys changed.'), findsOneWidget);
    expect(find.textContaining("Fingerprints you didn't use just now"), findsNothing);
  });

  testWidgets('a new recovery key is shown and checked before anything is committed', (t) async {
    final security = FakeSecurity();
    await pumpSheet(t, security);
    await tapKey(t, 'security.changeKeys.newKey');
    // prepared and shown: nothing is sent yet
    expect(security.calls, ['rotate remove= fresh']);
    for (final group in recoveryKeyText.split('-')) {
      expect(find.text(group), findsOneWidget);
    }
    await typeCheck(t);
    await tapKey(t, 'vault.continue');
    expect(security.calls, ['rotate remove= fresh', 'commit', 'reloadKeys']);
    expect(find.text('Your keys changed.'), findsOneWidget);
  });

  testWidgets('giving up on the new key drops the prepared rotation: nothing committed', (t) async {
    final security = FakeSecurity();
    await pumpSheet(t, security);
    await tapKey(t, 'security.changeKeys.newKey');
    await tapKey(t, 'vault.cancel');
    expect(security.calls, ['rotate remove= fresh', 'forget']);
    expect(find.byKey(const Key('security.changeKeys.key')), findsOneWidget);
    // closed without a change: nothing to hand back
    await t.tapAt(const Offset(10, 10));
    await t.pumpAndSettle();
    expect(closed, isTrue);
    expect(result, isNull);
  });

  testWidgets('rotated_elsewhere says so and reloads the keys and the list', (t) async {
    final security = FakeSecurity()..commitFailures.add(keysError('rotated_elsewhere'));
    await pumpSheet(t, security);
    await typeKey(t);
    await tapKey(t, 'security.changeKeys.confirm');
    expect(
      find.text(
        'Another device changed your keys at the same time. Wait a moment while they refresh here, then try again.',
      ),
      findsOneWidget,
    );
    // refused for sure: the prepared rotation is dropped, the keys read again
    expect(security.calls, ['rotate remove= typed:$recoveryKeyText', 'commit', 'reloadKeys']);
  });

  testWidgets('rotated_elsewhere on the new key comes back the same way', (t) async {
    final security = FakeSecurity()..commitFailures.add(keysError('rotated_elsewhere'));
    await pumpSheet(t, security);
    await tapKey(t, 'security.changeKeys.newKey');
    await typeCheck(t);
    await tapKey(t, 'vault.continue');
    expect(find.textContaining('Another device changed your keys'), findsOneWidget);
    expect(security.calls, contains('reloadKeys'));
  });

  testWidgets('an offline commit is retried with the same prepared rotation, never a new one', (
    t,
  ) async {
    final security = FakeSecurity()..commitFailures.add(keysError('offline'));
    await pumpSheet(t, security);
    await typeKey(t);
    await tapKey(t, 'security.changeKeys.confirm');
    expect(find.textContaining('You are offline'), findsOneWidget);
    expect(find.text('TRY AGAIN'), findsOneWidget);
    await tapKey(t, 'security.changeKeys.confirm');
    expect(security.calls, [
      'rotate remove= typed:$recoveryKeyText',
      'commit',
      'commit',
      'reloadKeys',
    ]);
    expect(find.text('Your keys changed.'), findsOneWidget);
  });

  testWidgets('a server failure of the commit is retried the same way', (t) async {
    final security = FakeSecurity()..commitFailures.add(keysError('server'));
    await pumpSheet(t, security);
    await typeKey(t);
    await tapKey(t, 'security.changeKeys.confirm');
    expect(find.text("We couldn't change your keys. Try again."), findsOneWidget);
    await tapKey(t, 'security.changeKeys.confirm');
    expect(security.calls.where((c) => c.startsWith('rotate')), hasLength(1));
    expect(security.calls.where((c) => c == 'commit'), hasLength(2));
  });

  testWidgets('a wrong key says so on the field and nothing is sent', (t) async {
    final security = FakeSecurity()..rotateFailure = keysError('wrong_recovery_key');
    await pumpSheet(t, security);
    await typeKey(t);
    await tapKey(t, 'security.changeKeys.confirm');
    expect(find.text('That key does not open this account'), findsOneWidget);
    expect(security.calls, ['rotate remove= typed:$recoveryKeyText']);
  });

  testWidgets(
    'a failed save of the new key stays on the key, and "Try again" commits the same one',
    (t) async {
      final security = FakeSecurity()..commitFailures.add(keysError('server'));
      await pumpSheet(t, security);
      await tapKey(t, 'security.changeKeys.newKey');
      await typeCheck(t);
      await tapKey(t, 'vault.continue');
      expect(
        find.text('It may have been saved: keep this new key until it says it is done.'),
        findsOneWidget,
      );
      // no way out while the key may be the only one that works
      expect(find.byKey(const Key('vault.cancel')), findsNothing);
      expect(find.text('TRY AGAIN'), findsOneWidget);
      await tapKey(t, 'vault.continue');
      expect(security.calls, ['rotate remove= fresh', 'commit', 'commit', 'reloadKeys']);
      expect(find.text('Your keys changed.'), findsOneWidget);
    },
  );

  testWidgets('after a failed commit the sheet stays: no way out but "Try again" (R17)', (t) async {
    final security = FakeSecurity()..commitFailures.add(keysError('offline'));
    await pumpSheet(t, security);
    await typeKey(t);
    await tapKey(t, 'security.changeKeys.confirm');
    expect(find.text('TRY AGAIN'), findsOneWidget);
    // the backdrop does not close it, nor does the system's back button
    await t.tapAt(const Offset(10, 10));
    await t.pumpAndSettle();
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(find.byKey(const Key('security.changeKeys.key')), findsOneWidget);
    expect(security.forgets, 0);
    await tapKey(t, 'security.changeKeys.confirm');
    expect(find.text('Your keys changed.'), findsOneWidget);
    expect(security.calls.where((c) => c == 'commit'), hasLength(2));
  });

  testWidgets('a tampered commit frees the sheet and says to stop', (t) async {
    final security = FakeSecurity()..commitFailures.add(keysError('tampered'));
    await pumpSheet(t, security);
    await typeKey(t);
    await tapKey(t, 'security.changeKeys.confirm');
    expect(find.textContaining('Stop:'), findsOneWidget);
    // no "Try again": it would say the same; the sheet closes again
    expect(find.text('TRY AGAIN'), findsNothing);
    await t.tapAt(const Offset(10, 10));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('security.changeKeys.key')), findsNothing);
  });

  testWidgets('after tampered neither "Change keys" nor "Make a new recovery key" is offered', (
    t,
  ) async {
    final security = FakeSecurity()..commitFailures.add(keysError('tampered'));
    await pumpSheet(t, security);
    await typeKey(t);
    await tapKey(t, 'security.changeKeys.confirm');
    expect(find.textContaining('Stop:'), findsOneWidget);
    expect(find.byKey(const Key('security.changeKeys.confirm')), findsNothing);
    expect(find.byKey(const Key('security.changeKeys.newKey')), findsNothing);
  });

  testWidgets('tampered on the new key comes back the same way', (t) async {
    final security = FakeSecurity()..commitFailures.add(keysError('tampered'));
    await pumpSheet(t, security);
    await tapKey(t, 'security.changeKeys.newKey');
    await typeCheck(t);
    await tapKey(t, 'vault.continue');
    expect(find.textContaining('Stop:'), findsOneWidget);
    expect(find.byKey(const Key('security.changeKeys.confirm')), findsNothing);
    expect(find.byKey(const Key('security.changeKeys.newKey')), findsNothing);
  });

  testWidgets('a refused-for-good commit frees the sheet again', (t) async {
    final security = FakeSecurity()..commitFailures.add(keysError('rotated_elsewhere'));
    await pumpSheet(t, security);
    await typeKey(t);
    await tapKey(t, 'security.changeKeys.confirm');
    await t.tapAt(const Offset(10, 10));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('security.changeKeys.key')), findsNothing);
  });
}
