// The web's TransactionRow (apps/web/app/ui/TransactionRow.tsx) and the CSS it uses: app.css
// `.lk-rowcard`, `.lk-row` (and its press), `.lk-tile`, `.lk-rowmain`, `.lk-rowtop`, `.lk-status`,
// `.lk-amount`, `.lk-row-control`, and the plain pending label `.lk-badge`.
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../money/format.dart';
import '../theme/surfaces.dart';
import '../theme/text_styles.dart';
import '../theme/tokens.g.dart';
import 'css_text.dart';
import 'lk_theme.dart';
import 'outset_box.dart';
import 'pending_badge.dart';
import 'pressable.dart';
import 'swipe_row.dart';
import 'lk_icons.dart';
import 'tile_glyph.dart';

/// Whether a transaction is paid or still to be.
enum TransactionRowStatus { paid, pending }

/// One transaction: glyph, name (or its category), category, and the amount (a real minus sign for
/// expenses; `+` in `good` for income). The card opens the editor through one button; a pending
/// row carries its own [PendingBadge] button, which sits above that hit area.
class TransactionRow extends StatefulWidget {
  const TransactionRow({
    super.key,
    required this.name,
    required this.categoryName,
    required this.glyph,
    required this.amount,
    required this.currency,
    required this.status,
    required this.onOpen,
    this.onPay,
    this.paidHere = false,
    this.unsent = false,
    this.reviewMark,
  });

  /// The transaction's name; blank shows the category name instead.
  final String name;
  final String categoryName;

  /// The category's emoji.
  final String glyph;

  /// Signed cents: expenses negative, income positive.
  final int amount;

  /// ISO 4217 code, e.g. `EUR`.
  final String currency;

  final TransactionRowStatus status;

  /// Opens the edit sheet.
  final VoidCallback? onOpen;

  /// Marks a pending transaction paid. Without it a pending row shows a plain label.
  final Future<void> Function()? onPay;

  /// Paid from this row just now: the badge stays (showing "✓ Pagado") although [status] is already
  /// paid, so the change is seen and announced where it happened.
  final bool paidHere;

  /// Saved with no network and not on the server yet: a cloud with a line through it says so.
  final bool unsent;

  /// Detected from a notification and not looked at yet: "por revisar · de Revolut", in the status
  /// line. Null for any other row.
  final String? reviewMark;

  @override
  State<TransactionRow> createState() => _TransactionRowState();
}

class _TransactionRowState extends State<TransactionRow> {
  /// The badge's box, which touches reach beyond the line it sits in.
  final _badgeKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final TransactionRow(
      :name,
      :categoryName,
      :glyph,
      :amount,
      :currency,
      :status,
      :onOpen,
      :onPay,
      :paidHere,
      :unsent,
      :reviewMark,
    ) = widget;
    final l10n = AppLocalizations.of(context);
    final lk = context.lk;
    final colors = lk.colors;
    final locale = Localizations.localeOf(context).languageCode;
    final title = name.trim().isEmpty ? categoryName : name.trim();
    final income = amount > 0;
    final money = formatMoney(
      amount,
      currency,
      locale,
      sign: income ? MoneySign.always : MoneySign.auto,
    );
    final pending = status == TransactionRowStatus.pending;
    final titleStyle = LkText.label.copyWith(leadingDistribution: TextLeadingDistribution.even);
    const statusStyle = LkText.caption;

    final Widget? badge = (pending || (paidHere && onPay != null))
        ? (onPay != null
              // `lk-row-control -my-3`: a 44px target in a 20px line, above the row's hit area.
              ? OutsetBox(
                  vertical: WambitoTokens.space3,
                  // The badge comes after the row in the tab order, as its button does in the DOM.
                  child: FocusTraversalOrder(
                    order: const NumericFocusOrder(1),
                    child: PendingBadge(key: _badgeKey, onPay: onPay, paid: !pending),
                  ),
                )
              : _PlainBadge(label: l10n.pending))
        : null;

    return FocusTraversalGroup(
      policy: OrderedTraversalPolicy(),
      child: FocusTraversalOrder(
        order: const NumericFocusOrder(0),
        child: Pressable(
          onPressed: onOpen,
          label: [title, money, categoryName, ?reviewMark, if (unsent) l10n.unsentLabel].join(' '),
          hint: SwipeHint.maybeOf(context),
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
                boxShadow: pressed
                    ? LkSurface.pressedEdge(lk)
                    : LkSurface.edgeShadow(lk, LkEdge.sm),
              ),
              ringRadius: state.focusVisible ? radius : null,
              ringColor: colors.focus,
              child: HitTargetBoost(
                targetKey: _badgeKey,
                child: SizedBox(
                  width: double.infinity,
                  child: Row(
                    spacing: 10,
                    children: [
                      // `.lk-tile`: 34 × 34, the sunken surface, the glyph at 17px.
                      ExcludeSemantics(
                        child: Container(
                          width: 34,
                          height: 34,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: colors.surfaceSunken,
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
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              spacing: 8,
                              children: [
                                Expanded(
                                  child: ExcludeSemantics(
                                    child: BlinkLine(
                                      style: titleStyle,
                                      child: Text(
                                        title,
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
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: WambitoTokens.space2,
                              children: [
                                ExcludeSemantics(
                                  child: BlinkLine(
                                    style: statusStyle,
                                    child: CssLines(
                                      style: statusStyle,
                                      child: _CategoryName(
                                        TextSpan(
                                          text: categoryName,
                                          style: statusStyle.copyWith(
                                            color: colors.inkMuted,
                                            leadingDistribution: TextLeadingDistribution.even,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                if (reviewMark != null)
                                  ExcludeSemantics(
                                    child: Text(
                                      reviewMark,
                                      key: const Key('row.review'),
                                      style: statusStyle.copyWith(
                                        color: colors.near,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ?badge,
                                if (unsent)
                                  LkIcon(
                                    LkIconName.cloudOff,
                                    key: const Key('row.unsent'),
                                    size: 14,
                                    color: colors.inkMuted,
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
          },
        ),
      ),
    );
  }
}

/// The category's name in a row's status line: laid out word by word as Blink does (so it lands on
/// the web's pixels) while it fits on a line; a name too long for the line wraps, as the `<span>`
/// does on the web (a 40-character category name is on two lines, never an overflow).
class _CategoryName extends StatelessWidget {
  const _CategoryName(this.span);

  final TextSpan span;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) =>
        CssText.widthOf(context, span) <= constraints.maxWidth ? CssText(span) : Text.rich(span),
  );
}

/// A pending transaction that cannot be paid from here: the badge's look without its button
/// (`.lk-badge` on a span, no edge, not pressable).
class _PlainBadge extends StatelessWidget {
  const _PlainBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.lkColors;
    final text = LkText.badge.copyWith(color: colors.near);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: LkSurface.radius(LkRadius.pill),
        // `border: 1.5px solid`, which Chrome lays out as 1px.
        border: Border.all(color: colors.near),
      ),
      child: Padding(
        // 7px by 2px inside the 1px border.
        padding: const EdgeInsets.symmetric(horizontal: 7 + 1, vertical: 2 + 1),
        child: Transform.translate(
          offset: Offset(letterSpacingShift(context, text.letterSpacing!), 0),
          child: BlinkLine(
            style: LkText.badge,
            child: Text(LkText.upperCase(label), style: text),
          ),
        ),
      ),
    );
  }
}
