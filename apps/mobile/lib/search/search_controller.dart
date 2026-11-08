import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/gen/wambito_api.dart';
import '../home/home_repository.dart';
import 'search_repository.dart';

/// How long typing must pause before the words are searched.
const searchDebounce = Duration(milliseconds: 300);

class SearchState {
  const SearchState({
    this.filters = const SearchFilters(),
    this.items = const [],
    this.totals,
    this.nextCursor,
    this.loading = false,
    this.loadingMore = false,
    this.failure,
  });

  final SearchFilters filters;

  /// The matches loaded so far, in the API's order.
  final List<Transaction> items;

  /// Over every match, not just [items]; null when nothing is searched or the server sent none.
  final SearchTotals? totals;

  /// Where the next page starts; null when everything is loaded.
  final String? nextCursor;

  /// The first page of a search is under way.
  final bool loading;
  final bool loadingMore;

  /// The last search or page failed; [items] stay as they were.
  final HomeFailure? failure;

  SearchState copyWith({
    SearchFilters? filters,
    List<Transaction>? items,
    SearchTotals? Function()? totals,
    String? Function()? nextCursor,
    bool? loading,
    bool? loadingMore,
    HomeFailure? Function()? failure,
  }) => SearchState(
    filters: filters ?? this.filters,
    items: items ?? this.items,
    totals: totals == null ? this.totals : totals(),
    nextCursor: nextCursor == null ? this.nextCursor : nextCursor(),
    loading: loading ?? this.loading,
    loadingMore: loadingMore ?? this.loadingMore,
    failure: failure == null ? this.failure : failure(),
  );
}

/// The search screen's state: words (debounced) and filters (at once) drive the repository; only
/// the latest request may touch the state, however late an older answer lands.
class SearchController extends Notifier<SearchState> {
  SearchRepository get _repo => ref.read(searchRepositoryProvider);

  Timer? _debounce;

  /// Counts the requests (searches and pages); an answer of an older one is dropped.
  var _generation = 0;

  @override
  SearchState build() {
    _debounce?.cancel();
    _generation = 0;
    ref.onDispose(() {
      _debounce?.cancel();
      // Anything still in flight lands on a dead notifier.
      _generation++;
    });
    return const SearchState();
  }

  void setText(String text) {
    state = state.copyWith(filters: _filters(text: text));
    _debounce?.cancel();
    if (!state.filters.isSearching) {
      _idle();
      return;
    }
    _debounce = Timer(searchDebounce, () => unawaited(_search()));
  }

  void setKind(SearchKind kind) => _changed(_filters(kind: kind));

  void setCategories(Set<String> categoryIds) => _changed(_filters(categoryIds: categoryIds));

  void setStatus(SearchStatus status) => _changed(_filters(status: status));

  SearchFilters _filters({
    String? text,
    SearchKind? kind,
    Set<String>? categoryIds,
    SearchStatus? status,
  }) {
    final f = state.filters;
    return SearchFilters(
      text: text ?? f.text,
      kind: kind ?? f.kind,
      categoryIds: categoryIds ?? f.categoryIds,
      status: status ?? f.status,
    );
  }

  void _changed(SearchFilters filters) {
    _debounce?.cancel();
    state = state.copyWith(filters: filters);
    if (!filters.isSearching) {
      _idle();
      return;
    }
    unawaited(_search());
  }

  /// Nothing to look for: no results, no request, no late answer.
  void _idle() {
    _generation++;
    state = SearchState(filters: state.filters);
  }

  /// Searches the first page of the current filters. [keep] leaves the shown results in place
  /// until the new ones land (a refresh).
  Future<void> _search({bool keep = false}) async {
    _debounce?.cancel();
    final filters = state.filters;
    final seq = ++_generation;
    state = keep
        ? state.copyWith(loading: true, loadingMore: false, failure: () => null)
        : SearchState(filters: filters, loading: true);
    try {
      final page = await _repo.search(filters);
      if (seq != _generation) return;
      state = SearchState(
        filters: filters,
        items: page.items,
        totals: page.totals,
        nextCursor: page.nextCursor,
      );
    } catch (error) {
      if (seq != _generation) return;
      state = state.copyWith(
        loading: false,
        failure: () => error is HomeFailure ? error : const HomeFailure(0),
      );
    }
  }

  /// Appends the next page; the totals stay. A failure keeps what is shown and sets
  /// [SearchState.failure].
  Future<void> loadMore() async {
    final cursor = state.nextCursor;
    if (cursor == null || state.loading || state.loadingMore) return;
    final filters = state.filters;
    final seq = ++_generation;
    state = state.copyWith(loadingMore: true, failure: () => null);
    try {
      final page = await _repo.search(filters, cursor: cursor);
      if (seq != _generation) return;
      state = state.copyWith(
        items: [...state.items, ...page.items],
        nextCursor: () => page.nextCursor,
        loadingMore: false,
      );
    } catch (error) {
      if (seq != _generation) return;
      state = state.copyWith(
        loadingMore: false,
        failure: () => error is HomeFailure ? error : const HomeFailure(0),
      );
    }
  }

  /// After a failure: the page that failed again, or the search when no page had loaded.
  Future<void> retry() {
    if (state.items.isNotEmpty && state.nextCursor != null) return loadMore();
    return refresh();
  }

  /// Reloads the first page with the same filters (pull to refresh); what is shown stays until it
  /// lands.
  Future<void> refresh() {
    if (!state.filters.isSearching) return Future.value();
    return _search(keep: true);
  }
}

final searchControllerProvider = NotifierProvider.autoDispose<SearchController, SearchState>(
  SearchController.new,
);
