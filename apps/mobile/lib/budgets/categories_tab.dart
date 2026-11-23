// The Categorías tab of home: the web's `CategoriesTab`
// (apps/web/app/features/categories/CategoriesTab.tsx), inside `.lk-panel` (a flex column with a gap
// of `--space-2`).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/gen/wambito_api.dart';
import '../categories/categories_actions.dart';
import '../categories/category_sheet.dart';
import '../home/category_look.dart';
import '../home/home_repository.dart';
import '../home/home_widgets.dart' show DashedBorderPainter;
import '../l10n/app_localizations.dart';
import '../theme/surfaces.dart';
import '../theme/text_styles.dart';
import '../theme/tokens.g.dart';
import '../ui/budget_bar.dart';
import '../ui/category_row.dart';
import '../ui/lk_icons.dart';
import '../ui/lk_theme.dart';
import '../ui/press_button.dart';
import '../ui/pressable.dart';
import '../ui/segmented_control.dart';
import '../ui/toast.dart';

/// How the API rates a category this month, as the bar takes it.
BudgetState budgetStateOf(SummaryCategoriesInnerStateEnum state) => switch (state) {
  SummaryCategoriesInnerStateEnum.near => BudgetState.near,
  SummaryCategoriesInnerStateEnum.over => BudgetState.over,
  _ => BudgetState.ok,
};

/// Where categories are managed (founder decision 2026-10-24; there is no separate page): a
/// Gastos | Ingresos switch ([kind], [onKind]); one row per category of that kind, in the categories'
/// own order, each opening its detail ([onOpen] gets its id): a spending category with its month's
/// budget bar (the figures are [summary]'s: never recomputed here), an income one with "Ingreso";
/// "Nueva categoría"; and the archived ones of that kind folded at the end ([showArchived],
/// [onToggleArchived]), each with "Restaurar". An archived spending category that has spending in
/// the month on screen is one of the rows instead, noted "archivada". Renaming, the emoji and
/// colour, and archiving are in the detail.
class CategoriesTab extends ConsumerWidget {
  const CategoriesTab({
    super.key,
    required this.summary,
    required this.categories,
    required this.currency,
    required this.kind,
    required this.onKind,
    required this.showArchived,
    required this.onToggleArchived,
    required this.onOpen,
  });

  final Summary summary;

  /// Every category by id (archived ones too).
  final Map<String, Category> categories;
  final String currency;

  /// Which kind is on screen.
  final CategoryKindEnum kind;
  final ValueChanged<CategoryKindEnum> onKind;
  final bool showArchived;
  final VoidCallback onToggleArchived;
  final void Function(String categoryId) onOpen;

  /// A spending category with no line in the summary (just made): no budget, nothing spent.
  static const _noLine = (budget: null, spent: 0, remaining: null);

  Future<void> _restore(BuildContext context, WidgetRef ref, Category category) async {
    final l10n = AppLocalizations.of(context);
    final toasts = ToastHost.of(context);
    try {
      await ref.read(categoriesActionsProvider).restore(category);
    } on HomeFailure catch (failure) {
      toasts.say(categoryFailureMessage(l10n, failure), error: true);
      return;
    }
    toasts.say(l10n.categoriesRestored(category.name));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final colors = context.lkColors;
    final lines = {for (final line in summary.categories) line.categoryId: line};
    final ofKind = [
      for (final (index, category) in categories.values.indexed)
        if (category.kind == kind) (index, category),
    ];
    // By the categories' own order, and the list's among equals (JavaScript's sort is stable).
    ofKind.sort((a, b) {
      final byOrder = a.$2.sortOrder.compareTo(b.$2.sortOrder);
      return byOrder != 0 ? byOrder : a.$1.compareTo(b.$1);
    });
    // An archived spending category with a line in the summary has spending in the month on screen
    // (the API keeps it only then): it stays among the rows, noted, as the web lists it; the rest
    // wait in the fold.
    bool spentThisMonth(Category category) =>
        kind == CategoryKindEnum.expense && category.archived && lines.containsKey(category.id);
    final active = [
      for (final (_, category) in ofKind)
        if (!category.archived || spentThisMonth(category)) category,
    ];
    final archived = [
      for (final (_, category) in ofKind)
        if (category.archived && !spentThisMonth(category)) category,
    ];
    final income = kind == CategoryKindEnum.income;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: WambitoTokens.space2,
      children: [
        SegmentedControl<CategoryKindEnum>(
          label: l10n.categoriesKindLabel,
          value: kind,
          options: [
            SegmentOption(
              CategoryKindEnum.expense,
              l10n.categoriesExpenses,
              key: const Key('categories.kind.expense'),
            ),
            SegmentOption(
              CategoryKindEnum.income,
              l10n.categoriesIncome,
              key: const Key('categories.kind.income'),
            ),
          ],
          onChanged: onKind,
        ),
        if (active.isEmpty)
          Text(
            income ? l10n.categoriesNoneOfKind : l10n.homeNoExpenseCategories,
            style: LkText.bodySm.copyWith(color: colors.inkMuted),
          )
        else
          for (final category in active) _row(l10n, category, lines[category.id], income),
        _AddRow(label: l10n.categoriesAdd, onAdd: () => unawaited(openCategorySheet(context))),
        if (archived.isNotEmpty)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: WambitoTokens.space2,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: PressButton(
                  key: const Key('categories.fold'),
                  tone: PressTone.secondary,
                  expanded: showArchived,
                  onPressed: onToggleArchived,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    spacing: WambitoTokens.space2,
                    children: [
                      ExcludeSemantics(child: Text(showArchived ? '▾' : '▸')),
                      Text(LkText.upperCase(l10n.categoriesArchivedFold(archived.length))),
                    ],
                  ),
                ),
              ),
              if (showArchived)
                Semantics(
                  container: true,
                  label: l10n.categoriesArchivedTitle,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: WambitoTokens.space2,
                    children: [
                      for (final category in archived) _archivedRow(context, ref, l10n, category),
                    ],
                  ),
                ),
            ],
          ),
      ],
    );
  }

  Widget _row(AppLocalizations l10n, Category category, SummaryCategoriesInner? line, bool income) {
    final look = categoryLook(icon: category.icon, color: category.color);
    return CategoryRow(
      key: ValueKey(category.id),
      name: category.name,
      glyph: look.glyph,
      tint: look.tint,
      budget: line?.budget ?? _noLine.budget,
      spent: line?.spent ?? _noLine.spent,
      remaining: line?.remaining ?? _noLine.remaining,
      state: line == null ? BudgetState.ok : budgetStateOf(line.state),
      currency: currency,
      line: income ? l10n.categoriesIncomeLine : null,
      note: category.archived ? l10n.budgetsArchivedNote : null,
      onOpen: () => onOpen(category.id),
    );
  }

  Widget _archivedRow(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
    Category category,
  ) {
    final look = categoryLook(icon: category.icon, color: category.color);
    return CategoryRow(
      key: ValueKey(category.id),
      name: category.name,
      glyph: look.glyph,
      tint: look.tint,
      budget: null,
      spent: 0,
      remaining: null,
      state: BudgetState.ok,
      currency: currency,
      line: l10n.categoryArchivedLine,
      onOpen: () => onOpen(category.id),
      control: PressButton(
        key: Key('categories.restore.${category.id}'),
        tone: PressTone.secondary,
        size: PressSize.sm,
        semanticLabel: l10n.categoriesRestoreNamed(category.name),
        onPressed: () => unawaited(_restore(context, ref, category)),
        child: Text(LkText.upperCase(l10n.categoriesRestore)),
      ),
    );
  }
}

/// "Nueva categoría" after the categories (and before the archived ones): a dashed row as wide as
/// them, its name written, so the page's one purple + stays the add-a-movement button. Making a
/// category is rare, so it waits where the list ends; with no category of the kind it sits right
/// under the line that says so. At least 48px tall, a thumb's target on both phones.
class _AddRow extends StatelessWidget {
  const _AddRow({required this.label, required this.onAdd});

  final String label;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final lk = context.lk;
    final colors = lk.colors;
    final radius = LkSurface.radius(LkRadius.lg);
    return Pressable(
      key: const Key('categories.add'),
      onPressed: onAdd,
      label: label,
      builder: (context, state) => RingBox(
        radius: state.focusVisible ? radius : null,
        color: colors.focus,
        child: CustomPaint(
          foregroundPainter: DashedBorderPainter(
            color: colors.stroke,
            radius: WambitoTokens.radiusLg,
            width: 2,
          ),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            constraints: const BoxConstraints(minHeight: 52),
            padding: const EdgeInsets.symmetric(
              horizontal: WambitoTokens.space3,
              vertical: WambitoTokens.space2,
            ),
            decoration: BoxDecoration(
              color: state.pressed ? colors.surfaceRow : const Color(0x00000000),
              borderRadius: radius,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              spacing: WambitoTokens.space2,
              children: [
                LkIcon(LkIconName.plus, size: 20, color: colors.ink),
                Flexible(
                  child: Text(label, style: LkText.cardTitle.copyWith(color: colors.ink)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
