// Settings' passkeys for an encrypted account: each says whether it opens the data (from the passkey
// wraps), "Turn on" touches that passkey and adds its wrap, and a new one is added with its wrap
// when the phone gives a PRF (twin of PasskeysSection.tsx with `security`).

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/local/prf.dart' show PasskeyPrf;
import 'package:wambito/settings/passkeys_section.dart';
import 'package:wambito/settings/passkeys_settings.dart';
import 'package:wambito/settings/security/security_api.dart';

import '../../support/fonts.dart';
import '../../support/ui_app.dart';
import 'fake_security.dart';

class _Passkeys implements SettingsPasskeys {
  _Passkeys(this.items);

  final List<PasskeyItem> items;
  PasskeyPrfUse? used;
  PasskeyPrf? toKeep;

  @override
  Future<bool> supported() async => true;

  @override
  Future<List<PasskeyItem>> list() async => items;

  @override
  Future<PasskeyOutcome> add({PasskeyPrfUse? prf}) async {
    used = prf;
    final give = toKeep;
    if (prf != null && give != null) await prf.keep(give);
    return PasskeyOutcome.added;
  }

  @override
  Future<void> remove(String id) async {}
}

PasskeyItem _item(String id, String credentialId, {String? name}) => PasskeyItem(
  id: id,
  credentialId: credentialId,
  name: name,
  createdAt: DateTime.utc(2026, 10, 2, 9),
);

Future<(FakeSecurity, _Passkeys)> pumpPasskeys(
  WidgetTester t, {
  SecurityApi? security,
  bool guest = false,
}) async {
  t.view
    ..physicalSize = const Size(824, 3200)
    ..devicePixelRatio = 2;
  addTearDown(t.view.reset);
  final fake = security is FakeSecurity ? security : FakeSecurity(snapshotOf(passkeyWrap: true));
  final passkeys = _Passkeys([_item('pk-1', 'cred-1', name: 'Pixel'), _item('pk-2', 'cred-2')]);
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        settingsPasskeysProvider.overrideWithValue(passkeys),
        securityApiProvider.overrideWithValue(security == null && !guest ? fake : security),
      ],
      child: uiApp(
        SingleChildScrollView(
          child: PasskeysSection(timeZone: 'America/Bogota', guest: guest),
        ),
        locale: const Locale('en'),
      ),
    ),
  );
  await t.pumpAndSettle();
  return (fake, passkeys);
}

void main() {
  setUpAll(loadAppFonts);

  testWidgets('says which passkeys open the data and offers "Turn on" for the others', (t) async {
    final handle = t.ensureSemantics();
    await pumpPasskeys(t);
    // cred-1 has a wrap, cred-2 has none
    expect(find.text('Opens your data'), findsOneWidget);
    expect(find.text('Does not open your data'), findsOneWidget);
    expect(find.byKey(const Key('settings.passkeys.turnOn.pk-1')), findsNothing);
    expect(find.byKey(const Key('settings.passkeys.turnOn.pk-2')), findsOneWidget);
    handle.dispose();
  });

  testWidgets('a plain account (no open vault) says nothing about the data', (t) async {
    t.view
      ..physicalSize = const Size(824, 3200)
      ..devicePixelRatio = 2;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          settingsPasskeysProvider.overrideWithValue(_Passkeys([_item('pk-1', 'cred-1')])),
          securityApiProvider.overrideWithValue(null),
        ],
        child: uiApp(
          const SingleChildScrollView(child: PasskeysSection(timeZone: 'UTC', guest: false)),
          locale: const Locale('en'),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('Opens your data'), findsNothing);
    expect(find.text('Does not open your data'), findsNothing);
    expect(find.byKey(const Key('settings.passkeys.turnOn.pk-1')), findsNothing);
  });

  testWidgets('"Turn on" touches that passkey, adds its wrap and zeroes the PRF', (t) async {
    final security = FakeSecurity(snapshotOf(passkeyWrap: true));
    final prf = PasskeyPrf(credentialId: 'cred-2', prf: List.filled(32, 9).toBytes());
    security.touched = prf;
    await pumpPasskeys(t, security: security);
    await t.ensureVisible(find.byKey(const Key('settings.passkeys.turnOn.pk-2')));
    await t.tap(find.byKey(const Key('settings.passkeys.turnOn.pk-2')));
    await t.pumpAndSettle();
    expect(security.calls, ['evaluatePrf cred-2', 'addPasskeyWrap cred-2']);
    expect(prf.prf, everyElement(0));
    expect(find.text('Done: this fingerprint opens your data too.'), findsOneWidget);
    // the wraps are read again
    expect(security.loads, 2);
  });

  testWidgets('a provider with no PRF says so under the passkey', (t) async {
    final handle = t.ensureSemantics();
    final security = FakeSecurity(snapshotOf(passkeyWrap: true))
      ..touchFailure = keysError('no_prf');
    await pumpPasskeys(t, security: security);
    await t.ensureVisible(find.byKey(const Key('settings.passkeys.turnOn.pk-2')));
    await t.tap(find.byKey(const Key('settings.passkeys.turnOn.pk-2')));
    await t.pumpAndSettle();
    expect(security.calls, ['evaluatePrf cred-2']);
    expect(
      find.bySemanticsLabel(RegExp("This fingerprint's provider can't open your data")),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('a cancelled touch changes nothing', (t) async {
    final security = FakeSecurity(snapshotOf(passkeyWrap: true));
    await pumpPasskeys(t, security: security);
    await t.ensureVisible(find.byKey(const Key('settings.passkeys.turnOn.pk-2')));
    await t.tap(find.byKey(const Key('settings.passkeys.turnOn.pk-2')));
    await t.pumpAndSettle();
    expect(security.calls, ['evaluatePrf cred-2']);
  });

  testWidgets('a new passkey is added with its wrap: add() gets a way to keep its PRF', (t) async {
    final security = FakeSecurity(snapshotOf(passkeyWrap: true));
    final (_, passkeys) = await pumpPasskeys(t, security: security);
    passkeys.toKeep = PasskeyPrf(credentialId: 'cred-3', prf: List.filled(32, 5).toBytes());
    await t.ensureVisible(find.byKey(const Key('settings.passkeys.add')));
    await t.tap(find.byKey(const Key('settings.passkeys.add')));
    await t.pumpAndSettle();
    expect(passkeys.used, isNotNull);
    expect(security.calls, ['addPasskeyWrap cred-3']);
    // the passkey list and the wraps are read again
    expect(security.loads, 2);
  });
}

extension on List<int> {
  Uint8List toBytes() => Uint8List.fromList(this);
}
