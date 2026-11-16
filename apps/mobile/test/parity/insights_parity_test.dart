@Tags(['golden'])
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/api/gen/wambito_api.dart';
import 'package:wambito/insights/insights_controller.dart';
import 'package:wambito/insights/insights_repository.dart';
import 'package:wambito/insights/insights_screen.dart';
import 'package:wambito/ui/app_shell.dart';
import 'package:wambito/ui/segmented_control.dart';

import '../support/parity.dart';
import '../support/parity_home.dart';

import 'package:wambito/ui/lk_icons.dart';

import '../support/icons.dart';

/// Análisis against the stories that show it, `insights-insights--*`
/// (apps/web/app/features/insights/Insights.stories.tsx), each as Storybook shows it after its
/// `play` function.
///
/// The app reads what the story's fake API answered (test/parity/fixtures): the profile, the
/// summary, the categories and the reports the page asked for. The page is as long as its three
/// cards (the web's page, and its background gradient with it), and the pictures show the top
/// 915px of it; the stories that look at a card below the fold scroll the page to it
/// (`TrendScrolled`, `TrendYearScrolled`, `TrendGapsScrolled`, `CostOfLivingScrolled`): the frame
/// moves the screen up by as much, which is what a scrolled page looks like with the bottom bar
/// fixed over it.
///
/// Update the goldens with `flutter test --update-goldens test/parity`, then compare with
/// `dart run tool/parity/compose.dart` (docs/mobile/parity.md).

/// The story's reports, as the fake API answered them.
class _FixtureInsights implements InsightsRepository {
  _FixtureInsights(this.fixture);

  final ParityFixture fixture;

  @override
  Future<CategoryReport> byCategory({
    required String from,
    required String to,
    required String kind,
    String? status,
  }) async {
    final query = 'from=$from&kind=$kind${status == null ? '' : '&status=$status'}&to=$to';
    return readBuilt(
      CategoryReport.serializer,
      fixtureJson(fixture, '/v1/reports/by-category?$query'),
    );
  }

  @override
  Future<TrendReport> trend({required String from, required String to}) async => readBuilt(
    TrendReport.serializer,
    fixtureJson(fixture, '/v1/reports/trend?from=$from&to=$to'),
  );

  @override
  Future<CostOfLivingReport> costOfLiving(int months) async => readBuilt(
    CostOfLivingReport.serializer,
    fixtureJson(fixture, '/v1/reports/cost-of-living?months=$months'),
  );
}

/// Análisis in the story's frame: Storybook's 16px of padding, the bar under it, no 🎤. The page is
/// the app's own: as long as its content, its gradient with it.
Widget _screen() =>
    ShellFrame(padding: const EdgeInsets.all(16), showMic: false, child: const InsightsScreen());

/// Scrolls the app's page to [offset], as the story's `window.scrollTo` does the web's (or as far as
/// the page goes).
void _scrollTo(WidgetTester t, double offset) {
  final position = t.state<ScrollableState>(find.byType(Scrollable).first).position;
  position.jumpTo(math.min(offset, position.maxScrollExtent));
}

/// A click in Chrome puts the focus on what it clicked, which rings it; a tap does not in Flutter.
/// A key puts the app in keyboard mode, where the focused control draws its ring.
Future<void> _keyboardMode(WidgetTester t) => t.sendKeyEvent(LogicalKeyboardKey.shift);

/// A click focuses a button in Chrome; a tap does not in Flutter: focus the control [inside] is in.
void _focus(WidgetTester t, Finder inside) => Focus.of(t.element(inside)).requestFocus();

/// The option [label] of the control that holds [T] values (the first of several with that text).
Finder _option<T>(String label) =>
    find.descendant(of: find.byType(SegmentedControl<T>), matching: find.text(label));

/// [act] does what the story's `play` function does, with the page at the top (the controls it
/// clicks are there); [scrolled] is how far the story then scrolls the page.
Future<void> _pair(
  WidgetTester t, {
  required String id,
  required String story,
  required String theme,
  double scrolled = 0,
  Locale locale = const Locale('es'),
  Future<void> Function(WidgetTester t)? act,
}) async {
  final fixture = ParityFixtures.load(story);
  await parityGolden(
    t,
    id,
    _screen(),
    theme: theme,
    locale: locale,
    overrides: [
      ...parityHomeOverrides(FixtureHomeRepository(fixture)),
      insightsRepositoryProvider.overrideWithValue(_FixtureInsights(fixture)),
    ],
    act: (t) async {
      await precacheWambi(t);
      await act?.call(t);
      if (scrolled > 0) {
        _scrollTo(t, scrolled);
        await t.pumpAndSettle();
      }
      // A key puts the app in keyboard mode, where the focused control draws its ring.
      if (act != null) await _keyboardMode(t);
    },
  );
}

void main() {
  for (final theme in ['night', 'day']) {
    testWidgets('insights parity: this month\'s spending by category ($theme)', (t) async {
      await _pair(
        t,
        id: 'insights-donut',
        story: 'insights-insights--donut-by-category',
        theme: theme,
      );
    });

    testWidgets('insights parity: income, Ingresos clicked ($theme)', (t) async {
      await _pair(
        t,
        id: 'insights-income',
        story: 'insights-insights--donut-income',
        theme: theme,
        act: (t) async {
          await t.tap(_option<InsightsKind>('Ingresos'));
          await t.pumpAndSettle();
        },
      );
    });

    testWidgets('insights parity: paid spending, Pendientes then Pagados clicked ($theme)', (
      t,
    ) async {
      await _pair(
        t,
        id: 'insights-pending',
        story: 'insights-insights--donut-pending',
        theme: theme,
        act: (t) async {
          await t.tap(_option<InsightsStatus>('Pendientes'));
          await t.pumpAndSettle();
          await t.tap(_option<InsightsStatus>('Pagados'));
          await t.pumpAndSettle();
        },
      );
    });

    testWidgets('insights parity: three months, then a month back ($theme)', (t) async {
      await _pair(
        t,
        id: 'insights-range',
        story: 'insights-insights--donut-range',
        theme: theme,
        act: (t) async {
          await t.tap(_option<int>('3 meses'));
          await t.pumpAndSettle();
          await t.tap(find.bySemanticsLabel('Mes anterior'));
          await t.pumpAndSettle();
          _focus(t, findIcon(LkIconName.chevronLeft).first);
        },
      );
    });

    testWidgets('insights parity: the trend over six months ($theme)', (t) async {
      await _pair(
        t,
        id: 'insights-trend',
        story: 'insights-insights--trend-scrolled',
        theme: theme,
        scrolled: 1027,
        act: (t) async {
          await t.tap(_option<int>('6 meses'));
          await t.pumpAndSettle();
        },
      );
    });

    testWidgets('insights parity: the trend over a year ($theme)', (t) async {
      await _pair(
        t,
        id: 'insights-trend-year',
        story: 'insights-insights--trend-year-scrolled',
        theme: theme,
        scrolled: 1027,
        act: (t) async {
          await t.tap(_option<int>('1 año'));
          await t.pumpAndSettle();
        },
      );
    });

    testWidgets('insights parity: the trend with gaps in the budget, an older month ($theme)', (
      t,
    ) async {
      await _pair(
        t,
        id: 'insights-trend-gaps',
        story: 'insights-insights--trend-gaps-scrolled',
        theme: theme,
        scrolled: 1027,
        act: (t) async {
          await t.tap(_option<int>('6 meses'));
          await t.pumpAndSettle();
          // The arrows of the trend are below the fold: the story clicks them from script.
          _scrollTo(t, 1027);
          await t.pumpAndSettle();
          for (var i = 0; i < 3; i++) {
            await t.tap(find.bySemanticsLabel('Ver el mes anterior en el gráfico'));
            await t.pumpAndSettle();
          }
          _focus(t, findIcon(LkIconName.chevronLeft).last);
        },
      );
    });

    testWidgets('insights parity: what living costs ($theme)', (t) async {
      await _pair(
        t,
        id: 'insights-living',
        story: 'insights-insights--cost-of-living-scrolled',
        theme: theme,
        scrolled: 1249,
      );
    });

    testWidgets('insights parity: nothing logged yet ($theme)', (t) async {
      await _pair(t, id: 'insights-empty', story: 'insights-insights--empty', theme: theme);
    });

    testWidgets('insights parity: in English ($theme)', (t) async {
      await _pair(
        t,
        id: 'insights-english',
        story: 'insights-insights--english',
        theme: theme,
        locale: const Locale('en'),
      );
    });
  }
}
