// The web's TrendChart (apps/web/app/features/insights/TrendChart.tsx) and the CSS it uses: app.css
// `.lk-trend-band`, `.lk-trend-hit`, `.lk-step`, `.lk-swatch`, `.lk-swatch-income`,
// `.lk-swatch-expense`, `.lk-swatch-line`, `.lk-num`.
import 'package:flutter/material.dart';

import '../api/gen/wambito_api.dart';
import '../l10n/app_localizations.dart';
import '../theme/text_styles.dart';
import '../theme/tokens.g.dart';
import '../ui/css_text.dart';
import '../ui/lk_icons.dart';
import '../ui/lk_theme.dart';
import '../ui/month_picker.dart' show StepButton;
import 'chart_geometry.dart';
import 'charts.dart';
import 'insights_model.dart';
import 'parts.dart';
import '../privacy/masked_money.dart';

/// The chart's height, in px (`HEIGHT`).
const trendHeight = 190.0;

/// Month by month (spec §2.7): income and spending as bars that rise from the axis, the budget as
/// a dashed line (with gaps where there was none), on a compact y-axis (`6 mil`), over the months
/// of the period. One month is selected (the latest by default) and its figures are written under
/// the chart: tapping a month selects it, and the arrows beside the figures step through them. With
/// no transactions in those months it says so instead of drawing.
///
/// Labels come from [range], the answer's own range, like its figures.
class TrendChart extends StatefulWidget {
  const TrendChart({
    super.key,
    required this.report,
    required this.range,
    required this.stale,
    required this.period,
    required this.current,
    required this.currency,
    required this.order,
    this.onSpin,
  });

  /// One entry per month, oldest first; null while loading.
  final TrendReport? report;

  /// What [report] answers.
  final Period? range;
  final bool stale;

  /// The months asked for: the subtitle until the first answer lands.
  final Period period;
  final String current;
  final String currency;
  final int order;

  /// Called as the bars grow into new figures (the screen makes it felt as a wheel).
  final VoidCallback? onSpin;

  @override
  State<TrendChart> createState() => _TrendChartState();
}

class _TrendChartState extends State<TrendChart> {
  /// The month the person tapped; null: the latest.
  String? _picked;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.lkColors;
    final locale = l10n.localeName;
    final reduce = reducedMotion(context);
    final phrase = periodPhrase(l10n, widget.range ?? widget.period, widget.current);
    String money(int cents) => shownMoney(hiddenAmountsOf(context), cents, widget.currency, locale);
    final months = widget.report?.months.toList() ?? const <TrendReportMonthsInner>[];
    final empty = months.every((m) => m.income == 0 && m.expenses == 0);
    String name(String month) => capitalize(monthLabel(month, widget.current, locale), locale);
    final found = months.indexWhere((m) => m.month == _picked);
    final selected = found == -1 ? months.length - 1 : found;
    final shown = selected >= 0 && selected < months.length ? months[selected] : null;
    String budgetText(int budget) => budget > 0 ? money(budget) : l10n.insightsTrendNoBudget;

    void select(int index) {
      if (index >= 0 && index < months.length) setState(() => _picked = months[index].month);
    }

    return InsightCard(
      title: l10n.insightsTrendTitle,
      subtitle: capitalize(phrase, locale),
      order: widget.order,
      busy: widget.stale,
      children: [
        if (widget.report == null)
          const InsightLoading(height: trendHeight + 64)
        else if (empty || shown == null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: WambitoTokens.space4),
            child: CssLines(
              style: LkText.body,
              child: Text(
                l10n.insightsTrendEmpty(phrase),
                textAlign: TextAlign.center,
                style: LkText.body.copyWith(color: colors.inkMuted),
              ),
            ),
          )
        else ...[
          ExcludeSemantics(
            // `-mx-(--space-1)`: the chart is 4px wider than the card's content either side.
            child: SizedBox(
              height: trendHeight,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth + 2 * WambitoTokens.space1;
                  final plot = width - yAxisWidth - trendMargin.right;
                  return OverflowBox(
                    minWidth: width,
                    maxWidth: width,
                    minHeight: trendHeight,
                    maxHeight: trendHeight,
                    child: SizedBox(
                      width: width,
                      height: trendHeight,
                      child: Stack(
                        children: [
                          // The selected month's band, behind the bars.
                          AnimatedPositioned(
                            duration: reduce ? Duration.zero : WambitoTokens.durationSheet,
                            curve: Curves.easeOut,
                            left: yAxisWidth + plot * selected / months.length,
                            width: plot / months.length,
                            top: trendMargin.top,
                            bottom: xAxisHeight,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: colors.surfaceSunken,
                                borderRadius: BorderRadius.circular(WambitoTokens.radiusSm),
                              ),
                            ),
                          ),
                          Positioned.fill(
                            child: TrendBars(
                              points: [
                                for (final m in months)
                                  TrendPoint(
                                    month: m.month,
                                    label: shortMonth(m.month, locale),
                                    income: m.income,
                                    expenses: m.expenses,
                                    budget: m.budget > 0 ? m.budget : null,
                                  ),
                              ],
                              height: trendHeight,
                              animate: !reduce,
                              duration: WambitoTokens.durationHop,
                              // Home's eye closed: the axis keeps its lines, not its figures.
                              formatTick: (cents) =>
                                  hiddenAmountsOf(context) ? '' : compactAmount(cents, locale),
                              onSweep: widget.onSpin,
                            ),
                          ),
                          // A tap target per month over the plot: tapping one selects it. Touch only
                          // (the arrows below are the other way), so it is not a control to a screen
                          // reader.
                          Positioned(
                            left: yAxisWidth,
                            right: trendMargin.right,
                            top: trendMargin.top,
                            bottom: xAxisHeight,
                            child: Row(
                              children: [
                                for (var i = 0; i < months.length; i++)
                                  Expanded(
                                    child: GestureDetector(
                                      key: ValueKey('trend.hit.${months[i].month}'),
                                      behavior: HitTestBehavior.opaque,
                                      onTap: () => select(i),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          Row(
            spacing: WambitoTokens.space2,
            children: [
              StepButton(
                icon: LkIconName.chevronLeft,
                label: l10n.insightsTrendPrevious,
                onPressed: selected <= 0 ? null : () => select(selected - 1),
              ),
              Expanded(
                child: Semantics(
                  liveRegion: true,
                  container: true,
                  label: _readout(l10n, name(shown.month), shown, money, budgetText),
                  child: ExcludeSemantics(
                    child: _Readout(
                      title: name(shown.month),
                      items: [
                        (_Swatch.income, l10n.insightsTrendIncome, money(shown.income)),
                        (_Swatch.expense, l10n.insightsTrendExpenses, money(shown.expenses)),
                        (_Swatch.line, l10n.insightsTrendBudget, budgetText(shown.budget)),
                      ],
                    ),
                  ),
                ),
              ),
              StepButton(
                icon: LkIconName.chevronRight,
                label: l10n.insightsTrendNext,
                onPressed: selected >= months.length - 1 ? null : () => select(selected + 1),
              ),
            ],
          ),
        ],
      ],
    );
  }

  /// The selected month's figures, as one reading (the web's polite live region).
  static String _readout(
    AppLocalizations l10n,
    String month,
    TrendReportMonthsInner shown,
    String Function(int) money,
    String Function(int) budgetText,
  ) =>
      '$month. ${l10n.insightsTrendIncome} ${money(shown.income)}. '
      '${l10n.insightsTrendExpenses} ${money(shown.expenses)}. '
      '${l10n.insightsTrendBudget} ${budgetText(shown.budget)}';
}

enum _Swatch { income, expense, line }

/// The selected month's name and its three figures (`data-testid="trend-readout"`).
class _Readout extends StatelessWidget {
  const _Readout({required this.title, required this.items});

  final String title;
  final List<(_Swatch, String, String)> items;

  /// `font-display text-[16px] font-semibold`.
  static const _titleStyle = TextStyle(
    fontFamily: 'Fredoka',
    fontSize: 16,
    fontWeight: FontWeight.w600,
    height: 1.5,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// `text-[12px] font-extrabold text-ink-muted`.
  static const _itemStyle = TextStyle(
    fontFamily: 'Nunito',
    fontSize: 12,
    fontWeight: FontWeight.w800,
    height: 1.5,
    leadingDistribution: TextLeadingDistribution.even,
  );

  @override
  Widget build(BuildContext context) {
    final colors = context.lkColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CssLines(
          style: _titleStyle,
          child: Text(title, style: _titleStyle.copyWith(color: colors.ink)),
        ),
        Wrap(
          spacing: WambitoTokens.space3,
          runSpacing: 2,
          children: [
            for (final (swatch, label, figure) in items)
              Row(
                mainAxisSize: MainAxisSize.min,
                spacing: WambitoTokens.space1,
                children: [
                  switch (swatch) {
                    _Swatch.income => _Square(colors.chartIncome),
                    _Swatch.expense => _Square(colors.chartExpense),
                    _Swatch.line => _DashedKey(colors.inkMuted),
                  },
                  CssLines(
                    style: _itemStyle,
                    child: Text(label, style: _itemStyle.copyWith(color: colors.inkMuted)),
                  ),
                  CssLines(
                    style: _itemStyle,
                    child: Text(
                      figure,
                      style: _itemStyle.copyWith(
                        color: colors.ink,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }
}

/// A legend key (`.lk-swatch`): a 10px square with 3px corners.
class _Square extends StatelessWidget {
  const _Square(this.color);

  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 10,
    child: DecoratedBox(
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
    ),
  );
}

/// The budget's key (`.lk-swatch-line`): 16px of a 2px dashed line.
class _DashedKey extends StatelessWidget {
  const _DashedKey(this.color);

  final Color color;

  @override
  Widget build(BuildContext context) =>
      SizedBox(width: 16, height: 2, child: CustomPaint(painter: _DashPainter(color)));
}

class _DashPainter extends CustomPainter {
  _DashPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // A 2px dashed border: dashes three widths long and gaps two (as Chrome draws a dashed edge).
    final paint = Paint()..color = color;
    var x = 0.0;
    while (x < size.width) {
      canvas.drawRect(Rect.fromLTWH(x, 0, (x + 6 > size.width ? size.width - x : 6), 2), paint);
      x += 10;
    }
  }

  @override
  bool shouldRepaint(_DashPainter old) => old.color != color;
}
