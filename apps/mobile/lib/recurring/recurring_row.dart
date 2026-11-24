// The web's RecurringItem (apps/web/app/features/recurring/RecurringPage.tsx) and the CSS it uses:
// app.css `.lk-rowcard`, `.lk-row` (and its press), `.lk-tile`, `.lk-rowmain`, `.lk-rowtop`,
// `.lk-status` and `.lk-amount`.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../api/gen/wambito_api.dart';
import '../home/category_look.dart';
import '../home/home_format.dart';
import '../l10n/app_localizations.dart';
import '../money/format.dart';
import '../theme/surfaces.dart';
import '../theme/text_styles.dart';
import '../theme/tokens.g.dart';
import '../ui/css_text.dart';
import '../ui/lk_theme.dart';
import '../ui/pressable.dart';
import 'recurring_model.dart';
import '../ui/tile_glyph.dart';

/// A date as `23 oct 2026` (es) or `Oct 23, 2026` (en): the web's `formatDate`
/// (`dateStyle: "medium"`, with the dots out). [date] is `YYYY-MM-DD`.
String formatRecurringDate(String date, String locale) {
  final p = date.split('-').map(int.parse).toList();
  return _dateFormats
      .putIfAbsent(locale, () => DateFormat.yMMMd(dateTag(locale)))
      .format(DateTime.utc(p[0], p[1], p[2]))
      .replaceAll('.', '');
}

final _dateFormats = <String, DateFormat>{};

/// A recurring payment's rule in words: "Cada mes, el día 5", "Cada año, el 15 de marzo".
String recurrenceRuleText(AppLocalizations l10n, Recurrence rule) {
  final month = rule.monthOfYear;
  if (rule.frequency == RecurrenceFrequencyEnum.yearly && month != null) {
    final name = monthInSentence('2026-${month.toString().padLeft(2, '0')}', l10n.localeName);
    return l10n.recurringYearlyRule(rule.dayOfMonth, name);
  }
  return l10n.recurringMonthlyRule(rule.dayOfMonth);
}

/// One recurring payment: its category's tile, name and amount, the rule in words (and its
/// category) and its next date, or "Ya terminó". The whole card opens the edit sheet.
class RecurringRow extends StatelessWidget {
  const RecurringRow({
    super.key,
    required this.rule,
    required this.category,
    required this.currency,
    required this.today,
    required this.onOpen,
  });

  final Recurrence rule;

  /// The rule's category, or null when it is not known.
  final Category? category;
  final String currency;

  /// Today in the person's time zone (`YYYY-MM-DD`): the next date counts it.
  final String today;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final lk = context.lk;
    final colors = lk.colors;
    final locale = l10n.localeName;
    final look = category == null
        ? null
        : categoryLook(icon: category!.icon, color: category!.color);
    final income = rule.amount > 0;
    final money = formatMoney(
      rule.amount,
      currency,
      locale,
      sign: income ? MoneySign.always : MoneySign.auto,
    );
    final ruleText = recurrenceRuleText(l10n, rule);
    final ruleLine = category == null ? ruleText : '$ruleText · ${category!.name}';
    final next = nextOccurrence(rule, today);
    final when = next == null
        ? l10n.recurringEnded
        : l10n.recurringNext(formatRecurringDate(next, locale));
    final titleStyle = LkText.label.copyWith(leadingDistribution: TextLeadingDistribution.even);
    const statusStyle = LkText.caption;

    return Pressable(
      onPressed: onOpen,
      label: '${rule.name} $money $ruleLine $when',
      keepChildSemantics: true,
      builder: (context, state) {
        final pressed = state.pressed;
        final radius = LkSurface.radius(LkRadius.lg);
        return PressSurface(
          minSize: 0,
          pressDy: pressed ? 3 : 0,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: colors.surfaceRow,
            borderRadius: radius,
            border: LkSurface.border(colors),
            boxShadow: pressed ? LkSurface.pressedEdge(lk) : LkSurface.edgeShadow(lk, LkEdge.sm),
          ),
          ringRadius: state.focusVisible ? radius : null,
          ringColor: colors.focus,
          child: SizedBox(
            width: double.infinity,
            child: Row(
              spacing: 10,
              children: [
                ExcludeSemantics(
                  child: Container(
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      // `color-mix(in srgb, tint 45%, var(--surface-sunken))`, or the stroke for
                      // a category that is gone.
                      color: Color.lerp(colors.surfaceSunken, look?.tint ?? colors.stroke, 0.45),
                      borderRadius: LkSurface.radius(LkRadius.sm),
                    ),
                    child: TileGlyph(look?.glyph ?? '🏷️', color: colors.ink),
                  ),
                ),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: 2,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: 8,
                        children: [
                          Expanded(
                            child: ExcludeSemantics(
                              child: BlinkLine(
                                style: titleStyle,
                                child: Text(
                                  rule.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: titleStyle.copyWith(color: colors.ink),
                                ),
                              ),
                            ),
                          ),
                          ExcludeSemantics(
                            child: BlinkLine(
                              style: LkText.amount,
                              child: Text(
                                money,
                                maxLines: 1,
                                softWrap: false,
                                style: LkText.amount.copyWith(
                                  color: income ? colors.good : colors.ink,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      Wrap(
                        spacing: WambitoTokens.space2,
                        children: [
                          for (final (text, color) in [
                            (ruleLine, colors.inkMuted),
                            (when, colors.ink),
                          ])
                            ExcludeSemantics(
                              child: BlinkLine(
                                style: statusStyle,
                                child: CssLines(
                                  style: statusStyle,
                                  child: _Fitted(
                                    TextSpan(
                                      text: text,
                                      style: statusStyle.copyWith(
                                        color: color,
                                        leadingDistribution: TextLeadingDistribution.even,
                                      ),
                                    ),
                                  ),
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
        );
      },
    );
  }
}

/// A status span: laid out word by word as Blink does (so it lands on the web's pixels) while it
/// fits on a line; a span too long for the line wraps, as the `<span>` does on the web.
class _Fitted extends StatelessWidget {
  const _Fitted(this.span);

  final TextSpan span;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) =>
        CssText.widthOf(context, span) <= constraints.maxWidth ? CssText(span) : Text.rich(span),
  );
}
