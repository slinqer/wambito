import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/l10n/app_localizations.dart';
import 'package:wambito/local/pairing.dart' show ApproverPairing, PairingError;
import 'package:wambito/settings/security/approve_device_screen.dart';
import 'package:wambito/theme/theme.dart';
import 'package:wambito/ui/press_button.dart';
import 'package:wambito/ui/toast.dart';

/// The approver's confirmation (twin of the web's ApproveDevice.tsx), over a fake pairing found by
/// "Connect another device" (connect_device_screen_test.dart has the scan and the typed code): what
/// each step shows, what each button asks of the pairing, and that the ephemeral key is let go
/// (`cancel`) whenever the screen is left before approving.
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

void main() {
  late FakeApprover pairing;
  late int restarts;

  Widget app({VoidCallback? onDone}) => ProviderScope(
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
                    pairing: pairing,
                    onStartAgain: () => restarts += 1,
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

  Future<void> open(WidgetTester tester, {VoidCallback? onDone}) async {
    // Made here, in the test's own zone: its futures settle with the test's clock.
    pairing = FakeApprover();
    restarts = 0;
    tester.view
      ..physicalSize = const Size(412, 915)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(onDone: onDone));
    await tester.tap(find.byKey(const Key('open')));
    await tester.pump();
    await tester.pump();
  }

  bool enabled(WidgetTester tester, Finder button) =>
      tester.widget<PressButton>(button).onPressed != null;

  testWidgets('the confirmation is named "Approve a new device"', (tester) async {
    await open(tester);
    expect(find.text('Approve a new device'), findsOneWidget);
    expect(find.text('Waiting for the new device…'), findsOneWidget);
  });

  testWidgets('Approve is enabled only once the number shows', (tester) async {
    await open(tester);
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
    await open(tester);
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
    await open(tester);
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
    await open(tester);
    await tester.tap(find.byKey(const Key('approve.cancel')));
    await tester.pumpAndSettle();
    expect(pairing.cancels, greaterThanOrEqualTo(1));
    expect(find.byType(ApproveDeviceScreen), findsNothing);
  });

  testWidgets('going back before approving cancels the pairing (the number showing)', (
    tester,
  ) async {
    await open(tester);
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
    await open(tester);
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
    await open(tester);
    expect(pairing.cancels, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(pairing.cancels, greaterThanOrEqualTo(1));
  });

  testWidgets('an expired request offers to start again', (tester) async {
    await open(tester);
    pairing.numbered.completeError(const PairingError('expired'));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('The request expired'), findsOneWidget);
    await tester.tap(find.byKey(const Key('approve.restart')));
    await tester.pumpAndSettle();
    // back to "Connect another device": the pairing was already let go
    expect(restarts, 1);
    expect(pairing.cancels, 1);
  });

  testWidgets('a tampered pairing stops with a warning and no restart', (tester) async {
    await open(tester);
    pairing.numbered.completeError(const PairingError('tampered'));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('Stop: someone may be interfering. Nothing was shared.'), findsOneWidget);
    expect(find.byKey(const Key('approve.restart')), findsNothing);
    expect(pairing.cancels, 1);
  });
}
