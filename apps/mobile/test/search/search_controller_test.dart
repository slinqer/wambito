import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/api/gen/wambito_api.dart';
import 'package:wambito/home/home_repository.dart';
import 'package:wambito/search/search_controller.dart';
import 'package:wambito/search/search_repository.dart';

Transaction _tx(String id) => Transaction(
  (b) => b
    ..id = id
    ..name = 'Cafe $id'
    ..amount = -1000
    ..currency = 'COP'
    ..date = '2026-10-25'
    ..status = TransactionStatusEnum.paid
    ..categoryId = 'c1'
    ..needsReview = false
    ..source_ = TransactionSource_Enum.app
    ..createdAt = '2026-10-01T10:00:00.000Z'
    ..updatedAt = '2026-10-01T10:00:00.000Z',
);

class _Call {
  _Call(this.filters, this.cursor);
  final SearchFilters filters;
  final String? cursor;
  final completer = Completer<SearchPage>();
}

class _FakeRepo implements SearchRepository {
  final calls = <_Call>[];

  @override
  Future<SearchPage> search(SearchFilters f, {String? cursor}) {
    final call = _Call(f, cursor);
    calls.add(call);
    return call.completer.future;
  }
}

SearchPage _page(List<String> ids, {String? next, SearchTotals? totals}) => SearchPage(
  items: ids.map(_tx).toList(),
  nextCursor: next,
  totals: totals ?? SearchTotals(count: ids.length, expense: 1000 * ids.length, income: 0),
);

void main() {
  late _FakeRepo repo;
  late ProviderContainer container;
  setUp(() {
    repo = _FakeRepo();
    container = ProviderContainer(overrides: [searchRepositoryProvider.overrideWithValue(repo)]);
    addTearDown(container.dispose);
  });

  SearchState read() => container.read(searchControllerProvider);
  SearchController ctl() => container.read(searchControllerProvider.notifier);

  test('setText searches once, 300 ms after the last call', () {
    fakeAsync((async) {
      container.listen(searchControllerProvider, (_, _) {});
      ctl().setText('c');
      async.elapse(const Duration(milliseconds: 200));
      ctl().setText('ca');
      async.elapse(const Duration(milliseconds: 200));
      ctl().setText('caf');
      async.elapse(const Duration(milliseconds: 299));
      expect(repo.calls, isEmpty);
      expect(read().filters.text, 'caf');
      async.elapse(const Duration(milliseconds: 1));
      expect(repo.calls, hasLength(1));
      expect(repo.calls.single.filters.text, 'caf');
      expect(read().loading, isTrue);
      repo.calls.single.completer.complete(_page(['a', 'b'], next: 'n'));
      async.flushMicrotasks();
      expect(read().loading, isFalse);
      expect(read().items.map((t) => t.id), ['a', 'b']);
      expect(read().nextCursor, 'n');
      expect(read().totals?.count, 2);
    });
  });

  test('a filter change searches at once and cancels a pending text search', () {
    fakeAsync((async) {
      container.listen(searchControllerProvider, (_, _) {});
      ctl().setText('caf');
      ctl().setKind(SearchKind.expense);
      expect(repo.calls, hasLength(1));
      expect(repo.calls.last.filters.kind, SearchKind.expense);
      expect(repo.calls.last.filters.text, 'caf');
      async.elapse(const Duration(seconds: 1));
      expect(repo.calls, hasLength(1));
      ctl().setCategories({'c1'});
      expect(repo.calls, hasLength(2));
      expect(repo.calls.last.filters.categoryIds, {'c1'});
      ctl().setStatus(SearchStatus.pending);
      expect(repo.calls, hasLength(3));
      expect(repo.calls.last.filters.status, SearchStatus.pending);
    });
  });

  test('an older response arriving after a newer one is dropped', () {
    fakeAsync((async) {
      container.listen(searchControllerProvider, (_, _) {});
      ctl().setKind(SearchKind.expense);
      ctl().setKind(SearchKind.income);
      expect(repo.calls, hasLength(2));
      repo.calls[1].completer.complete(_page(['new']));
      async.flushMicrotasks();
      repo.calls[0].completer.complete(_page(['old']));
      async.flushMicrotasks();
      expect(read().items.map((t) => t.id), ['new']);
      expect(read().loading, isFalse);
    });
  });

  test('only spaces: no call, idle state', () {
    fakeAsync((async) {
      container.listen(searchControllerProvider, (_, _) {});
      ctl().setText('caf');
      async.elapse(const Duration(milliseconds: 300));
      repo.calls.single.completer.complete(_page(['a']));
      async.flushMicrotasks();
      expect(read().items, isNotEmpty);

      ctl().setText('   ');
      async.elapse(const Duration(seconds: 1));
      expect(repo.calls, hasLength(1));
      expect(read().items, isEmpty);
      expect(read().totals, isNull);
      expect(read().nextCursor, isNull);
      expect(read().loading, isFalse);
    });
  });

  test('blanking the text while a search is in flight drops its answer', () {
    fakeAsync((async) {
      container.listen(searchControllerProvider, (_, _) {});
      ctl().setText('caf');
      async.elapse(const Duration(milliseconds: 300));
      ctl().setText('');
      repo.calls.single.completer.complete(_page(['a']));
      async.flushMicrotasks();
      expect(read().items, isEmpty);
      expect(read().loading, isFalse);
    });
  });

  test('loadMore appends and keeps the totals', () {
    fakeAsync((async) {
      container.listen(searchControllerProvider, (_, _) {});
      ctl().setKind(SearchKind.expense);
      repo.calls[0].completer.complete(
        _page(['a'], next: 'n1', totals: const SearchTotals(count: 3, expense: 3000, income: 0)),
      );
      async.flushMicrotasks();
      unawaited(ctl().loadMore());
      expect(read().loadingMore, isTrue);
      expect(repo.calls[1].cursor, 'n1');
      expect(repo.calls[1].filters.kind, SearchKind.expense);
      repo.calls[1].completer.complete(_page(['b', 'c']));
      async.flushMicrotasks();
      expect(read().items.map((t) => t.id), ['a', 'b', 'c']);
      expect(read().totals?.count, 3);
      expect(read().nextCursor, isNull);
      expect(read().loadingMore, isFalse);
    });
  });

  test('loadMore does nothing without a cursor or while loading more', () {
    fakeAsync((async) {
      container.listen(searchControllerProvider, (_, _) {});
      ctl().setKind(SearchKind.expense);
      repo.calls[0].completer.complete(_page(['a'], next: 'n1'));
      async.flushMicrotasks();
      unawaited(ctl().loadMore());
      unawaited(ctl().loadMore());
      expect(repo.calls, hasLength(2));
      repo.calls[1].completer.complete(_page(['b']));
      async.flushMicrotasks();
      unawaited(ctl().loadMore());
      expect(repo.calls, hasLength(2));
    });
  });

  test('a loadMore failure keeps the items and sets failure; retry loads that page', () {
    fakeAsync((async) {
      container.listen(searchControllerProvider, (_, _) {});
      ctl().setKind(SearchKind.expense);
      repo.calls[0].completer.complete(_page(['a'], next: 'n1'));
      async.flushMicrotasks();
      unawaited(ctl().loadMore());
      repo.calls[1].completer.completeError(const HomeFailure(0));
      async.flushMicrotasks();
      expect(read().items.map((t) => t.id), ['a']);
      expect(read().nextCursor, 'n1');
      expect(read().failure, isNotNull);
      expect(read().loadingMore, isFalse);

      unawaited(ctl().retry());
      expect(read().failure, isNull);
      expect(repo.calls[2].cursor, 'n1');
      repo.calls[2].completer.complete(_page(['b']));
      async.flushMicrotasks();
      expect(read().items.map((t) => t.id), ['a', 'b']);
    });
  });

  test('a first-page failure sets failure with no items; retry searches again', () {
    fakeAsync((async) {
      container.listen(searchControllerProvider, (_, _) {});
      ctl().setKind(SearchKind.expense);
      repo.calls[0].completer.completeError(const HomeFailure(500));
      async.flushMicrotasks();
      expect(read().failure?.status, 500);
      expect(read().items, isEmpty);
      expect(read().loading, isFalse);

      unawaited(ctl().retry());
      expect(read().failure, isNull);
      expect(read().loading, isTrue);
      expect(repo.calls[1].cursor, isNull);
      repo.calls[1].completer.complete(_page(['a']));
      async.flushMicrotasks();
      expect(read().items.map((t) => t.id), ['a']);
    });
  });

  test('refresh reloads the first page with the same filters', () {
    fakeAsync((async) {
      container.listen(searchControllerProvider, (_, _) {});
      ctl().setStatus(SearchStatus.paid);
      repo.calls[0].completer.complete(_page(['a'], next: 'n1'));
      async.flushMicrotasks();
      unawaited(ctl().refresh());
      expect(repo.calls, hasLength(2));
      expect(repo.calls[1].cursor, isNull);
      expect(repo.calls[1].filters.status, SearchStatus.paid);
      repo.calls[1].completer.complete(_page(['z']));
      async.flushMicrotasks();
      expect(read().items.map((t) => t.id), ['z']);
      expect(read().nextCursor, isNull);
    });
  });

  test('refresh with nothing to search does not call', () {
    fakeAsync((async) {
      container.listen(searchControllerProvider, (_, _) {});
      unawaited(ctl().refresh());
      expect(repo.calls, isEmpty);
    });
  });

  test('totals stay null when the page has none', () {
    fakeAsync((async) {
      container.listen(searchControllerProvider, (_, _) {});
      ctl().setKind(SearchKind.income);
      repo.calls[0].completer.complete(const SearchPage(items: [], nextCursor: null, totals: null));
      async.flushMicrotasks();
      expect(read().totals, isNull);
      expect(read().items, isEmpty);
    });
  });

  test('loadMore does nothing while a text debounce is pending', () {
    fakeAsync((async) {
      container.listen(searchControllerProvider, (_, _) {});
      ctl().setKind(SearchKind.expense);
      repo.calls[0].completer.complete(_page(['a'], next: 'n1'));
      async.flushMicrotasks();
      ctl().setText('caf');
      unawaited(ctl().loadMore());
      expect(repo.calls, hasLength(1), reason: 'the new text must not page with the old cursor');
      expect(read().loadingMore, isFalse);
      async.elapse(searchDebounce);
      expect(repo.calls, hasLength(2));
      expect(repo.calls[1].cursor, isNull);
      expect(repo.calls[1].filters.text, 'caf');
    });
  });

  test('retry after a failed refresh repeats the refresh, not loadMore', () {
    fakeAsync((async) {
      container.listen(searchControllerProvider, (_, _) {});
      ctl().setKind(SearchKind.expense);
      repo.calls[0].completer.complete(_page(['a'], next: 'n1'));
      async.flushMicrotasks();
      unawaited(ctl().refresh());
      repo.calls[1].completer.completeError(const HomeFailure(0));
      async.flushMicrotasks();
      expect(read().failure, isNotNull);
      expect(read().items.map((t) => t.id), ['a']);

      unawaited(ctl().retry());
      expect(repo.calls, hasLength(3));
      expect(repo.calls[2].cursor, isNull, reason: 'the first page again');
      repo.calls[2].completer.complete(_page(['z']));
      async.flushMicrotasks();
      expect(read().items.map((t) => t.id), ['z']);
      expect(read().failure, isNull);
    });
  });

  test('the text is cut at 100 characters and the categories at 20', () {
    fakeAsync((async) {
      container.listen(searchControllerProvider, (_, _) {});
      ctl().setText('x' * 150);
      expect(read().filters.text, hasLength(100));
      ctl().setCategories({for (var i = 0; i < 30; i++) 'c$i'});
      expect(read().filters.categoryIds, hasLength(20));
    });
  });
}
