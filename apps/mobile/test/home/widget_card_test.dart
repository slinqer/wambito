import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/feedback/stored_flag.dart';
import 'package:wambito/home/widget_pin.dart';

import '../settings/fakes.dart' show FakeFlagStore;
import '../settings/harness.dart';
import 'fakes.dart';
import 'fixtures.dart';
import 'home_harness.dart';

void main() {
  const card = Key('home.widgetCard');

  FakeHomeRepository withMovement() =>
      FakeHomeRepository(items: [tx('t1', '2026-10-20', -500000, name: 'Pan')]);

  // Android unless the test says otherwise; the override is reset inside the test, before the
  // framework checks that no debug variable was left changed.
  void androidTest(String name, Future<void> Function(WidgetTester tester) body) {
    testWidgets(name, (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        await body(tester);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  androidTest('no card while there are no movements', (tester) async {
    await pumpHome(
      tester,
      FakeHomeRepository(),
      overrides: [widgetPinProvider.overrideWithValue(FakeWidgetPin(isInstalled: false))],
    );
    expect(find.byKey(card), findsNothing);
  });

  androidTest('the card shows once there is a movement', (tester) async {
    await pumpHome(
      tester,
      withMovement(),
      overrides: [widgetPinProvider.overrideWithValue(FakeWidgetPin(isInstalled: false))],
    );
    expect(find.byKey(card), findsOneWidget);
    expect(find.text('Anota sin abrir la app'), findsOneWidget);
  });

  androidTest('no card when a widget is already on the home screen', (tester) async {
    await pumpHome(
      tester,
      withMovement(),
      overrides: [widgetPinProvider.overrideWithValue(FakeWidgetPin(isInstalled: true))],
    );
    expect(find.byKey(card), findsNothing);
  });

  androidTest('Ahora no hides it for good', (tester) async {
    final flags = <String, FakeFlagStore>{};
    final overrides = [
      widgetPinProvider.overrideWithValue(FakeWidgetPin(isInstalled: false)),
      flagStoreProvider.overrideWith((ref, key) => flags.putIfAbsent(key, FakeFlagStore.new)),
    ];
    await pumpHome(tester, withMovement(), overrides: overrides);
    await tester.tap(find.byKey(const Key('widgetCard.close')));
    await tester.pumpAndSettle();
    expect(find.byKey(card), findsNothing);
    expect(flags['wambito.widgetCard.closed']?.value, isTrue);

    // The next start: the same phone, a new home.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 15));
    await pumpHome(tester, withMovement(), overrides: overrides);
    expect(find.byKey(card), findsNothing);
  });

  androidTest('Añadir widget asks the launcher when it can', (tester) async {
    final pin = FakeWidgetPin(isInstalled: false);
    await pumpHome(tester, withMovement(), overrides: [widgetPinProvider.overrideWithValue(pin)]);
    await tester.tap(find.byKey(const Key('widgetCard.add')));
    await tester.pumpAndSettle();
    expect(pin.pins, 1);
    expect(find.text('Así añades el widget'), findsNothing);
  });

  androidTest('the card goes once the widget is on the home screen, on the next resume', (
    tester,
  ) async {
    final pin = FakeWidgetPin(isInstalled: false);
    await pumpHome(tester, withMovement(), overrides: [widgetPinProvider.overrideWithValue(pin)]);
    await tester.tap(find.byKey(const Key('widgetCard.add')));
    await tester.pumpAndSettle();
    expect(find.byKey(card), findsOneWidget);
    pin.isInstalled = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.byKey(card), findsNothing);
  });

  androidTest('Añadir widget shows the steps when the launcher cannot', (tester) async {
    final pin = FakeWidgetPin(isInstalled: false, isSupported: false);
    await pumpHome(tester, withMovement(), overrides: [widgetPinProvider.overrideWithValue(pin)]);
    await tester.tap(find.byKey(const Key('widgetCard.add')));
    await tester.pumpAndSettle();
    expect(pin.pins, 0);
    expect(find.text('Así añades el widget'), findsOneWidget);
    expect(find.text('Toca «Widgets».'), findsOneWidget);
  });

  androidTest('never on iOS', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await pumpHome(
      tester,
      withMovement(),
      overrides: [widgetPinProvider.overrideWithValue(FakeWidgetPin(isInstalled: false))],
    );
    expect(find.byKey(card), findsNothing);
  });

  androidTest('Settings offers Añadir widget on Android until one is added', (tester) async {
    final pin = FakeWidgetPin(isInstalled: false);
    await pumpSettingsApp(
      tester,
      location: '/settings',
      overrides: [widgetPinProvider.overrideWithValue(pin)],
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('settings.addWidget')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Anota desde tu pantalla de inicio'), findsOneWidget);
    await tester.tap(find.byKey(const Key('settings.addWidget')));
    await tester.pumpAndSettle();
    expect(pin.pins, 1);
  });

  androidTest('Settings has no Añadir widget once one is added', (tester) async {
    await pumpSettingsApp(tester, location: '/settings');
    await tester.scrollUntilVisible(
      find.byKey(const Key('settings.hideAmount')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const Key('settings.addWidget')), findsNothing);
  });
}
