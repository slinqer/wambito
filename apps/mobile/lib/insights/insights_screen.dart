// The web's Insights (apps/web/app/features/insights/Insights.tsx), `/app/insights`: the month on
// screen (the person's current one first, earlier ones browsable) or a run of months ending at it;
// Wambi saying what took the biggest bite; where the money went by category; income, spending
// and budget month by month; and what living costs.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show SchedulerBinding;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../add/add_sheet.dart';
import '../capture/capture_sheet.dart';
import '../feedback/feedback.dart';
import '../home/home_controller.dart';
import '../home/home_repository.dart';
import '../home/wambi_face.dart';
import '../home/screen_error.dart';
import '../home/home_widgets.dart' show QuietSpinner;
import '../home/shell_navigation.dart';
import '../l10n/app_localizations.dart';
import '../theme/text_styles.dart';
import '../theme/tokens.g.dart';
import '../ui/app_shell.dart';
import '../ui/css_text.dart';
import '../ui/lk_theme.dart';
import '../ui/wambi_bubble.dart';
import '../ui/month_picker.dart';
import '../ui/press_button.dart';
import '../ui/segmented_control.dart';
import '../ui/swipe_row.dart' show SwipeScope;
import 'category_donut.dart';
import 'cost_of_living.dart';
import 'insights_controller.dart';
import 'insights_model.dart';
import 'parts.dart';
import 'trend_chart.dart';
import '../privacy/masked_money.dart';

/// The widest the content grows on a big screen (the web's `max-w-[480px]`, padding included).
const _maxContentWidth = 480.0;

final _monthFormat = RegExp(r'^\d{4}-(0[1-9]|1[0-2])$');

/// Análisis, as the web draws it. [initialMonth] (the route's `?month=`) is the month the period
/// ends at; null: the current one. The profile, the currency and the categories are home's: the
/// screen waits for them as the budgets' detail does.
class InsightsScreen extends ConsumerStatefulWidget {
  const InsightsScreen({super.key, this.initialMonth});

  final String? initialMonth;

  @override
  ConsumerState<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends ConsumerState<InsightsScreen> {
  /// Whether a wheel has been felt this frame: the donut and the trend that move together (a new
  /// period, a new month) turn one wheel, not two at once.
  bool _spunThisFrame = false;

  /// The charts sweep into new figures: it feels like a wheel spinning down to a stop.
  void _spin() {
    if (_spunThisFrame) return;
    _spunThisFrame = true;
    SchedulerBinding.instance.addPostFrameCallback((_) => _spunThisFrame = false);
    ref.read(feedbackProvider)(FeedbackEvent.wheelSpun);
  }

  var _started = false;

  InsightsController get _controller => ref.read(insightsProvider.notifier);

  @override
  void didUpdateWidget(InsightsScreen old) {
    super.didUpdateWidget(old);
    final month = widget.initialMonth;
    if (_started && old.initialMonth != month && month != null && _monthFormat.hasMatch(month)) {
      // Not while the tree builds: the controller changes state.
      scheduleMicrotask(() {
        if (mounted) unawaited(_controller.showMonth(month));
      });
    }
  }

  String _failureMessage(AppLocalizations l10n, HomeFailure failure) =>
      failure.offline ? l10n.errorNetwork : l10n.errorGeneric;

  /// Why what is on screen may be old: no answer at all, or a failed refresh with the network up.
  String _staleNote(AppLocalizations l10n, HomeFailure failure) =>
      failure.offline ? l10n.homeOffline : l10n.homeRefreshFailed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final home = ref.watch(homeProvider);
    final data = home.data;
    // Whatever changes the movements or the figures (a movement added from the ＋, the 🎤, an edit,
    // a Deshacer) goes through home: the charts catch up, as the web's queries do when invalidated.
    ref.listen(homeProvider.select((s) => (s.data?.summary, s.data?.items)), (previous, _) {
      if (previous != null && _started) unawaited(_controller.refresh());
    });

    if (data == null) {
      return _frame(
        context,
        home.failure != null
            ? ScreenError(
                message: _failureMessage(l10n, home.failure!),
                retryLabel: l10n.retry,
                onRetry: () => unawaited(ref.read(homeProvider.notifier).refresh()),
              )
            : const _Loading(),
      );
    }
    final today = data.todayAt(ref.read(clockProvider)());
    final current = today.substring(0, 7);
    if (!_started) {
      _started = true;
      final month = widget.initialMonth;
      // Not while the tree builds: the controller changes state.
      scheduleMicrotask(() {
        if (mounted) {
          unawaited(
            _controller.start(month != null && _monthFormat.hasMatch(month) ? month : null),
          );
        }
      });
    }
    final state = ref.watch(insightsProvider);
    final end = state.end;
    if (end == null) return _frame(context, const _Loading());

    final failure = state.failure;
    if (failure != null) {
      return _frame(
        context,
        ScreenError(
          message: _failureMessage(l10n, failure),
          retryLabel: l10n.retry,
          onRetry: () => unawaited(_controller.refresh()),
        ),
      );
    }

    final period = periodOf(end, state.span);
    final locale = l10n.localeName;
    final colors = context.lkColors;
    String money(int cents) => shownMoney(hiddenAmountsOf(context), cents, data.currency, locale);

    // Wambi speaks about the answer he has, with its own period: never a new month's name with
    // an old month's figures.
    final spending = state.spending.data;
    final spendingRange = state.spending.dataKey;
    String? line;
    if (spending != null && spendingRange is ByCategoryRange) {
      final phrase = periodPhrase(l10n, spendingRange.period, current);
      final top = spending.items.firstOrNull;
      line = top == null
          ? l10n.insightsWambiEmpty(phrase)
          : l10n.insightsWambiTop(top.name, phrase, money(top.total));
    }
    final byCategoryRange = state.byCategory.dataKey;
    final trendRange = state.trend.dataKey;
    final staleFailure = state.staleFailure;

    return _frame(
      context,
      RefreshIndicator(
        onRefresh: _controller.refresh,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final inset = math.max(
              WambitoTokens.space4,
              (constraints.maxWidth - _maxContentWidth) / 2 + WambitoTokens.space4,
            );
            // The page is a screen tall at least (`min-h-dvh`), and a pull anywhere on it refreshes.
            return SwipeScope(
              child: SizedBox(
                height: constraints.maxHeight,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  // The page is this scroll content: the shell paints its gradient over all of it.
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ShellRoom.leading(context),
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          inset + ShellRoom.sides(context).left,
                          WambitoTokens.space3,
                          inset + ShellRoom.sides(context).right,
                          ShellRoom.of(context),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          spacing: WambitoTokens.space3,
                          children: [
                            _Header(
                              title: l10n.insightsTitle,
                              picker: MonthPicker(
                                month: end,
                                max: current,
                                onChange: (month) => unawaited(_controller.showMonth(month)),
                              ),
                            ),
                            SegmentedControl<int>(
                              label: l10n.insightsPeriodLabel,
                              value: state.span,
                              options: [
                                for (final span in spans)
                                  SegmentOption(span, _spanLabel(l10n, span)),
                              ],
                              onChanged: (span) => unawaited(_controller.setSpan(span)),
                            ),
                            if (staleFailure != null)
                              Row(
                                spacing: WambitoTokens.space3,
                                children: [
                                  Expanded(
                                    child: Semantics(
                                      liveRegion: true,
                                      child: Text(
                                        _staleNote(l10n, staleFailure),
                                        style: LkText.caption.copyWith(
                                          fontWeight: FontWeight.w800,
                                          color: colors.near,
                                        ),
                                      ),
                                    ),
                                  ),
                                  PressButton.text(
                                    l10n.retry,
                                    tone: PressTone.secondary,
                                    size: PressSize.sm,
                                    onPressed: () => unawaited(_controller.refresh()),
                                  ),
                                ],
                              ),
                            InsightBody(
                              busy: state.spending.stale,
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(minHeight: 72),
                                child: line == null
                                    ? const SizedBox.shrink()
                                    : WambiBubble(message: line, mood: WambiMood.happy),
                              ),
                            ),
                            CategoryDonut(
                              report: state.byCategory.data,
                              range: byCategoryRange is ByCategoryRange ? byCategoryRange : null,
                              stale: state.byCategory.stale,
                              kind: state.kind,
                              onKind: (kind) => unawaited(_controller.setKind(kind)),
                              status: state.status,
                              onStatus: (status) => unawaited(_controller.setStatus(status)),
                              period: period,
                              current: current,
                              currency: data.currency,
                              order: 0,
                              onSpin: _spin,
                            ),
                            TrendChart(
                              report: state.trend.data,
                              range: trendRange is Period ? trendRange : null,
                              stale: state.trend.stale,
                              period: period,
                              current: current,
                              currency: data.currency,
                              order: 1,
                              onSpin: _spin,
                            ),
                            CostOfLiving(
                              report: state.living.data,
                              noHistory: state.livingMonths == 0,
                              categories: data.categories,
                              currency: data.currency,
                              order: 2,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  static String _spanLabel(AppLocalizations l10n, int span) => switch (span) {
    1 => l10n.insightsSpan1,
    3 => l10n.insightsSpan3,
    6 => l10n.insightsSpan6,
    _ => l10n.insightsSpan12,
  };

  /// The screen's frame: the background and the bottom bar, which marks Análisis.
  Widget _frame(BuildContext context, Widget child) => AppShell(
    current: 'insights',
    addKey: const Key('home.add'),
    micKey: const Key('home.capture'),
    onAdd: () => unawaited(openAddSheet(context)),
    onMic: () => unawaited(openCapture(context, listen: true)),
    onNavigate: (to) => navigateFromShell(context, ref, to, current: 'insights'),
    child: SafeArea(bottom: false, child: child),
  );
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Semantics(
        label: l10n.homeLoading,
        liveRegion: true,
        child: const QuietSpinner(size: 28),
      ),
    );
  }
}

/// The screen's heading and the month picker beside it (`flex flex-wrap items-center
/// justify-between gap-x-(--space-2) gap-y-(--space-1)`): under 400px the picker takes a row of
/// its own, centred (`order-last`).
class _Header extends StatelessWidget {
  const _Header({required this.title, required this.picker});

  final String title;
  final Widget picker;

  /// The web's `min-[400px]`, a width of the viewport.
  static const _wide = 400.0;

  /// `font-display text-[28px] font-bold`, on the page's 1.5 line height.
  static const _titleStyle = TextStyle(
    fontFamily: 'Fredoka',
    fontSize: 28,
    fontWeight: FontWeight.w700,
    height: 1.5,
    leadingDistribution: TextLeadingDistribution.even,
  );

  @override
  Widget build(BuildContext context) {
    final colors = context.lkColors;
    final wide = MediaQuery.sizeOf(context).width >= _wide;
    return SizedBox(
      width: double.infinity,
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: WambitoTokens.space2,
        runSpacing: WambitoTokens.space1,
        children: [
          Semantics(
            header: true,
            child: CssLines(
              style: _titleStyle,
              child: Text(title, style: _titleStyle.copyWith(color: colors.ink)),
            ),
          ),
          if (wide)
            picker
          else
            SizedBox(
              width: double.infinity,
              child: Center(child: picker),
            ),
        ],
      ),
    );
  }
}
