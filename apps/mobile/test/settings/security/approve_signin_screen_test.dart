// Approving a web sign-in from the phone (phone-first spec 8.1 step 3): the browser's label, the
// server's host, Approve and Cancel, over the real `findSigninRequest` and a fake relay.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/api/server_url.dart';
import 'package:wambito/crypto/crypto.dart';
import 'package:wambito/local/keys.dart' show KeysOptions;
import 'package:wambito/local/signin_approval.dart' as signin;
import 'package:wambito/scanner/qr_scanner.dart';
import 'package:wambito/settings/security/approve_signin_screen.dart';
import 'package:wambito/settings/security/security_api.dart';

import '../../local/fake_keys.dart';
import '../../local/fake_signin.dart';
import '../../support/fonts.dart';
import '../../support/ui_app.dart';
import 'fake_security.dart';

class _Server extends ServerUrl {
  @override
  Uri build() => Uri.parse('https://money.example.org');
}

class _Scanner implements QrScanner {
  _Scanner(this.text);

  final String? text;
  final asked = <List<String>>[];

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<String?> scan({List<String> prefixes = const [pairQrPrefix]}) async {
    asked.add(prefixes);
    return text;
  }
}

/// This phone's open vault and a fake relay with one browser request in it.
class _World {
  _World(this.relay, this.row, this.qr, this.security);

  final FakeSignin relay;
  final SigninRow row;
  final String qr;
  final FakeSecurity security;
}

Future<_World> _world() async {
  final clock = FakeClock();
  final keys = FakeKeys();
  final relay = FakeSignin(clock, keys);
  final storage = memoryKeyStorage();
  final userId = newUser();
  final dk = generateDataKey();
  await seedDevice(
    api: keys,
    storage: storage,
    userId: userId,
    held: {2: Uint8List.fromList(dk)},
    current: 2,
    deviceDk: dk,
    deviceV: 2,
  );
  final browser = Browser(await generateDeviceKeyPair());
  relay.reveal = (_) => browser.key;
  final row = await relay.open(browser, label: 'Firefox on Mac');
  final options = KeysOptions(userId: userId, dio: relay.dio(), storage: storage);
  final security = FakeSecurity()
    ..findSignin = ({code, qr}) =>
        signin.findSigninRequest(options, code: code, qr: qr, clock: clock);
  return _World(relay, row, 'wambito://signin?id=${row.id}&key=${browser.key}', security);
}

Future<void> _pump(WidgetTester t, _World w, {String? qr, QrScanner? scanner}) async {
  t.view
    ..physicalSize = const Size(824, 2400)
    ..devicePixelRatio = 2;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        securityApiProvider.overrideWithValue(w.security),
        serverUrlProvider.overrideWith(_Server.new),
        qrScannerProvider.overrideWithValue(scanner ?? _Scanner(null)),
      ],
      child: uiApp(ApproveSigninScreen(qr: qr), locale: const Locale('en')),
    ),
  );
  await t.pumpAndSettle();
}

void main() {
  setUpAll(loadAppFonts);

  testWidgets("shows the label and the server's host", (t) async {
    final w = await _world();
    await _pump(t, w, qr: w.qr);
    expect(find.textContaining('Sign in on Firefox on Mac?'), findsOneWidget);
    expect(find.textContaining('Only scan a code you see on money.example.org'), findsOneWidget);
    expect(find.byKey(const Key('signin.approve')), findsOneWidget);
    expect(find.byKey(const Key('signin.cancel')), findsOneWidget);
    // only the read: nothing posted before Approve
    expect(w.relay.log, ['GET /v2/signin/${w.row.id}']);
  });

  testWidgets('Cancel posts nothing', (t) async {
    final w = await _world();
    await _pump(t, w, qr: w.qr);
    await t.tap(find.byKey(const Key('signin.cancel')));
    await t.pumpAndSettle();
    expect(w.relay.log.where((l) => l.startsWith('POST')), isEmpty);
    expect(w.row.approverKey, isNull);
  });

  testWidgets('a scanned QR: Approve seals it and says done, with no number', (t) async {
    final w = await _world();
    final scanner = _Scanner(w.qr);
    await _pump(t, w, scanner: scanner);
    await t.tap(find.byKey(const Key('signin.scan')));
    await t.pumpAndSettle();
    expect(scanner.asked, [
      [signinQrPrefix],
    ]);
    await t.tap(find.byKey(const Key('signin.approve')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('signin.number')), findsNothing);
    expect(w.row.sealed, isNotNull);
    expect(find.textContaining('You are signed in on Firefox on Mac'), findsOneWidget);
  });

  testWidgets('a typed code: the number, and They match seals it', (t) async {
    final w = await _world();
    await _pump(t, w);
    await t.enterText(find.byKey(const Key('signin.code')), w.row.code.toLowerCase());
    await t.tap(find.byKey(const Key('signin.submit')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('signin.approve')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('signin.number')), findsOneWidget);
    expect(w.row.sealed, isNull);
    await t.tap(find.byKey(const Key('signin.match')));
    await t.pumpAndSettle();
    expect(w.row.sealed, isNotNull);
    expect(find.textContaining('You are signed in on Firefox on Mac'), findsOneWidget);
  });

  testWidgets('a typed code whose numbers do not match seals nothing', (t) async {
    final w = await _world();
    await _pump(t, w);
    await t.enterText(find.byKey(const Key('signin.code')), w.row.code);
    await t.tap(find.byKey(const Key('signin.submit')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('signin.approve')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('signin.noMatch')));
    await t.pumpAndSettle();
    expect(w.relay.log.any((l) => l.endsWith('/seal')), isFalse);
    expect(find.byKey(const Key('signin.close')), findsOneWidget);
  });

  testWidgets('a QR that is not a sign-in request says so, and posts nothing', (t) async {
    final w = await _world();
    await _pump(t, w, qr: 'wambito://signin?id=nope');
    expect(
      find.text(
        'That code does not match any request. Check it, or open a new one on the computer.',
      ),
      findsOneWidget,
    );
    expect(w.relay.log, isEmpty);
  });
}
