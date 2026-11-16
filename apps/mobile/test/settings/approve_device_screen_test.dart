import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/l10n/app_localizations.dart';
import 'package:wambito/local/key_storage.dart';
import 'package:wambito/local/keys.dart' show KeysOptions;
import 'package:wambito/local/pairing.dart' show ApproverPairing, PairingError;
import 'package:wambito/scanner/qr_scanner.dart';
import 'package:wambito/settings/security/approve_device_screen.dart';
import 'package:wambito/theme/theme.dart';
import 'package:wambito/ui/press_button.dart';
import 'package:wambito/ui/toast.dart';

/// The approver's screen (twin of the web's ApproveDevice.tsx), over a fake pairing and a fake
/// scanner: what each step shows, what each button asks of the pairing, and that the ephemeral key
/// is let go (`cancel`) whenever the screen is left before approving.
class FakeApprover implements ApproverPairing {
  final numbered = Completer<String>();
  final approved = Completer<void>();
  int cancels = 0;
  int approves = 0;

  @override
  Future<String> number() => numbered.future;

  @override
  Future<void> approve() {
    approves += 1;
    return approved.future;
  }

  @override
  void cancel() => cancels += 1;
}

class FakeScanner implements QrScanner {
  FakeScanner({this.available = true, this.text});

  final bool available;
  String? text;
  int scans = 0;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<String?> scan() async {
    scans += 1;
    return text;
  }
}

const _qr =
    'wambito://pair?id=0a1b2c3d-0000-4000-8000-0123456789ab&key=abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQ';

void main() {
  late FakeApprover pairing;
  late List<({String? code, String? qr})> finds;
  Object? findError;

  Future<ApproverPairing> fakeFind(KeysOptions options, {String? code, String? qr}) async {
    finds.add((code: code, qr: qr));
    if (findError != null) throw findError!;
    return pairing;
  }

  setUp(() {
    finds = [];
    findError = null;
  });

  final options = KeysOptions(userId: 'u1', dio: Dio(), storage: KeyStorage());

  Widget app(FakeScanner scanner, {VoidCallback? onDone, Widget? before}) => ProviderScope(
    overrides: [qrScannerProvider.overrideWithValue(scanner)],
    child: MaterialApp(
      theme: nightTheme,
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, home) => ToastHost(animateBar: false, child: home!),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              key: const Key('open'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ApproveDeviceScreen(
                    options: options,
                    findPairing: fakeFind,
                    onDone: onDone ?? () => Navigator.of(context).pop(),
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );

  Future<void> open(WidgetTester tester, FakeScanner scanner, {VoidCallback? onDone}) async {
    // Made here, in the test's own zone: its futures settle with the test's clock.
    pairing = FakeApprover();
    tester.view
      ..physicalSize = const Size(412, 915)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(scanner, onDone: onDone));
    await tester.tap(find.byKey(const Key('open')));
    await tester.pumpAndSettle();
  }

  Future<void> typeCode(WidgetTester tester, String code) async {
    await tester.enterText(find.byKey(const Key('approve.code')), code);
    await tester.pump();
    await tester.tap(find.byKey(const Key('approve.submit')));
    await tester.pump();
    await tester.pump();
  }

  bool enabled(WidgetTester tester, Finder button) =>
      tester.widget<PressButton>(button).onPressed != null;

  testWidgets('the screen is named "Approve a new device"', (tester) async {
    await open(tester, FakeScanner(available: false));
    expect(find.text('Approve a new device'), findsOneWidget);
  });

  testWidgets('scanner unavailable shows the code field only', (tester) async {
    await open(tester, FakeScanner(available: false));
    expect(find.byKey(const Key('approve.code')), findsOneWidget);
    expect(find.byKey(const Key('approve.scan')), findsNothing);
  });

  testWidgets('scanner available shows Scan and the code field', (tester) async {
    await open(tester, FakeScanner());
    expect(find.byKey(const Key('approve.scan')), findsOneWidget);
    expect(find.byKey(const Key('approve.code')), findsOneWidget);
  });

  testWidgets('a scanned text goes to findPairing(qr:)', (tester) async {
    final scanner = FakeScanner(text: _qr);
    await open(tester, scanner);
    await tester.tap(find.byKey(const Key('approve.scan')));
    await tester.pump();
    await tester.pump();
    expect(scanner.scans, 1);
    expect(finds, [(code: null, qr: _qr)]);
  });

  testWidgets('a cancelled scan (null) changes nothing', (tester) async {
    final scanner = FakeScanner();
    await open(tester, scanner);
    await tester.tap(find.byKey(const Key('approve.scan')));
    await tester.pumpAndSettle();
    expect(finds, isEmpty);
    expect(find.byKey(const Key('approve.code')), findsOneWidget);
    expect(find.text('We couldn\'t use the camera. Type the code instead.'), findsNothing);
  });

  testWidgets('a typed code goes to findPairing(code:)', (tester) async {
    await open(tester, FakeScanner(available: false));
    await typeCode(tester, 'ab3d efgh');
    expect(finds, [(code: 'AB3D EFGH', qr: null)]);
  });

  testWidgets('bad_code shows the web message and keeps the field', (tester) async {
    findError = const PairingError('bad_code');
    await open(tester, FakeScanner(available: false));
    await typeCode(tester, 'ZZZZ');
    await tester.pumpAndSettle();
    expect(
      find.text(
        'That code does not match any request. Check it, or start again on the new device.',
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('approve.code')), findsOneWidget);
  });

  testWidgets('Approve is enabled only once the number shows', (tester) async {
    await open(tester, FakeScanner(available: false));
    await typeCode(tester, 'AB3DEFGH');
    expect(find.text('Waiting for the new device…'), findsOneWidget);
    expect(find.byKey(const Key('approve.match')), findsNothing);

    pairing.numbered.complete('483920');
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('483 920'), findsOneWidget);
    expect(enabled(tester, find.byKey(const Key('approve.match'))), isTrue);
    expect(pairing.approves, 0);
  });

  testWidgets('They match approves, then shows Done', (tester) async {
    await open(tester, FakeScanner(available: false));
    await typeCode(tester, 'AB3DEFGH');
    pairing.numbered.complete('483920');
    await tester.pump();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('approve.match')));
    await tester.pump();
    expect(pairing.approves, 1);
    expect(enabled(tester, find.byKey(const Key('approve.match'))), isFalse);
    pairing.approved.complete();
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('Done'), findsOneWidget);
    expect(find.text('The new device can open your data now.'), findsOneWidget);
    // Approved: the pairing is finished, leaving the screen cancels nothing more.
    await tester.tap(find.byKey(const Key('approve.close')));
    await tester.pumpAndSettle();
    expect(pairing.cancels, 0);
  });

  testWidgets('They do not match cancels and shares nothing', (tester) async {
    await open(tester, FakeScanner(available: false));
    await typeCode(tester, 'AB3DEFGH');
    pairing.numbered.complete('483920');
    await tester.pump();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('approve.noMatch')));
    await tester.pumpAndSettle();
    expect(pairing.cancels, 1);
    expect(pairing.approves, 0);
    expect(find.text('Nothing was shared'), findsOneWidget);
  });

  testWidgets('Cancel while waiting cancels the pairing and closes', (tester) async {
    await open(tester, FakeScanner(available: false));
    await typeCode(tester, 'AB3DEFGH');
    await tester.tap(find.byKey(const Key('approve.cancel')));
    await tester.pumpAndSettle();
    expect(pairing.cancels, greaterThanOrEqualTo(1));
    expect(find.byType(ApproveDeviceScreen), findsNothing);
  });

  testWidgets('going back before approving cancels the pairing (the number showing)', (
    tester,
  ) async {
    await open(tester, FakeScanner(available: false));
    await typeCode(tester, 'AB3DEFGH');
    pairing.numbered.complete('483920');
    await tester.pump();
    await tester.pumpAndSettle();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(ApproveDeviceScreen), findsNothing);
    expect(pairing.cancels, greaterThanOrEqualTo(1));
    expect(pairing.approves, 0);
  });

  testWidgets('going back while approving still lets go of the key', (tester) async {
    await open(tester, FakeScanner(available: false));
    await typeCode(tester, 'AB3DEFGH');
    pairing.numbered.complete('483920');
    await tester.pump();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('approve.match')));
    await tester.pump();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(pairing.cancels, greaterThanOrEqualTo(1));
  });

  testWidgets('disposing the screen cancels the pairing', (tester) async {
    await open(tester, FakeScanner(available: false));
    await typeCode(tester, 'AB3DEFGH');
    expect(pairing.cancels, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(pairing.cancels, greaterThanOrEqualTo(1));
  });

  testWidgets('a pairing found after the screen went away is cancelled at once', (tester) async {
    pairing = FakeApprover();
    final late = Completer<ApproverPairing>();
    Future<ApproverPairing> slow(KeysOptions o, {String? code, String? qr}) => late.future;
    tester.view
      ..physicalSize = const Size(412, 915)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [qrScannerProvider.overrideWithValue(FakeScanner(available: false))],
        child: MaterialApp(
          theme: nightTheme,
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ApproveDeviceScreen(options: options, findPairing: slow, onDone: () {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('approve.code')), 'AB3DEFGH');
    await tester.tap(find.byKey(const Key('approve.submit')));
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    late.complete(pairing);
    await tester.pump();
    await tester.pump();
    expect(pairing.cancels, 1);
  });

  testWidgets('an expired request offers to start again', (tester) async {
    await open(tester, FakeScanner(available: false));
    await typeCode(tester, 'AB3DEFGH');
    pairing.numbered.completeError(const PairingError('expired'));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('The request expired'), findsOneWidget);
    await tester.tap(find.byKey(const Key('approve.restart')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('approve.code')), findsOneWidget);
  });

  testWidgets('a tampered pairing stops with a warning and no restart', (tester) async {
    await open(tester, FakeScanner(available: false));
    await typeCode(tester, 'AB3DEFGH');
    pairing.numbered.completeError(const PairingError('tampered'));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('Stop: someone may be interfering. Nothing was shared.'), findsOneWidget);
    expect(find.byKey(const Key('approve.restart')), findsNothing);
    expect(pairing.cancels, 1);
  });
}
