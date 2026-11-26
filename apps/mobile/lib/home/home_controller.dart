import 'dart:async';
import 'dart:async' as dart_async show AsyncError;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/gen/wambito_api.dart';
import '../api/session.dart';
import '../capture/parser/dates.dart';
import '../offline/pending_saves.dart';
import '../settings/locale_resolution.dart';
import 'home_cache.dart';
import 'home_repository.dart';
import 'wambi_line.dart';
import 'widget_sync.dart';

/// How long Wambi talks about a save or a payment before going back to the month's line (the
/// web's `EVENT_LINE_MS`, founder feedback 2026-10-22: a line that stayed for ages).
const eventLineDuration = Duration(seconds: 10);

/// The clock, replaced in tests.
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// Writes the widget's snapshot after the month's figures load (replaced in tests).
final widgetSnapshotWriterProvider =
    Provider<
      Future<void> Function(
        Summary summary, {
        required String currency,
        required String locale,
        required String timezone,
      })
    >(
      (ref) =>
          (summary, {required currency, required locale, required timezone}) => ref
              .read(widgetSyncProvider)
              .summaryLoaded(summary, currency: currency, locale: locale, timezone: timezone),
    );

/// The language amounts and dates are written in: the phone's language when the app has it
/// (English, Italian, Portuguese), Spanish otherwise (the same rule as the app's
/// `localeResolutionCallback`, `resolveAppLocale`). A region never matters: `pt-BR` reads `pt`.
String languageOfTag(String tag) {
  final code = tag.toLowerCase().split(RegExp('[-_]')).first;
  return appLanguages.contains(code) ? code : 'es';
}

/// The month on screen: its summary and movements.
class HomeData {
  const HomeData({
    this.userId = '',
    required this.month,
    required this.timezone,
    required this.currency,
    required this.summary,
    required this.categories,
    required this.items,
    required this.nextCursor,
  });

  /// The person these figures are of.
  final String userId;

  /// `YYYY-MM`.
  final String month;

  /// The profile's time zone (an IANA name): "today" is read in it.
  final String timezone;
  final String currency;
  final Summary summary;

  /// Every category (archived ones too) by id.
  final Map<String, Category> categories;

  /// The movements loaded so far, newest first.
  final List<Transaction> items;

  /// Where the next page starts; null when everything is loaded.
  final String? nextCursor;

  /// Today (`YYYY-MM-DD`) in the profile's time zone at [now]. Always asked of the clock, never
  /// kept: the app can sit in the background past midnight, and what is "this month" changes with
  /// it.
  String todayAt(DateTime now) => todayIn(timezone, now.toUtc());

  HomeData copyWith({
    Summary? summary,
    Map<String, Category>? categories,
    List<Transaction>? items,
    String? Function()? nextCursor,
  }) => HomeData(
    userId: userId,
    month: month,
    timezone: timezone,
    currency: currency,
    summary: summary ?? this.summary,
    categories: categories ?? this.categories,
    items: items ?? this.items,
    nextCursor: nextCursor == null ? this.nextCursor : nextCursor(),
  );
}

/// The save or payment Wambi is talking about.
class HomeEvent {
  const HomeEvent(this.id, this.event, this.month);

  /// Grows with each event, so the same kind of event twice still counts as new.
  final int id;
  final WambiEvent event;

  /// The month (`YYYY-MM`) the movement belongs to: Wambi talks about it only while that month is
  /// on screen (the web's `fresh.event.month === summary.month`).
  final String month;
}

/// How long home keeps the month that was on screen while another one loads.
const monthGrace = Duration(milliseconds: 300);

class HomeState {
  const HomeState({
    this.data,
    this.month,
    this.loading = true,
    this.failure,
    this.stale = false,
    this.staleOffline = false,
    this.loadingMore = false,
    this.event,
    this.restored = const {},
    this.paidHere = const {},
    this.quietKey = 0,
  });

  /// The last month loaded. Kept while a refresh fails: offline, it stays on screen (spec 6.3).
  /// It is of [month] only when [shown] says so: while another month loads (or cannot), it is still
  /// the month before.
  final HomeData? data;

  /// The month the screen is on (`YYYY-MM`), which the person asked for or which loaded last; null
  /// before anything did.
  final String? month;

  /// [data] when it is of [month]: what the screen may show as that month. Never another month's
  /// figures, and never the cache of a month that is not the one asked for.
  HomeData? get shown {
    final data = this.data;
    return data != null && (month == null || data.month == month) ? data : null;
  }

  /// What home draws: [shown], or, for the first moments ([monthGrace]) while another month loads
  /// ([holding]), the month that was on screen, so a quick load only changes the figures and nothing
  /// blinks through the loading state. Past that, the loading state: figures of one month under
  /// another month's name never linger.
  HomeData? onScreen({required bool holding}) => shown ?? (loading && holding ? data : null);

  /// A load is under way and nothing of it is on screen yet: the first one, or another month.
  final bool loading;

  /// Why the load failed with nothing to show: the first one, or another month's.
  final HomeFailure? failure;

  /// The last refresh failed: [data] is from an earlier load.
  final bool stale;

  /// With [stale]: the failure was no answer at all (offline), not a server error.
  final bool staleOffline;
  final bool loadingMore;

  /// While Wambi should still talk about it.
  final HomeEvent? event;

  /// Rows brought back by Deshacer, which slide in.
  final Set<String> restored;

  /// Pending rows paid from home: their badge says "Pagado" although the row is already paid.
  final Set<String> paidHere;

  /// Changes whenever a line about an event ends (Wambi goes back to the month's line): the
  /// bubble takes it as a new live region, so the month's line is not read out a second time.
  final int quietKey;

  HomeState copyWith({
    HomeData? data,
    String? month,
    bool? loading,
    HomeFailure? Function()? failure,
    bool? stale,
    bool? staleOffline,
    bool? loadingMore,
    HomeEvent? Function()? event,
    Set<String>? restored,
    Set<String>? paidHere,
    int? quietKey,
  }) => HomeState(
    data: data ?? this.data,
    month: month ?? this.month,
    loading: loading ?? this.loading,
    failure: failure == null ? this.failure : failure(),
    stale: stale ?? this.stale,
    staleOffline: staleOffline ?? this.staleOffline,
    loadingMore: loadingMore ?? this.loadingMore,
    event: event == null ? this.event : event(),
    restored: restored ?? this.restored,
    paidHere: paidHere ?? this.paidHere,
    quietKey: quietKey ?? this.quietKey,
  );
}

/// Orders by date then id, newest first: the API's order.
int _newestFirst(Transaction a, Transaction b) {
  final byDate = b.date.compareTo(a.date);
  return byDate != 0 ? byDate : b.id.compareTo(a.id);
}

/// Home's state and what changes it: the month's summary and movements (loaded, paged, refreshed),
/// deleting with Deshacer, marking a pending movement paid, and the event Wambi talks about.
///
/// Changes show at once (optimistic) and roll back when the server refuses; a failure is thrown as
/// a [HomeFailure] for the screen to say. Every load of the summary also writes the widget's
/// snapshot (spec section 7.1: every app load or save updates the widget).
class HomeController extends Notifier<HomeState> {
  HomeRepository get _repo => ref.read(homeRepositoryProvider);
  HomeCache get _cache => ref.read(homeCacheProvider);

  var _alive = true;
  Timer? _eventTimer;
  var _eventId = 0;
  Future<void>? _loading;

  /// Counts the summary requests: only the latest one may touch the screen, the cache and the
  /// widget, so an old answer that lands late cannot undo a newer one.
  var _summarySeq = 0;

  /// Counts the loads of a month (the first, a refresh, another month asked for): only the latest
  /// one may put its month on screen.
  var _monthSeq = 0;

  /// Counts the widget's own summary requests (see [_refreshWidget]).
  var _widgetSeq = 0;
  HomeProfile? _profile;

  /// The month the person asked for with [showMonth]; null while they follow the current one.
  String? _wanted;

  @override
  HomeState build() {
    // A new session (another person signing in) starts from nothing.
    ref.watch(homeRepositoryProvider);
    ref.watch(homeCacheProvider);
    _alive = true;
    _loading = null;
    _summarySeq = 0;
    _monthSeq = 0;
    _widgetSeq = 0;
    _categoriesSeq = 0;
    _profile = null;
    _wanted = null;
    _eventTimer?.cancel();
    ref.onDispose(() {
      _alive = false;
      _eventTimer?.cancel();
    });
    // The first load starts once the provider is built.
    scheduleMicrotask(refresh);
    return const HomeState();
  }

  void _set(HomeState next) {
    if (_alive) state = next;
  }

  /// A failure that means the session is over: the server does not know the token any more.
  void _checkSession(Object error) {
    if (!_alive) return;
    if (error is HomeFailure && error.unauthorized) {
      unawaited(ref.read(sessionProvider.notifier).signOut(discardGuest: true));
    }
  }

  HomeFailure _failure(Object error) {
    _checkSession(error);
    return error is HomeFailure ? error : const HomeFailure(0);
  }

  /// The current month (`YYYY-MM`) in the profile's time zone, asked of the clock. Null before the
  /// profile is known.
  String? get _currentMonth {
    final profile = _profile;
    if (profile == null) return null;
    return todayIn(profile.timezone, ref.read(clockProvider)().toUtc()).substring(0, 7);
  }

  /// Whether [month] is the current one: the only month the widget and the cache hold.
  bool _isCurrent(String month) => month == _currentMonth;

  /// The month a load is of: the one asked for (never past the current one), or the current one.
  String _target(String current) {
    final wanted = _wanted;
    return wanted == null || wanted.compareTo(current) >= 0 ? current : wanted;
  }

  /// Moves to [month] (`YYYY-MM`): its summary and movements load and replace what is on screen.
  /// A month after the current one is the current one. Only the latest month asked for may arrive,
  /// however late an older answer lands. Offline it says so ([HomeState.failure]) and shows no
  /// figures: the cache holds the current month only, and is never shown as another month. Moving
  /// to an earlier month leaves the widget and the cache as they are (they read the current month);
  /// moving to the current month follows the clock again.
  Future<void> showMonth(String month) {
    final current = _currentMonth;
    // Following the current month again (or asking beyond it).
    _wanted = current != null && month.compareTo(current) >= 0 ? null : month;
    if (current == null) {
      // The profile is not known yet (a link opened home on a month): the first load takes it.
      _set(state.copyWith(month: month));
      return refresh();
    }
    final target = _target(current);
    if (state.month == target && state.shown != null) return refresh();
    _set(state.copyWith(month: target, loading: true, failure: () => null));
    // The widget already has the current month: moving around the calendar does not touch it.
    return _load(tellWidget: false);
  }

  /// Follows the current month again (the route's `?month=` went away).
  Future<void> showCurrentMonth() => showMonth(_currentMonth ?? '9999-12');

  /// Loads the month on screen again: the profile, the summary, the categories and the first page.
  /// Offline (or on any failure) what is on screen stays, marked stale. On an earlier month it
  /// reloads that one, and tells the widget the current one.
  Future<void> refresh() => _loading ??= _load().whenComplete(() => _loading = null);

  /// [tellWidget]: an earlier month on screen also tells the widget the current one (a refresh, or
  /// the first load); moving to a month by hand does not.
  Future<void> _load({bool tellWidget = true}) async {
    final seq = ++_monthSeq;
    if (state.data == null && !state.loading) {
      _set(const HomeState());
    }
    String? month;
    try {
      final profile = _profile ??= await _repo.profile();
      if (!_alive) return;
      final current = _currentMonth!;
      month = _target(current);
      final target = month;
      final (summary, categories, page) = await (
        _repo.summary(target),
        _repo.categories(),
        _repo.transactions(target),
      ).wait;
      // Home was left (signed out, say) while this was on its way: nobody is waiting for it.
      if (!_alive || seq != _monthSeq) return;
      // This load is the latest word: an older summary still on its way is dropped.
      _summarySeq++;
      final data = HomeData(
        userId: profile.id,
        month: target,
        timezone: profile.timezone,
        currency: profile.currency,
        summary: summary,
        categories: {for (final c in categories) c.id: c},
        items: page.items,
        nextCursor: page.nextCursor,
      );
      _set(
        HomeState(
          data: data,
          month: target,
          loading: false,
          event: state.event,
          restored: state.restored,
          paidHere: state.paidHere,
          quietKey: state.quietKey,
        ),
      );
      // The network is there: whatever was saved without it goes up now (the queue is there
      // whenever home is on screen).
      if (ref.exists(pendingSavesProvider)) {
        unawaited(ref.read(pendingSavesProvider.notifier).send());
      }
      if (_isCurrent(target)) {
        unawaited(_writeSnapshot(summary, data.currency, data.timezone));
        unawaited(_persist());
      } else {
        // An earlier month: the widget reads the current one.
        if (tellWidget) unawaited(_refreshWidget());
      }
    } on ParallelWaitError<dynamic, dynamic> catch (error) {
      // What each of the three failed with (a record of dart:async AsyncError, null for the ones that
      // worked; not Riverpod's AsyncError, which shares the name).
      final failed = error.errors as (Object?, Object?, Object?);
      final errors = [
        for (final e in [failed.$1, failed.$2, failed.$3])
          if (e != null) e is dart_async.AsyncError ? e.error : e,
      ];
      // A refused session wins over any other failure: it ends the session.
      await _loadFailed(
        errors.firstWhere(
          (e) => e is HomeFailure && e.unauthorized,
          orElse: () => errors.firstOrNull ?? const HomeFailure(0),
        ),
        seq,
        month,
      );
    } on Object catch (error) {
      await _loadFailed(error, seq, month);
    }
  }

  /// A load of [month] (null: not known yet, the profile did not come) failed. What is on screen of
  /// that month stays, stale. When another month is on screen, the current month's cache shows if
  /// it holds that month; any other month has no cache, so it says why it is not there. With
  /// nothing on screen (a cold start with no network) the last good month saved on this phone shows
  /// instead, stale; and with neither, the failure.
  Future<void> _loadFailed(Object error, int seq, String? month) async {
    final failure = _failure(error);
    if (!_alive || seq != _monthSeq) return;
    // The month on screen failed to refresh (the clock may have moved on to the next one: what was
    // on screen stays, and says which month it is).
    if (state.shown != null) {
      _set(state.copyWith(loading: false, stale: true, staleOffline: failure.offline));
      return;
    }
    // A refused session shows nothing: signing out wipes the cache. And only the current month is
    // cached: never another month's figures under this month's name.
    final cacheable = !failure.unauthorized && (month == null || _isCurrent(month));
    final cached = cacheable ? await _cache.read() : null;
    if (!_alive || seq != _monthSeq) return;
    // Never another user's month (the cache is also bound to the session that wrote it).
    final known = _profile?.id;
    if (cached == null ||
        (known != null && known != cached.userId) ||
        (month != null && cached.month != month)) {
      _set(
        HomeState(
          data: state.data,
          month: month ?? state.month,
          loading: false,
          failure: failure,
          event: state.event,
          restored: state.restored,
          paidHere: state.paidHere,
          quietKey: state.quietKey,
        ),
      );
      return;
    }
    _set(
      HomeState(
        loading: false,
        stale: true,
        staleOffline: failure.offline,
        month: cached.month,
        quietKey: state.quietKey,
        data: HomeData(
          userId: cached.userId,
          month: cached.month,
          timezone: cached.timezone,
          currency: cached.currency,
          summary: cached.summary,
          categories: {for (final c in cached.categories) c.id: c},
          items: cached.items,
          nextCursor: null,
        ),
      ),
    );
  }

  /// Saves what is on screen (its first page of movements) for a start with no network. Best
  /// effort, never after home was left, and only for the current month: that is all the cache holds.
  Future<void> _persist() async {
    if (!_alive) return;
    final data = state.data;
    final profile = _profile;
    if (data == null || profile == null || !_isCurrent(data.month)) return;
    await _cache.write(
      CachedHome(
        userId: profile.id,
        currency: data.currency,
        timezone: profile.timezone,
        month: data.month,
        summary: data.summary,
        categories: data.categories.values.toList(),
        items: data.items.take(transactionsPageSize).toList(),
      ),
    );
  }

  Future<void> _writeSnapshot(Summary summary, String currency, String timezone) async {
    if (!_alive) return;
    try {
      final locale = widgetLanguage(ref);
      await ref.read(widgetSnapshotWriterProvider)(
        summary,
        currency: currency,
        locale: locale,
        timezone: timezone,
      );
    } catch (_) {
      // The widget keeps its last figure; this never breaks home (nor, after home was left, the app).
    }
  }

  /// Tells the widget the current month's figures while an earlier month is on screen (a refresh,
  /// a save, a payment): the widget and the notices read the current month only. Best effort, and
  /// only the latest request writes.
  Future<void> _refreshWidget() async {
    final profile = _profile;
    final current = _currentMonth;
    if (!_alive || profile == null || current == null) return;
    final request = ++_widgetSeq;
    try {
      final summary = await _repo.summary(current);
      if (!_alive || request != _widgetSeq) return;
      await _writeSnapshot(summary, profile.currency, profile.timezone);
    } on Object catch (error) {
      // A refused session still ends the session; anything else leaves the widget as it was.
      _checkSession(error);
    }
  }

  /// Brings the next page ("Ver más movimientos") below the rows shown. Throws a [HomeFailure] and
  /// keeps the list as it is when it fails.
  Future<void> loadMore() async {
    final data = state.data;
    if (data == null || data.nextCursor == null || state.loadingMore) return;
    _set(state.copyWith(loadingMore: true));
    try {
      final page = await _repo.transactions(data.month, cursor: data.nextCursor);
      final current = state.data;
      // Another month was chosen while the page was on its way: its rows and its cursor are that
      // month's, never to be put under this one's name.
      if (!_alive || current == null || current.month != data.month) {
        if (_alive) _set(state.copyWith(loadingMore: false));
        return;
      }
      final known = {for (final tx in current.items) tx.id};
      _set(
        state.copyWith(
          loadingMore: false,
          data: current.copyWith(
            items: [...current.items, ...page.items.where((tx) => !known.contains(tx.id))],
            nextCursor: () => page.nextCursor,
          ),
        ),
      );
    } on Object catch (error) {
      _set(state.copyWith(loadingMore: false));
      throw _failure(error);
    }
  }

  /// The summary again, after a change (silently: the rows already show the change). On an earlier
  /// month the widget is told the current one meanwhile.
  Future<void> _refreshSummary() async {
    if (!_alive) return;
    final data = state.data;
    if (data == null) return;
    if (!_isCurrent(data.month)) unawaited(_refreshWidget());
    final request = ++_summarySeq;
    try {
      final summary = await _repo.summary(data.month);
      // Dropped when it is not the latest request (see [_summarySeq]).
      if (!_alive || request != _summarySeq) return;
      final current = state.data;
      // The month on screen changed while this was on its way: its figures are another month's.
      if (current == null || current.month != data.month) return;
      _set(state.copyWith(data: current.copyWith(summary: summary)));
      if (_isCurrent(current.month)) {
        unawaited(_writeSnapshot(summary, current.currency, current.timezone));
        unawaited(_persist());
      }
    } on Object catch (error) {
      if (!_alive) return;
      // One mapping of an error to what it means, as in a load; and a refused session ends the
      // session even when the request was an older one whose answer is dropped.
      final failure = _failure(error);
      if (request != _summarySeq) return;
      _set(state.copyWith(stale: true, staleOffline: failure.offline));
    }
  }

  /// Counts the requests for the categories: only the latest one may touch the screen.
  var _categoriesSeq = 0;

  /// The categories again (a budget changed what `currentBudget` says), silently, and only the
  /// latest answer counts. What is on screen stays when it fails.
  Future<void> _refreshCategories() async {
    if (!_alive) return;
    final request = ++_categoriesSeq;
    try {
      final categories = await _repo.categories();
      if (!_alive || request != _categoriesSeq) return;
      final current = state.data;
      if (current == null) return;
      _set(
        state.copyWith(data: current.copyWith(categories: {for (final c in categories) c.id: c})),
      );
      unawaited(_persist());
    } on Object catch (error) {
      // A refused session still ends the session; anything else leaves the categories as they were.
      _checkSession(error);
    }
  }

  /// A budget was set or changed (from a category's detail): the month's summary (Te quedan, the
  /// Categorías bars) and the categories (what each has in force) are asked again, silently: the
  /// last figures stay on screen while it is on its way, or when it fails (then they are marked as
  /// possibly old). Only the latest summary counts, and the widget and the saved month follow it
  /// (on an earlier month the widget is told the current one meanwhile).
  Future<void> budgetChanged() async {
    if (!_alive || state.data == null) return;
    unawaited(_refreshCategories());
    await _refreshSummary();
  }

  /// A category was made, changed or brought back (from the Categorías tab or a category's detail):
  /// the categories and the month's summary are asked again, silently, and the widget and the saved
  /// month follow the summary (as for [budgetChanged]). Completes when both are in.
  Future<void> categoriesChanged() async {
    if (!_alive || state.data == null) return;
    await Future.wait([_refreshCategories(), _refreshSummary()]);
  }

  /// Something the server changed reaches the movements as well as the categories (archiving a
  /// category ends its recurring payments and drops their unpaid rows from today on): the whole
  /// month is loaded again, after any load already under way (which may have started before the
  /// change), and the widget and the saved month follow.
  Future<void> reloaded() async {
    if (!_alive) return;
    final underWay = _loading;
    if (underWay != null) await underWay.catchError((Object _) {});
    await refresh();
  }

  /// The profile changed on the server under the app (an import switched the empty account to the
  /// file's currency): the next load reads it again, and the month is loaded now, so the figures, the
  /// widget's snapshot and the saved month follow the new currency.
  Future<void> profileChanged() async {
    _profile = null;
    await reloaded();
  }

  /// A row brought back by Deshacer has slid in: it is a plain row again.
  void settleRestored(String id) {
    if (!state.restored.contains(id)) return;
    _set(state.copyWith(restored: {...state.restored}..remove(id)));
  }

  void _replaceItems(List<Transaction> items) {
    final data = state.data;
    if (data != null) _set(state.copyWith(data: data.copyWith(items: items)));
  }

  /// Deletes [tx]: the row goes at once, and comes back if the server refuses (then a
  /// [HomeFailure] is thrown).
  Future<void> remove(Transaction tx) async {
    final data = state.data;
    if (data == null) return;
    _replaceItems([
      for (final t in data.items)
        if (t.id != tx.id) t,
    ]);
    try {
      await _repo.delete(tx.id);
    } on Object catch (error) {
      final current = state.data;
      // Back where it was, unless another month is on screen by now (its rule: `_place`).
      if (current != null && !current.items.any((t) => t.id == tx.id)) _place(tx);
      throw _failure(error);
    }
    // The row is already gone: what is saved for a start with no network follows it at once, and
    // the summary in the background, so Deshacer shows as soon as the server has the delete,
    // however slow the summary is.
    unawaited(_persist());
    unawaited(_refreshSummary());
  }

  /// Brings a deleted [tx] back (Deshacer): the same row, in its place, sliding in.
  Future<void> restore(Transaction tx) async {
    try {
      final back = await _repo.restore(tx.id);
      if (!_alive) return;
      final data = state.data;
      if (data == null) return;
      // The server has it back. It shows only where it belongs: Deshacer outlives a change of
      // month, and a September row never appears in August's list (it is there when September is).
      if (back.date.startsWith(data.month)) {
        _set(state.copyWith(restored: {...state.restored, back.id}));
        _place(back);
      }
    } on Object catch (error) {
      throw _failure(error);
    }
    unawaited(_persist());
    unawaited(_refreshSummary());
  }

  /// Marks a pending [tx] paid. Wambi talks about it for [eventLineDuration]. A refusal puts the
  /// row back to pending and throws a [HomeFailure].
  Future<void> markPaid(Transaction tx) async {
    final data = state.data;
    if (data == null || state.paidHere.contains(tx.id)) return;
    final paid = tx.rebuild((b) => b.status = TransactionStatusEnum.paid);
    _set(state.copyWith(paidHere: {...state.paidHere, tx.id}));
    _replaceItems([for (final t in data.items) t.id == tx.id ? paid : t]);
    try {
      await _repo.markPaid(tx.id);
    } on Object catch (error) {
      final current = state.data;
      if (current != null) {
        _replaceItems([for (final t in current.items) t.id == tx.id ? tx : t]);
      }
      _set(state.copyWith(paidHere: {...state.paidHere}..remove(tx.id)));
      throw _failure(error);
    }
    // The figures after the payment first, so the line says the truth.
    await _refreshSummary();
    report(
      WambiEvent(
        kind: WambiEventKind.paid,
        categoryId: tx.categoryId,
        amount: tx.amount,
        name: tx.name,
      ),
      month: tx.date.substring(0, 7),
    );
  }

  /// Puts [tx] among the rows when it belongs to the month on screen (replacing its earlier
  /// version), or takes it off when it does not (an edit moved it to another month).
  void _place(Transaction tx) {
    final data = state.data;
    if (data == null) return;
    final rest = [
      for (final t in data.items)
        if (t.id != tx.id) t,
    ];
    final here = tx.date.startsWith(data.month);
    // A page boundary hides what is below it: a row older than the last one loaded would sit at
    // the end of a list that has more to come, so it waits for "Ver más movimientos".
    final last = rest.isEmpty ? null : rest.last;
    final beyond =
        data.nextCursor != null && last != null && _newestFirst(tx, last) > 0 && tx.id != last.id;
    _replaceItems(here && !beyond ? ([...rest, tx]..sort(_newestFirst)) : rest);
  }

  /// A movement the add sheet just saved: its row is there at once, what is saved for a start with
  /// no network follows, and the summary is asked again (only the latest answer counts). Wambi
  /// talks about it once the figures are in, unless a newer event has taken over meanwhile.
  Future<void> saved(Transaction tx) async {
    if (state.data == null) return;
    final eventBefore = _eventId;
    _place(tx);
    unawaited(_persist());
    await _refreshSummary();
    if (!_alive || _eventId != eventBefore) return;
    report(
      WambiEvent(
        kind: WambiEventKind.saved,
        categoryId: tx.categoryId,
        amount: tx.amount,
        name: tx.name,
      ),
      month: tx.date.substring(0, 7),
    );
  }

  /// Movements a quick capture just saved together: their rows are there at once, what is saved
  /// for a start with no network follows, and the summary is asked once (only the latest answer
  /// counts). No Wambi event: capture shows its own celebration for the batch.
  Future<void> savedBatch(List<Transaction> saved) async {
    if (state.data == null) return;
    for (final tx in saved) {
      _place(tx);
    }
    unawaited(_persist());
    await _refreshSummary();
  }

  /// Takes the rows [ids] off at once, after the server deleted them (a capture's Deshacer), and
  /// asks for the summary again.
  Future<void> forget(List<String> ids) async {
    final data = state.data;
    if (data == null) return;
    final gone = ids.toSet();
    _replaceItems([
      for (final t in data.items)
        if (!gone.contains(t.id)) t,
    ]);
    unawaited(_persist());
    await _refreshSummary();
  }

  /// A movement the add sheet just edited: its row is replaced where it belongs, and the summary
  /// follows. No event: an edit is no celebration.
  Future<void> updated(Transaction tx) async {
    if (state.data == null) return;
    _place(tx);
    unawaited(_persist());
    await _refreshSummary();
  }

  /// Wambi talks about [event] for [eventLineDuration], then goes back to the month's line. Also
  /// for a save (the add sheet reports it). [month] is the month the movement belongs to (the
  /// month on screen when not given): Wambi speaks of it only while that month is shown.
  void report(WambiEvent event, {String? month}) {
    _eventTimer?.cancel();
    final id = ++_eventId;
    _set(
      state.copyWith(
        event: () => HomeEvent(id, event, month ?? state.data?.month ?? _currentMonth ?? ''),
      ),
    );
    _eventTimer = Timer(eventLineDuration, () {
      if (_eventId == id) _set(state.copyWith(event: () => null, quietKey: state.quietKey + 1));
    });
  }
}

/// Home's state, kept while home is on screen. Leaving it (signing out, say) drops it, so the next
/// person never sees it and nothing is fetched for a screen nobody sees.
final homeProvider = NotifierProvider.autoDispose<HomeController, HomeState>(HomeController.new);
