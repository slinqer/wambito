// Twin of the behaviour of RemoveDeviceSheet.tsx: removing a device is one tap after the screen lock
// (asked by the caller). Its wrap is deleted (`removeDevice`), the keys stay, nothing asks for the
// recovery key. Offline or any other failure keeps the sheet and says so. From the sign-in notice's
// "That wasn't me", the done step suggests changing the keys.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/local/keys_error.dart';
import 'package:wambito/settings/security/remove_device_sheet.dart';
import 'package:wambito/settings/security/security_model.dart';

import '../../support/fonts.dart';
import '../../support/ui_app.dart';
import 'fake_security.dart';

const _laptop = DeviceRow(
  id: laptopId,
  label: 'Firefox on Linux',
  createdAt: '2026-10-03T10:00:00Z',
  thisPhone: false,
  verified: true,
  removable: true,
);

int changed = 0;

Future<void> pumpSheet(
  WidgetTester t,
  FakeSecurity security, {
  bool suggestChangeKeys = false,
}) async {
  t.view
    ..physicalSize = const Size(824, 2400)
    ..devicePixelRatio = 2;
  addTearDown(t.view.reset);
  changed = 0;
  await t.pumpWidget(
    ProviderScope(
      child: uiApp(
        Builder(
          builder: (context) => TextButton(
            key: const Key('open'),
            onPressed: () => RemoveDeviceSheet.show(
              context,
              device: _laptop,
              security: security,
              onChanged: () => changed += 1,
              suggestChangeKeys: suggestChangeKeys,
            ),
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

void main() {
  setUpAll(loadAppFonts);

  testWidgets('the sheet says what removing does and asks for no recovery key', (t) async {
    final handle = t.ensureSemantics();
    await pumpSheet(t, FakeSecurity());
    expect(find.text('Remove Firefox on Linux'), findsOneWidget);
    expect(
      find.bySemanticsLabel(
        "This device will be signed out of your account and won't receive anything new.",
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('security.remove.key')), findsNothing);
    expect(find.byKey(const Key('security.remove.newKey')), findsNothing);
    handle.dispose();
  });

  testWidgets('Remove deletes the wrap once, never rotates, closes and says it', (t) async {
    final security = FakeSecurity();
    await pumpSheet(t, security);
    await tapKey(t, 'security.remove.confirm');
    expect(security.calls, ['removeDevice $laptopId']);
    expect(find.byKey(const Key('security.remove.confirm')), findsNothing);
    expect(find.text('Firefox on Linux no longer has access.'), findsOneWidget);
    expect(changed, 1);
    // a plain removal suggests nothing
    expect(find.byKey(const Key('security.remove.changeKeys')), findsNothing);
  });

  testWidgets('offline keeps the sheet with the offline line; nothing changed', (t) async {
    final security = FakeSecurity()..removeFailure = const KeysError('offline');
    await pumpSheet(t, security);
    await tapKey(t, 'security.remove.confirm');
    expect(find.textContaining('You are offline'), findsOneWidget);
    expect(find.byKey(const Key('security.remove.confirm')), findsOneWidget);
    expect(changed, 0);
    // pressed again once online: the same one call
    security.removeFailure = null;
    await tapKey(t, 'security.remove.confirm');
    expect(security.calls, ['removeDevice $laptopId', 'removeDevice $laptopId']);
    expect(changed, 1);
  });

  testWidgets('any other failure says it could not remove it', (t) async {
    final security = FakeSecurity()..removeFailure = const KeysError('failed');
    await pumpSheet(t, security);
    await tapKey(t, 'security.remove.confirm');
    expect(find.text("We couldn't remove it. Try again."), findsOneWidget);
    expect(security.calls.where((c) => c.startsWith('rotate')), isEmpty);
    expect(changed, 0);
  });

  testWidgets('from "That wasn\'t me" the done step suggests changing the keys', (t) async {
    final handle = t.ensureSemantics();
    final security = FakeSecurity();
    await pumpSheet(t, security, suggestChangeKeys: true);
    await tapKey(t, 'security.remove.confirm');
    expect(security.calls, ['removeDevice $laptopId']);
    expect(find.bySemanticsLabel('Firefox on Linux no longer has access.'), findsOneWidget);
    expect(
      find.bySemanticsLabel(
        "If someone else had your key, change it: they won't be able to read anything you save "
        'from now on.',
      ),
      findsOneWidget,
    );
    expect(changed, 1);
    await tapKey(t, 'security.remove.changeKeys');
    // the removal sheet went; Change keys asks for the recovery key
    expect(find.byKey(const Key('security.remove.changeKeys')), findsNothing);
    expect(find.byKey(const Key('security.changeKeys.key')), findsOneWidget);
    expect(security.calls, ['removeDevice $laptopId']);
    handle.dispose();
  });
}
