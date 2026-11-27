// The web's CategoryDonut (apps/web/app/features/insights/CategoryDonut.tsx) and the CSS it uses:
// app.css `.lk-tile`, `.lk-bar`, `.lk-bar-sm`, `.lk-amount`, `.lk-num`.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../api/gen/wambito_api.dart';
import '../home/category_look.dart';
import '../l10n/app_localizations.dart';
import '../theme/text_styles.dart';
import '../theme/tokens.g.dart';
import '../ui/css_text.dart';
import '../ui/lk_theme.dart';
import '../ui/money.dart';
import '../ui/segmented_control.dart';
import 'charts.dart';
import 'insights_controller.dart';
import 'insights_model.dart';
import 'parts.dart';
import '../ui/tile_glyph.dart';
import '../privacy/masked_money.dart';

/// The donut's size, in px (`SIZE`).
const donutSize = 200.0;

/// Where the money went (or came from) in the period, by category (spec §2.7): spending or
/// income, all, paid or pending. A donut in the categories' tints with the total in its hole
/// (its sectors sweep in), and a legend with each category's share and amount (its bar grows).
/// With nothing to show it says so in words.
///
/// Every label comes from [range], the answer's own range, so while another answer loads
/// ([stale]) the card keeps saying what its figures are.
class CategoryDonut extends StatelessWidget {
  const CategoryDonut({
    super.key,
    required this.report,
    required this.range,
    required this.stale,
    required this.kind,
    required this.onKind,
    required this.status,
    required this.onStatus,
    required this.period,
    required this.current,
    required this.currency,
    required this.order,
    this.onSpin,
  });

  /// Totals per category; null while the first one loads.
  final CategoryReport? report;

  /// What [report] answers.
  final ByCategoryRange? range;
  final bool stale;
  final InsightsKind kind;
  final ValueChanged<InsightsKind> onKind;
  final InsightsStatus status;
  final ValueChanged<InsightsStatus> onStatus;

  /// The period asked for: the subtitle until the first answer lands.
  final Period period;
  final String current;
  final String currency;
  final int order;

  /// Called as the donut sweeps into new figures (the screen makes it felt as a wheel).
  final VoidCallback? onSpin;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.lkColors;
    final locale = l10n.localeName;
    final reduce = reducedMotion(context);
    final shownKind = range?.kind ?? kind;
    final shownStatus = range?.status ?? status;
    final phrase = periodPhrase(l10n, range?.period ?? period, current);
    final what = _what(l10n, shownKind, shownStatus);
    String money(int cents) => shownMoney(hiddenAmountsOf(context), cents, currency, locale);
    final items = report?.items.toList() ?? const <CategoryReportItemsInner>[];
    final shares = sharesOf([for (final item in items) item.total]);

    return InsightCard(
      title: l10n.insightsDonutTitle,
      subtitle: capitalize(phrase, locale),
      order: order,
      busy: stale,
      controls: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: WambitoTokens.space2,
        children: [
          SegmentedControl<InsightsKind>(
            label: l10n.insightsDonutKindLabel,
            value: kind,
            options: [
              SegmentOption(InsightsKind.expense, l10n.insightsDonutExpense),
              SegmentOption(InsightsKind.income, l10n.insightsDonutIncome),
            ],
            onChanged: onKind,
          ),
          SegmentedControl<InsightsStatus>(
            label: l10n.insightsDonutStatusLabel,
            value: status,
            options: [
              SegmentOption(InsightsStatus.all, l10n.insightsDonutAll),
              SegmentOption(InsightsStatus.paid, l10n.insightsDonutPaid),
              SegmentOption(InsightsStatus.pending, l10n.insightsDonutPending),
            ],
            onChanged: onStatus,
          ),
        ],
      ),
      children: [
        if (report == null)
          const InsightLoading(height: donutSize)
        else if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: WambitoTokens.space4),
            child: CssLines(
              style: LkText.body,
              child: Text(
                l10n.insightsDonutEmpty(what.toLowerCase(), phrase),
                textAlign: TextAlign.center,
                style: LkText.body.copyWith(color: colors.inkMuted),
              ),
            ),
          )
        else ...[
          // The chart and its legend are for the eyes: screen readers get the same as one summary.
          Semantics(
            container: true,
            label: _summary(l10n, what, phrase, items, shares, report!.total, money),
            child: ExcludeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: WambitoTokens.space3,
                children: [
                  Center(
                    child: SizedBox.square(
                      dimension: donutSize,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          DonutChart(
                            size: donutSize,
                            slices: [
                              for (final item in items)
                                DonutSlice(
                                  id: item.categoryId,
                                  value: item.total,
                                  fill: markColor(
                                    colors,
                                    categoryLook(icon: item.icon, color: item.color).tint,
                                  ),
                                ),
                            ],
                            animate: !reduce,
                            duration: WambitoTokens.durationHop,
                            onSweep: onSpin,
                          ),
                          _Centre(
                            label: shownKind == InsightsKind.expense
                                ? l10n.insightsDonutCenterExpense
                                : l10n.insightsDonutCenterIncome,
                            cents: report!.total,
                            currency: currency,
                          ),
                        ],
                      ),
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: WambitoTokens.space3,
                    children: [
                      for (var i = 0; i < items.length; i++)
                        _LegendRow(
                          key: ValueKey(items[i].categoryId),
                          item: items[i],
                          index: i,
                          share: shares[i],
                          money: money(items[i].total),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  static String _what(AppLocalizations l10n, InsightsKind kind, InsightsStatus status) =>
      switch ((kind, status)) {
        (InsightsKind.expense, InsightsStatus.all) => l10n.insightsDonutWhatExpenseAll,
        (InsightsKind.expense, InsightsStatus.paid) => l10n.insightsDonutWhatExpensePaid,
        (InsightsKind.expense, InsightsStatus.pending) => l10n.insightsDonutWhatExpensePending,
        (InsightsKind.income, InsightsStatus.all) => l10n.insightsDonutWhatIncomeAll,
        (InsightsKind.income, InsightsStatus.paid) => l10n.insightsDonutWhatIncomePaid,
        (InsightsKind.income, InsightsStatus.pending) => l10n.insightsDonutWhatIncomePending,
      };

  /// What the chart and the legend say, for screen readers: the web's table, as one reading.
  static String _summary(
    AppLocalizations l10n,
    String what,
    String phrase,
    List<CategoryReportItemsInner> items,
    List<double> shares,
    int total,
    String Function(int) money,
  ) {
    final locale = l10n.localeName;
    final rows = [
      for (var i = 0; i < items.length; i++)
        '${items[i].name}, ${formatShare(shares[i], locale)}, ${money(items[i].total)}',
    ];
    return '${l10n.insightsDonutCaption(what, phrase)}. ${rows.join('. ')}. '
        '${l10n.insightsDonutTotal}, ${money(total)}';
  }
}

/// The hole of the donut: what the figure is, and the total (`pointer-events-none absolute
/// inset-0 flex flex-col items-center justify-center text-center`).
class _Centre extends StatelessWidget {
  const _Centre({required this.label, required this.cents, required this.currency});

  final String label;
  final int cents;
  final String currency;

  /// `text-[11px] font-extrabold uppercase tracking-[0.06em]`.
  static const _labelStyle = TextStyle(
    fontFamily: 'Nunito',
    fontSize: 11,
    fontWeight: FontWeight.w800,
    letterSpacing: 0.06 * 11,
    height: 1.5,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// `font-display text-[18px] font-bold`.
  static const _amountStyle = TextStyle(
    fontFamily: 'Fredoka',
    fontSize: 18,
    fontWeight: FontWeight.w700,
    height: 1.5,
    leadingDistribution: TextLeadingDistribution.even,
  );

  @override
  Widget build(BuildContext context) {
    final colors = context.lkColors;
    return IgnorePointer(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CssLines(
            style: _labelStyle,
            child: Text(
              label.toUpperCase(),
              textAlign: TextAlign.center,
              style: _labelStyle.copyWith(color: colors.inkMuted),
            ),
          ),
          CssLines(
            style: _amountStyle,
            child: Money(
              cents: cents,
              currency: currency,
              animate: true,
              countFrom: 0,
              style: _amountStyle.copyWith(color: colors.ink),
            ),
          ),
        ],
      ),
    );
  }
}

/// A category's row of the legend: its tile, name and amount, and under them its share as a bar
/// and a percentage. It slides in from the left, a beat after the one before it, and its bar grows.
class _LegendRow extends StatelessWidget {
  const _LegendRow({
    super.key,
    required this.item,
    required this.index,
    required this.share,
    required this.money,
  });

  final CategoryReportItemsInner item;
  final int index;
  final double share;
  final String money;

  /// `text-[14px] font-extrabold`.
  static final _nameStyle = LkText.cardTitle;

  /// `w-[4.5em] text-right text-[12px] font-extrabold text-ink-muted tabular-nums`.
  static const _shareStyle = TextStyle(
    fontFamily: 'Nunito',
    fontSize: 12,
    fontWeight: FontWeight.w800,
    height: 1.5,
    leadingDistribution: TextLeadingDistribution.even,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  @override
  Widget build(BuildContext context) {
    final colors = context.lkColors;
    final locale = AppLocalizations.of(context).localeName;
    final look = categoryLook(icon: item.icon, color: item.color);
    final delay = Duration(milliseconds: math.min(index, 8) * 40);
    return Entrance(
      duration: WambitoTokens.durationSheet,
      delay: delay,
      builder: (context, t) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(-10 * (1 - t), 0),
          child: Row(
            spacing: WambitoTokens.space3,
            children: [
              CategoryTile(glyph: look.glyph, tint: look.tint),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 4,
                  children: [
                    // `flex items-baseline`: the name's line and the amount's sit on one baseline,
                    // which puts the name 1px under the amount's top and makes the row 22px.
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: WambitoTokens.space2,
                      children: [
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 1),
                            child: CssLines(
                              style: _nameStyle,
                              child: Text(
                                item.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: _nameStyle.copyWith(color: colors.ink),
                              ),
                            ),
                          ),
                        ),
                        SizedBox(
                          height: 22,
                          child: CssLines(
                            style: LkText.amount,
                            child: Text(
                              money,
                              maxLines: 1,
                              softWrap: false,
                              style: LkText.amount.copyWith(color: colors.ink),
                            ),
                          ),
                        ),
                      ],
                    ),
                    Row(
                      spacing: WambitoTokens.space2,
                      children: [
                        Expanded(
                          child: _ShareBar(
                            fraction: math.max(share, 0.01),
                            color: markColor(colors, look.tint),
                            delay: Duration(milliseconds: math.min(index, 8) * 40),
                          ),
                        ),
                        SizedBox(
                          width: 4.5 * 12,
                          child: CssLines(
                            style: _shareStyle,
                            child: Text(
                              formatShare(share, locale),
                              textAlign: TextAlign.right,
                              maxLines: 1,
                              softWrap: false,
                              style: _shareStyle.copyWith(color: colors.inkMuted),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A category's tile (`.lk-tile`): 34px, `radius-sm`, its glyph at 17px, on the tint mixed into the
/// sunken surface.
class CategoryTile extends StatelessWidget {
  const CategoryTile({super.key, required this.glyph, required this.tint});

  final String glyph;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    final colors = context.lkColors;
    return ExcludeSemantics(
      child: Container(
        width: 34,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: tileGround(colors, tint),
          borderRadius: BorderRadius.circular(WambitoTokens.radiusSm),
        ),
        child: TileGlyph(glyph, color: colors.ink),
      ),
    );
  }
}

/// A share as a bar (`.lk-bar .lk-bar-sm`, 7px): the fill is [fraction] of the track wide and
/// grows from the left over `--hop` after [delay].
class _ShareBar extends StatelessWidget {
  const _ShareBar({required this.fraction, required this.color, required this.delay});

  final double fraction;
  final Color color;
  final Duration delay;

  @override
  Widget build(BuildContext context) {
    final colors = context.lkColors;
    final pill = BorderRadius.circular(WambitoTokens.radiusPill);
    return SizedBox(
      height: 7,
      child: DecoratedBox(
        decoration: BoxDecoration(color: colors.surfaceSunken, borderRadius: pill),
        child: ClipRRect(
          borderRadius: pill,
          child: Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: fraction,
              heightFactor: 1,
              child: Entrance(
                duration: WambitoTokens.durationHop,
                delay: delay,
                builder: (context, t) => Transform.scale(
                  scaleX: t,
                  alignment: Alignment.centerLeft,
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: color, borderRadius: pill),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
