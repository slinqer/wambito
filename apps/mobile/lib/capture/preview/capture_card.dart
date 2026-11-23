// One movement of the capture preview, in the language of the web's TransactionRow
// (apps/web/app/ui/TransactionRow.tsx; app.css `.lk-rowcard`, `.lk-tile`, `.lk-rowtop`,
// `.lk-status`, `.lk-amount`): a card with the category's glyph in a tile, the name, the category
// and the amount. Capture has no web story: this is the same pieces, set for a movement that is
// still being read.
import 'package:flutter/material.dart';

import '../../api/gen/wambito_api.dart';
import '../../home/category_look.dart';
import '../../l10n/app_localizations.dart';
import '../../money/format.dart';
import '../../theme/surfaces.dart';
import '../../theme/text_styles.dart';
import '../../theme/theme.dart' show WambitoTheme;
import '../../theme/tokens.g.dart';
import '../../ui/lk_theme.dart';
import '../../ui/outset_box.dart';
import '../../ui/pressable.dart';
import '../parser/parse.dart' as p;
import 'capture_card_editor.dart';
import 'capture_preview.dart';
import '../../ui/lk_icons.dart';
import '../../ui/tile_glyph.dart';

/// The glyph in the tile of a card with no category yet.
const noCategoryGlyph = '🏷️';

/// The box of a card of the preview: `.lk-rowcard` on a `surface-row`, its border the stroke, or
/// [outline] (the amber of what still needs something from the person).
BoxDecoration captureCardBox(WambitoTheme theme, {Color? outline, bool pressed = false}) =>
    BoxDecoration(
      color: theme.colors.surfaceRow,
      borderRadius: LkSurface.radius(LkRadius.lg),
      border: Border.all(color: outline ?? theme.colors.stroke, width: 2),
      boxShadow: pressed ? LkSurface.pressedEdge(theme) : LkSurface.edgeShadow(theme, LkEdge.sm),
    );

/// `.lk-tile`: 34 × 34 on the sunken surface, with [glyph] at 17px.
class CaptureTile extends StatelessWidget {
  const CaptureTile({super.key, required this.glyph});

  final String glyph;

  @override
  Widget build(BuildContext context) {
    final colors = context.lkColors;
    return ExcludeSemantics(
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
    );
  }
}

/// One movement of the preview: its name, category and amount at a glance, a button to remove it
/// and, open, the fields to change it. Tapping the card opens or closes them.
class CaptureCardView extends StatefulWidget {
  const CaptureCardView({
    super.key,
    required this.index,
    required this.card,
    required this.open,
    required this.categories,
    required this.currency,
    required this.today,
    required this.enabled,
    required this.onToggle,
    required this.onPick,
    required this.onRemove,
    required this.onChange,
    required this.onPicked,
  });

  final int index;
  final CaptureCard card;
  final bool open;
  final List<Category> categories;
  final String currency;
  final String today;
  final bool enabled;
  final VoidCallback onToggle;
  final VoidCallback onPick;
  final VoidCallback onRemove;
  final CardChange onChange;
  final VoidCallback onPicked;

  @override
  State<CaptureCardView> createState() => _CaptureCardViewState();
}

class _CaptureCardViewState extends State<CaptureCardView> {
  /// The category button's box, which touches reach beyond the line it sits in.
  final _pickKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final lk = context.lk;
    final colors = lk.colors;
    final card = widget.card;
    final i = widget.index;
    final category = widget.categories.where((c) => c.id == card.categoryId).firstOrNull;
    final hasAmount = (card.amount ?? 0) > 0;
    final expense = card.kind == p.Kind.expense;
    final title = card.name.trim().isEmpty ? (category?.name ?? '') : card.name.trim();
    final money = hasAmount
        ? formatMoney(
            expense ? -card.amount! : card.amount!,
            widget.currency,
            l10n.localeName,
            sign: expense ? MoneySign.auto : MoneySign.always,
          )
        : l10n.captureNeedsAmount;
    final titleStyle = LkText.label.copyWith(leadingDistribution: TextLeadingDistribution.even);
    // What still needs the person amber-rims the card; open, it is the brand's.
    final outline = !card.complete ? colors.near : (widget.open ? colors.brand : null);
    final radius = LkSurface.radius(LkRadius.lg);

    final face = FocusTraversalGroup(
      policy: OrderedTraversalPolicy(),
      child: FocusTraversalOrder(
        order: const NumericFocusOrder(0),
        child: Pressable(
          onPressed: widget.enabled ? widget.onToggle : null,
          label: '$title $money${category == null ? '' : ' ${category.name}'}',
          expanded: widget.open,
          keepChildSemantics: true,
          builder: (context, state) => PressSurface(
            minSize: 0,
            pressDy: state.pressed ? 3 : 0,
            // 12px at the left; at the right the remove button's own 44px box.
            padding: const EdgeInsets.fromLTRB(12, 5, 2, 5),
            decoration: captureCardBox(lk, outline: outline, pressed: state.pressed),
            ringRadius: state.focusVisible ? radius : null,
            ringColor: colors.focus,
            child: HitTargetBoost(
              targetKey: _pickKey,
              child: SizedBox(
                width: double.infinity,
                child: Row(
                  spacing: 10,
                  children: [
                    CaptureTile(
                      glyph: category == null
                          ? noCategoryGlyph
                          : categoryLook(icon: category.icon, color: category.color).glyph,
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
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
                                    style: hasAmount ? LkText.amount : titleStyle,
                                    child: Text(
                                      money,
                                      maxLines: 1,
                                      softWrap: false,
                                      style: hasAmount
                                          ? LkText.amount.copyWith(
                                              color: expense ? colors.ink : colors.good,
                                            )
                                          : titleStyle.copyWith(color: colors.near),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (category != null)
                              ExcludeSemantics(
                                child: BlinkLine(
                                  style: LkText.caption,
                                  child: Text(
                                    category.name,
                                    style: LkText.caption.copyWith(color: colors.inkMuted),
                                  ),
                                ),
                              )
                            else
                              Align(
                                alignment: Alignment.centerLeft,
                                // `lk-row-control -my-3`: a 44px target in a 20px line, above the
                                // row's hit area.
                                child: OutsetBox(
                                  vertical: WambitoTokens.space3,
                                  child: FocusTraversalOrder(
                                    order: const NumericFocusOrder(1),
                                    child: _PickBadge(
                                      key: _pickKey,
                                      buttonKey: Key('capture.card.$i.pick'),
                                      label: l10n.capturePickCategory,
                                      onPressed: widget.enabled ? widget.onPick : null,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    _RemoveButton(
                      key: Key('capture.card.$i.remove'),
                      label: l10n.captureRemove,
                      onPressed: widget.enabled ? widget.onRemove : null,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    return Column(
      key: Key('capture.card.$i'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: WambitoTokens.space2,
      children: [
        face,
        if (widget.open)
          CaptureCardEditor(
            key: ValueKey('editor-${card.id}'),
            index: i,
            card: card,
            categories: widget.categories,
            currency: widget.currency,
            today: widget.today,
            onChange: widget.onChange,
            onPicked: widget.onPicked,
          ),
      ],
    );
  }
}

/// "Elige categoría" in the status line: the look of the web's "Pendiente" badge (`.lk-badge`, in
/// the amber of what is waiting), a 44px button around the small pill.
class _PickBadge extends StatelessWidget {
  const _PickBadge({
    super.key,
    required this.buttonKey,
    required this.label,
    required this.onPressed,
  });

  final Key buttonKey;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final lk = context.lk;
    final colors = lk.colors;
    final text = LkText.badge.copyWith(color: colors.near);
    const radius = BorderRadius.all(Radius.circular(WambitoTokens.radiusPill));
    return Pressable(
      key: buttonKey,
      onPressed: onPressed,
      label: label,
      builder: (context, state) {
        final pressed = state.pressed;
        final pill = PressSurface(
          minSize: 0,
          pressDy: pressed ? 2 : 0,
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(color: colors.near),
          ),
          outsideShadow: pressed
              ? const []
              : [BoxShadow(color: colors.surfaceEdge, offset: const Offset(0, 2))],
          ringRadius: state.focusVisible ? radius : null,
          ringColor: colors.focus,
          child: Transform.translate(
            offset: Offset(letterSpacingShift(context, text.letterSpacing!), 0),
            child: BlinkLine(
              style: LkText.badge,
              child: Text(LkText.upperCase(label), style: text),
            ),
          ),
        );
        // The pill sits in the middle of a 44px target (`min-h-11 min-w-11`).
        return ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          child: Center(widthFactor: 1, heightFactor: 1, child: pill),
        );
      },
    );
  }
}

/// A 44px button with a cross in it, at the card's right: takes the movement out of the batch.
class _RemoveButton extends StatelessWidget {
  const _RemoveButton({super.key, required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.lkColors;
    return FocusTraversalOrder(
      order: const NumericFocusOrder(2),
      child: Pressable(
        onPressed: onPressed,
        label: label,
        builder: (context, state) => SizedBox.square(
          dimension: 44,
          child: Center(
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: state.focusVisible ? Border.all(color: colors.focus, width: 3) : null,
              ),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: LkIcon(
                  LkIconName.close,
                  size: 18,
                  color: onPressed == null
                      ? colors.inkMuted.withValues(alpha: 0.5)
                      : (state.pressed ? colors.ink : colors.inkMuted),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
