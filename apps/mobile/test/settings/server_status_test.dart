// Más' server row says whether the server answers (a green dot that blinks, or a red one)
// and which version it runs, asking again every 30 seconds while Settings is open.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/settings/server_status.dart';
import 'package:wambito/theme/tokens.g.dart';

import 'harness.dart';

/// A server whose answer the test sets, counting the times it was asked.
class _FakeServer {
  ServerHealth answer = const ServerHealth(online: true, version: '0.0.0-dev.abc1234');
  final asked = <Uri>[];

  Future<ServerHealth> check(Uri server) async {
    asked.add(server);
    return answer;
  }
}

Future<_FakeServer> _pump(WidgetTester tester, {bool pulses = false, _FakeServer? server}) async {
  final fake = server ?? _FakeServer();
  await pumpSettingsApp(
    tester,
    location: '/settings/more',
    overrides: [
      serverHealthCheckProvider.overrideWithValue(fake.check),
      serverDotPulsesProvider.overrideWithValue(pulses),
    ],
    settle: !pulses,
  );
  if (pulses) {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }
  await tester.scrollUntilVisible(
    find.byKey(const Key('settings.server.status')),
    300,
    scrollable: find.byType(Scrollable).first,
  );
  if (!pulses) await tester.pumpAndSettle();
  return fake;
}

Color _dot(WidgetTester tester) {
  final box = tester.widget<DecoratedBox>(find.byKey(const Key('settings.server.dot')));
  return (box.decoration as BoxDecoration).color!;
}

void main() {
  testWidgets('a server that answers: En línea, its version, and a green dot', (tester) async {
    final handle = tester.ensureSemantics();
    final server = await _pump(tester);
    expect(find.text('Conectado'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('En línea · Versión 0.0.0-dev.abc1234')), findsOneWidget);
    expect(_dot(tester), WambitoColors.night.good);
    expect(server.asked, isNotEmpty);
    handle.dispose();
  });

  testWidgets('a server that names no version: just En línea', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, server: _FakeServer()..answer = const ServerHealth(online: true));
    expect(find.text('Conectado'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('En línea')), findsOneWidget);
    handle.dispose();
  });

  testWidgets('a server that does not answer: No responde, and a red dot', (tester) async {
    await _pump(tester, server: _FakeServer()..answer = const ServerHealth.offline());
    expect(find.text('No responde'), findsOneWidget);
    expect(_dot(tester), WambitoColors.night.over);
  });

  testWidgets('it asks again every 30 seconds, and says when the server goes away', (tester) async {
    final server = await _pump(tester);
    final before = server.asked.length;
    server.answer = const ServerHealth.offline();
    await tester.pump(serverHealthEvery);
    await tester.pumpAndSettle();
    expect(server.asked.length, before + 1);
    expect(find.text('No responde'), findsOneWidget);
  });

  testWidgets('the green dot blinks; the red one does not', (tester) async {
    final server = await _pump(tester, pulses: true);
    expect(tester.hasRunningAnimations, isTrue, reason: 'online: the dot blinks');
    server.answer = const ServerHealth.offline();
    await tester.pump(serverHealthEvery);
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('No responde'), findsOneWidget);
    expect(tester.hasRunningAnimations, isFalse, reason: 'offline: the dot stays still');
  });

  testWidgets('with animations removed the green dot stays still', (tester) async {
    final handle = tester.ensureSemantics();
    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
      disableAnimations: true,
    );
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await _pump(tester, pulses: true);
    expect(find.text('Conectado'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('En línea · Versión 0.0.0-dev.abc1234')), findsOneWidget);
    expect(tester.hasRunningAnimations, isFalse);
    handle.dispose();
  });
}
