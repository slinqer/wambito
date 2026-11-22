// "Hora y moneda" in Settings (apps/web/app/features/settings/TimeAndMoneySection.tsx), and Review
// Focus 4 of Stage 3c: the currency is refused after the first movement, with the web's words, and a
// new time zone moves "today" everywhere (home, the widget's snapshot and the notices).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/api/device.dart';
import 'package:wambito/api/gen/wambito_api.dart';
import 'package:wambito/home/home_controller.dart';
import 'package:wambito/home/home_repository.dart';
import 'package:wambito/notices/notice_backend.dart';
import 'package:wambito/notices/notice_platform.dart';
import 'package:wambito/notices/notice_sync.dart';
import 'package:wambito/recurring/recurring_repository.dart';
import 'package:wambito/router.dart';
import 'package:wambito/settings/settings_model.dart';
import 'package:wambito/welcome/onboarding_repository.dart';

import '../home/fakes.dart';
import '../home/fixtures.dart';
import '../notices/fakes.dart';
import '../recurring/fakes.dart';
import 'harness.dart';
import 'fakes.dart';

/// 23:30 UTC on 21 October 2026: still the 21st in Bogota (18:30), already the 22nd in Madrid (01:30).
final _now = DateTime.utc(2026, 10, 21, 23, 30);

class _Env {
  _Env(this.settings, this.home, this.server, this.platform, this.recurring, this.snapshots);

  final SettingsEnv settings;
  final FakeHomeRepository home;
  final FakeProfileServer server;
  final FakeNoticePlatform platform;
  final FakeRecurringRepository recurring;
  final List<({String currency, String timezone})> snapshots;

  HomeState get homeState => settings.container.read(homeProvider);
}

Future<_Env> _pump(
  WidgetTester t, {
  String currency = 'COP',
  bool movements = false,
  List<Recurrence> rules = const [],
  String deviceZone = 'America/Bogota',
  String zone = 'America/Bogota',
  Locale locale = const Locale('es'),
  bool guest = false,
}) async {
  final home = FakeHomeRepository(
    currency: currency,
    timezone: zone,
    items: [if (movements) tx('t1', '2026-10-20', -1500000, currency: currency)],
  );
  final notices = FakeNoticeBackend(hasRecurring: rules.isNotEmpty);
  final server = FakeProfileServer(home, notices: notices);
  final platform = FakeNoticePlatform(permissionState: NoticePermission.granted);
  final recurring = FakeRecurringRepository(home, rules: rules);
  final snapshots = <({String currency, String timezone})>[];
  final settings = await pumpSettingsApp(
    t,
    locale: locale,
    guest: guest,
    homeRepo: home,
    overrides: [
      onboardingRepositoryProvider.overrideWithValue(server),
      recurringRepositoryProvider.overrideWithValue(recurring),
      noticePlatformProvider.overrideWithValue(platform),
      noticeBackendProvider.overrideWithValue(notices),
      clockProvider.overrideWithValue(() => _now),
      deviceHintsProvider.overrideWithValue(DeviceHints(timezone: deviceZone, locale: 'es')),
      widgetSnapshotWriterProvider.overrideWithValue(
        (summary, {required currency, required locale, required timezone}) async =>
            snapshots.add((currency: currency, timezone: timezone)),
      ),
    ],
  );
  await settings.container.read(noticeSyncProvider).idle;
  await t.pumpAndSettle();
  // Settings opens over home, which stays mounted under it.
  settings.container.listen(homeProvider, (_, _) {});
  settings.container.read(routerProvider).push('/settings/preferences');
  await t.pumpAndSettle();
  return _Env(settings, home, server, platform, recurring, snapshots);
}

/// A test with the screen reader's tree on, for the texts [said] finds.
void testPage(String name, Future<void> Function(WidgetTester t) body) =>
    testWidgets(name, (t) async {
      final handle = t.ensureSemantics();
      await body(t);
      handle.dispose();
    });

/// A text drawn by `CssParagraph` (the card titles, the hints, the lines under a field): broken into
/// lines of words as the web breaks it, so it is found by what a screen reader reads.
Finder said(String text) => find.bySemanticsLabel(text);

Future<void> _scrollTo(WidgetTester t, String key) async {
  await t.scrollUntilVisible(find.byKey(Key(key)), 200, scrollable: find.byType(Scrollable).first);
  await t.pumpAndSettle();
}

/// Opens the sheet of the currency row.
Future<void> _openCurrency(WidgetTester t) async {
  await _scrollTo(t, 'settings.currency.row');
  await t.tap(find.byKey(const Key('settings.currency.row')));
  await t.pumpAndSettle();
}

Future<void> _openZones(WidgetTester t) async {
  await _scrollTo(t, 'settings.timezone.change');
  await t.tap(find.byKey(const Key('settings.timezone.change')));
  await t.pumpAndSettle();
}

Future<void> _search(WidgetTester t, String query) async {
  await t.enterText(find.byKey(const Key('settings.timezone.search')), query);
  await t.pumpAndSettle();
}

void main() {
  group('the time zone', () {
    testPage('its row shows the profile\'s city; the sheet has the hint, the region and offset', (
      t,
    ) async {
      await _pump(t);
      await _scrollTo(t, 'settings.timezone.change');
      expect(said('Hora y moneda'), findsWidgets);
      expect(find.text('Zona horaria'), findsOneWidget);
      expect(find.text('Bogota'), findsOneWidget);
      await _openZones(t);
      expect(said('Con ella sabemos cuándo empieza tu día y tu mes.'), findsOneWidget);
      await _search(t, 'bogota');
      expect(find.text('America · GMT-5'), findsOneWidget);
    });

    testPage('its row is named "Zona horaria" for a screen reader', (t) async {
      await _pump(t);
      await _scrollTo(t, 'settings.timezone.change');
      expect(find.bySemanticsLabel(RegExp(r'Zona horaria[\s\S]*Bogota')), findsOneWidget);
    });

    testPage('a search sheet finds a zone by city, without accents; picking saves it', (t) async {
      final env = await _pump(t);
      await _openZones(t);
      expect(find.text('Elige tu zona horaria'), findsOneWidget);
      await _search(t, 'bogotá');
      expect(find.byKey(const Key('settings.timezone.option.America/Bogota')), findsOneWidget);
      await _search(t, 'madrid');
      expect(find.byKey(const Key('settings.timezone.option.America/Bogota')), findsNothing);
      await t.tap(find.byKey(const Key('settings.timezone.option.Europe/Madrid')));
      await t.pumpAndSettle();

      expect(env.server.patches, [
        {'timezone': 'Europe/Madrid'},
      ]);
      expect(find.text('Elige tu zona horaria'), findsNothing, reason: 'the sheet closed');
      expect(find.text('Listo: ahora usamos la hora de Madrid.'), findsOneWidget);
      expect(find.text('Madrid'), findsOneWidget);
      await t.pump(const Duration(seconds: 10));
    });

    testPage('a country finds its zones too, and nothing found says so', (t) async {
      await _pump(t);
      await _openZones(t);
      await _search(t, 'colombia');
      expect(find.byKey(const Key('settings.timezone.option.America/Bogota')), findsOneWidget);
      await _search(t, 'zzzz');
      expect(
        said('No encontramos «zzzz». Prueba con la ciudad grande más cercana.'),
        findsOneWidget,
      );
    });

    testPage('the zone in use is marked "Actual"; picking it again only closes the sheet', (
      t,
    ) async {
      final env = await _pump(t);
      await _openZones(t);
      await _search(t, 'bogota');
      expect(find.text('ACTUAL'), findsOneWidget);
      await t.tap(find.byKey(const Key('settings.timezone.option.America/Bogota')));
      await t.pumpAndSettle();
      expect(env.server.patches, isEmpty);
      expect(find.text('Elige tu zona horaria'), findsNothing);
    });

    testPage('a long list shows 40 and says how many more there are', (t) async {
      await _pump(t);
      await _openZones(t);
      await _search(t, 'america');
      final found = searchZones(
        pickableTimeZones(),
        'america',
        40,
        zoneSearchIndex(pickableTimeZones()),
      );
      expect(found.more, greaterThan(0));
      expect(
        said('Hay ${found.more} más: sigue escribiendo para encontrar la tuya.'),
        findsOneWidget,
      );
    });

    testPage('offers the phone\'s own zone while nothing is typed', (t) async {
      final env = await _pump(t, deviceZone: 'Europe/Madrid');
      await _openZones(t);
      expect(find.text('USAR LA DE ESTE DISPOSITIVO: MADRID'), findsOneWidget);
      await _search(t, 'lima');
      expect(find.text('USAR LA DE ESTE DISPOSITIVO: MADRID'), findsNothing);
      await _search(t, '');
      await t.tap(find.byKey(const Key('settings.timezone.useDevice')));
      await t.pumpAndSettle();
      expect(env.server.patches, [
        {'timezone': 'Europe/Madrid'},
      ]);
      await t.pump(const Duration(seconds: 10));
    });

    testPage(
      'a phone on IANA\'s Buenos_Aires and a profile on the web\'s: it is "Actual", not offered again',
      (t) async {
        final env = await _pump(
          t,
          zone: 'America/Buenos_Aires',
          deviceZone: 'America/Argentina/Buenos_Aires',
        );
        await _openZones(t);
        expect(find.byKey(const Key('settings.timezone.useDevice')), findsNothing);
        await _search(t, 'argentina');
        expect(
          find.byKey(const Key('settings.timezone.option.America/Buenos_Aires')),
          findsOneWidget,
        );
        expect(find.text('ACTUAL'), findsOneWidget);
        await t.tap(find.byKey(const Key('settings.timezone.option.America/Buenos_Aires')));
        await t.pumpAndSettle();
        expect(env.server.patches, isEmpty, reason: 'it is the zone in use');
      },
    );

    testPage(
      'a profile on IANA\'s spelling (the welcome saved the phone\'s) is "Actual" on the web\'s',
      (t) async {
        final env = await _pump(t, zone: 'Asia/Kolkata', deviceZone: 'Asia/Calcutta');
        await _openZones(t);
        expect(find.byKey(const Key('settings.timezone.useDevice')), findsNothing);
        await _search(t, 'calcutta');
        expect(find.text('ACTUAL'), findsOneWidget);
        expect(env.server.patches, isEmpty);
      },
    );

    testPage('the phone\'s zone is offered, and saved, in the web\'s spelling', (t) async {
      final env = await _pump(t, deviceZone: 'Asia/Kolkata');
      await _openZones(t);
      expect(find.text('USAR LA DE ESTE DISPOSITIVO: CALCUTTA'), findsOneWidget);
      await t.tap(find.byKey(const Key('settings.timezone.useDevice')));
      await t.pumpAndSettle();
      expect(env.server.patches, [
        {'timezone': 'Asia/Calcutta'},
      ]);
      await t.pump(const Duration(seconds: 10));
    });

    testPage('does not offer the phone\'s zone when it is the one in use', (t) async {
      await _pump(t);
      await _openZones(t);
      expect(find.byKey(const Key('settings.timezone.useDevice')), findsNothing);
    });

    testPage('a failed save says why and keeps the sheet and the zone', (t) async {
      final env = await _pump(t);
      env.server.failure = const HomeFailure(503, code: 'internal_error');
      await _openZones(t);
      await _search(t, 'madrid');
      await t.tap(find.byKey(const Key('settings.timezone.option.Europe/Madrid')));
      await t.pumpAndSettle();
      expect(
        find.text('Tuvimos un problema de nuestro lado. Inténtalo de nuevo en un momento.'),
        findsOneWidget,
      );
      expect(find.text('Elige tu zona horaria'), findsOneWidget, reason: 'for another try');
      expect(env.home.timezone, 'America/Bogota');
      // And it can be tried again.
      await t.pump(const Duration(seconds: 10));
      await t.tap(find.byKey(const Key('settings.timezone.option.Europe/Madrid')));
      await t.pumpAndSettle();
      expect(env.home.timezone, 'Europe/Madrid');
      await t.pump(const Duration(seconds: 10));
    });

    testPage('a second tap while one is saving is ignored', (t) async {
      final env = await _pump(t);
      final gate = Completer<void>();
      env.server.onPatch = () => gate.future;
      await _openZones(t);
      await _search(t, 'madrid');
      await t.tap(find.byKey(const Key('settings.timezone.option.Europe/Madrid')));
      await t.pump();
      await t.tap(find.byKey(const Key('settings.timezone.option.Europe/Madrid')));
      await t.pump();
      gate.complete();
      await t.pumpAndSettle();
      expect(env.server.patches, hasLength(1));
      await t.pump(const Duration(seconds: 10));
    });

    testPage('an answer lost on the way still shows what the server did', (t) async {
      final env = await _pump(t);
      env.server.lostAnswer = const HomeFailure(0);
      await _openZones(t);
      await _search(t, 'madrid');
      await t.tap(find.byKey(const Key('settings.timezone.option.Europe/Madrid')));
      await t.pumpAndSettle();
      expect(find.text('Sin conexión. Revisa tu internet e inténtalo de nuevo.'), findsOneWidget);
      await t.pump(const Duration(seconds: 10));
      // The server did save it: the card and home read it again instead of keeping the old one.
      expect(env.homeState.data?.timezone, 'Europe/Madrid');
    });

    testPage('"today" moves everywhere: home, the widget\'s snapshot and the notices', (t) async {
      final env = await _pump(
        t,
        rules: [rule('rent', 'cat-groceries', name: 'Arriendo', amount: -50000000)],
      );
      // Before: the 21st in Bogota, the notice scheduled for Bogota's 9:00.
      expect(env.homeState.data!.todayAt(_now), '2026-10-21');
      expect(env.platform.callsNamed('scheduleDue').last, 'scheduleDue America/Bogota es');
      env.platform.clear();
      final before = env.snapshots.length;

      await _openZones(t);
      await _search(t, 'madrid');
      await t.tap(find.byKey(const Key('settings.timezone.option.Europe/Madrid')));
      await t.pumpAndSettle();
      await env.settings.container.read(noticeSyncProvider).idle;
      await t.pumpAndSettle();

      // Home reads "today" in the new zone: the 22nd.
      expect(env.homeState.data!.timezone, 'Europe/Madrid');
      expect(env.homeState.data!.todayAt(_now), '2026-10-22');
      // The widget's snapshot carries the new zone (it reads "this month" and midnight in it).
      expect(env.snapshots, hasLength(greaterThan(before)));
      expect(env.snapshots.last.timezone, 'Europe/Madrid');
      // The 9:00 notice is scheduled again, in the new zone.
      expect(env.platform.callsNamed('scheduleDue'), ['scheduleDue Europe/Madrid es']);
      await t.pump(const Duration(seconds: 10));
    });
  });

  group('the currency', () {
    testPage('an empty account can choose: one option for each, with an example amount', (t) async {
      await _pump(t);
      await _openCurrency(t);
      expect(said('Moneda'), findsWidgets);
      expect(said('Puedes cambiarla hasta tu primer movimiento.'), findsOneWidget);
      expect(find.text('Peso colombiano'), findsOneWidget);
      expect(find.text(r'$50.000 (50 lukas)'), findsOneWidget);
      expect(find.text('Dólar estadounidense'), findsOneWidget);
      expect(find.byKey(const Key('settings.currency.EUR')), findsOneWidget);
      expect(
        t.getSemantics(find.bySemanticsLabel('Peso colombiano \$50.000 (50 lukas) COP')),
        matchesSemantics(
          label: 'Peso colombiano \$50.000 (50 lukas) COP',
          hasCheckedState: true,
          isChecked: true,
          hasEnabledState: true,
          isEnabled: true,
          isFocusable: true,
          hasTapAction: true,
          hasFocusAction: true,
        ),
      );
    });

    testPage('choosing one saves it, and everything reads the new currency', (t) async {
      final env = await _pump(t);
      await _openCurrency(t);
      await t.tap(find.byKey(const Key('settings.currency.USD')));
      await t.pumpAndSettle();
      expect(env.server.patches, [
        {'currency': 'USD'},
      ]);
      expect(find.text('Listo: tu moneda ahora es USD.'), findsOneWidget);
      expect(env.homeState.data!.currency, 'USD');
      expect(env.snapshots.last.currency, 'USD');
      await t.pump(const Duration(seconds: 10));
    });

    testPage('choosing the one in use does nothing', (t) async {
      final env = await _pump(t);
      await _openCurrency(t);
      await t.tap(find.byKey(const Key('settings.currency.COP')));
      await t.pumpAndSettle();
      expect(env.server.patches, isEmpty);
    });

    const locked = 'Tu moneda es COP. Ya tienes movimientos o recurrentes, así que se queda así.';

    testPage('after the first movement it is refused, in the web\'s words', (t) async {
      final env = await _pump(t, movements: true);
      await _openCurrency(t);
      expect(said(locked), findsOneWidget);
      expect(find.byKey(const Key('settings.currency.USD')), findsNothing);
      expect(env.server.patches, isEmpty);
    });

    testPage('a recurring payment locks it too', (t) async {
      await _pump(t, rules: [rule('rent', 'cat-groceries')]);
      await _openCurrency(t);
      expect(said(locked), findsOneWidget);
      expect(find.byKey(const Key('settings.currency.USD')), findsNothing);
    });

    testPage('the server has the last word: a 409 turns the choice into the same line', (t) async {
      final env = await _pump(t);
      env.server.lockedByServer = true;
      await _openCurrency(t);
      await t.tap(find.byKey(const Key('settings.currency.USD')));
      await t.pumpAndSettle();
      expect(said(locked), findsOneWidget);
      expect(find.byKey(const Key('settings.currency.USD')), findsNothing);
      expect(env.server.patches, hasLength(1));
      expect(find.text('Listo: tu moneda ahora es USD.'), findsNothing);
      expect(env.home.currency, 'COP');
    });

    testPage('any other failure is said in a toast and the choice stays', (t) async {
      final env = await _pump(t);
      env.server.failure = const HomeFailure(503, code: 'internal_error');
      await _openCurrency(t);
      await t.tap(find.byKey(const Key('settings.currency.USD')));
      await t.pumpAndSettle();
      expect(
        find.text('Tuvimos un problema de nuestro lado. Inténtalo de nuevo en un momento.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('settings.currency.USD')), findsOneWidget);
      await t.pump(const Duration(seconds: 10));
    });

    testPage('a currency the app does not offer is not changed from here', (t) async {
      await _pump(t, currency: 'MXN');
      await _openCurrency(t);
      expect(
        said('Tu moneda es MXN. Ya tienes movimientos o recurrentes, así que se queda así.'),
        findsOneWidget,
      );
    });

    testPage('where the lists cannot be read the options still show, for the server to decide', (
      t,
    ) async {
      final env = await _pump(t);
      env.home.failures['hasTransactions'] = const HomeFailure(0);
      env.recurring.failures['list'] = const HomeFailure(0);
      // Open Settings again so it asks again.
      env.settings.container.read(routerProvider).go('/');
      await t.pumpAndSettle();
      env.settings.container.read(routerProvider).go('/settings/preferences');
      await t.pumpAndSettle();
      await _openCurrency(t);
      expect(find.byKey(const Key('settings.currency.USD')), findsOneWidget);
    });

    testPage('in English, with the web\'s English words', (t) async {
      await _pump(t, locale: const Locale('en'));
      await _openCurrency(t);
      expect(said('Time and currency'), findsWidgets);
      expect(find.text('Colombian Peso'), findsOneWidget);
      expect(find.text('COP\u00a050,000 (50k)'), findsOneWidget);
      expect(said('You can change it until your first transaction.'), findsOneWidget);
    });
  });
}
