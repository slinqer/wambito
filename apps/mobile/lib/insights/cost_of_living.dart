// The web's CostOfLiving (apps/web/app/features/insights/CostOfLiving.tsx).
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
import 'category_donut.dart' show CategoryTile;
import 'insights_model.dart';
import 'parts.dart';
import '../privacy/masked_money.dart';

/// "¿Cuánto me cuesta vivir?" (spec §2.7, §4.2): what a normal month costs, as the average
/// monthly spending over the last six complete months, split into fixed (categories with a
/// recurrence) and variable, and per category. A short history is averaged over the months it
/// has (from the first complete month with transactions), not divided by six. Without a complete
/// month to go on, it says so.
class CostOfLiving extends StatelessWidget {
  const CostOfLiving({
    super.key,
    required this.report,
    required this.noHistory,
    required this.categories,
    required this.currency,
    required this.order,
  });

  /// The averages; null while they load.
  final CostOfLivingReport? report;

  /// There is no complete month with movements to average (the web's `months === 0`).
  final bool noHistory;

  /// Every category, archived ones too (past months can be in them), by id.
  final Map<String, Category> categories;
  final String currency;
  final int order;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.lkColors;
    final locale = l10n.localeName;
    final data = report;
    final empty = noHistory || (data != null && (data.total <= 0 || data.categories.isEmpty));
    String money(int cents) => shownMoney(hiddenAmountsOf(context), cents, currency, locale);
    return InsightCard(
      title: l10n.insightsLivingTitle,
      order: order,
      children: [
        if (empty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: WambitoTokens.space2),
            child: CssLines(
              style: LkText.body,
              child: Text(
                l10n.insightsLivingEmpty,
                style: LkText.body.copyWith(color: colors.inkMuted),
              ),
            ),
          )
        else if (data == null)
          const InsightLoading(height: 180)
        else ...[
          Semantics(
            container: true,
            label: _summary(l10n, data, money),
            child: ExcludeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: WambitoTokens.space3,
                children: [
                  CssLines(
                    style: LkText.bodySm,
                    child: Text(
                      l10n.insightsLivingLead(data.months),
                      style: LkText.bodySm.copyWith(color: colors.inkMuted),
                    ),
                  ),
                  _Total(data: data, currency: currency),
                  _Split(data: data, money: money),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: WambitoTokens.space2,
                    children: [
                      for (var i = 0; i < data.categories.length; i++)
                        _CategoryRow(
                          key: ValueKey(data.categories[i].categoryId),
                          row: data.categories[i],
                          category: categories[data.categories[i].categoryId],
                          index: i,
                          money: money(data.categories[i].average),
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

  String _summary(AppLocalizations l10n, CostOfLivingReport data, String Function(int) money) {
    String type(CostOfLivingReportCategoriesInnerTypeEnum t) =>
        t == CostOfLivingReportCategoriesInnerTypeEnum.fixed
        ? l10n.insightsLivingTypeFixed
        : l10n.insightsLivingTypeVariable;
    final rows = [
      for (final row in data.categories)
        () {
          final category = categories[row.categoryId];
          final name = category == null
              ? '—'
              : category.archived
              ? '${category.name} (${l10n.insightsLivingArchived})'
              : category.name;
          return '$name, ${type(row.type)}, ${money(row.average)}';
        }(),
    ];
    return '${l10n.insightsLivingCaption}. ${l10n.insightsLivingLead(data.months)} '
        '${money(data.total)} ${l10n.insightsLivingPerMonth}. ${rows.join('. ')}. '
        '${l10n.insightsLivingFixed}, ${money(data.fixed)}. '
        '${l10n.insightsLivingVariable}, ${money(data.variable)}. '
        '${l10n.insightsLivingTotal}, ${money(data.total)}';
  }
}

/// The monthly average in large type and "al mes" after it (`flex flex-wrap items-baseline
/// gap-x-(--space-2)`).
class _Total extends StatelessWidget {
  const _Total({required this.data, required this.currency});

  final CostOfLivingReport data;
  final String currency;

  /// `font-display text-[34px] font-bold leading-none`.
  static const _amountStyle = TextStyle(
    fontFamily: 'Fredoka',
    fontSize: 34,
    fontWeight: FontWeight.w700,
    height: 1,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// `text-[15px] font-extrabold text-ink-muted`.
  static const _perMonthStyle = TextStyle(
    fontFamily: 'Nunito',
    fontSize: 15,
    fontWeight: FontWeight.w800,
    height: 1.5,
    leadingDistribution: TextLeadingDistribution.even,
  );

  @override
  Widget build(BuildContext context) {
    final colors = context.lkColors;
    final l10n = AppLocalizations.of(context);
    // `flex flex-wrap items-baseline`: "al mes" sits on the amount's baseline, 13px under its top,
    // which makes the row 35.5px, not the amount's 34.
    return Wrap(
      spacing: WambitoTokens.space2,
      children: [
        Money(
          cents: data.total,
          currency: currency,
          animate: true,
          countFrom: 0,
          style: _amountStyle.copyWith(color: colors.ink),
        ),
        // `items-baseline`: "al mes" sits on the amount's baseline, 13px under its top, which makes
        // the row 35.5px, not the amount's 34.
        Padding(
          padding: const EdgeInsets.only(top: 13),
          child: CssLines(
            style: _perMonthStyle,
            child: Text(
              l10n.insightsLivingPerMonth,
              style: _perMonthStyle.copyWith(color: colors.inkMuted),
            ),
          ),
        ),
      ],
    );
  }
}

/// The split of the average between fixed and variable: a bar in two colours that grow from the
/// left, and under it each part with its amount and what it means (`data-testid="living-split"`).
class _Split extends StatelessWidget {
  const _Split({required this.data, required this.money});

  final CostOfLivingReport data;
  final String Function(int) money;

  /// `text-[13px] font-extrabold`.
  static const _nameStyle = TextStyle(
    fontFamily: 'Nunito',
    fontSize: 13,
    fontWeight: FontWeight.w800,
    height: 1.5,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// `lk-amount text-[16px]`.
  static final _amountStyle = LkText.amount.copyWith(fontSize: 16);

  /// `text-[12px] font-bold text-ink-muted`.
  static const _hintStyle = TextStyle(
    fontFamily: 'Nunito',
    fontSize: 12,
    fontWeight: FontWeight.w700,
    height: 1.5,
    leadingDistribution: TextLeadingDistribution.even,
  );

  @override
  Widget build(BuildContext context) {
    final colors = context.lkColors;
    final l10n = AppLocalizations.of(context);
    final fixed = colors.tintIndigo;
    final variable = colors.tintTeal;
    Widget part(Color color, String name, int cents, String hint) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 2,
      children: [
        Row(
          spacing: WambitoTokens.space1,
          children: [
            SizedBox.square(
              dimension: 10,
              child: DecoratedBox(
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
              ),
            ),
            Expanded(
              child: CssLines(
                style: _nameStyle,
                child: Text(name, style: _nameStyle.copyWith(color: colors.ink)),
              ),
            ),
          ],
        ),
        CssLines(
          style: _amountStyle,
          child: Text(money(cents), style: _amountStyle.copyWith(color: colors.ink)),
        ),
        CssLines(
          style: _hintStyle,
          child: Text(hint, style: _hintStyle.copyWith(color: colors.inkMuted)),
        ),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: WambitoTokens.space3,
      children: [
        SizedBox(
          height: 14,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colors.surfaceSunken,
              borderRadius: BorderRadius.circular(WambitoTokens.radiusPill),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(WambitoTokens.radiusPill),
              child: Row(
                children: [
                  _Part(
                    fraction: fraction(data.fixed, data.total),
                    color: fixed,
                    delay: const Duration(milliseconds: 100),
                  ),
                  _Part(
                    fraction: fraction(data.variable, data.total),
                    color: variable,
                    delay: const Duration(milliseconds: 300),
                  ),
                ],
              ),
            ),
          ),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: WambitoTokens.space3,
          children: [
            Expanded(
              child: part(
                fixed,
                l10n.insightsLivingFixed,
                data.fixed,
                l10n.insightsLivingFixedHint,
              ),
            ),
            Expanded(
              child: part(
                variable,
                l10n.insightsLivingVariable,
                data.variable,
                l10n.insightsLivingVariableHint,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// One part of the split bar: [fraction] of the bar wide, growing from the left over `--hop`.
class _Part extends StatelessWidget {
  const _Part({required this.fraction, required this.color, required this.delay});

  final double fraction;
  final Color color;
  final Duration delay;

  @override
  Widget build(BuildContext context) {
    if (fraction <= 0) return const SizedBox.shrink();
    return Expanded(
      flex: math.max(1, (fraction * 100000).round()),
      child: Entrance(
        duration: WambitoTokens.durationHop,
        delay: delay,
        builder: (context, t) => Transform.scale(
          scaleX: t,
          alignment: Alignment.centerLeft,
          child: ColoredBox(color: color, child: const SizedBox.expand()),
        ),
      ),
    );
  }
}

/// A category's row: its tile, name (and "archivada" after it) and whether it is fixed, and its
/// average. It rises into place a beat after the one before it.
class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    super.key,
    required this.row,
    required this.category,
    required this.index,
    required this.money,
  });

  final CostOfLivingReportCategoriesInner row;
  final Category? category;
  final int index;
  final String money;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.lkColors;
    final category = this.category;
    final look = category == null
        ? CategoryLook('🏷️', colors.tintGray)
        : categoryLook(icon: category.icon, color: category.color);
    final fixed = row.type == CostOfLivingReportCategoriesInnerTypeEnum.fixed;
    final nameStyle = LkText.cardTitle;
    const typeStyle = TextStyle(
      fontFamily: 'Nunito',
      fontSize: 12,
      fontWeight: FontWeight.w700,
      height: 1.5,
      leadingDistribution: TextLeadingDistribution.even,
    );
    return Entrance(
      duration: WambitoTokens.durationSheet,
      delay: Duration(milliseconds: math.min(index, 10) * 30),
      builder: (context, t) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, 6 * (1 - t)),
          child: Row(
            spacing: WambitoTokens.space3,
            children: [
              CategoryTile(glyph: look.glyph, tint: look.tint),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    CssLines(
                      style: nameStyle,
                      child: Text.rich(
                        TextSpan(
                          style: nameStyle.copyWith(color: colors.ink),
                          children: [
                            TextSpan(text: category?.name ?? '—'),
                            if (category?.archived ?? false)
                              TextSpan(
                                text: ' · ${l10n.insightsLivingArchived}',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: colors.inkMuted,
                                ),
                              ),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    CssLines(
                      style: typeStyle,
                      child: Text(
                        fixed ? l10n.insightsLivingTypeFixed : l10n.insightsLivingTypeVariable,
                        style: typeStyle.copyWith(color: fixed ? colors.ink : colors.inkMuted),
                      ),
                    ),
                  ],
                ),
              ),
              CssLines(
                style: LkText.amount,
                child: Text(
                  money,
                  maxLines: 1,
                  softWrap: false,
                  style: LkText.amount.copyWith(color: colors.ink),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
