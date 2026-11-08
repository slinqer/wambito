// The web's Search (apps/web/app/features/search/Search.tsx).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LengthLimitingTextInputFormatter;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../add/add_sheet.dart';
import '../api/gen/wambito_api.dart';
import '../capture/capture_sheet.dart';
import '../home/category_look.dart';
import '../home/day_groups.dart';
import '../home/home_controller.dart';
import '../home/home_format.dart';
import '../home/home_widgets.dart' show DayHeading, QuietSpinner;
import '../home/screen_error.dart';
import '../home/shell_navigation.dart';
import '../home/wambi_face.dart';
import '../l10n/app_localizations.dart';
import '../money/format.dart';
import '../review/review_mark.dart';
import '../theme/text_styles.dart';
import '../theme/tokens.g.dart';
import '../ui/category_chip.dart';
import '../ui/failure_row.dart';
import '../ui/lk_theme.dart';
import '../ui/manage_page.dart';
import '../ui/page_header.dart';
import '../ui/press_button.dart';
import '../ui/segmented_control.dart';
import '../ui/sheet.dart';
import '../ui/transaction_row.dart';
import '../ui/wambi_bubble.dart';
import '../ui/web_text_field.dart';
import 'search_controller.dart';
import 'search_repository.dart';

/// How a tapped result is edited; tests replace it.
final searchOpenEditProvider = Provider<Future<void> Function(BuildContext, Transaction)>(
  (ref) =>
      (context, tx) => openEditSheet(context, tx),
);

/// `/search`: movements across every month, by name or note, kind, category and status. The text
/// reaches the server 300 ms after the last key (the controller's debounce); results are home's
/// days and rows with the server's totals above them. The next page loads when the end is near.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _text = TextEditingController();
  final _focus = FocusNode(debugLabel: 'search');
  final _scroll = ScrollController();

  /// How close to the end the next page is asked for.
  static const _nearEnd = 300.0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_maybeLoadMore);
  }

  @override
  void dispose() {
    _scroll
      ..removeListener(_maybeLoadMore)
      ..dispose();
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _back() {
    final router = GoRouter.of(context);
    if (router.canPop()) {
      router.pop();
    } else {
      router.go('/');
    }
  }

  void _maybeLoadMore() {
    if (!_scroll.hasClients) return;
    final state = ref.read(searchControllerProvider);
    if (state.nextCursor == null || state.failure != null) return;
    if (_scroll.position.extentAfter < _nearEnd) {
      unawaited(ref.read(searchControllerProvider.notifier).loadMore());
    }
  }

  /// A short page that does not fill the screen has no scrolling to ask for the next one.
  void _afterFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _maybeLoadMore();
    });
  }

  Future<void> _edit(Transaction tx) async {
    await ref.read(searchOpenEditProvider)(context, tx);
    if (!mounted) return;
    await ref.read(searchControllerProvider.notifier).refresh();
  }

  Future<void> _pickCategories(List<Category> categories) async {
    final l10n = AppLocalizations.of(context);
    final ordered = [...categories]
      ..sort((a, b) {
        final byArchived = (a.archived ? 1 : 0) - (b.archived ? 1 : 0);
        return byArchived != 0 ? byArchived : a.sortOrder - b.sortOrder;
      });
    await LkSheet.show<void>(
      context,
      title: l10n.searchCategory,
      footer: [
        Builder(
          builder: (context) => PressButton.text(
            l10n.searchDone,
            key: const Key('search.done'),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
      ],
      children: [_CategoryChoices(categories: ordered)],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.lkColors;
    final search = ref.watch(searchControllerProvider);
    final controller = ref.read(searchControllerProvider.notifier);
    final home = ref.watch(homeProvider);
    final data = home.data;
    final filters = search.filters;
    _afterFrame();

    Widget results;
    if (data == null) {
      results = home.failure != null
          ? ScreenError(
              message: home.failure!.offline ? l10n.errorNetwork : l10n.errorGeneric,
              retryLabel: l10n.retry,
              onRetry: () => unawaited(ref.read(homeProvider.notifier).refresh()),
            )
          : const Center(child: QuietSpinner(size: 28));
    } else {
      results = _results(l10n, data, search);
    }

    return ManagePage(
      key: const Key('search.page'),
      current: 'search',
      controller: _scroll,
      onAdd: () => unawaited(openAddSheet(context)),
      onMic: () => unawaited(openCapture(context, listen: true)),
      onNavigate: (to) => navigateFromShell(context, ref, to, current: 'search'),
      header: PageHeader(
        backLabel: l10n.manageBack,
        backShort: l10n.manageBackShort,
        onBack: _back,
      ),
      mainGap: WambitoTokens.space3,
      children: [
        Semantics(
          header: true,
          child: Text(l10n.searchTitle, style: LkText.pageTitle.copyWith(color: colors.ink)),
        ),
        WebTextField(
          controller: _text,
          focusNode: _focus,
          fieldKey: const Key('search.field'),
          label: l10n.searchPlaceholder,
          placeholder: l10n.searchPlaceholder,
          autofocus: true,
          enableSuggestions: true,
          inputMinHeight: 24,
          leading: const ExcludeSemantics(child: Text('🔍')),
          textInputAction: TextInputAction.search,
          inputFormatters: [LengthLimitingTextInputFormatter(searchMaxText)],
          onChanged: controller.setText,
        ),
        SegmentedControl<SearchKind>(
          label: l10n.searchKind,
          value: filters.kind,
          options: [
            SegmentOption(SearchKind.all, l10n.searchKindAll, key: const Key('search.kind.all')),
            SegmentOption(
              SearchKind.expense,
              l10n.searchKindExpense,
              key: const Key('search.kind.expense'),
            ),
            SegmentOption(
              SearchKind.income,
              l10n.searchKindIncome,
              key: const Key('search.kind.income'),
            ),
          ],
          onChanged: controller.setKind,
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: PressButton.text(
            filters.categoryIds.isEmpty
                ? l10n.searchCategory
                : l10n.searchCategoryCount(filters.categoryIds.length),
            key: const Key('search.categories'),
            tone: PressTone.secondary,
            size: PressSize.sm,
            onPressed: data == null
                ? null
                : () => unawaited(_pickCategories(data.categories.values.toList())),
          ),
        ),
        SegmentedControl<SearchStatus>(
          label: l10n.searchStatus,
          value: filters.status,
          options: [
            SegmentOption(
              SearchStatus.all,
              l10n.searchStatusAll,
              key: const Key('search.status.all'),
            ),
            SegmentOption(
              SearchStatus.paid,
              l10n.searchStatusPaid,
              key: const Key('search.status.paid'),
            ),
            SegmentOption(
              SearchStatus.pending,
              l10n.searchStatusPending,
              key: const Key('search.status.pending'),
            ),
          ],
          onChanged: controller.setStatus,
        ),
        results,
      ],
    );
  }

  Widget _results(AppLocalizations l10n, HomeData data, SearchState search) {
    final colors = context.lkColors;
    final controller = ref.read(searchControllerProvider.notifier);
    if (!search.filters.isSearching) {
      return WambiBubble(message: l10n.searchHint, mood: WambiMood.happy);
    }
    final failure = search.failure;
    if (failure != null && search.items.isEmpty) {
      return SaveFailureRow(
        key: const Key('search.failure'),
        message: failure.offline ? l10n.errorNetwork : l10n.errorGeneric,
        retryLabel: l10n.retry,
        retryKey: const Key('search.retry'),
        onRetry: () => unawaited(controller.retry()),
      );
    }
    if (search.loading && search.items.isEmpty) {
      return const SizedBox(height: 120);
    }
    if (search.items.isEmpty) {
      final text = search.filters.text.trim();
      return WambiBubble(
        message: text.isNotEmpty ? l10n.searchNone(text) : l10n.searchNoneFilters,
        mood: WambiMood.worried,
      );
    }
    final locale = l10n.localeName;
    final today = data.todayAt(ref.read(clockProvider)());
    final totals = search.totals;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: WambitoTokens.space3,
      children: [
        if (totals != null)
          Semantics(
            liveRegion: true,
            child: Text(
              l10n.searchTotals(
                totals.count,
                formatMoney(totals.expense, data.currency, locale),
                formatMoney(totals.income, data.currency, locale),
              ),
              key: const Key('search.totals'),
              style: LkText.bodySm.copyWith(fontWeight: FontWeight.w700, color: colors.inkMuted),
            ),
          ),
        for (final group in groupNewestFirst(search.items, today)) ...[
          DayHeading(
            label: switch (group.when) {
              DayWhen.today => l10n.homeDayToday(formatDay(group.date, locale)),
              DayWhen.yesterday => l10n.homeDayYesterday(formatDay(group.date, locale)),
              DayWhen.upcoming => l10n.homeDayUpcoming(formatDay(group.date, locale)),
              DayWhen.past => formatDay(group.date, locale),
            },
            total: formatMoney(
              group.total,
              data.currency,
              locale,
              sign: group.total > 0 ? MoneySign.always : MoneySign.auto,
            ),
          ),
          for (final tx in group.items) _row(l10n, data, tx),
        ],
        if (failure != null)
          SaveFailureRow(
            key: const Key('search.failure'),
            message: failure.offline ? l10n.errorNetwork : l10n.errorGeneric,
            retryLabel: l10n.retry,
            retryKey: const Key('search.retry'),
            onRetry: () => unawaited(controller.retry()),
          )
        else if (search.loadingMore)
          const Center(child: QuietSpinner(size: 24)),
      ],
    );
  }

  Widget _row(AppLocalizations l10n, HomeData data, Transaction tx) {
    final category = data.categories[tx.categoryId];
    return TransactionRow(
      key: ValueKey(tx.id),
      name: tx.name,
      categoryName: category?.name ?? '',
      glyph: category == null
          ? '🏷️'
          : categoryLook(icon: category.icon, color: category.color).glyph,
      amount: tx.amount,
      currency: data.currency,
      status: tx.status == TransactionStatusEnum.pending
          ? TransactionRowStatus.pending
          : TransactionRowStatus.paid,
      reviewMark: reviewMarkOf(l10n, tx),
      onOpen: () => unawaited(_edit(tx)),
    );
  }
}

/// Every category (archived ones last, marked): any number can be on at once, up to the API's
/// limit. Follows the controller, so a tap shows at once.
class _CategoryChoices extends ConsumerWidget {
  const _CategoryChoices({required this.categories});

  final List<Category> categories;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final selected = ref.watch(searchControllerProvider.select((s) => s.filters.categoryIds));
    final controller = ref.read(searchControllerProvider.notifier);
    return Semantics(
      container: true,
      label: l10n.searchCategory,
      child: CategoryChipGrid(
        children: [
          for (final c in categories)
            CategoryChip(
              key: Key('category.${c.id}'),
              glyph: categoryLook(icon: c.icon, color: c.color).glyph,
              label: c.name,
              note: c.archived ? l10n.addArchived : null,
              selected: selected.contains(c.id),
              onSelect: () {
                if (selected.contains(c.id)) {
                  controller.setCategories({...selected}..remove(c.id));
                } else if (selected.length < searchMaxCategories) {
                  controller.setCategories({...selected, c.id});
                }
              },
            ),
        ],
      ),
    );
  }
}
