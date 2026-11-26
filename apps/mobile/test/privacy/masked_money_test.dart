// The masking layer: one masked form for any amount, live, and read as "amount hidden".
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/money/format.dart';
import 'package:wambito/privacy/hide_amounts.dart';
import 'package:wambito/privacy/masked_money.dart';
import 'package:wambito/settings/settings_store.dart';
import 'package:wambito/ui/money.dart';

import '../settings/fakes.dart';
import '../support/amounts.dart';
import '../support/ui_app.dart';

void main() {
  test('shownMoney masks any amount and sign the same way', () {
    expect(hiddenAmount, '••••');
    expect(shownMoney(true, -410, 'EUR', 'es'), '••••');
    expect(shownMoney(true, 123456789, 'USD', 'en'), '••••');
    expect(shownMoney(true, 0, 'EUR', 'es'), '••••');
    expect(shownMoney(false, -410, 'EUR', 'es'), formatMoney(-410, 'EUR', 'es'));
    expect(
      shownMoney(false, 410, 'EUR', 'es', sign: MoneySign.always),
      formatMoney(410, 'EUR', 'es', sign: MoneySign.always),
    );
  });

  testWidgets('Money shows •••• and reads "amount hidden" while hidden, and flips live', (t) async {
    final semantics = t.ensureSemantics();
    final container = ProviderContainer(
      overrides: [settingsStoreProvider.overrideWithValue(FakeSettingsStore())],
    );
    addTearDown(container.dispose);
    await t.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: uiApp(
          const HiddenAmountsScope(child: Money(cents: -410, currency: 'EUR', animate: true)),
        ),
      ),
    );
    expect(find.text(formatMoney(-410, 'EUR', 'es')), findsOneWidget);

    await container.read(amountsHiddenProvider.notifier).set(true);
    await t.pump();
    expect(find.text('••••'), findsOneWidget);
    expect(find.bySemanticsLabel('Monto oculto'), findsOneWidget);
    expectNoAmounts(t);

    await container.read(amountsHiddenProvider.notifier).set(false);
    await t.pump();
    expect(find.text(formatMoney(-410, 'EUR', 'es')), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('expectNoAmounts finds amounts in text and passes on the masked form', (t) async {
    for (final amount in ['4,10 €', '€4.10', '1.234 USD', '−12,50 €', '£3']) {
      await t.pumpWidget(uiApp(Text(amount)));
      expect(() => expectNoAmounts(t), throwsA(isA<TestFailure>()), reason: amount);
    }
    await t.pumpWidget(uiApp(const Text('Gastado este mes ••••')));
    expectNoAmounts(t);
  });
}
