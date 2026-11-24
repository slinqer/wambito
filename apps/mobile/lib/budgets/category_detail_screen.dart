// The web's CategoryDetail (apps/web/app/features/categories/CategoryDetail.tsx) and the CSS it
// uses: `ManageFrame`, `PageHeader`, `.lk-hero`, `.lk-tile`, `.lk-nudge`.
//
// Along with home's Categorías tab, this is where categories are managed: "Editar" opens the
// category sheet (rename, emoji and colour, archive) and an archived one says so and has "Restaurar".
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../add/add_sheet.dart';
import '../api/gen/wambito_api.dart';
import '../capture/capture_sheet.dart';
import '../categories/categories_actions.dart';
import '../categories/category_sheet.dart';
import '../feedback/feedback.dart';
import '../home/category_look.dart';
import '../home/day_groups.dart';
import '../home/home_controller.dart';
import '../home/home_format.dart';
import '../home/home_repository.dart';
import '../home/home_screen.dart' show HomeView, homeViewRequestProvider;
import '../home/home_widgets.dart';
import '../home/screen_error.dart';
import '../home/shell_navigation.dart';
import '../l10n/app_localizations.dart';
import '../money/format.dart';
import '../theme/surfaces.dart';
import '../theme/text_styles.dart';
import '../theme/tokens.g.dart';
import '../ui/app_shell.dart';
import '../ui/budget_bar.dart';
import '../ui/css_text.dart';
import '../ui/lk_theme.dart';
import '../ui/month_picker.dart';
import '../ui/page_header.dart';
import '../ui/press_button.dart';
import '../ui/press_link.dart';
import '../ui/swipe_row.dart';
import '../ui/toast.dart';
import '../ui/transaction_row.dart';
import 'budget_sheet.dart';
import 'categories_tab.dart';
import 'category_detail_controller.dart';
import '../ui/tile_glyph.dart';

/// The widest the content grows on a big screen (the web's `max-w-[480px]`, padding included).
const _maxContentWidth = 480.0;

/// What a screen opening a category's detail from home's Categorías tab passes as the route's
/// `extra`: "back" then says "Volver a Categorías" (the web's `DetailState`).
const detailFromCategories = 'categories';

/// The kind line under a category's name: `text-[13px] font-bold`, Nunito 13px 700.
final _kindLineStyle = LkText.bodySm.copyWith(fontSize: 13);

final _monthFormat = RegExp(r'^\d{4}-(0[1-9]|1[0-2])$');

/// A category's detail (`/categories/:id`, spec section 2.7): the month on screen (`?month=`, home's
/// month when opened from a budget row; never past the current one), the budget in force that
/// month with a change that applies from it on, and the category's movements that month (each opens
/// the edit sheet; the web's swipes work too).
///
/// "Editar" changes the category's name, emoji and colour and archives it, after asking; an archived
/// category says so and can be restored. [fromCategories]: it was opened from home's Categorías
/// tab, so "back" says so (the web's `DetailState`).
class CategoryDetailScreen extends ConsumerStatefulWidget {
  const CategoryDetailScreen({
    super.key,
    required this.categoryId,
    this.initialMonth,
    this.fromCategories = false,
  });

  final String categoryId;

  /// The month to open on (`YYYY-MM`), or null for the current one.
  final String? initialMonth;

  final bool fromCategories;

  @override
  ConsumerState<CategoryDetailScreen> createState() => _CategoryDetailScreenState();
}

class _CategoryDetailScreenState extends ConsumerState<CategoryDetailScreen> {
  /// The month the person stepped to; null: the one the screen opened on.
  String? _chosen;
  var _started = false;

  CategoryDetailController get _controller =>
      ref.read(categoryDetailProvider(widget.categoryId).notifier);

  /// The month on screen, once known.
  String? _shownMonth;

  String _monthFor(String current) {
    final asked = _chosen ?? widget.initialMonth ?? '';
    return _monthFormat.hasMatch(asked) && asked.compareTo(current) <= 0 ? asked : current;
  }

  void _back() {
    final router = GoRouter.of(context);
    if (router.canPop()) {
      router.pop();
    } else {
      router.go('/');
    }
  }

  void _step(String month) {
    setState(() => _chosen = month);
    unawaited(_controller.showMonth(month));
  }

  String _failureMessage(AppLocalizations l10n, HomeFailure failure) =>
      failure.offline ? l10n.errorNetwork : l10n.errorGeneric;

  /// "Ver mis categorías": back to home, on its Categorías tab.
  void _toCategories() {
    ref.read(homeViewRequestProvider.notifier).show(HomeView.budgets);
    _back();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final home = ref.watch(homeProvider);
    final data = home.data;
    // Whatever changes the month's movements or figures (a movement added from the ＋, the 🎤 or
    // the empty month's button, an edit, a Deshacer of either) goes through home: the detail's
    // list and bar catch up, as the web's queries do when they are invalidated.
    ref.listen(homeProvider.select((s) => (s.data?.summary, s.data?.items)), (previous, _) {
      if (previous != null && _started) unawaited(_controller.refresh());
    });

    final Widget body;
    if (data == null) {
      body = home.failure != null
          ? ScreenError(
              message: _failureMessage(l10n, home.failure!),
              retryLabel: l10n.retry,
              onRetry: () => unawaited(ref.read(homeProvider.notifier).refresh()),
            )
          : const SizedBox.shrink();
      return _frame(context, body);
    }
    final current = data.todayAt(ref.read(clockProvider)()).substring(0, 7);
    final month = _shownMonth = _monthFor(current);
    if (!_started) {
      _started = true;
      // Not while the tree builds: the controller changes state.
      scheduleMicrotask(() {
        if (mounted) unawaited(_controller.showMonth(month));
      });
    }
    final detail = ref.watch(categoryDetailProvider(widget.categoryId));
    final category = data.categories[widget.categoryId];
    final picker = MonthPicker(month: month, max: current, onChange: _step);
    final header = PageHeader(
      backLabel: widget.fromCategories ? l10n.manageBackCategories : l10n.manageBack,
      backShort: widget.fromCategories ? l10n.manageBackCategoriesShort : l10n.manageBackShort,
      onBack: _back,
      aside: category == null ? null : picker,
    );

    final List<Widget> children;
    if (category == null) {
      children = [header, _NotFound(onCategories: _toCategories)];
    } else if (detail.failure != null) {
      children = [
        header,
        ScreenError(
          message: _failureMessage(l10n, detail.failure!),
          retryLabel: l10n.retry,
          onRetry: () => unawaited(_controller.showMonth(month)),
        ),
      ];
    } else {
      children = [
        header,
        _DetailView(
          key: ValueKey(category.id),
          category: category,
          detail: detail,
          month: month,
          today: data.todayAt(ref.read(clockProvider)()),
          currency: data.currency,
          controller: _controller,
        ),
      ];
    }
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
                          children: children,
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

  Widget _frame(BuildContext context, Widget child) => AppShell(
    // The web marks no tab on a category's page (its section is Categorías).
    current: 'categories',
    addKey: const Key('home.add'),
    micKey: const Key('home.capture'),
    onAdd: () => unawaited(openAddSheet(context)),
    onMic: () => unawaited(openCapture(context, listen: true)),
    // Análisis opens on the month the detail is on.
    onNavigate: (to) =>
        navigateFromShell(context, ref, to, current: 'categories', month: _shownMonth),
    child: SafeArea(bottom: false, child: child),
  );
}

class _NotFound extends StatelessWidget {
  const _NotFound({required this.onCategories});

  final VoidCallback onCategories;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.lkColors;
    return HeroCard(
      padding: const EdgeInsets.fromLTRB(
        WambitoTokens.space4,
        WambitoTokens.space3,
        WambitoTokens.space4,
        WambitoTokens.space4,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: WambitoTokens.space2,
        children: [
          Text(
            l10n.categoryNotFoundTitle,
            style: LkText.title.copyWith(fontSize: 22, height: 1.5, color: colors.ink),
          ),
          Text(l10n.categoryNotFoundLead, style: LkText.bodySm.copyWith(color: colors.inkMuted)),
          PressLink.text(l10n.categoryToCategories, onPressed: onCategories),
        ],
      ),
    );
  }
}

/// The web's `DetailView`: the category's name, its budget (or what came in), and its movements.
class _DetailView extends ConsumerStatefulWidget {
  const _DetailView({
    super.key,
    required this.category,
    required this.detail,
    required this.month,
    required this.today,
    required this.currency,
    required this.controller,
  });

  final Category category;
  final CategoryDetailState detail;
  final String month;
  final String today;
  final String currency;
  final CategoryDetailController controller;

  @override
  ConsumerState<_DetailView> createState() => _DetailViewState();
}

class _DetailViewState extends ConsumerState<_DetailView> {
  Category get _category => widget.category;
  CategoryDetailController get _controller => widget.controller;

  String _failureMessage(AppLocalizations l10n, HomeFailure failure) =>
      failure.offline ? l10n.errorNetwork : l10n.errorGeneric;

  /// The edit sheet saves through home, which the detail follows (see the screen's `ref.listen`).
  Future<void> _edit(Transaction tx) => openEditSheet(context, tx);

  Future<void> _delete(Transaction tx) async {
    final toasts = ToastHost.of(context);
    final l10n = AppLocalizations.of(context);
    // Deshacer outlives this screen (the toast sits above the router): it goes through home's
    // controller, as the add and capture sheets do, never through this screen's `ref`.
    final container = ProviderScope.containerOf(context);
    ref.read(feedbackProvider)(FeedbackEvent.deleted);
    try {
      await _controller.remove(tx);
    } on HomeFailure catch (failure) {
      toasts.say(_failureMessage(l10n, failure), error: true);
      return;
    }
    toasts.say(
      l10n.transactionDeleted(tx.name),
      actionLabel: l10n.undo,
      onAction: () => unawaited(_restore(container, toasts, l10n, tx)),
    );
  }

  Future<void> _restore(
    ProviderContainer container,
    ToastController toasts,
    AppLocalizations l10n,
    Transaction tx,
  ) async {
    try {
      await container.read(homeProvider.notifier).restore(tx);
    } on HomeFailure catch (failure) {
      toasts.say(_failureMessage(l10n, failure), error: true);
      return;
    }
    container.read(feedbackProvider)(FeedbackEvent.undo);
    // Still here: the row slides in. Gone: home has it, and the detail loads afresh when opened.
    if (mounted) _controller.showRestored(tx);
    toasts.say(l10n.transactionRestored(tx.name));
  }

  /// Marks [tx] paid. Rethrows a failure after saying it, so the badge goes back to "Pendiente".
  Future<void> _pay(Transaction tx) async {
    final toasts = ToastHost.of(context);
    final l10n = AppLocalizations.of(context);
    try {
      await _controller.markPaid(tx);
    } on HomeFailure catch (failure) {
      toasts.say(_failureMessage(l10n, failure), error: true);
      rethrow;
    }
    if (mounted) ref.read(feedbackProvider)(FeedbackEvent.paid);
    toasts.say(
      l10n.transactionPaid(tx.name, formatMoney(tx.amount, widget.currency, l10n.localeName)),
    );
  }

  /// "Restaurar" on an archived category: it comes back, and a toast says so. A failure says why.
  void _restoreCategory() {
    final toasts = ToastHost.of(context);
    final l10n = AppLocalizations.of(context);
    final actions = ref.read(categoriesActionsProvider);
    unawaited(() async {
      try {
        await actions.restore(_category);
      } on HomeFailure catch (failure) {
        toasts.say(categoryFailureMessage(l10n, failure), error: true);
        return;
      }
      toasts.say(l10n.categoriesRestored(_category.name));
    }());
  }

  Future<void> _loadMore() async {
    final toasts = ToastHost.of(context);
    final l10n = AppLocalizations.of(context);
    try {
      await _controller.loadMore();
    } on HomeFailure catch (failure) {
      toasts.say(_failureMessage(l10n, failure), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.lkColors;
    final category = _category;
    final look = categoryLook(icon: category.icon, color: category.color);
    final income = category.kind == CategoryKindEnum.income;
    final kindLine =
        '${income ? l10n.categoryKindIncome : l10n.categoryKindExpense}'
        '${category.archived ? ' · ${l10n.categoryArchivedLine}' : ''}';
    final nameStyle = TextStyle(
      fontFamily: LkText.displayFamily,
      fontSize: 26,
      fontWeight: FontWeight.w700,
      height: 1.25,
      leadingDistribution: TextLeadingDistribution.even,
    );
    final detail = widget.detail;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: WambitoTokens.space3,
      children: [
        Row(
          spacing: WambitoTokens.space3,
          children: [
            ExcludeSemantics(
              child: Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  // `color-mix(in srgb, tint 45%, var(--surface-sunken))`.
                  color: Color.lerp(colors.surfaceSunken, look.tint, 0.45),
                  borderRadius: LkSurface.radius(LkRadius.sm),
                ),
                child: TileGlyph(look.glyph, size: 24, color: colors.ink),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Semantics(
                    header: true,
                    child: CssLines(
                      style: nameStyle,
                      child: BlinkLine(
                        style: nameStyle,
                        child: Text(
                          category.name,
                          key: const Key('detail.title'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: nameStyle.copyWith(color: colors.ink),
                        ),
                      ),
                    ),
                  ),
                  // `<p className="m-0 text-[13px] font-bold text-ink-muted">`: 13px, 700.
                  CssLines(
                    style: _kindLineStyle,
                    child: Text(kindLine, style: _kindLineStyle.copyWith(color: colors.inkMuted)),
                  ),
                ],
              ),
            ),
            PressButton.text(
              l10n.categoryEditShort,
              key: const Key('detail.edit'),
              tone: PressTone.secondary,
              size: PressSize.sm,
              semanticLabel: l10n.categoryEditLabel,
              onPressed: () => unawaited(openCategorySheet(context, editing: category)),
            ),
          ],
        ),
        if (category.archived) _ArchivedNote(onRestore: _restoreCategory),
        if (!income)
          _BudgetCard(
            key: const Key('detail.budget'),
            line: detail.line(category.id),
            loaded: detail.summary != null,
            month: widget.month,
            currency: widget.currency,
            archived: category.archived,
            onEdit: () => unawaited(
              openBudgetSheet(
                context,
                categoryId: category.id,
                categoryName: category.name,
                month: widget.month,
                budget: detail.line(category.id)?.budget,
                currency: widget.currency,
              ),
            ),
          )
        else
          _IncomeCard(
            month: widget.month,
            currency: widget.currency,
            total: detail.items == null ? null : detail.income,
          ),
        _Movements(
          category: category,
          detail: detail,
          month: widget.month,
          today: widget.today,
          currency: widget.currency,
          onEdit: _edit,
          onDelete: _delete,
          onPay: _pay,
          onMore: _loadMore,
          onSettled: _controller.settleRestored,
        ),
      ],
    );
  }
}

/// `.lk-nudge`'s archived note: what an archived category means, and "Restaurar".
class _ArchivedNote extends StatelessWidget {
  const _ArchivedNote({required this.onRestore});

  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.lkColors;
    return Semantics(
      container: true,
      label: l10n.categoryArchivedLine,
      child: CustomPaint(
        // `.lk-nudge`: `border: 2px dashed var(--stroke)`.
        foregroundPainter: DashedBorderPainter(
          color: colors.stroke,
          radius: WambitoTokens.radiusLg,
          width: 2,
          bottomPhase: 4,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surfaceRow,
            borderRadius: BorderRadius.circular(WambitoTokens.radiusLg),
          ),
          child: Padding(
            // `padding: var(--space-3)` inside the 2px border.
            padding: const EdgeInsets.all(WambitoTokens.space3 + 2),
            child: Row(
              spacing: WambitoTokens.space3,
              children: [
                Expanded(
                  child: Text(
                    l10n.categoryArchivedNote,
                    style: LkText.bodySm.copyWith(color: colors.ink),
                  ),
                ),
                PressButton.text(
                  l10n.categoriesRestore,
                  key: const Key('detail.restore'),
                  tone: PressTone.secondary,
                  size: PressSize.sm,
                  onPressed: onRestore,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The web's `BudgetCard`: the budget in force that month in words and as a bar, with the button
/// that changes it (not for an archived category).
class _BudgetCard extends StatelessWidget {
  const _BudgetCard({
    super.key,
    required this.line,
    required this.loaded,
    required this.month,
    required this.currency,
    required this.archived,
    required this.onEdit,
  });

  final SummaryCategoriesInner? line;
  final bool loaded;
  final String month;
  final String currency;
  final bool archived;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.lkColors;
    final locale = l10n.localeName;
    String money(int cents) => formatMoney(cents, currency, locale);
    final monthName = monthInSentence(month, locale);
    final budget = line?.budget;
    final spent = line?.spent ?? 0;
    final remaining = line?.remaining;
    final state = line == null ? BudgetState.ok : budgetStateOf(line!.state);
    final over = budget != null && state == BudgetState.over;
    final meta = LkText.meta.copyWith(color: colors.inkMuted);
    const amountStyle = TextStyle(
      fontFamily: LkText.displayFamily,
      fontSize: 28,
      fontWeight: FontWeight.w700,
      height: 1.5,
      leadingDistribution: TextLeadingDistribution.even,
    );

    final Widget content;
    if (!loaded) {
      content = const SizedBox(height: 72);
    } else if (budget == null) {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: WambitoTokens.space2,
        children: [
          CssLines(
            style: LkText.body,
            child: Text(
              l10n.categoryNoBudget(monthName),
              style: LkText.body.copyWith(color: colors.ink),
            ),
          ),
          if (spent != 0)
            CssLines(
              style: LkText.meta,
              child: Text(l10n.categorySpent(monthName, money(spent)), style: meta),
            ),
        ],
      );
    } else {
      final left = remaining ?? budget - spent;
      final status = over
          ? l10n.categoryRowOver(money(left.abs()))
          : l10n.categoryRowRemaining(money(left));
      final spentOf = l10n.categorySpentOf(money(spent), money(budget));
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: WambitoTokens.space2,
        children: [
          CssLines(
            style: amountStyle,
            child: Text(
              status,
              style: amountStyle.copyWith(color: over ? colors.over : colors.good),
            ),
          ),
          BudgetBar(spent: spent, budget: budget, state: state, label: spentOf),
          CssLines(
            style: LkText.meta,
            child: Text(spentOf, style: meta),
          ),
        ],
      );
    }

    return Semantics(
      container: true,
      label: l10n.categoryBudgetTitle,
      child: HeroCard(
        padding: const EdgeInsets.fromLTRB(
          WambitoTokens.space4,
          WambitoTokens.space3,
          WambitoTokens.space4,
          WambitoTokens.space4,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: WambitoTokens.space2,
          children: [
            Semantics(
              header: true,
              child: CssLines(
                style: LkText.heroLabel,
                child: Text(
                  l10n.categoryBudgetTitle,
                  style: LkText.heroLabel.copyWith(color: colors.inkMuted),
                ),
              ),
            ),
            content,
            if (!archived)
              Align(
                alignment: Alignment.centerLeft,
                child: PressButton.text(
                  budget == null ? l10n.categorySetBudget : l10n.categoryChangeBudget,
                  key: const Key('detail.changeBudget'),
                  tone: PressTone.secondary,
                  onPressed: loaded ? onEdit : null,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// What came in to an income category that month, from the month's totals per income category.
class _IncomeCard extends StatelessWidget {
  const _IncomeCard({required this.month, required this.currency, required this.total});

  final String month;
  final String currency;

  /// Null while it loads.
  final int? total;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.lkColors;
    const style = TextStyle(
      fontFamily: LkText.displayFamily,
      fontSize: 22,
      fontWeight: FontWeight.w700,
      height: 1.5,
      leadingDistribution: TextLeadingDistribution.even,
    );
    return HeroCard(
      padding: const EdgeInsets.fromLTRB(
        WambitoTokens.space4,
        WambitoTokens.space3,
        WambitoTokens.space4,
        WambitoTokens.space4,
      ),
      child: Text(
        l10n.categoryReceived(
          monthInSentence(month, l10n.localeName),
          formatMoney(total ?? 0, currency, l10n.localeName),
        ),
        style: style.copyWith(color: colors.good),
      ),
    );
  }
}

/// The category's movements of the month, by day, then "Ver más movimientos" (or the empty state).
class _Movements extends StatelessWidget {
  const _Movements({
    required this.category,
    required this.detail,
    required this.month,
    required this.today,
    required this.currency,
    required this.onEdit,
    required this.onDelete,
    required this.onPay,
    required this.onMore,
    required this.onSettled,
  });

  final Category category;
  final CategoryDetailState detail;
  final String month;
  final String today;
  final String currency;
  final void Function(Transaction) onEdit;
  final void Function(Transaction) onDelete;
  final Future<void> Function(Transaction) onPay;
  final VoidCallback onMore;
  final void Function(String id) onSettled;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.lkColors;
    final locale = l10n.localeName;
    final monthName = monthInSentence(month, locale);
    final items = detail.items;
    const titleStyle = TextStyle(
      fontFamily: LkText.displayFamily,
      fontSize: 20,
      fontWeight: FontWeight.w700,
      height: 1.5,
      leadingDistribution: TextLeadingDistribution.even,
    );
    final glyph = categoryLook(icon: category.icon, color: category.color).glyph;

    final List<Widget> rows;
    if (items == null) {
      rows = const [SizedBox(height: 120)];
    } else if (items.isEmpty) {
      rows = [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: WambitoTokens.space3,
          children: [
            Text(
              l10n.categoryEmpty(category.name, monthName),
              style: LkText.bodySm.copyWith(color: colors.inkMuted),
            ),
            if (!category.archived)
              PressButton.text(
                category.kind == CategoryKindEnum.income
                    ? l10n.categoryAddIncome
                    : l10n.categoryAddExpense,
                tone: PressTone.secondary,
                onPressed: () => unawaited(
                  openAddSheet(
                    context,
                    kind: category.kind == CategoryKindEnum.income ? Kind.income : Kind.expense,
                    categoryId: category.id,
                  ),
                ),
              ),
          ],
        ),
      ];
    } else {
      rows = [
        for (final group in groupByDay(items, today)) ...[
          DayHeading(
            label: dayHeadingLabel(l10n, group),
            total: formatMoney(
              group.total,
              currency,
              locale,
              sign: group.total > 0 ? MoneySign.always : MoneySign.auto,
            ),
          ),
          for (final tx in group.items) _row(context, l10n, tx, glyph),
        ],
        if (detail.nextCursor != null)
          Center(
            child: PressButton.text(
              l10n.homeMoreTransactions,
              tone: PressTone.secondary,
              onPressed: detail.loadingMore ? null : onMore,
            ),
          ),
      ];
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: CssLines(
            style: titleStyle,
            child: Text(
              l10n.categoryTransactionsTitle(monthName),
              style: titleStyle.copyWith(color: colors.ink),
            ),
          ),
        ),
        // The rows and day headings carry their own gaps (`gap-2`), as on home.
        const SizedBox(height: WambitoTokens.space2),
        ...rows,
      ],
    );
  }

  Widget _row(BuildContext context, AppLocalizations l10n, Transaction tx, String glyph) {
    final pending = tx.status == TransactionStatusEnum.pending;
    return SwipeRow(
      key: ValueKey(tx.id),
      gap: WambitoTokens.space2,
      enter: detail.restored.contains(tx.id),
      onEntered: () => onSettled(tx.id),
      deleteLabel: l10n.swipeDelete,
      onDelete: () => onDelete(tx),
      right: pending
          ? SwipeRight(
              SwipeRightKind.paid,
              // Paid once: a second quick swipe (or the badge) never pays it again.
              () => unawaited(onPay(tx).then((_) {}, onError: (Object _) {})),
              l10n.swipePaid,
            )
          : SwipeRight(SwipeRightKind.edit, () => onEdit(tx), l10n.swipeEdit),
      child: TransactionRow(
        name: tx.name,
        categoryName: category.name,
        glyph: glyph,
        amount: tx.amount,
        currency: currency,
        status: pending ? TransactionRowStatus.pending : TransactionRowStatus.paid,
        paidHere: detail.paidHere.contains(tx.id),
        onOpen: () => onEdit(tx),
        onPay: () => onPay(tx),
      ),
    );
  }
}
