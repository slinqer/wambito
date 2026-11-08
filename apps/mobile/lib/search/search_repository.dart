import 'package:built_collection/built_collection.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/gen/wambito_api.dart';
import '../api/session.dart';
import '../home/home_repository.dart';

enum SearchKind { all, expense, income }

enum SearchStatus { all, paid, pending }

/// What the search screen asks for: words, a kind, categories and a status.
@immutable
class SearchFilters {
  const SearchFilters({
    this.text = '',
    this.kind = SearchKind.all,
    this.categoryIds = const {},
    this.status = SearchStatus.all,
  });

  final String text;
  final SearchKind kind;
  final Set<String> categoryIds;
  final SearchStatus status;

  /// Whether there is anything to look for: words (not just blanks) or any filter.
  bool get isSearching =>
      text.trim().isNotEmpty ||
      kind != SearchKind.all ||
      categoryIds.isNotEmpty ||
      status != SearchStatus.all;

  @override
  bool operator ==(Object other) =>
      other is SearchFilters &&
      other.text == text &&
      other.kind == kind &&
      other.status == status &&
      setEquals(other.categoryIds, categoryIds);

  @override
  int get hashCode => Object.hash(text, kind, status, Object.hashAllUnordered(categoryIds));
}

/// Totals over every match, positive cents, independent of the page.
class SearchTotals {
  const SearchTotals({required this.count, required this.expense, required this.income});

  final int count;
  final int expense;
  final int income;
}

class SearchPage {
  const SearchPage({required this.items, required this.nextCursor, required this.totals});

  final List<Transaction> items;
  final String? nextCursor;

  /// Null when the server sent none.
  final SearchTotals? totals;
}

abstract interface class SearchRepository {
  Future<SearchPage> search(SearchFilters f, {String? cursor});
}

/// [SearchRepository] over the generated client.
class ApiSearchRepository implements SearchRepository {
  ApiSearchRepository(this._api);

  final DefaultApi _api;

  @override
  Future<SearchPage> search(SearchFilters f, {String? cursor}) async {
    final text = f.text.trim();
    try {
      final page = (await _api.listTransactions(
        q: text.isEmpty ? null : BuiltList<String>([text]),
        category: f.categoryIds.isEmpty ? null : BuiltList<String>(f.categoryIds),
        kind: f.kind == SearchKind.all ? null : f.kind.name,
        status: f.status == SearchStatus.all ? null : f.status.name,
        totals: cursor == null ? 'true' : null,
        cursor: cursor,
        limit: transactionsPageSize,
      )).data;
      if (page == null) throw const HomeFailure(500);
      final t = page.totals;
      return SearchPage(
        items: page.items.toList(),
        nextCursor: page.nextCursor,
        totals: t == null
            ? null
            : SearchTotals(count: t.count, expense: t.expense, income: t.income),
      );
    } on DioException catch (error) {
      throw HomeFailure.fromDio(error);
    }
  }
}

final searchRepositoryProvider = Provider<SearchRepository>(
  (ref) => ApiSearchRepository(ref.watch(apiClientProvider).api.getDefaultApi()),
);
