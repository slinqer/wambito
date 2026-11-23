// The web's CategoryRow (apps/web/app/ui/CategoryRow.tsx) and the CSS it uses: app.css `.lk-rowcard`,
// `.lk-row` (and its press), `.lk-tile`, `.lk-rowmain`, `.lk-rowtop`, `.lk-status` (`is-near`,
// `is-over`), `.lk-num`.
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../money/format.dart';
import '../theme/surfaces.dart';
import '../theme/text_styles.dart';
import '../theme/tokens.g.dart';
import 'budget_bar.dart';
import 'css_text.dart';
import 'lk_theme.dart';
import 'pressable.dart';
import 'tile_glyph.dart';

/// One category in the budget list: a tinted glyph tile, the name and the budget, the status in
/// words (`Quedan 46,33 €` / `Te pasaste 14,12 €` / `Sin presupuesto`) and a small bar. Status is
/// never colour alone. The whole card opens the detail through one button named by the name and
/// the status.
class CategoryRow extends StatelessWidget {
  const CategoryRow({
    super.key,
    required this.name,
    this.note,
    required this.glyph,
    required this.tint,
    required this.budget,
    required this.spent,
    required this.remaining,
    required this.state,
    required this.currency,
    required this.onOpen,
    this.line,
    this.control,
  });

  final String name;

  /// A short muted word after the name, e.g. "archivada". Part of the row's name.
  final String? note;

  /// The emoji shown in the tile.
  final String glyph;

  /// The category's colour; the tile mixes it into the sunken surface so it reads in both themes.
  final Color tint;

  /// Cents budgeted this month, or null without a budget.
  final int? budget;

  /// Cents spent this month.
  final int spent;

  /// Cents left (negative when over), or null without a budget.
  final int? remaining;

  /// From the month summary; never recomputed here.
  final BudgetState state;

  /// ISO 4217 code, e.g. `EUR`.
  final String currency;

  /// Opens the category detail.
  final VoidCallback onOpen;

  /// A plain line instead of the budget's status, bar and figures: an income category ("Ingreso")
  /// or an archived one ("Archivada"). The budget figures are then ignored.
  final String? line;

  /// A button of its own at the row's end (an archived category's "Restaurar"), above the row's
  /// own press (`.lk-row-control`).
  final Widget? control;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final lk = context.lk;
    final colors = lk.colors;
    final locale = Localizations.localeOf(context).languageCode;
    String money(int cents) => formatMoney(cents, currency, locale);

    final line = this.line;
    final budget = line == null ? this.budget : null;
    final note = this.note;
    final status =
        line ??
        (budget == null
            ? l10n.categoryRowNoBudget
            : state == BudgetState.over
            ? l10n.categoryRowOver(money((remaining ?? budget - spent).abs()))
            : l10n.categoryRowRemaining(money(remaining ?? budget - spent)));
    final statusColor = budget == null
        ? colors.inkMuted
        : switch (state) {
            BudgetState.near => colors.near,
            BudgetState.over => colors.over,
            BudgetState.ok => colors.inkMuted,
          };
    final titleStyle = LkText.label.copyWith(leadingDistribution: TextLeadingDistribution.even);
    const statusStyle = LkText.caption;
    final label = note == null ? name : '$name $note';

    return Pressable(
      onPressed: onOpen,
      label: '$label $status',
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
                      // `color-mix(in srgb, tint 45%, var(--surface-sunken))`.
                      color: Color.lerp(colors.surfaceSunken, tint, 0.45),
                      borderRadius: LkSurface.radius(LkRadius.sm),
                    ),
                    child: TileGlyph(glyph, color: colors.ink),
                  ),
                ),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: 2,
                    children: [
                      CssLines(
                        style: titleStyle,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          spacing: 8,
                          children: [
                            Expanded(
                              child: ExcludeSemantics(
                                child: BlinkLine(
                                  style: titleStyle,
                                  child: Text.rich(
                                    TextSpan(
                                      style: titleStyle.copyWith(color: colors.ink),
                                      children: [
                                        TextSpan(text: name),
                                        if (note != null) ...[
                                          const TextSpan(text: ' '),
                                          TextSpan(
                                            text: '· $note',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w700,
                                              color: colors.inkMuted,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            ),
                            if (budget != null)
                              ExcludeSemantics(
                                child: BlinkLine(
                                  style: titleStyle,
                                  child: Text(
                                    money(budget),
                                    maxLines: 1,
                                    softWrap: false,
                                    style: titleStyle.copyWith(
                                      color: colors.ink,
                                      fontFeatures: const [FontFeature.tabularFigures()],
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      CssLines(
                        style: statusStyle,
                        child: Wrap(
                          spacing: WambitoTokens.space2,
                          children: [
                            ExcludeSemantics(
                              child: BlinkLine(
                                style: statusStyle,
                                child: CssText(
                                  TextSpan(
                                    text: status,
                                    style: statusStyle.copyWith(
                                      color: statusColor,
                                      leadingDistribution: TextLeadingDistribution.even,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            if (budget == null && line == null && spent != 0)
                              ExcludeSemantics(
                                child: BlinkLine(
                                  style: statusStyle,
                                  child: CssText(
                                    TextSpan(
                                      text: l10n.categoryRowSpent(money(spent)),
                                      style: statusStyle.copyWith(
                                        color: colors.inkMuted,
                                        leadingDistribution: TextLeadingDistribution.even,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (budget != null)
                        BudgetBar(
                          spent: spent,
                          budget: budget,
                          state: this.state,
                          size: BudgetBarSize.sm,
                          label: l10n.categoryRowMeter(name, status),
                        ),
                    ],
                  ),
                ),
                ?control,
              ],
            ),
          ),
        );
      },
    );
  }
}
