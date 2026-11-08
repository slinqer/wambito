import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderAbstractViewport;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../add/add_repository.dart' show TransactionPatch;
import '../add/add_sheet.dart';
import '../add/save_outcome.dart' show deleteUnsent, uploadedRow;
import '../api/gen/wambito_api.dart';
import '../budgets/category_detail_screen.dart' show detailFromCategories;
import '../budgets/categories_tab.dart';
import '../capture/capture_sheet.dart';
import '../feedback/feedback.dart';
import '../l10n/app_localizations.dart';
import '../money/format.dart';
import '../offline/pending_saves.dart';
import '../review/review_controller.dart';
import '../review/review_home_row.dart';
import '../review/review_mark.dart';
import '../theme/surfaces.dart';
import '../theme/text_styles.dart';
import '../theme/theme.dart';
import '../theme/tokens.g.dart';
import '../ui/app_shell.dart';
import '../ui/lk_theme.dart';
import '../ui/wambi_bubble.dart';
import '../ui/press_button.dart';
import '../ui/segmented_control.dart';
import '../ui/swipe_row.dart';
import '../ui/toast.dart';
import '../ui/transaction_row.dart';
import 'category_look.dart';
import 'day_groups.dart';
import 'home_controller.dart';
import 'home_format.dart';
import 'home_header.dart';
import 'home_repository.dart';
import 'home_widgets.dart';
import 'wambi_line.dart';
import 'wambi_face.dart';
import 'nudges.dart';
import 'screen_error.dart';
import 'shell_navigation.dart';

/// Picks which of Wambi's three phrasings a line uses (1 to 3). Replaced in tests.
final wambiVariantProvider = Provider<int Function()>((ref) {
  final random = math.Random();
  return () => 1 + random.nextInt(3);
});

/// How long Wambi celebrates a save or a payment (the web's `CELEBRATE_MS`).
const _celebrateFor = Duration(milliseconds: 2500);

/// The widest the content grows on a big screen (the web's `max-w-[480px]`, padding included).
const _maxContentWidth = 480.0;

/// The two lists under the hero: Movimientos first.
enum HomeView { transactions, budgets }

/// A tab to show on home, asked from outside it: the face menu's Categorías (the web's link to its
/// categories page is, in the app, home's Categorías tab), or a screen that sends the person there.
/// Home takes the request when it sees it (at once, or when it opens), shows the tab and clears it,
/// so asking for the same tab twice works the second time too.
class HomeViewRequest extends Notifier<HomeView?> {
  @override
  HomeView? build() => null;

  /// Asks home to show [view].
  void show(HomeView view) => state = view;

  /// Home has taken it.
  void clear() => state = null;
}

final homeViewRequestProvider = NotifierProvider<HomeViewRequest, HomeView?>(HomeViewRequest.new);

/// Home (spec section 6.1.2), as the web draws it (apps/web/app/features/home/Home.tsx): the
/// header (the wordmark, the month with ‹ ›, the face button), Wambi's line, "Te quedan" (or,
/// without budgets, "Gastado este mes") in large type, a card or two for an account that skipped
/// the setup, and under the Movimientos | Categorías tabs the movements by day, with the web's
/// gestures: swipe left deletes (with an 8 s Deshacer), swipe right edits, or marks a pending row
/// paid. Wambi names a save or a payment for 10 s, then goes back to the month's line. The last
/// figures stay on screen while offline. The bottom bar has Inicio, ＋ (the add sheet), the 🎤
/// (quick capture, listening) and Análisis.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key, this.onEdit, this.menu, this.initialMonth});

  /// What the face button's menu holds, as [HomeMenuLink]s: Recurrentes, Categorías, Ajustes, and a guest's "Guarda tu
  /// progreso". Null (tests, goldens): no menu.
  final Widget Function(BuildContext context, VoidCallback close)? menu;

  /// Opens a movement to edit (a tap on its row, or a swipe right on a paid one). Null: the edit
  /// sheet. Tests pass their own to see what was asked for.
  final void Function(Transaction transaction)? onEdit;

  /// The month to open on (`YYYY-MM`, the route's `?month=`); null: the current one. A new value
  /// moves home to that month.
  final String? initialMonth;

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  /// Events up to this one happened before home opened: they are old news.
  late final int _since = ref.read(homeProvider).event?.id ?? 0;

  /// The phrasing picked for the line on screen, picked again only when the situation changes.
  int _variant = 1;
  Object? _variantFor;

  bool _celebrating = false;
  Timer? _celebrateTimer;

  var _view = HomeView.transactions;

  /// The Categorías tab's own choices: which kind is listed, and whether the archived ones are
  /// unfolded. They stay while the other tab is on screen, as the web's panels keep theirs.
  var _kind = CategoryKindEnum.expense;
  var _showArchived = false;

  /// The page's scroll, and the box above the tabs' strip: where the strip comes to rest at the
  /// top of the screen is the end of that box (and the 4px under it).
  final _scroll = ScrollController();
  final _aboveTabs = GlobalKey();

  /// Where the tabs' thumb is, in tabs: 0 Movimientos, 1 Categorías.
  late final AnimationController _thumb = AnimationController(
    vsync: this,
    duration: WambitoTokens.durationSheet,
  );

  HomeController get _controller => ref.read(homeProvider.notifier);

  static final _monthFormat = RegExp(r'^\d{4}-(0[1-9]|1[0-2])$');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final month = widget.initialMonth;
    if (month != null && _monthFormat.hasMatch(month)) {
      // Not while the tree builds: the controller changes state.
      scheduleMicrotask(() {
        if (mounted) unawaited(_controller.showMonth(month));
      });
    }
    // Asked for a tab before home was here (from a screen over it, then back).
    final requested = ref.read(homeViewRequestProvider);
    if (requested != null) scheduleMicrotask(() => _takeRequest(requested));
  }

  /// The import card's button. Back from the import the account may have movements now.
  Future<void> _openImport() async {
    await context.push<void>('/import');
    if (mounted) ref.invalidate(hasTransactionsProvider);
  }

  /// Shows the tab [view] that was asked for, and clears the request.
  void _takeRequest(HomeView view) {
    if (!mounted) return;
    ref.read(homeViewRequestProvider.notifier).clear();
    if (view == HomeView.budgets) {
      _showBudgets();
    } else {
      _selectView(view);
    }
  }

  @override
  void didUpdateWidget(HomeScreen old) {
    super.didUpdateWidget(old);
    if (old.initialMonth == widget.initialMonth) return;
    final month = widget.initialMonth;
    // Not while the tree builds: the controller changes state.
    scheduleMicrotask(() {
      if (!mounted) return;
      if (month == null) {
        unawaited(_controller.showCurrentMonth());
      } else if (_monthFormat.hasMatch(month)) {
        unawaited(_controller.showMonth(month));
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _celebrateTimer?.cancel();
    _thumb.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back in the app: the figures (and the widget) catch up.
    if (state == AppLifecycleState.resumed) {
      unawaited(_controller.refresh());
      ref.invalidate(hasTransactionsProvider);
      ref.invalidate(reviewProvider);
    }
  }

  void _selectView(HomeView view) {
    if (view == _view) return;
    setState(() => _view = view);
    final target = view.index.toDouble();
    if (MediaQuery.disableAnimationsOf(context)) {
      _thumb.value = target;
    } else {
      unawaited(_thumb.animateTo(target, curve: Curves.easeOut));
    }
  }

  /// The card's "Ir a Categorías" (the web's goes to its categories page; the app's categories
  /// are the Categorías tab): shows that tab, and brings its strip up to the top of the screen,
  /// so the categories are what is in view, not the card above them.
  void _showBudgets() {
    _selectView(HomeView.budgets);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final box = _aboveTabs.currentContext?.findRenderObject();
      if (!mounted || box is! RenderBox || !box.attached || !_scroll.hasClients) return;
      final top = RenderAbstractViewport.of(box).getOffsetToReveal(box, 0).offset;
      final target = (top + box.size.height + 4).clamp(0.0, _scroll.position.maxScrollExtent);
      if (MediaQuery.disableAnimationsOf(context)) {
        _scroll.jumpTo(target);
      } else {
        unawaited(
          _scroll.animateTo(target, duration: WambitoTokens.durationSheet, curve: Curves.easeOut),
        );
      }
    });
  }

  // -- messages ------------------------------------------------------------------------------

  String _failureMessage(AppLocalizations l10n, HomeFailure failure) =>
      failure.offline ? l10n.errorNetwork : l10n.errorGeneric;

  Future<void> _delete(Transaction tx) async {
    final toasts = ToastHost.of(context);
    final l10n = AppLocalizations.of(context);
    if (isUnsent(tx)) {
      final uploaded = await deleteUnsent(
        container: ProviderScope.containerOf(context),
        toasts: toasts,
        l10n: l10n,
        transaction: tx,
      );
      if (uploaded == null || !mounted) return;
      tx = uploaded;
    }
    // At the gesture, not at the server's answer: the row is already gone (the web does the same).
    ref.read(feedbackProvider)(FeedbackEvent.deleted);
    try {
      await _controller.remove(tx);
    } on HomeFailure catch (failure) {
      toasts.say(_failureMessage(l10n, failure), error: true);
      return;
    }
    if (tx.needsReview) ref.invalidate(reviewProvider);
    toasts.say(
      l10n.transactionDeleted(tx.name),
      actionLabel: l10n.undo,
      onAction: () => unawaited(_restore(tx, toasts, l10n)),
    );
  }

  Future<void> _restore(Transaction tx, ToastController toasts, AppLocalizations l10n) async {
    try {
      await _controller.restore(tx);
    } on HomeFailure catch (failure) {
      toasts.say(_failureMessage(l10n, failure), error: true);
      return;
    }
    if (tx.needsReview && mounted) ref.invalidate(reviewProvider);
    if (mounted) ref.read(feedbackProvider)(FeedbackEvent.undo);
    toasts.say(l10n.transactionRestored(tx.name));
  }

  /// Marks [tx] paid. Rethrows a failure after saying it, so the badge goes back to "Pendiente".
  Future<void> _pay(Transaction tx) async {
    final toasts = ToastHost.of(context);
    final l10n = AppLocalizations.of(context);
    final data = ref.read(homeProvider).data;
    if (isUnsent(tx)) {
      final container = ProviderScope.containerOf(context);
      final queue = ref.read(pendingSavesProvider.notifier);
      if (await queue.edit(tx.id, const TransactionPatch(pending: false))) {
        if (mounted) ref.read(feedbackProvider)(FeedbackEvent.paid);
        if (data != null) {
          toasts.say(
            l10n.transactionPaid(tx.name, formatMoney(tx.amount, data.currency, l10n.localeName)),
          );
        }
        return;
      }
      // It went up meanwhile: the server's row is paid.
      final uploaded = uploadedRow(container, tx);
      if (uploaded == null) {
        toasts.say(l10n.errorGeneric, error: true);
        throw const HomeFailure(500);
      }
      tx = uploaded;
    }
    try {
      await _controller.markPaid(tx);
    } on HomeFailure catch (failure) {
      toasts.say(_failureMessage(l10n, failure), error: true);
      rethrow;
    }
    if (mounted) ref.read(feedbackProvider)(FeedbackEvent.paid);
    if (data != null) {
      toasts.say(
        l10n.transactionPaid(tx.name, formatMoney(tx.amount, data.currency, l10n.localeName)),
      );
    }
  }

  // -- Wambi -------------------------------------------------------------------------------

  /// A new event starts a celebration (not near or over a limit: no party for that).
  void _onEvent(HomeEvent? event) {
    if (event == null || event.id <= _since) return;
    final summary = ref.read(homeProvider).data?.summary;
    final state = summary?.categories
        .where((c) => c.categoryId == event.event.categoryId)
        .map((c) => c.state)
        .firstOrNull;
    if (state == SummaryCategoriesInnerStateEnum.near ||
        state == SummaryCategoriesInnerStateEnum.over) {
      return;
    }
    _celebrate();
  }

  /// Wambi celebrates for a moment, then goes back to his mood.
  void _celebrate() {
    _celebrateTimer?.cancel();
    setState(() => _celebrating = true);
    _celebrateTimer = Timer(_celebrateFor, () {
      if (mounted) setState(() => _celebrating = false);
    });
  }

  ({String message, WambiMood mood}) _wambi(
    AppLocalizations l10n,
    HomeState home,
    HomeData data,
    String today,
  ) {
    final locale = l10n.localeName;
    final current = today.substring(0, 7);
    String money(int cents) => formatMoney(cents, data.currency, locale);
    final worried = data.summary.categories.any(
      (c) => c.state != SummaryCategoriesInnerStateEnum.ok,
    );
    // Figures of an earlier month that could not be brought up to date (a cache opened after the
    // month changed): Wambi says so, and never talks about "this month" or a month that just
    // closed as if it were live.
    if (home.stale && data.month != current) {
      return (
        message: l10n.wambiOtherMonth(monthInSentence(data.month, locale)),
        mood: worried ? WambiMood.worried : WambiMood.happy,
      );
    }
    // The event is about its own month: Wambi speaks of it only while that month is on screen.
    final fresh = home.event;
    final event = fresh != null && fresh.month == data.month && fresh.event.categoryId.isNotEmpty
        ? fresh
        : null;
    final line = wambiLine(
      summary: data.summary,
      today: today,
      todayCount: data.items.where((t) => t.date == today).length,
      event: event?.event,
      categoryName: (id) => data.categories[id]?.name ?? '',
    );
    // One of the line's variants, picked again only when the situation changes.
    final situation = (line.key, event?.id, data.month);
    if (_variantFor != situation) {
      _variantFor = situation;
      _variant = ref.read(wambiVariantProvider)();
    }
    // A month closed in green gets a celebration of its own (the web's `closedGreen`).
    final closedGreen =
        data.month.compareTo(current) < 0 &&
        data.summary.budgetTotal > 0 &&
        data.summary.remaining >= 0;
    return (
      message: wambiLineText(l10n, line, _variant, money),
      mood: _celebrating || closedGreen
          ? WambiMood.celebrating
          : (worried ? WambiMood.worried : WambiMood.happy),
    );
  }

  // -- build ---------------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    ref.listen(homeProvider.select((s) => s.event), (_, next) => _onEvent(next));
    // A batch from quick capture has no event of its own to talk about: he just celebrates.
    ref.listen(celebrationProvider, (_, _) => _celebrate());
    ref.listen(homeViewRequestProvider, (_, next) {
      if (next != null) scheduleMicrotask(() => _takeRequest(next));
    });
    ref.listen(pendingSavesProvider.select((s) => s.notice), (_, next) {
      if (next != null) _onPendingNotice(next);
    });
    final home = ref.watch(homeProvider);
    final colors = Theme.of(context).extension<WambitoTheme>()!.colors;
    final l10n = AppLocalizations.of(context);
    final data = home.data;

    // Nothing to add to until the categories are known: no bar, and the screen alone.
    if (data == null) {
      return DecoratedBox(
        decoration: BoxDecoration(gradient: LkSurface.background(colors)),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: SafeArea(
            child: home.failure != null
                ? ScreenError(
                    message: _failureMessage(l10n, home.failure!),
                    retryLabel: l10n.retry,
                    onRetry: () => unawaited(_controller.refresh()),
                  )
                : _LoadingView(label: l10n.homeLoading),
          ),
        ),
      );
    }

    return AppShell(
      current: 'home',
      addKey: const Key('home.add'),
      micKey: const Key('home.capture'),
      onAdd: () => unawaited(openAddSheet(context)),
      // The same path the widget's 🎤 takes: quick capture, listening.
      onMic: () => unawaited(openCapture(context, listen: true)),
      // Análisis opens on the month on screen. Inicio is where the person is.
      onNavigate: (to) =>
          navigateFromShell(context, ref, to, current: 'home', month: home.month ?? data.month),
      child: SafeArea(bottom: false, child: _content(context, home, data, l10n)),
    );
  }

  Widget _content(BuildContext context, HomeState home, HomeData data, AppLocalizations l10n) {
    final locale = l10n.localeName;
    // Asked of the clock on every build: after a night in the background, what was this month is
    // last month, whether or not the refresh worked.
    final today = data.todayAt(ref.read(clockProvider)());
    final current = today.substring(0, 7);
    final shown = home.shown;
    final wambi = shown == null ? null : _wambi(l10n, home, shown, today);
    final entries = shown == null
        ? const <_Entry>[]
        : _entries(
            home,
            shown,
            ref.watch(pendingSavesProvider.select((s) => s.saves)),
            l10n,
            today,
          );
    final colors = context.lkColors;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Read here, below the `AppShell` that provides it: 112px plus the system's bottom inset.
        final room = ShellRoom.of(context);
        // The content is inset from the page's edge, and by the frame's padding too (none in the app).
        final inset =
            math.max(
              WambitoTokens.space4,
              (constraints.maxWidth - _maxContentWidth) / 2 + WambitoTokens.space4,
            ) +
            ShellRoom.sides(context).left;
        return SwipeScope(
          child: RefreshIndicator(
            onRefresh: () {
              ref.invalidate(reviewProvider);
              return _controller.refresh();
            },
            child: CustomScrollView(
              controller: _scroll,
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                // What goes above the screen's content: nothing in the app.
                SliverToBoxAdapter(child: ShellRoom.leading(context)),
                SliverPadding(
                  // `px-4 pt-3`; the tabs' strip reaches 8px up into the gap above it, so the
                  // gap is 12 - 8.
                  padding: EdgeInsets.fromLTRB(inset, WambitoTokens.space3, inset, 4),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      key: _aboveTabs,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: WambitoTokens.space3,
                      children: [
                        HomeHeader(
                          month: home.month ?? data.month,
                          onMonth: (month) => unawaited(_controller.showMonth(month)),
                          max: current,
                          onSearch: () => unawaited(context.push<void>('/search')),
                          menu: widget.menu,
                        ),
                        if (shown != null) ...[
                          if (home.stale)
                            Semantics(
                              liveRegion: true,
                              child: Text(
                                _staleNote(l10n, home, shown, today),
                                style: LkText.caption.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: colors.near,
                                ),
                              ),
                            ),
                          WambiBubble(
                            message: wambi!.message,
                            mood: wambi.mood,
                            quietKey: home.quietKey,
                          ),
                          HomeHero(
                            summary: shown.summary,
                            currency: shown.currency,
                            pastMonth: shown.month.compareTo(current) < 0
                                ? monthInSentence(shown.month, locale)
                                : null,
                          ),
                          // Only while something waits: an empty slot would still add its gap.
                          if (ref.watch(
                            reviewProvider.select((s) => (s.value ?? const []).isNotEmpty),
                          ))
                            const ReviewHomeRow(),
                          ?_nudges(shown, l10n),
                        ] else
                          const HomeHeroPlaceholder(),
                      ],
                    ),
                  ),
                ),
                PinnedHeaderSliver(
                  child: HomeTabsStrip(
                    bleed: inset,
                    child: SegmentedControl<HomeView>(
                      label: l10n.homeViewLabel,
                      value: _view,
                      position: _thumb,
                      options: [
                        SegmentOption(HomeView.transactions, l10n.homeMovements),
                        SegmentOption(
                          HomeView.budgets,
                          l10n.homeBudgetsTab,
                          key: const Key('home.tab.budgets'),
                        ),
                      ],
                      onChanged: _selectView,
                    ),
                  ),
                ),
                if (shown == null)
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(inset, WambitoTokens.space2, inset, room),
                    sliver: SliverToBoxAdapter(
                      child: _MonthUnavailable(
                        failure: home.failure,
                        message: home.failure == null ? null : _failureMessage(l10n, home.failure!),
                        retryLabel: l10n.retry,
                        onRetry: () => unawaited(_controller.refresh()),
                      ),
                    ),
                  )
                else if (_view == HomeView.budgets)
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(inset, WambitoTokens.space2, inset, room),
                    sliver: SliverToBoxAdapter(
                      child: CategoriesTab(
                        summary: shown.summary,
                        categories: shown.categories,
                        currency: shown.currency,
                        kind: _kind,
                        onKind: (kind) => setState(() => _kind = kind),
                        showArchived: _showArchived,
                        onToggleArchived: () => setState(() => _showArchived = !_showArchived),
                        // Its detail, in the month on screen, and back to this tab from it.
                        onOpen: (id) => unawaited(
                          context.push<void>(
                            '/categories/$id?month=${shown.month}',
                            extra: detailFromCategories,
                          ),
                        ),
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(inset, WambitoTokens.space2, inset, room),
                    sliver: SliverList.builder(
                      itemCount: entries.length,
                      findChildIndexCallback: (key) {
                        if (key is! ValueKey<String>) return null;
                        final index = entries.indexWhere((e) => e.key == key.value);
                        return index < 0 ? null : index;
                      },
                      itemBuilder: (context, index) => KeyedSubtree(
                        key: ValueKey(entries[index].key),
                        child: entries[index].build(),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// The cards for an account that skipped the setup (the web's `Nudges`), budgets first: one for
  /// an account without a budget on any category, one for an account with no movements at all to
  /// bring its history in. Each is gone once put away ("Ahora no", kept on this phone).
  Widget? _nudges(HomeData data, AppLocalizations l10n) {
    final categories = data.categories.values.where((c) => !c.archived).toList();
    final noBudgets =
        data.summary.budgetTotal == 0 &&
        categories.any((c) => c.kind == CategoryKindEnum.expense) &&
        categories.every((c) => c.currentBudget == null);
    final budgetsKey = nudgeKey(data.userId, Nudge.budgets);
    final importKey = nudgeKey(data.userId, Nudge.import);
    final showBudgets = noBudgets && ref.watch(nudgeDismissedProvider(budgetsKey)) == false;
    // Movements on screen settle it; otherwise the account is asked (any month counts).
    final showImport =
        data.items.isEmpty &&
        ref.watch(hasTransactionsProvider).value == false &&
        ref.watch(nudgeDismissedProvider(importKey)) == false;
    if (!showBudgets && !showImport) return null;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: l10n.homeNudgesLabel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: WambitoTokens.space2,
        children: [
          if (showBudgets)
            NudgeCard(
              key: const Key('home.nudge.budgets'),
              title: l10n.homeNudgeBudgetsTitle,
              lead: l10n.homeNudgeBudgetsLead,
              actionLabel: l10n.homeNudgeBudgetsAction,
              onAction: _showBudgets,
              onDismiss: () =>
                  unawaited(ref.read(nudgeDismissedProvider(budgetsKey).notifier).dismiss()),
            ),
          if (showImport)
            NudgeCard(
              key: const Key('home.nudge.import'),
              title: l10n.homeNudgeImportTitle,
              lead: l10n.homeNudgeImportLead,
              actionLabel: l10n.homeNudgeImportAction,
              onAction: _openImport,
              onDismiss: () =>
                  unawaited(ref.read(nudgeDismissedProvider(importKey).notifier).dismiss()),
            ),
        ],
      ),
    );
  }

  /// Why what is on screen may be old: no answer at all, or a failed refresh with the network up;
  /// naming the month when it is not this one.
  String _staleNote(AppLocalizations l10n, HomeState home, HomeData data, String today) {
    final other = data.month != today.substring(0, 7);
    final month = monthInSentence(data.month, l10n.localeName);
    if (home.staleOffline) return other ? l10n.homeOfflineMonth(month) : l10n.homeOffline;
    return other ? l10n.homeRefreshFailedMonth(month) : l10n.homeRefreshFailed;
  }

  /// The movements list as widgets in order: each day's heading and rows, then "Ver más
  /// movimientos" (or the empty state).
  List<_Entry> _entries(
    HomeState home,
    HomeData data,
    List<PendingSave> unsent,
    AppLocalizations l10n,
    String today,
  ) {
    final locale = l10n.localeName;
    final colors = context.lkColors;
    final items = withUnsent(data, unsent);
    if (items.isEmpty) {
      return [
        _Entry(
          'empty',
          () => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: WambitoTokens.space3,
            children: [
              Text(
                l10n.homeEmptyTransactions(formatMonthName(data.month, locale)),
                style: LkText.bodySm.copyWith(color: colors.inkMuted),
              ),
              PressButton.text(
                l10n.addFabLabel,
                tone: PressTone.secondary,
                onPressed: () => unawaited(openAddSheet(context)),
              ),
            ],
          ),
        ),
      ];
    }
    final entries = <_Entry>[];
    for (final group in groupByDay(items, today)) {
      final day = formatDay(group.date, locale);
      final label = switch (group.when) {
        DayWhen.today => l10n.homeDayToday(day),
        DayWhen.yesterday => l10n.homeDayYesterday(day),
        DayWhen.upcoming => l10n.homeDayUpcoming(day),
        DayWhen.past => day,
      };
      entries.add(
        _Entry(
          'day-${group.date}',
          () => DayHeading(
            label: label,
            total: formatMoney(
              group.total,
              data.currency,
              locale,
              sign: group.total > 0 ? MoneySign.always : MoneySign.auto,
            ),
          ),
        ),
      );
      for (final tx in group.items) {
        entries.add(_Entry('tx-${tx.id}', () => _row(home, data, tx, l10n)));
      }
    }
    if (data.nextCursor != null) {
      entries.add(
        _Entry(
          'more',
          () => Center(
            child: PressButton.text(
              l10n.homeMoreTransactions,
              tone: PressTone.secondary,
              onPressed: home.loadingMore ? null : _loadMore,
            ),
          ),
        ),
      );
    }
    return entries;
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

  /// What home says about the saves that waited for the network: they are up, or one was refused.
  void _onPendingNotice(PendingNotice notice) {
    final toasts = ToastHost.of(context);
    final l10n = AppLocalizations.of(context);
    final refused = notice.refused;
    if (refused != null) {
      final name = refused.name.trim().isNotEmpty
          ? refused.name.trim()
          : ref.read(homeProvider).data?.categories[refused.categoryId]?.name ?? '';
      toasts.say(l10n.unsentRefused(name), error: true);
    } else if (notice.sent > 0) {
      toasts.say(l10n.unsentUploaded(notice.sent));
    }
  }

  Widget _row(HomeState home, HomeData data, Transaction tx, AppLocalizations l10n) {
    // A row not on the server yet is edited, deleted and paid like any other: the change waits with
    // it, on the phone, and goes up after it.
    final pending = tx.status == TransactionStatusEnum.pending;
    final onEdit = widget.onEdit ?? (Transaction tx) => unawaited(openEditSheet(context, tx));
    return SwipeRow(
      key: ValueKey(tx.id),
      gap: WambitoTokens.space2,
      enter: home.restored.contains(tx.id),
      onEntered: () => _controller.settleRestored(tx.id),
      deleteLabel: l10n.swipeDelete,
      onDelete: () => unawaited(_delete(tx)),
      right: pending
          ? SwipeRight(
              SwipeRightKind.paid,
              // Paid once: a second quick swipe (or the badge) never pays it again.
              () => unawaited(_pay(tx).then((_) {}, onError: (Object _) {})),
              l10n.swipePaid,
            )
          : SwipeRight(SwipeRightKind.edit, () => onEdit(tx), l10n.swipeEdit),
      child: _txRow(
        data,
        tx,
        home.paidHere.contains(tx.id),
        onEdit,
        () => _pay(tx),
        unsent: isUnsent(tx),
        reviewMark: reviewMarkOf(l10n, tx),
      ),
    );
  }
}

/// The web's `TransactionRow` for [tx]: its category's glyph and name, and the row's actions.
Widget _txRow(
  HomeData data,
  Transaction tx,
  bool paidHere,
  void Function(Transaction) onEdit,
  Future<void> Function()? onPay, {
  bool unsent = false,
  String? reviewMark,
}) {
  final category = data.categories[tx.categoryId];
  return TransactionRow(
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
    paidHere: paidHere,
    onOpen: () => onEdit(tx),
    onPay: onPay,
    unsent: unsent,
    reviewMark: reviewMark,
  );
}

class _Entry {
  const _Entry(this.key, this.build);

  final String key;
  final Widget Function() build;
}

/// What the lists show while another month loads (the web's `min-h-[120px]`, busy), or why it is not
/// there: never another month's figures.
class _MonthUnavailable extends StatelessWidget {
  const _MonthUnavailable({
    required this.failure,
    required this.message,
    required this.retryLabel,
    required this.onRetry,
  });

  final HomeFailure? failure;
  final String? message;
  final String retryLabel;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.lkColors;
    final message = this.message;
    if (message == null) return const SizedBox(height: 120);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: WambitoTokens.space3,
      children: [
        Semantics(
          liveRegion: true,
          child: Text(message, style: LkText.bodySm.copyWith(color: colors.inkMuted)),
        ),
        PressButton.text(retryLabel, tone: PressTone.secondary, onPressed: onRetry),
      ],
    );
  }
}

class _LoadingView extends StatelessWidget {
  const _LoadingView({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<WambitoTheme>()!.colors;
    return Center(
      child: Semantics(
        label: label,
        liveRegion: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const QuietSpinner(size: 28),
            const SizedBox(height: WambitoTokens.space3),
            Text(
              label,
              style: TextStyle(color: colors.inkMuted, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

/// The movements of [data] with the rows of the saves still waiting for the network that belong to
/// its month, newest first.
List<Transaction> withUnsent(HomeData data, List<PendingSave> unsent) {
  final rows = [
    for (final save in unsent)
      for (final row in save.rows(data.currency))
        if (row.date.startsWith(data.month)) row,
  ];
  if (rows.isEmpty) return data.items;
  // Within a day, what waits comes first: it was saved last.
  return [...data.items, ...rows]..sort((a, b) {
    final byDate = b.date.compareTo(a.date);
    if (byDate != 0) return byDate;
    final waiting = (isUnsent(a) ? 0 : 1) - (isUnsent(b) ? 0 : 1);
    return waiting != 0 ? waiting : b.id.compareTo(a.id);
  });
}
