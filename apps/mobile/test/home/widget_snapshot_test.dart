import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/home/widget_snapshot.dart';

import 'fakes.dart';
import 'fixtures.dart';

Map<String, Object?> written(FakeWidgetStore store) =>
    jsonDecode(store.saved[widgetSnapshotKey]!) as Map<String, Object?>;

void main() {
  final now = DateTime.utc(2026, 10, 22, 15, 30);

  group('signed in', () {
    test('keeps the month figures as cents, with the currency, language and choices', () {
      final doc = signedInSnapshot(
        summary(budgetTotal: 200000000, spent: 50000000),
        currency: 'COP',
        timezone: 'America/Bogota',
        locale: 'es',
        hideAmount: false,
        theme: 'dark',
        updatedAt: now,
      );
      expect(doc, {
        'v': 3,
        'signedIn': true,
        'remaining': 150000000,
        'spent': 50000000,
        'budgetTotal': 200000000,
        'currency': 'COP',
        'locale': 'es',
        'month': '2026-10',
        'mood': 'happy',
        'updatedAt': '2026-10-22T15:30:00.000Z',
        'hideAmount': false,
        'theme': 'dark',
        'timezone': 'America/Bogota',
      });
    });

    test(
      'over the budgets the remaining is negative, and a category near its limit is worried',
      () {
        final doc = signedInSnapshot(
          summary(
            budgetTotal: 100000,
            spent: 150000,
            categories: [categorySummary('c', budget: 100000, spent: 150000, state: 'over')],
          ),
          currency: 'EUR',
          timezone: 'America/Bogota',
          locale: 'en',
          hideAmount: true,
          theme: 'light',
          updatedAt: now,
        );
        expect(doc['remaining'], -50000);
        expect(doc['mood'], 'worried');
        expect(doc['hideAmount'], true);
        expect(doc['theme'], 'light');
      },
    );

    test('without budgets the budget total is 0 and the spending is kept', () {
      final doc = signedInSnapshot(
        summary(spent: 4200000),
        currency: 'COP',
        timezone: 'America/Bogota',
        locale: 'es',
        hideAmount: false,
        theme: 'system',
        updatedAt: now,
      );
      expect(doc['budgetTotal'], 0);
      expect(doc['spent'], 4200000);
    });
  });

  test('signed out it says so and carries no figure, no currency and no month', () {
    final doc = signedOutSnapshot(hideAmount: true, theme: 'light', locale: 'en');
    expect(doc, {'v': 3, 'signedIn': false, 'hideAmount': true, 'theme': 'light', 'locale': 'en'});
  });

  group('choices changed', () {
    test('a signed-in snapshot keeps its figures and its time, with the new choices', () {
      final before = signedInSnapshot(
        summary(budgetTotal: 200000000, spent: 50000000),
        currency: 'COP',
        timezone: 'America/Bogota',
        locale: 'es',
        hideAmount: false,
        theme: 'dark',
        updatedAt: now,
      );
      final after = withChoices(jsonEncode(before), hideAmount: true, theme: 'light')!;
      expect(after, {...before, 'hideAmount': true, 'theme': 'light'});
    });

    test('nothing written yet, or an older version, gives nothing to patch', () {
      expect(withChoices(null, hideAmount: true, theme: 'dark'), isNull);
      expect(withChoices('{"v":1,"amount":"\$1"}', hideAmount: true, theme: 'dark'), isNull);
      // Version 2 had no zone: the app writes a new one at its next load.
      expect(withChoices('{"v":2,"signedIn":true}', hideAmount: true, theme: 'dark'), isNull);
      expect(withChoices('not json', hideAmount: true, theme: 'dark'), isNull);
    });
  });

  group('saving', () {
    test('is one JSON document under one key, and both widgets are told to redraw', () async {
      final store = FakeWidgetStore();
      await saveWidgetSnapshot(store, signedOutSnapshot(hideAmount: false, theme: 'dark'));
      expect(store.saved.keys, ['wambito.widget.snapshot']);
      expect(written(store)['signedIn'], false);
      expect(store.updates, 1);
    });

    test('a store that cannot be reached never breaks the app', () async {
      final store = FakeWidgetStore()..failure = MissingPluginException();
      await saveWidgetSnapshot(store, signedOutSnapshot(hideAmount: false, theme: 'dark'));
      store.failure = PlatformException(code: 'x');
      await saveWidgetSnapshot(store, signedOutSnapshot(hideAmount: false, theme: 'dark'));
      expect(store.saved, isEmpty);
    });
  });

  group('the real store', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    final calls = <String>[];

    setUp(() {
      calls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('home_widget'),
        (call) async {
          calls.add(call.method);
          return true;
        },
      );
    });

    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('home_widget'),
        null,
      );
    });

    test('asks Android to redraw both widgets', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      await const HomeWidgetStore().updateWidgets();
      expect(calls, ['updateWidget', 'updateWidget']);
    });

    test('calls nothing on iOS, which has no widgets here', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      await const HomeWidgetStore().updateWidgets();
      expect(calls, isEmpty);
    });
  });
}
