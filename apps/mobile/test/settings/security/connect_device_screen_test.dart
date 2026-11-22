// "Connect another device" (Settings → Security): one entry for a web sign-in and a device to
// approve. A scanned QR goes by its prefix, a typed code is looked up as a web sign-in first and as
// a pairing after; then the matching confirmation (ApproveSigninScreen, ApproveDeviceScreen) takes
// over, unchanged. Over the real `findSigninRequest` and a fake relay; the pairing is a fake.
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/api/server_url.dart';
import 'package:wambito/crypto/crypto.dart';
import 'package:wambito/local/keys.dart' show KeysOptions;
import 'package:wambito/local/pairing.dart' show ApproverPairing, PairingError;
import 'package:wambito/local/signin_approval.dart' as signin;
import 'package:wambito/scanner/qr_scanner.dart';
import 'package:wambito/settings/security/approve_device_screen.dart';
import 'package:wambito/settings/security/approve_signin_screen.dart';
import 'package:wambito/settings/security/connect_device_screen.dart';
import 'package:wambito/settings/security/security_api.dart';
import 'package:wambito/ui/press_button.dart';

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
  _Scanner(this.text, {this.available = true});

  final String? text;
  final bool available;
  final asked = <List<String>>[];

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<String?> scan({List<String> prefixes = const [pairQrPrefix]}) async {
    asked.add(prefixes);
    return text;
  }
}

class _Expiring implements ApproverPairing {
  int cancels = 0;

  @override
  Future<String> number() => Future.error(const PairingError('expired'));

  @override
  Future<void> approve() async {}

  @override
  void cancel() => cancels += 1;
}

const _pairQr =
    'wambito://pair?id=0a1b2c3d-0000-4000-8000-0123456789ab&key=abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQ';

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
    ..findSignin = ({code, qr, fromLink = false}) =>
        signin.findSigninRequest(options, code: code, qr: qr, fromLink: fromLink, clock: clock);
  return _World(relay, row, 'wambito://signin?id=${row.id}&key=${browser.key}', security);
}

Future<ProviderContainer> _pump(WidgetTester t, FakeSecurity security, {QrScanner? scanner}) async {
  t.view
    ..physicalSize = const Size(824, 2400)
    ..devicePixelRatio = 2;
  addTearDown(t.view.reset);
  final container = ProviderContainer(
    overrides: [
      securityApiProvider.overrideWithValue(security),
      serverUrlProvider.overrideWith(_Server.new),
      qrScannerProvider.overrideWithValue(scanner ?? _Scanner(null)),
    ],
  );
  addTearDown(container.dispose);
  await t.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: uiApp(const ConnectDeviceScreen(), locale: const Locale('en')),
    ),
  );
  await t.pumpAndSettle();
  return container;
}

Future<void> _type(WidgetTester t, String code) async {
  await t.enterText(find.byKey(const Key('connect.code')), code);
  await t.pump();
  await t.tap(find.byKey(const Key('connect.submit')));
  await t.pump();
  await t.pumpAndSettle();
}

bool _enabled(WidgetTester t, String key) =>
    t.widget<PressButton>(find.byKey(Key(key))).onPressed != null;

void main() {
  setUpAll(loadAppFonts);

  testWidgets('is titled "Connect another device" and asks for a QR or a code', (t) async {
    final w = await _world();
    await _pump(t, w.security);
    expect(find.text('Connect another device'), findsOneWidget);
    expect(
      find.text('Scan the QR code your computer or another phone shows you, or type its code.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('connect.scan')), findsOneWidget);
    expect(find.byKey(const Key('connect.code')), findsOneWidget);
    // nothing is looked up before a code or a scan
    expect(w.security.calls.where((c) => c.startsWith('find')), isEmpty);
  });

  testWidgets('no camera: only the code field', (t) async {
    final w = await _world();
    await _pump(t, w.security, scanner: _Scanner(null, available: false));
    expect(find.byKey(const Key('connect.scan')), findsNothing);
    expect(find.byKey(const Key('connect.code')), findsOneWidget);
  });

  testWidgets('one scan takes both QRs', (t) async {
    final w = await _world();
    final scanner = _Scanner(null);
    await _pump(t, w.security, scanner: scanner);
    await t.tap(find.byKey(const Key('connect.scan')));
    await t.pumpAndSettle();
    expect(scanner.asked, [
      [pairQrPrefix, signinQrPrefix],
    ]);
    // a closed scan: back to the field, nothing looked up
    expect(find.byKey(const Key('connect.code')), findsOneWidget);
    expect(w.security.calls.where((c) => c.startsWith('find')), isEmpty);
  });

  testWidgets('a scanned sign-in QR reaches the sign-in confirmation', (t) async {
    final w = await _world();
    await _pump(t, w.security, scanner: _Scanner(w.qr));
    await t.tap(find.byKey(const Key('connect.scan')));
    // as soon as the question shows, not once everything settled
    for (var i = 0; i < 50 && find.byKey(const Key('signin.approve')).evaluate().isEmpty; i++) {
      await t.pump(const Duration(milliseconds: 10));
    }
    expect(find.byType(ApproveSigninScreen), findsOneWidget);
    expect(find.textContaining('Sign in on “Firefox on Mac”?'), findsOneWidget);
    expect(find.textContaining('Only scan a code you see on money.example.org'), findsOneWidget);
    // the 1 s wait before Approve, as from its own screen
    expect(_enabled(t, 'signin.approve'), isFalse);
    await t.pump(signinApproveDelay);
    expect(_enabled(t, 'signin.approve'), isTrue);
    expect(w.security.calls, ['findSigninRequest code=null qr=${w.qr}']);
    // only the read: nothing posted before Approve
    expect(w.relay.log, ['GET /v2/signin/${w.row.id}']);
    await t.tap(find.byKey(const Key('signin.approve')));
    await t.pumpAndSettle();
    expect(find.text('You are signed in on Firefox on Mac.'), findsOneWidget);
  });

  testWidgets('a scanned pairing QR reaches the device approval', (t) async {
    final w = await _world();
    await _pump(t, w.security, scanner: _Scanner(_pairQr));
    await t.tap(find.byKey(const Key('connect.scan')));
    await t.pumpAndSettle();
    expect(w.security.calls, ['findPairing code=null qr=$_pairQr']);
    expect(find.byType(ApproveDeviceScreen), findsOneWidget);
    expect(find.text('123 456'), findsOneWidget);
    expect(find.byKey(const Key('approve.match')), findsOneWidget);
  });

  testWidgets('a typed code found as a sign-in goes there, never to a pairing', (t) async {
    final w = await _world();
    await _pump(t, w.security, scanner: _Scanner(null, available: false));
    await _type(t, w.row.code);
    expect(w.security.calls, ['findSigninRequest code=${w.row.code} qr=null']);
    expect(find.byType(ApproveSigninScreen), findsOneWidget);
    expect(find.textContaining('Sign in on “Firefox on Mac”?'), findsOneWidget);
    // a typed code compares the number before the seal, as from its own screen
    await t.tap(find.byKey(const Key('signin.approve')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('signin.number')), findsOneWidget);
  });

  testWidgets('a typed code not found as a sign-in but as a pairing goes to the approval', (
    t,
  ) async {
    final w = await _world();
    await _pump(t, w.security, scanner: _Scanner(null, available: false));
    await _type(t, 'ZZZZ ZZZZ');
    expect(w.security.calls, [
      'findSigninRequest code=ZZZZ ZZZZ qr=null',
      'findPairing code=ZZZZ ZZZZ qr=null',
    ]);
    expect(find.byType(ApproveDeviceScreen), findsOneWidget);
    expect(find.text('123 456'), findsOneWidget);
  });

  testWidgets('a typed code found as neither says so and keeps the field', (t) async {
    final w = await _world();
    w.security.pairingFailure = const PairingError('bad_code');
    await _pump(t, w.security, scanner: _Scanner(null, available: false));
    await _type(t, 'ZZZZ ZZZZ');
    expect(w.security.calls, hasLength(2));
    expect(
      find.text(
        'That code does not match any request. Check it, or start again on the other device.',
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('connect.code')), findsOneWidget);
    expect(find.byType(ApproveDeviceScreen), findsNothing);
  });

  testWidgets('offline says so, and looks no further', (t) async {
    final w = await _world();
    w.security.findSignin = ({code, qr, fromLink = false}) =>
        Future.error(const signin.SigninError('offline'));
    await _pump(t, w.security, scanner: _Scanner(null, available: false));
    await _type(t, 'ABCD 2345');
    expect(w.security.calls, ['findSigninRequest code=ABCD 2345 qr=null']);
    expect(find.text('You are offline. Try again when you are back online.'), findsOneWidget);
    expect(find.byKey(const Key('connect.code')), findsOneWidget);
  });

  testWidgets('"Start again" after a failed approval comes back here', (t) async {
    final w = await _world();
    final expiring = _Expiring();
    w.security.approver = expiring;
    await _pump(t, w.security, scanner: _Scanner(_pairQr));
    await t.tap(find.byKey(const Key('connect.scan')));
    await t.pumpAndSettle();
    expect(find.text('The request expired'), findsOneWidget);
    await t.tap(find.byKey(const Key('approve.restart')));
    await t.pumpAndSettle();
    expect(find.byType(ApproveDeviceScreen), findsNothing);
    expect(find.text('Connect another device'), findsOneWidget);
    expect(find.byKey(const Key('connect.code')), findsOneWidget);
  });

  testWidgets('a sign-in link is dropped while this screen is open', (t) async {
    final w = await _world();
    final container = await _pump(t, w.security);
    expect(container.read(openSigninApprovalsProvider).any, isTrue);
    await t.pumpWidget(
      UncontrolledProviderScope(container: container, child: const SizedBox.shrink()),
    );
    expect(container.read(openSigninApprovalsProvider).any, isFalse);
  });

  testWidgets('a pairing found after the screen went away is cancelled at once', (t) async {
    final w = await _world();
    final expiring = _Expiring();
    final gate = Completer<void>();
    w.security
      ..approver = expiring
      ..pairingGate = gate.future;
    final container = await _pump(t, w.security, scanner: _Scanner(_pairQr));
    await t.tap(find.byKey(const Key('connect.scan')));
    await t.pump();
    await t.pumpWidget(
      UncontrolledProviderScope(container: container, child: const SizedBox.shrink()),
    );
    gate.complete();
    await t.pump();
    await t.pump();
    expect(expiring.cancels, 1);
  });
}
