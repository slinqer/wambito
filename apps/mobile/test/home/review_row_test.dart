import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../review/fakes.dart';
import '../settings/harness.dart';
import 'fakes.dart';
import 'fixtures.dart';
import 'home_harness.dart';

void main() {
  FakeHomeRepository month(int detectedCount) => FakeHomeRepository(
    items: [
      for (var i = 1; i <= detectedCount; i++)
        detected('d$i', '2026-10-21', -1000 * i, name: 'Cafe $i'),
      tx('t1', '2026-10-20', -500000, name: 'Pan'),
    ],
  );

  testWidgets('says how many wait', (tester) async {
    await pumpHome(tester, month(3));
    expect(find.text('3 gastos por revisar'), findsOneWidget);
  });

  testWidgets('one waiting reads in the singular', (tester) async {
    await pumpHome(tester, month(1));
    expect(find.text('1 gasto por revisar'), findsOneWidget);
  });

  testWidgets('nothing waiting: no row', (tester) async {
    await pumpHome(tester, month(0));
    expect(find.byKey(const Key('home.review')), findsNothing);
    expect(find.byKey(const Key('row.review')), findsNothing);
  });

  testWidgets('a detected row carries the mark', (tester) async {
    await pumpHome(tester, month(1));
    expect(find.text('por revisar · de Revolut'), findsOneWidget);
    expect(find.byKey(const Key('row.review')), findsOneWidget);
  });

  testWidgets('English and Google Wallet', (tester) async {
    final repo = FakeHomeRepository(
      items: [detected('d1', '2026-10-21', -1000, source: 'google_wallet')],
    );
    await pumpHome(tester, repo, locale: const Locale('en'));
    expect(find.text('1 to review'), findsOneWidget);
    expect(find.text('to review · from Google Wallet'), findsOneWidget);
  });

  testWidgets('tapping it opens the inbox', (tester) async {
    final env = await pumpSettingsApp(tester, homeRepo: month(3));
    await tester.tap(find.text('3 gastos por revisar'));
    await tester.pumpAndSettle();
    expect(env.router.state.uri.path, '/review');
    expect(find.text('Cafe 1'), findsOneWidget);
  });
}
