import 'dart:async';
import 'dart:convert';

import 'package:wambito/api/gen/wambito_api.dart';
import 'package:wambito/home/home_cache.dart';
import 'package:wambito/home/home_repository.dart';
import 'package:wambito/home/widget_pin.dart';
import 'package:wambito/home/widget_snapshot.dart';
import 'package:wambito/offline/pending_saves.dart';

import 'fixtures.dart';

int _newestFirst(Transaction a, Transaction b) {
  final byDate = b.date.compareTo(a.date);
  return byDate != 0 ? byDate : b.id.compareTo(a.id);
}

/// The server in memory: a month's transactions and categories, paged like the API, and a summary
/// computed from them (a budget total and spending per category). Records every call, and fails a
/// call when told to.
class FakeHomeRepository implements HomeRepository {
  FakeHomeRepository({
    this.currency = 'COP',
    this.timezone = 'America/Bogota',
    this.userId = 'user-1',
    this.email = '',
    this.budgetTotal = 0,
    List<Category>? categoryList,
    List<Transaction>? items,
    this.pageSize = 50,
  }) : categoryList = categoryList ?? [category('cat-groceries', 'Supermercado')],
       items = items ?? [] {
    // The API's order: date, then id, newest first.
    this.items.sort(_newestFirst);
  }

  /// The profile's currency and time zone: Settings changes them (the server's PATCH).
  String currency;
  String timezone;
  final String userId;

  /// The profile's email ("Entraste como…" in Settings).
  final String email;

  /// Cents. Zero: no budgets.
  int budgetTotal;
  final List<Category> categoryList;

  /// Live transactions, newest first. Deleted ones move to [deleted].
  final List<Transaction> items;
  final deleted = <Transaction>[];
  int pageSize;

  final calls = <String>[];

  /// Runs as a summary is asked, before it is computed (a server whose lines follow its data).
  void Function()? beforeSummary;

  /// While set, every [summary] answer waits for it (a slow connection).
  Completer<void>? holdSummary;

  /// The next [summary] calls each take (and wait for) one of these, in order: a slow request
  /// followed by faster ones.
  final summaryGates = <Completer<void>>[];

  /// While set, a next page ("Ver más movimientos": a call with a cursor) waits for it.
  Completer<void>? holdPage;

  /// While set, [delete] waits for it, and then fails with [deleteFailure] when that is set.
  Completer<void>? holdDelete;
  Object? deleteFailure;

  /// What the next call of that name throws (then cleared).
  final failures = <String, Object>{};

  void _call(String name) {
    calls.add(name);
    final failure = failures.remove(name.split(' ').first);
    if (failure != null) throw failure;
  }

  @override
  Future<HomeProfile> profile() async {
    _call('profile');
    return HomeProfile(id: userId, currency: currency, timezone: timezone, email: email);
  }

  @override
  Future<Summary> summary(String month) async {
    _call('summary $month');
    beforeSummary?.call();
    final gate = summaryGates.isEmpty ? null : summaryGates.removeAt(0);
    final spent = items
        .where(
          (t) => t.date.startsWith(month) && t.amount < 0 && t.status == TransactionStatusEnum.paid,
        )
        .fold<int>(0, (sum, t) => sum - t.amount);
    // The server computes it when the request arrives, and answers when it is done.
    final answer = Summary(
      (b) => b
        ..month = month
        ..budgetTotal = budgetTotal
        ..spent = spent
        ..remaining = budgetTotal - spent
        ..income = 0
        ..balance = -spent
        ..categories.replace(categoryLines),
    );
    await holdSummary?.future;
    await gate?.future;
    return answer;
  }

  /// The summary's per-category lines (budgets and states), as the test needs them.
  List<SummaryCategoriesInner> categoryLines = const [];

  @override
  Future<List<Category>> categories() async {
    _call('categories');
    return categoryList;
  }

  @override
  Future<TransactionsPage> transactions(String month, {String? cursor}) async {
    _call('transactions $month ${cursor ?? ''}'.trimRight());
    final live = items.where((t) => t.date.startsWith(month)).toList();
    final start = cursor == null ? 0 : int.parse(cursor);
    final end = (start + pageSize).clamp(0, live.length);
    if (cursor != null) await holdPage?.future;
    return TransactionsPage(live.sublist(start, end), end < live.length ? '$end' : null);
  }

  /// Not in [calls]: the many tests that list them are about the month, not this.
  @override
  Future<bool> hasTransactions() async {
    final failure = failures.remove('hasTransactions');
    if (failure != null) throw failure;
    return items.isNotEmpty;
  }

  @override
  Future<void> delete(String id) async {
    _call('delete $id');
    await holdDelete?.future;
    if (deleteFailure != null) throw deleteFailure!;
    final tx = items.firstWhere((t) => t.id == id);
    items.remove(tx);
    deleted.add(tx);
  }

  @override
  Future<Transaction> restore(String id) async {
    _call('restore $id');
    final tx = deleted.firstWhere((t) => t.id == id);
    deleted.remove(tx);
    items
      ..add(tx)
      ..sort(_newestFirst);
    return tx;
  }

  @override
  Future<Transaction> markPaid(String id) async {
    _call('markPaid $id');
    final index = items.indexWhere((t) => t.id == id);
    final paid = items[index].rebuild((b) => b.status = TransactionStatusEnum.paid);
    items[index] = paid;
    return paid;
  }
}

/// The widget's storage in memory.
class FakeWidgetStore implements WidgetStore {
  final saved = <String, String>{};
  Object? failure;

  /// How many times the widgets were told to redraw.
  var updates = 0;

  @override
  Future<void> save(String key, String value) async {
    if (failure != null) throw failure!;
    saved[key] = value;
  }

  @override
  Future<String?> read(String key) async {
    if (failure != null) throw failure!;
    return saved[key];
  }

  @override
  Future<void> remove(String key) async {
    if (failure != null) throw failure!;
    saved.remove(key);
  }

  @override
  Future<void> updateWidgets() async {
    if (failure != null) throw failure!;
    updates++;
  }
}

/// Whether [store] holds the signed-out snapshot: "Abre Wambito para empezar" and no figure of
/// anyone (Review Focus 4).
bool widgetSignedOut(FakeWidgetStore store) {
  final json = store.saved[widgetSnapshotKey];
  if (json == null) return false;
  final doc = jsonDecode(json) as Map<String, Object?>;
  return doc['v'] == widgetSnapshotVersion &&
      doc['signedIn'] == false &&
      !doc.containsKey('remaining') &&
      !doc.containsKey('spent') &&
      !doc.containsKey('budgetTotal') &&
      !doc.containsKey('currency') &&
      !doc.containsKey('month');
}

/// The home cache's storage in memory: one JSON string.
class FakeCacheStore implements HomeCacheStore {
  String? value;
  Object? failure;

  @override
  Future<String?> read() async {
    if (failure != null) throw failure!;
    return value;
  }

  @override
  Future<void> write(String json) async {
    if (failure != null) throw failure!;
    value = json;
  }

  @override
  Future<void> clear() async {
    if (failure != null) throw failure!;
    value = null;
  }
}

/// The queue of saves waiting for the network, kept in memory: one JSON string.
class FakePendingSavesStore implements PendingSavesStore {
  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String json) async => value = json;

  @override
  Future<void> clear() async => value = null;
}

/// The launcher in memory. By default a widget is already on the home screen, so no test sees the
/// card unless it asks for one.
class FakeWidgetPin extends WidgetPin {
  FakeWidgetPin({this.isInstalled = true, this.isSupported = true});

  bool isInstalled;
  bool isSupported;
  int pins = 0;

  @override
  Future<bool> installed() async => isInstalled;

  @override
  Future<bool> supported() async => isSupported;

  @override
  Future<bool> pin() async {
    pins++;
    return isSupported;
  }
}
