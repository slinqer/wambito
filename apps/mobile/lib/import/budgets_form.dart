// The web's budgets list (apps/web/app/features/onboarding/BudgetsStep.tsx `BudgetsList`,
// `BudgetsTotal`, `AmountWithHint`, `BudgetRow`) and the CSS it uses: app.css `.lk-rowcard`,
// `.lk-tile`, `.lk-input`, `.lk-num`. Shared by the import page and, later, the welcome's last step.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';
import '../money/format.dart';
import '../theme/surfaces.dart';
import '../theme/text_styles.dart';
import '../theme/tokens.g.dart';
import '../ui/css_text.dart' show CssLines;
import '../ui/input_box.dart';
import '../ui/lk_theme.dart';
import 'budget_input.dart';
import 'note_text.dart';
import '../ui/tile_glyph.dart';

/// A spending category as the list shows it.
class BudgetCategory {
  const BudgetCategory({
    required this.id,
    required this.name,
    required this.glyph,
    required this.tint,
  });

  final String id;
  final String name;
  final String glyph;
  final Color tint;
}

/// A draft read as hundredths: null when empty, [invalidDraft] when it is not an amount.
const invalidDraft = -1;

/// Hundredths, null (empty) or [invalidDraft]. The web's `readDraft`.
int? readDraft(String? text, String locale) {
  try {
    return parseBudgetInput(text ?? '', locale);
  } on InvalidAmountException {
    return invalidDraft;
  }
}

/// The total of the valid drafts, in hundredths.
int draftsTotal(Iterable<String> ids, Map<String, String> drafts, String locale) {
  var sum = 0;
  for (final id in ids) {
    final value = readDraft(drafts[id], locale);
    if (value != null && value != invalidDraft) sum += value;
  }
  return sum;
}

/// An amount with the COP lukas hint after it, small and muted. [hintShownElsewhere]: the hint is
/// beside the field already, so here it is only read out, not shown twice.
class AmountWithHint extends StatelessWidget {
  const AmountWithHint({
    super.key,
    required this.cents,
    required this.currency,
    this.style,
    this.hintShownElsewhere = false,
  });

  final int cents;
  final String currency;
  final TextStyle? style;
  final bool hintShownElsewhere;

  /// The amount and its hint as the line says them (also what [BudgetsTotal] measures to know
  /// whether it fits beside its label).
  static TextSpan span(
    BuildContext context, {
    required int cents,
    required String currency,
    TextStyle? style,
    bool hintShownElsewhere = false,
  }) {
    final locale = Localizations.localeOf(context).languageCode;
    final colors = context.lkColors;
    final hint = lukasHint(cents, locale, currency: currency);
    final base = (style ?? LkText.note).copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return TextSpan(
      style: base,
      children: [
        TextSpan(text: formatMoney(cents, currency, locale)),
        if (hint != null && !hintShownElsewhere) ...[
          const TextSpan(text: ' '),
          TextSpan(
            text: hint,
            style: TextStyle(
              fontSize: (base.fontSize ?? 16) * 0.8,
              fontWeight: FontWeight.w700,
              color: colors.inkMuted,
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).languageCode;
    final hint = lukasHint(cents, locale, currency: currency);
    final base = (style ?? LkText.note).copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final money = formatMoney(cents, currency, locale);
    return Semantics(
      label: hint == null ? money : '$money $hint',
      excludeSemantics: true,
      child: CssLines(
        style: base,
        child: Text.rich(
          span(
            context,
            cents: cents,
            currency: currency,
            style: style,
            hintShownElsewhere: hintShownElsewhere,
          ),
        ),
      ),
    );
  }
}

/// "Lo que puedes gastar al mes": the running total, read out as it changes.
class BudgetsTotal extends StatelessWidget {
  const BudgetsTotal({super.key, required this.total, required this.currency});

  final int total;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.lkColors;
    final labelStyle = LkText.note.copyWith(color: colors.inkMuted);
    final amountStyle = LkText.sectionTitle.copyWith(fontSize: 24, height: 1.5, color: colors.good);
    final label = NoteText(l10n.budgetsTotalLabel, labelStyle);
    final amount = AmountWithHint(cents: total, currency: currency, style: amountStyle);
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        padding: const EdgeInsets.only(top: WambitoTokens.space3),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: colors.stroke, width: 2)),
        ),
        // `flex flex-wrap items-baseline justify-between gap-x-3`: the amount drops to a line of
        // its own, at the start, when it does not fit beside the label.
        child: LayoutBuilder(
          builder: (context, constraints) {
            double width(InlineSpan span) {
              final painter = TextPainter(
                text: span,
                textDirection: TextDirection.ltr,
                textScaler: MediaQuery.textScalerOf(context),
              )..layout();
              final w = painter.width;
              painter.dispose();
              return w;
            }

            final fits =
                width(TextSpan(text: l10n.budgetsTotalLabel, style: labelStyle)) +
                    WambitoTokens.space3 +
                    width(
                      AmountWithHint.span(
                        context,
                        cents: total,
                        currency: currency,
                        style: amountStyle,
                      ),
                    ) <=
                constraints.maxWidth;
            return fits
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    spacing: WambitoTokens.space3,
                    children: [
                      Flexible(child: label),
                      amount,
                    ],
                  )
                : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [label, amount]);
          },
        ),
      ),
    );
  }
}

/// One budget field per spending category (shared by the welcome's step and the import page).
class BudgetsList extends StatelessWidget {
  const BudgetsList({
    super.key,
    required this.categories,
    required this.drafts,
    required this.onChange,
    required this.currency,
  });

  final List<BudgetCategory> categories;
  final Map<String, String> drafts;
  final void Function(String id, String text) onChange;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.lkColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: WambitoTokens.space4,
      children: [
        if (categories.isEmpty)
          Text(l10n.budgetsEmpty, style: LkText.copy.copyWith(color: colors.inkMuted)),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: WambitoTokens.space2,
          children: [
            for (final category in categories)
              BudgetRow(
                key: ValueKey('budget.${category.id}'),
                category: category,
                text: drafts[category.id] ?? '',
                currency: currency,
                onChanged: (text) => onChange(category.id, text),
              ),
          ],
        ),
      ],
    );
  }
}

/// A category's tile, name and its budget field, with what the typed text comes to under it.
class BudgetRow extends StatefulWidget {
  const BudgetRow({
    super.key,
    required this.category,
    required this.text,
    required this.currency,
    required this.onChanged,
  });

  final BudgetCategory category;
  final String text;
  final String currency;
  final ValueChanged<String> onChanged;

  @override
  State<BudgetRow> createState() => _BudgetRowState();
}

class _BudgetRowState extends State<BudgetRow> {
  late final TextEditingController _controller = TextEditingController(text: widget.text);
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(_refocused);
  }

  void _refocused() => setState(() {});

  @override
  void didUpdateWidget(BudgetRow old) {
    super.didUpdateWidget(old);
    // The import filled the field (or emptied it): show what the draft says.
    if (widget.text != _controller.text) {
      _controller.value = TextEditingValue(
        text: widget.text,
        selection: TextSelection.collapsed(offset: widget.text.length),
      );
    }
  }

  @override
  void dispose() {
    _focus.removeListener(_refocused);
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final lk = context.lk;
    final colors = lk.colors;
    final locale = Localizations.localeOf(context).languageCode;
    final category = widget.category;
    final value = readDraft(widget.text, locale);
    final invalid = value == invalidDraft;
    final hint = value != null && !invalid
        ? lukasHint(value, locale, currency: widget.currency)
        : null;
    final nameStyle = LkText.sectionTitle.copyWith(fontSize: 17, height: 1.5, color: colors.ink);
    final fieldStyle = LkText.copy.copyWith(
      color: colors.ink,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Container(
      decoration: LkSurface.rowCard(lk),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 10,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: WambitoTokens.space1),
            child: ExcludeSemantics(
              child: Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Color.lerp(colors.surfaceSunken, category.tint, 0.45),
                  borderRadius: LkSurface.radius(LkRadius.sm),
                ),
                child: TileGlyph(category.glyph, color: colors.ink),
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: WambitoTokens.space1,
              children: [
                CssLines(
                  style: nameStyle,
                  child: Text(
                    category.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: nameStyle,
                  ),
                ),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _focus.requestFocus,
                  child: InputBox(
                    focused: _focus.hasFocus,
                    borderColor: invalid ? colors.over : null,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 36),
                      child: Row(
                        spacing: 8,
                        children: [
                          Expanded(
                            child: Semantics(
                              label: l10n.budgetsAmountLabel(category.name),
                              textField: true,
                              child: EditableText(
                                key: Key('budget.field.${category.id}'),
                                controller: _controller,
                                focusNode: _focus,
                                style: fieldStyle,
                                cursorColor: colors.ink,
                                backgroundCursorColor: colors.inkMuted,
                                selectionColor: colors.brand.withValues(alpha: 0.4),
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                textInputAction: TextInputAction.next,
                                autocorrect: false,
                                enableSuggestions: false,
                                inputFormatters: [
                                  _BudgetFormatter(BudgetFormat(locale, widget.currency)),
                                ],
                                onChanged: widget.onChanged,
                              ),
                            ),
                          ),
                          if (hint != null)
                            ExcludeSemantics(
                              child: Text(
                                hint,
                                style: LkText.bodySm.copyWith(color: colors.inkMuted),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (value != null && !invalid)
                  AmountWithHint(
                    cents: value,
                    currency: widget.currency,
                    hintShownElsewhere: true,
                    style: LkText.note.copyWith(color: colors.ink),
                  )
                else
                  NoteText(l10n.budgetsNone, LkText.note.copyWith(color: colors.inkMuted)),
                if (invalid)
                  Semantics(
                    liveRegion: true,
                    child: NoteText(
                      l10n.budgetsInvalid(budgetExample(widget.currency, locale)),
                      LkText.note.copyWith(color: colors.over),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Groups a budget as it is typed (`300000` → `300.000`), the cursor staying after the same digit.
class _BudgetFormatter extends TextInputFormatter {
  const _BudgetFormatter(this.format);

  final BudgetFormat format;

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final caret = newValue.selection.isValid
        ? newValue.selection.extentOffset
        : newValue.text.length;
    final typed = formatBudgetTyping(newValue.text, caret, format);
    return TextEditingValue(
      text: typed.text,
      selection: TextSelection.collapsed(offset: typed.caret),
    );
  }
}
