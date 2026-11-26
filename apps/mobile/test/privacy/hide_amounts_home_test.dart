// Home's eye: right after the hero figure, it hides every amount on home (the hero, the meter,
// Wambi's line, the rows) with the blind coming down, and shows them again with the blind going up.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/api/server_address.dart';
import 'package:wambito/feedback/feedback.dart';
import 'package:wambito/settings/initial_settings.dart';
import 'package:wambito/settings/settings_store.dart';

import '../feedback/fakes.dart';
import '../home/home_harness.dart';
import '../settings/fakes.dart';
import '../support/amounts.dart';

Future<(HomeHarness, FakeFeedbackPlatform)> _pump(WidgetTester t, {bool hidden = false}) async {
  final platform = FakeFeedbackPlatform();
  final harness = await pumpHome(
    t,
    monthWithBudgets(),
    overrides: [
      feedbackPlatformProvider.overrideWithValue(platform),
      soundSettingStoreProvider.overrideWithValue(FakeSoundStore()),
      vibrationSettingStoreProvider.overrideWithValue(FakeSoundStore()),
      settingsStoreProvider.overrideWithValue(FakeSettingsStore()),
      initialSettingsProvider.overrideWithValue(
        InitialSettings(
          serverUrl: defaultServerUrl,
          themeMode: ThemeMode.dark,
          hideAmounts: hidden,
        ),
      ),
    ],
  );
  await harness.container.read(vibrationEnabledProvider.notifier).ready;
  return (harness, platform);
}

void main() {
  testWidgets('the eye hides every amount on home and Wambi says why', (t) async {
    final semantics = t.ensureSemantics();
    final (_, platform) = await _pump(t);
    expect(find.bySemanticsLabel('Ocultar montos'), findsOneWidget);
    await t.tap(find.byKey(const Key('home.hideAmounts')));
    await t.pumpAndSettle();
    expectNoAmounts(t);
    expect(find.text('Tus montos están ocultos. Toca el ojo para verlos.'), findsOneWidget);
    expect(find.bySemanticsLabel('Mostrar montos'), findsOneWidget);
    expect(platform.haptics.last, hapticPatterns[FeedbackEvent.amountsHidden]);
    semantics.dispose();
  });

  testWidgets('a second tap shows them again with the blind going up', (t) async {
    final (_, platform) = await _pump(t);
    await t.tap(find.byKey(const Key('home.hideAmounts')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('home.hideAmounts')));
    await t.pumpAndSettle();
    expect(find.text('Tus montos están ocultos. Toca el ojo para verlos.'), findsNothing);
    expect(find.textContaining(RegExp(r'\d')), findsWidgets);
    expect(platform.haptics.last, hapticPatterns[FeedbackEvent.amountsShown]);
  });

  testWidgets('started hidden, the first frame already has no amount', (t) async {
    final semantics = t.ensureSemantics();
    await _pump(t, hidden: true);
    expectNoAmounts(t);
    semantics.dispose();
  });
}
