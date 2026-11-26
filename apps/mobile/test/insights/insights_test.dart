import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/feedback/feedback.dart';
import 'package:wambito/home/home_controller.dart';
import 'package:wambito/home/home_repository.dart';
import 'package:wambito/home/home_screen.dart';
import 'package:wambito/insights/chart_geometry.dart';
import 'package:wambito/insights/charts.dart';
import 'package:wambito/insights/insights_controller.dart';
import 'package:wambito/insights/insights_repository.dart';
import 'package:wambito/insights/insights_screen.dart';
import 'package:wambito/theme/theme.dart';
import 'package:wambito/ui/month_picker.dart';
import 'package:wambito/ui/segmented_control.dart';

import '../feedback/fakes.dart';
import '../home/fakes.dart';
import '../home/fixtures.dart';
import '../home/home_harness.dart' show testNow;
import '../settings/harness.dart';
import '../support/page_gradient.dart';
import 'fakes.dart';
import '../support/amounts.dart';

/// Análisis in the whole app (the real router, home under it) against fakes of the server. How it
/// looks is the parity pairs' business (test/parity/insights_parity_test.dart) and the charts'
/// geometry is test/insights/chart_geometry_test.dart's; here is what it does.

class Env {
  Env(this.settings, this.home, this.reports);

  final SettingsEnv settings;
  final FakeHomeRepository home;
  final FakeInsightsRepository reports;
}

Future<Env> pumpInsights(
  WidgetTester tester, {
  FakeHomeRepository? home,
  FakeInsightsRepository? reports,
  Locale locale = const Locale('es'),
  String? location,
  List<Override> overrides = const [],
  Size? size,
  bool reduceMotion = false,
}) async {
  final server = home ?? insightsHome();
  final fake = reports ?? insightsFor(server);
  if (reduceMotion) {
    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
      disableAnimations: true,
    );
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  }
  final settings = await pumpSettingsApp(
    tester,
    homeRepo: server,
    locale: locale,
    location: location,
    overrides: [
      insightsRepositoryProvider.overrideWithValue(fake),
      clockProvider.overrideWithValue(() => testNow),
      wambiVariantProvider.overrideWithValue(() => 1),
      ...overrides,
    ],
  );
  if (size != null) {
    tester.view.physicalSize = size;
    await tester.pumpAndSettle();
  }
  return Env(settings, server, fake);
}

/// A widget test with semantics on: figures are found by what a screen reader hears.
void testInsights(String description, Future<void> Function(WidgetTester tester) body) {
  testWidgets(description, (tester) async {
    final handle = tester.ensureSemantics();
    try {
      await body(tester);
    } finally {
      handle.dispose();
    }
  });
}

Future<void> openInsights(WidgetTester tester) async {
  await tester.tap(find.text('Análisis'));
  await tester.pumpAndSettle();
}

/// The option [label] of the control that holds [T] values.
Finder option<T>(String label) =>
    find.descendant(of: find.byType(SegmentedControl<T>), matching: find.text(label));

/// The month the picker says.
Finder pickerMonth(String name) =>
    find.descendant(of: find.byType(MonthPicker), matching: find.text(name));

/// The text of the donut's card, as one reading for a screen reader.
Finder summary(Pattern start) => find.bySemanticsLabel(RegExp(start.toString()));

void main() {
  group('opening Análisis', () {
    testInsights('the bottom bar opens it on the month home is on, and the back button returns', (
      tester,
    ) async {
      final env = await pumpInsights(tester);
      // Home is on September.
      await tester.tap(find.bySemanticsLabel('Mes anterior'));
      await tester.pumpAndSettle();
      await openInsights(tester);

      expect(pickerMonth('Septiembre'), findsOneWidget, reason: 'the month picker is September');
      expect(find.text('En septiembre'), findsWidgets);
      expect(env.reports.calls.first, 'byCategory 2026-09 2026-09 expense -');
      expect(env.settings.router.canPop(), isTrue, reason: 'home is under it');
      env.settings.router.pop();
      await tester.pumpAndSettle();
      expect(pickerMonth('Septiembre'), findsOneWidget);
      expect(find.byType(InsightsScreen), findsNothing);
    });

    testInsights('shows the same figures as the web: the heading, Wambi and the three cards', (
      tester,
    ) async {
      await pumpInsights(tester, location: '/insights');

      expect(find.text('Análisis'), findsWidgets);
      expect(pickerMonth('Octubre'), findsOneWidget);
      for (final title in ['Por categoría', 'Mes a mes', '¿Cuánto me cuesta vivir?']) {
        expect(find.text(title), findsOneWidget, reason: title);
      }
      expect(
        find.textContaining('Hogar fue lo que más lukas se llevó en octubre: \$'),
        findsOneWidget,
      );
      // The donut's figures for a screen reader: the web's table, as one reading.
      expect(summary('Gastos por categoría en octubre'), findsOneWidget);
      // The donut's total, in its hole: 600.000 + 180.000 + 30.000 pesos.
      expect(find.text('GASTADO'), findsOneWidget);
      // What living costs: August and September are complete, so two months are averaged.
      expect(find.textContaining('tus últimos 2 meses completos'), findsOneWidget);
      expect(find.text('Fijos'), findsOneWidget);
      expect(find.text('Variables'), findsOneWidget);
    });

    testInsights('a link can carry the month, never one after the current month', (tester) async {
      final env = await pumpInsights(tester, location: '/insights?month=2026-08');
      expect(pickerMonth('Agosto'), findsOneWidget);
      expect(env.reports.calls.first, 'byCategory 2026-08 2026-08 expense -');

      env.settings.router.go('/insights?month=2030-01');
      await tester.pumpAndSettle();
      expect(pickerMonth('Octubre'), findsOneWidget);
    });

    testInsights('in English it says the same in English, in the web\'s words', (tester) async {
      await pumpInsights(tester, locale: const Locale('en'), location: '/insights');
      expect(find.text('Insights'), findsWidgets);
      expect(find.text('By category'), findsOneWidget);
      expect(find.text('Month by month'), findsOneWidget);
      expect(find.text('How much does it cost me to live?'), findsOneWidget);
      expect(find.text('SPENT'), findsOneWidget);
      expect(find.textContaining('took the biggest bite in October'), findsOneWidget);
      expect(find.textContaining('your last 2 complete months'), findsOneWidget);
    });

    testInsights('the bottom bar marks Análisis as the current section', (tester) async {
      await pumpInsights(tester, location: '/insights');
      expect(
        tester.getSemantics(find.text('Análisis').last).flagsCollection.isSelected.name,
        'isTrue',
      );
    });
  });

  group('the charts turn like a wheel', () {
    Future<(Env, FakeFeedbackPlatform)> pumpFelt(WidgetTester tester, {bool reduce = false}) async {
      final platform = FakeFeedbackPlatform();
      final env = await pumpInsights(
        tester,
        location: '/insights',
        reduceMotion: reduce,
        overrides: [feedbackPlatformProvider.overrideWithValue(platform)],
      );
      return (env, platform);
    }

    List<HapticPattern> spins(FakeFeedbackPlatform platform) => [
      for (final p in platform.haptics)
        if (identical(p, hapticPatterns[FeedbackEvent.wheelSpun])) p,
    ];

    testInsights(
      'opening Análisis spins the wheel once, though the donut and the trend both move',
      (tester) async {
        final (_, platform) = await pumpFelt(tester);
        expect(spins(platform), hasLength(1));
      },
    );

    testInsights('each new span spins it again, once', (tester) async {
      final (_, platform) = await pumpFelt(tester);
      for (final span in ['3 meses', '6 meses', '1 mes']) {
        platform.haptics.clear();
        await tester.tap(option<int>(span));
        await tester.pumpAndSettle();
        expect(spins(platform), hasLength(1), reason: span);
      }
    });

    testInsights('the same span again moves nothing, and spins nothing', (tester) async {
      final (_, platform) = await pumpFelt(tester);
      platform.haptics.clear();
      await tester.tap(option<int>('1 mes'));
      await tester.pumpAndSettle();
      expect(spins(platform), isEmpty);
    });

    testInsights('with reduced motion the charts do not sweep, so nothing spins', (tester) async {
      final (_, platform) = await pumpFelt(tester, reduce: true);
      await tester.tap(option<int>('3 meses'));
      await tester.pumpAndSettle();
      expect(spins(platform), isEmpty);
    });
  });

  group('choosing what to see', () {
    testInsights('a span asks for that many months and the labels follow', (tester) async {
      final env = await pumpInsights(tester, location: '/insights');
      env.reports.calls.clear();

      await tester.tap(option<int>('3 meses'));
      await tester.pumpAndSettle();

      expect(env.reports.calls, contains('byCategory 2026-08 2026-10 expense -'));
      expect(env.reports.calls, contains('trend 2026-08 2026-10'));
      expect(find.text('De agosto a octubre'), findsWidgets);
      expect(find.textContaining('en qué'), findsNothing);
      expect(
        find.textContaining('Hogar fue lo que más lukas se llevó de agosto a octubre'),
        findsOneWidget,
      );
    });

    testInsights('Ingresos shows where the money came from, and Pendientes what is still to pay', (
      tester,
    ) async {
      final env = await pumpInsights(tester, location: '/insights');
      await tester.tap(option<InsightsKind>('Ingresos'));
      await tester.pumpAndSettle();
      expect(summary('Ingresos por categoría en octubre'), findsOneWidget);
      expect(find.text('RECIBIDO'), findsOneWidget);
      expect(find.text('Nómina'), findsOneWidget);
      // Wambi still talks about the spending.
      expect(find.textContaining('Hogar fue lo que más lukas'), findsOneWidget);

      await tester.tap(option<InsightsKind>('Gastos'));
      await tester.pumpAndSettle();
      await tester.tap(option<InsightsStatus>('Pendientes'));
      await tester.pumpAndSettle();
      expect(summary('Gastos pendientes por categoría en octubre'), findsOneWidget);
      expect(find.text('Ocio'), findsOneWidget, reason: 'this month\'s Spotify is pending');
      expect(env.reports.calls.last, 'byCategory 2026-10 2026-10 expense pending');
    });

    testInsights('the month picker moves the period, and stops at the current month', (
      tester,
    ) async {
      await pumpInsights(tester, location: '/insights');
      expect(
        tester.getSemantics(find.bySemanticsLabel('Mes siguiente')).flagsCollection.isEnabled.name,
        'isFalse',
      );
      await tester.tap(find.bySemanticsLabel('Mes anterior'));
      await tester.pumpAndSettle();
      expect(pickerMonth('Septiembre'), findsOneWidget);
      expect(find.text('En septiembre'), findsWidgets);
      expect(
        tester.getSemantics(find.bySemanticsLabel('Mes siguiente')).flagsCollection.isEnabled.name,
        'isTrue',
      );
    });

    testInsights('the trend: tapping a month selects it, and the arrows step through', (
      tester,
    ) async {
      await pumpInsights(tester, location: '/insights', size: const Size(390, 2400));
      await tester.tap(option<int>('3 meses'));
      await tester.pumpAndSettle();
      final readout = find.bySemanticsLabel(RegExp(r'Octubre\. Ingresos'));
      expect(readout, findsOneWidget);
      expect(
        tester
            .getSemantics(find.bySemanticsLabel('Ver el mes siguiente en el gráfico'))
            .flagsCollection
            .isEnabled
            .name,
        'isFalse',
        reason: 'the latest month is selected',
      );

      await tester.tap(find.bySemanticsLabel('Ver el mes anterior en el gráfico'));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel(RegExp(r'Septiembre\. Ingresos')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(r'Presupuesto \$900\.000')), findsOneWidget);

      // A tap on a month's column of the chart selects it.
      await tester.tap(find.byKey(const ValueKey('trend.hit.2026-08')));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel(RegExp(r'Agosto\. Ingresos')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(r'Presupuesto Sin presupuesto')), findsOneWidget);
    });
  });

  group('a month without data, and not enough history', () {
    testInsights('says so in words in every card, and Wambi says what will show up', (
      tester,
    ) async {
      await pumpInsights(
        tester,
        home: FakeHomeRepository(timezone: 'America/Bogota', categoryList: [category('c', 'Casa')]),
        location: '/insights',
      );
      expect(find.text('No hay gastos en octubre.'), findsOneWidget);
      expect(find.text('Aún no hay movimientos en octubre.'), findsOneWidget);
      expect(find.textContaining('Necesito al menos un mes completo con gastos'), findsOneWidget);
      expect(find.textContaining('No veo gastos en octubre.'), findsOneWidget);
    });
  });

  group('when a report cannot load', () {
    testInsights('the web\'s error screen, offline, with Reintentar that tries again', (
      tester,
    ) async {
      final server = insightsHome();
      final reports = insightsFor(server)..failures['byCategory'] = const HomeFailure(0);
      await pumpInsights(tester, home: server, reports: reports, location: '/insights');

      expect(find.text('Sin conexión. Revisa tu internet e inténtalo de nuevo.'), findsOneWidget);
      expect(find.text('REINTENTAR'), findsOneWidget);
      expect(find.text('Por categoría'), findsNothing);

      await tester.tap(find.text('REINTENTAR'));
      await tester.pumpAndSettle();
      expect(find.text('Por categoría'), findsOneWidget);
      expect(find.text('REINTENTAR'), findsNothing);
    });

    testInsights('a server error is said as one, not as being offline', (tester) async {
      final server = insightsHome();
      final reports = insightsFor(server)..failures['trend'] = const HomeFailure(500);
      await pumpInsights(tester, home: server, reports: reports, location: '/insights');
      expect(find.text('Algo salió mal. Inténtalo de nuevo en un momento.'), findsOneWidget);
      expect(find.text('REINTENTAR'), findsOneWidget);
    });

    testInsights('another month offline keeps the last figures, as what they are, and says so', (
      tester,
    ) async {
      final server = insightsHome();
      final reports = insightsFor(server);
      await pumpInsights(tester, home: server, reports: reports, location: '/insights');
      reports.failures['byCategory'] = const HomeFailure(0);

      await tester.tap(find.bySemanticsLabel('Mes anterior'));
      await tester.pumpAndSettle();

      // September in the picker; October's figures under it, saying they are October's.
      expect(pickerMonth('Septiembre'), findsOneWidget);
      expect(find.text('En octubre'), findsWidgets);
      expect(find.text('Sin conexión. Te mostramos lo último que cargó.'), findsOneWidget);
      expect(find.text('Por categoría'), findsOneWidget);
      // Reintentar asks again, and September's figures come.
      await tester.tap(find.text('REINTENTAR'));
      await tester.pumpAndSettle();
      expect(find.text('En septiembre'), findsWidgets);
      expect(find.text('Sin conexión. Te mostramos lo último que cargó.'), findsNothing);
    });

    testInsights('a refresh that fails with the network up says the figures may be old', (
      tester,
    ) async {
      final server = insightsHome();
      final reports = insightsFor(server);
      final env = await pumpInsights(tester, home: server, reports: reports, location: '/insights');
      reports.failures['byCategory'] = const HomeFailure(503);

      await env.settings.container.read(insightsProvider.notifier).refresh();
      await tester.pumpAndSettle();
      expect(find.textContaining('No pudimos actualizar'), findsOneWidget);
      expect(find.text('Por categoría'), findsOneWidget);
    });
  });

  group('what changes the figures from elsewhere', () {
    testInsights('a movement saved meanwhile (the ＋) shows in the charts', (tester) async {
      final env = await pumpInsights(tester, location: '/insights');
      expect(find.textContaining('Hogar fue lo que más lukas'), findsOneWidget);

      // A big Ocio expense, saved from the add sheet: it is what took the biggest bite now.
      final added = tx('big', '2026-10-22', -900000000, name: 'Viaje', categoryId: 'cat-fun');
      env.home.items.add(added);
      await env.settings.container.read(homeProvider.notifier).saved(added);
      await tester.pumpAndSettle();
      // Wambi talks about it for ten seconds; then he is quiet.
      await tester.pump(const Duration(seconds: 11));

      expect(find.textContaining('Ocio fue lo que más lukas se llevó en octubre'), findsOneWidget);
    });
  });

  group('long names and big amounts', () {
    testInsights('a 40-character category and \$1.500.000.000 truncate or fit, without overflow', (
      tester,
    ) async {
      const name = 'Una categoría con un nombre de cuarenta ch';
      expect(name.length, 42);
      final server = FakeHomeRepository(
        categoryList: [category('cat-long', name, icon: '🛒')],
        items: [
          tx('a', '2026-10-05', -150000000000, name: 'Compra', categoryId: 'cat-long'),
          tx('b', '2026-09-05', -150000000000, name: 'Compra', categoryId: 'cat-long'),
        ],
      );
      final reports = FakeInsightsRepository(server, budgets: {'2026-10': 150000000000});
      await pumpInsights(
        tester,
        home: server,
        reports: reports,
        location: '/insights',
        size: const Size(360, 640),
      );
      expect(tester.takeException(), isNull);
      // The name is cut with an ellipsis where the amount takes its room; the amount is whole.
      expect(find.text(name), findsWidgets);
      final nameText = tester.widgetList<Text>(find.text(name)).first;
      expect(nameText.overflow, TextOverflow.ellipsis);
      expect(find.text('\$1.500.000.000'), findsWidgets);
      await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -3000));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testInsights('at 130 % of the phone\'s text size nothing overflows or is clipped', (
      tester,
    ) async {
      await pumpInsights(tester, location: '/insights');
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -1500));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -3000));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('the page background', () {
    testInsights('the glow scrolls away with the content, as the web\'s page does', (tester) async {
      await pumpInsights(tester, location: '/insights');
      final screen = screenOf(tester);
      final start = pageGradient(tester);
      expect(start.top, 0);
      expect(start.width, screen.width);
      expect(start.height, greaterThan(screen.height * 2), reason: 'as tall as the page');

      // Scrolls the page by 600px (a drag spends 20px of it on the touch slop).
      tester.state<ScrollableState>(find.byType(Scrollable).first).position.jumpTo(600);
      await tester.pumpAndSettle();
      final scrolled = pageGradient(tester);
      expect(scrolled.top, -600, reason: 'the glow moved up by what the content did');
      expect(scrolled.height, start.height);
      // The page's colour is all that is left under the top of the screen: the glow is above it.
      expect(scrolled.bottom, greaterThan(screen.height));
    });

    testInsights('a page shorter than the screen is still a screen tall, as min-h-dvh makes it', (
      tester,
    ) async {
      await pumpInsights(tester, location: '/insights', size: const Size(390, 2800));
      expect(pageGradient(tester), Offset.zero & const Size(390, 2800));
    });
  });

  group('reduced motion', () {
    /// A picture of [finder]'s painting now.
    Future<Uint8List> picture(WidgetTester tester, Finder finder) async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(finder);
      final bytes = await tester.runAsync(() async {
        final image = await boundary.toImage();
        return (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      });
      return bytes!.buffer.asUint8List();
    }

    Widget app(Widget child, {bool reduce = false}) => MaterialApp(
      theme: nightTheme,
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduce),
        child: Center(
          child: RepaintBoundary(key: const Key('chart'), child: child),
        ),
      ),
    );

    const slices = [
      DonutSlice(id: 'a', value: 70, fill: Color(0xFFFF0000)),
      DonutSlice(id: 'b', value: 30, fill: Color(0xFF0000FF)),
    ];

    testWidgets('the donut sweeps in over --hop, and with reduced motion is whole at once', (
      tester,
    ) async {
      Widget donut(bool animate) => DonutChart(
        slices: slices,
        size: 200,
        animate: animate,
        duration: const Duration(milliseconds: 520),
      );
      await tester.pumpWidget(app(donut(true)));
      final first = await picture(tester, find.byKey(const Key('chart')));
      await tester.pump(const Duration(milliseconds: 260));
      final half = await picture(tester, find.byKey(const Key('chart')));
      await tester.pumpAndSettle();
      final end = await picture(tester, find.byKey(const Key('chart')));
      expect(first, isNot(end), reason: 'it starts empty');
      expect(half, isNot(end), reason: 'and is half drawn half-way through');
      expect(half, isNot(first));

      await tester.pumpWidget(app(donut(false), reduce: true));
      final still = await picture(tester, find.byKey(const Key('chart')));
      expect(still, end, reason: 'with reduced motion the first picture is the last');
    });

    testWidgets('the bars rise from the axis and the line is drawn; reduced, they are there', (
      tester,
    ) async {
      const points = [
        TrendPoint(month: '2026-09', label: 'sept', income: 600, expenses: 300, budget: 400),
        TrendPoint(month: '2026-10', label: 'oct', income: 500, expenses: 200, budget: 400),
      ];
      Widget bars(bool animate) => SizedBox(
        width: 324,
        height: 190,
        child: TrendBars(
          points: points,
          height: 190,
          animate: animate,
          duration: const Duration(milliseconds: 520),
          formatTick: (c) => '$c',
        ),
      );
      await tester.pumpWidget(app(bars(true)));
      final first = await picture(tester, find.byKey(const Key('chart')));
      await tester.pump(const Duration(milliseconds: 300));
      final middle = await picture(tester, find.byKey(const Key('chart')));
      await tester.pumpAndSettle();
      final end = await picture(tester, find.byKey(const Key('chart')));
      expect(first, isNot(end));
      expect(middle, isNot(end));

      await tester.pumpWidget(app(bars(false), reduce: true));
      expect(await picture(tester, find.byKey(const Key('chart'))), end);
    });

    testInsights('the cards and the legend are in their place at once', (tester) async {
      await pumpInsights(tester, location: '/insights', reduceMotion: true);
      // No entrance is running, and nothing is half faded or off its place.
      expect(tester.hasRunningAnimations, isFalse);
      final row = find.ancestor(of: find.text('Hogar'), matching: find.byType(Opacity));
      expect(row, findsWidgets);
      for (final opacity in tester.widgetList<Opacity>(row)) {
        expect(opacity.opacity, 1.0);
      }
    });
  });

  group('the axis names fit as the web measures them', () {
    testWidgets('Flutter measures the months\' names as Chrome does, within a hundredth of a px', (
      tester,
    ) async {
      // What Chrome measures Nunito 11px at the body's weight 700 to be (apps/web, Playwright).
      const chrome = {
        'ene': 18.359375,
        'feb': 16.4375,
        'mar': 19.984375,
        'abr': 16.9375,
        'may': 21.40625,
        'jun': 15.65625,
        'jul': 12.734375,
        'ago': 19.0,
        'sept': 22.109375,
        'oct': 15.78125,
        'nov': 18.46875,
        'dic': 14.609375,
      };
      for (final MapEntry(:key, :value) in chrome.entries) {
        expect(measureTickName(key), closeTo(value, 0.02), reason: key);
      }
    });
  });

  testWidgets('with home\'s eye closed, Análisis shows no amount, not even on the axis', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final env = await pumpInsights(tester);
    await closeEye(tester, env.settings.container);
    expectNoAmounts(tester);
    expect(find.textContaining(RegExp(r'\d+(,\d)?\s?(mil|M|k)\b')), findsNothing);
    semantics.dispose();
  });
}
