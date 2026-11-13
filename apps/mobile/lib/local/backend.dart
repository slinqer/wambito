// Port of apps/web/app/local/backend.ts: the `/v1/*` finance routes answered from a
// `FinanceStore` with the API's shapes, the `lib/core` rules, the same validation and the same
// problem+json codes. Nothing leaves the phone.
//
// Each request runs in one store transaction: it reads a consistent snapshot, its writes commit
// together, and a refusal (a 4xx) leaves the store untouched. Non-record state (the idempotency
// keys) lives here, not in the store.
import 'dart:convert';

import '../core/budget.dart';
import '../core/cost_of_living.dart';
import '../core/dates.dart';
import '../core/js_math.dart' show stableSorted;
import '../core/movement_search.dart';
import '../core/recurrence.dart';
import '../core/reports.dart';
import '../core/schemas.dart';
import '../core/summary.dart';
import '../crypto/records.dart' show RecordType;
import 'ids.dart';
import 'store.dart';

/// A route this backend refuses with 403 `demo_unavailable`.
class UnavailableRoute {
  const UnavailableRoute(this.method, this.path, {this.prefix = false});

  /// An HTTP method, or `*`.
  final String method;

  /// Under `/v1`, e.g. `/v1/me/export`.
  final String path;

  /// Also match every path below it.
  final bool prefix;
}

/// What the phone turns off for a vault account (the web's `LOCAL_UNAVAILABLE`): export, imports
/// and the assistants.
const localUnavailable = [
  UnavailableRoute('*', '/v1/me/export'),
  UnavailableRoute('*', '/v1/imports', prefix: true),
  UnavailableRoute('*', '/v1/me/assistants', prefix: true),
];

/// The account facts the settings record does not hold.
class LocalProfile {
  const LocalProfile({
    this.id = 'local',
    this.email = '',
    this.isAnonymous = false,
    this.encryption = 'plain',
  });

  final String id;
  final String email;
  final bool isAnonymous;

  /// What `GET /v1/me` says.
  final String encryption;
}

class LocalResponse {
  const LocalResponse(this.status, [this.body]);

  final int status;

  /// JSON-encodable, or null (204).
  final Object? body;
}

/// Answers `/v1` requests from the store.
abstract interface class LocalBackend {
  /// [path] starts at `/v1`. [body] is the decoded JSON (or its text). A [query] value is a
  /// `String` or a `List<String>` (repeated parameters: `q`, `category`). Returns null for a path
  /// this backend does not serve, so the caller sends it to the network.
  Future<LocalResponse?> handle(
    String method,
    String path,
    Map<String, Object> query,
    Object? body, {
    Map<String, String> headers,
  });
}

LocalBackend createLocalBackend({
  required FinanceStore store,
  required DateTime Function() now,
  List<UnavailableRoute> unavailable = const [],
  String timezone = 'UTC',
  LocalProfile profile = const LocalProfile(),
  String Function()? newId,
}) => _Backend(
  store: store,
  now: now,
  unavailable: unavailable,
  freshTimezone: timezone,
  profile: profile,
  newId: newId ?? () => uuidv7(now().millisecondsSinceEpoch),
);

// -- Problems ---------------------------------------------------------------------------------

/// A refusal, rendered as the API's problem+json.
class _Problem implements Exception {
  _Problem(this.status, this.code, [this.detail, this.errors]);

  final int status;
  final String code;
  final String? detail;
  final List<Issue>? errors;
}

const _titles = {
  400: 'Bad Request',
  403: 'Forbidden',
  404: 'Not Found',
  409: 'Conflict',
  422: 'Unprocessable Content',
  500: 'Internal Server Error',
};

final _uuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  caseSensitive: false,
);

Json _valid(Schema<Json> schema, Object? value, [String detail = 'The request is invalid']) {
  return switch (validate(schema, value)) {
    Valid<Json>(:final data) => data,
    Invalid<Json>(:final issues) => throw _Problem(422, 'validation_failed', detail, issues),
  };
}

_Problem _invalid(String path, String message) =>
    _Problem(422, 'validation_failed', 'The request is invalid', [Issue(path, message)]);

// -- Rows -------------------------------------------------------------------------------------

/// A record body with its envelope id (categories, recurrences, budgets).
typedef Row = Json;

Row _row(String id, Json body) => {...body, 'id': id};

Json _bodyOf(Row row) => {...row}..remove('id');

Future<List<Row>> _rows(StoreOps s, RecordType type) async => [
  for (final r in await s.list(type)) _row(r.id, r.body),
];

/// A transaction as the screens and the core reports read it.
class _Tx {
  _Tx(this.id, this.body, [this.deleted = false]);

  final String id;
  final Json body;
  final bool deleted;

  String get name => body['name']! as String;
  int get amount => body['amount']! as int;
  String get date => body['date']! as String;
  String get status => body['status']! as String;
  String? get note => body['note'] as String?;
  String get categoryId => body['categoryId']! as String;
  String? get recurrenceId => body['recurrenceId'] as String?;
  String? get occurrenceMonth => body['occurrenceMonth'] as String?;
  String? get source => body['source'] as String?;
  bool get needsReview => body['needsReview'] == true;
  String get createdAt => (body['createdAt'] as String?) ?? '';
  String get updatedAt => (body['updatedAt'] as String?) ?? createdAt;

  Json toDto() => {
    'id': id,
    'name': name,
    'amount': amount,
    'currency': body['currency'],
    'date': date,
    'status': status,
    'note': note,
    'categoryId': categoryId,
    'recurrenceId': recurrenceId,
    'importId': null,
    'source': source,
    'needsReview': needsReview,
    'captureSource': body['captureSource'],
    'createdAt': createdAt,
    'updatedAt': updatedAt,
  };

  SearchableMovement get searchable => SearchableMovement(
    name: name,
    note: note,
    categoryId: categoryId,
    amount: amount,
    status: TxStatus.parse(status),
  );

  ReportTransaction get report => ReportTransaction(
    categoryId: categoryId,
    amount: amount,
    date: date,
    status: TxStatus.parse(status),
  );
}

Future<List<_Tx>> _txRows(StoreOps s, [ReadOptions opts = const ReadOptions()]) async => [
  for (final r in await s.list(RecordType.transaction, opts)) _Tx(r.id, r.body, r.deleted),
];

Json _recurrenceDto(Row r) => {
  'id': r['id'],
  'name': r['name'],
  'amount': r['amount'],
  'categoryId': r['categoryId'],
  'frequency': r['frequency'],
  'dayOfMonth': r['dayOfMonth'],
  'monthOfYear': r['monthOfYear'],
  'startDate': r['startDate'],
  'endDate': r['endDate'],
};

String _text(Object? o) => (o as String?) ?? '';

int _cmp(String a, String b) => a.compareTo(b);

int _byNewest(_Tx x, _Tx y) =>
    x.date != y.date ? (x.date.compareTo(y.date) < 0 ? 1 : -1) : -x.id.compareTo(y.id).sign;

int _byOrder(Row x, Row y) {
  final order = (x['sortOrder']! as int).compareTo(y['sortOrder']! as int);
  return order != 0 ? order : _cmp(_text(x['createdAt']), _text(y['createdAt']));
}

String _encodeCursor(_Tx row) =>
    base64Url.encode(utf8.encode('${row.date}|${row.id}')).replaceAll('=', '');

({String date, String id}) _decodeCursor(String cursor) {
  try {
    final parts = utf8.decode(base64Url.decode(base64Url.normalize(cursor))).split('|');
    if (parts.length >= 2 && RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(parts[0])) {
      if (parts[1].isNotEmpty && _uuid.hasMatch(parts[1])) return (date: parts[0], id: parts[1]);
    }
  } on FormatException {
    // Not base64: invalid like any other.
  }
  throw _Problem(422, 'validation_failed', 'Invalid cursor', [
    const Issue('cursor', 'Invalid cursor'),
  ]);
}

// -- Query parameters -------------------------------------------------------------------------

/// The request's query: every name's values, in order.
class _Params {
  _Params(Map<String, Object> raw)
    : _all = {
        for (final e in raw.entries)
          e.key: e.value is List ? [for (final v in e.value as List) '$v'] : ['${e.value}'],
      };

  final Map<String, List<String>> _all;

  String? get(String name) => _all[name]?.first;
  List<String> getAll(String name) => _all[name] ?? const [];

  /// An integer parameter within [min, max], or its default when absent.
  int integer(String name, int min, int max, int fallback) {
    final raw = get(name);
    if (raw == null) return fallback;
    final value = raw.trim().isEmpty ? null : num.tryParse(raw.trim());
    if (value == null ||
        !value.isFinite ||
        value != value.truncate() ||
        value < min ||
        value > max) {
      throw _invalid(name, 'Expected an integer from $min to $max');
    }
    return value.toInt();
  }

  String? month(String name, {bool required = false}) {
    final raw = get(name);
    if (raw == null) {
      if (required) throw _invalid(name, 'Required');
      return null;
    }
    if (!isMonth(raw)) throw _invalid(name, 'Expected a month as YYYY-MM');
    return raw;
  }

  String? enumeration(String name, List<String> values) {
    final raw = get(name);
    if (raw == null) return null;
    if (!values.contains(raw)) throw _invalid(name, 'Expected one of ${values.join(', ')}');
    return raw;
  }

  /// The search params of the list, validated like the API: repeated `q` and `category`, `kind`,
  /// `match`.
  MovementSearch search() {
    final terms = getAll('q');
    if (terms.length > 10) throw _invalid('q', 'At most 10 terms');
    if (terms.any((t) => t.length > 100)) throw _invalid('q', 'At most 100 characters per term');
    final categoryIds = getAll('category');
    if (categoryIds.length > 20) throw _invalid('category', 'At most 20 categories');
    if (categoryIds.any((c) => !_uuid.hasMatch(c))) throw _invalid('category', 'Invalid UUID');
    final kind = enumeration('kind', ['expense', 'income']);
    final match = enumeration('match', ['all', 'any']);
    return MovementSearch(
      terms: terms.isNotEmpty ? terms : null,
      categoryIds: categoryIds.isNotEmpty ? categoryIds : null,
      kind: kind == null ? null : CategoryKind.parse(kind),
      match: match == null ? null : MatchMode.values.byName(match),
    );
  }
}

const _maxMonths = 36;

List<String> _rangeParams(_Params params) {
  final from = params.month('from', required: true)!;
  final to = params.month('to', required: true)!;
  if (from.compareTo(to) > 0) throw _invalid('from', 'from must not be after to');
  final months = monthsBetween(from, to);
  if (months.length > _maxMonths) {
    throw _Problem(422, 'range_too_large', 'Ranges are limited to $_maxMonths months');
  }
  return months;
}

/// The settings of an account that has not saved any yet.
Json _freshSettings(String timezone) => {
  's': 1,
  'name': null,
  'currency': 'USD',
  'locale': 'en',
  'timezone': timezone,
  'onboardingCompletedAt': null,
  'revokedDevices': <Object?>[],
};

/// What one request works with: its transaction and the account's clock.
class _Env {
  _Env(this.s, this.settings, this.settingsId, this.today) : month = monthOf(today);

  final StoreOps s;
  final Json settings;
  final String? settingsId;
  final String today;
  final String month;
}

class _Answer {
  const _Answer(this.status, [this.body]);

  final int status;
  final Object? body;
}

_Answer _ok(Object? body, [int status = 200]) => _Answer(status, body);

class _Seen {
  _Seen(this.body, this.status, this.payload);

  final String body;
  final int status;
  final Object? payload;
}

// -- Routes served ----------------------------------------------------------------------------

final _txById = RegExp(r'^/v1/transactions/([^/]+)$');
final _txRestore = RegExp(r'^/v1/transactions/([^/]+)/restore$');
final _categoryById = RegExp(r'^/v1/categories/([^/]+)$');
final _categoryBudget = RegExp(r'^/v1/categories/([^/]+)/budget$');
final _recurrenceById = RegExp(r'^/v1/recurrences/([^/]+)$');

/// The paths this backend answers (the family, whatever the method).
bool _serves(String path) =>
    const {
      '/v1/me',
      '/v1/summary',
      '/v1/transactions',
      '/v1/categories',
      '/v1/recurrences',
      '/v1/reports/by-category',
      '/v1/reports/trend',
      '/v1/reports/cost-of-living',
    }.contains(path) ||
    _txById.hasMatch(path) ||
    _txRestore.hasMatch(path) ||
    _categoryById.hasMatch(path) ||
    _categoryBudget.hasMatch(path) ||
    _recurrenceById.hasMatch(path);

class _Backend implements LocalBackend {
  _Backend({
    required this.store,
    required this.now,
    required this.unavailable,
    required this.freshTimezone,
    required this.profile,
    required this.newId,
  });

  final FinanceStore store;
  final DateTime Function() now;
  final List<UnavailableRoute> unavailable;
  final String freshTimezone;
  final LocalProfile profile;
  final String Function() newId;

  /// Idempotency-Key → the body it was sent with and what it got.
  final Map<String, _Seen> _idempotency = {};

  /// The clock as the API stamps it: ISO 8601 UTC with milliseconds.
  String stamp() => DateTime.fromMillisecondsSinceEpoch(
    now().millisecondsSinceEpoch,
    isUtc: true,
  ).toIso8601String();

  Future<_Env> _envOf(StoreOps s) async {
    final all = await s.list(RecordType.settings);
    final first = all.isEmpty ? null : all.first;
    final settings = first?.body ?? _freshSettings(freshTimezone);
    return _Env(s, settings, first?.id, todayIn(settings['timezone']! as String, now()));
  }

  Future<List<BudgetEntry>> _budgetEntries(StoreOps s) async => [
    for (final r in await s.list(RecordType.budget))
      BudgetEntry(
        categoryId: r.body['categoryId']! as String,
        amount: r.body['amount']! as int,
        effectiveFrom: r.body['effectiveFrom']! as String,
      ),
  ];

  Future<Row> _findCategory(StoreOps s, String id) async {
    final found = await s.get(RecordType.category, id);
    if (found == null) throw _Problem(404, 'not_found', 'Category not found');
    return _row(id, found.body);
  }

  Future<Row> _requireActiveCategory(StoreOps s, String id) async {
    final found = await s.get(RecordType.category, id);
    if (found == null || found.body['archivedAt'] != null) {
      throw _Problem(422, 'category_not_found', 'Pick one of your active categories');
    }
    return _row(id, found.body);
  }

  Future<StoredRecord> _findLive(StoreOps s, String id) async {
    final found = await s.get(RecordType.transaction, id);
    if (found == null) throw _Problem(404, 'not_found', 'Transaction not found');
    return found;
  }

  Future<Row> _findRecurrence(StoreOps s, String id) async {
    final found = await s.get(RecordType.recurrence, id);
    if (found == null) throw _Problem(404, 'not_found', 'Recurrence not found');
    return _row(id, found.body);
  }

  Json _categoryDto(_Env e, Row row, List<BudgetEntry> budgets) => {
    'id': row['id'],
    'name': row['name'],
    'kind': row['kind'],
    'icon': row['icon'],
    'color': row['color'],
    'sortOrder': row['sortOrder'],
    'archived': row['archivedAt'] != null,
    'currentBudget': row['kind'] == 'expense'
        ? effectiveBudget(budgets, row['id']! as String, e.month)
        : null,
  };

  Future<void> _requireUniqueName(StoreOps s, String name, [String? except]) async {
    final key = name.toLowerCase();
    final taken = (await _rows(s, RecordType.category)).any(
      (c) =>
          c['id'] != except &&
          c['archivedAt'] == null &&
          (c['name']! as String).toLowerCase() == key,
    );
    if (taken) {
      throw _Problem(409, 'category_name_taken', 'You already have a category with that name');
    }
  }

  /// The API's materializeRecurrences: the missing pending occurrences of these months. An
  /// occurrence's id is the UUID v5 of its rule and month, so every device makes the same one.
  Future<void> _materialize(_Env e, List<String> months) async {
    final limit = addMonths(e.month, 1);
    final wanted = [
      for (final m in months)
        if (m.compareTo(limit) <= 0) m,
    ];
    if (wanted.isEmpty) return;
    final rules = await _rows(e.s, RecordType.recurrence);
    if (rules.isEmpty) return;
    final categories = {
      for (final c in await _rows(e.s, RecordType.category)) c['id']! as String: c,
    };
    final existing = await _txRows(e.s, const ReadOptions(includeDeleted: true));
    final byKey = <String, List<_Tx>>{};
    for (final t in existing) {
      final ruleId = t.recurrenceId;
      final month = t.occurrenceMonth;
      if (ruleId == null || month == null) continue;
      byKey.putIfAbsent('$ruleId|$month', () => []).add(t);
    }
    for (final month in wanted) {
      for (final rule in rules) {
        final category = categories[rule['categoryId']];
        if (category == null || category['archivedAt'] != null) continue;
        final ruleId = rule['id']! as String;
        for (final date in occurrences(RecurrenceRule.fromJson(rule), month)) {
          final id = uuidv5(ruleId, '$month:${rule['rev'] ?? 0}');
          // One per rule and month, deleted or not. A pending occurrence of an older revision
          // that was dropped (a tombstone under another id) does not count.
          final blocked = (byKey['$ruleId|$month'] ?? const []).any(
            (t) => !t.deleted || t.id == id || t.status != 'pending' || t.source != 'recurrence',
          );
          if (blocked) continue;
          byKey['$ruleId|$month'] = [_Tx(id, const {})];
          await e.s.put(RecordType.transaction, id, {
            's': 1,
            'name': rule['name'],
            'amount': rule['amount'],
            'currency': e.settings['currency'],
            'date': date,
            'status': 'pending',
            'note': null,
            'categoryId': rule['categoryId'],
            'accountId': null,
            'recurrenceId': ruleId,
            'occurrenceMonth': month,
            'source': 'recurrence',
            'needsReview': false,
            'captureSource': null,
            'capturedAt': null,
            'captureMerchantKey': null,
            'createdAt': stamp(),
            'updatedAt': stamp(),
          });
        }
      }
    }
  }

  /// Unpaid, not dismissed pending rows of these rules, from a month (by occurrence) or a date on,
  /// go (a normal delete). The rules then move to the next revision, so the occurrences made again
  /// get new ids; the occurrences the person had deleted move with them and stay deleted.
  /// `bump: false` is for rules that are going away.
  Future<void> _dropPending(
    StoreOps s,
    List<String> ids, {
    String? fromMonth,
    String? fromDate,
    bool bump = true,
  }) async {
    final all = await _txRows(s, const ReadOptions(includeDeleted: true));
    final kept = <_Tx>[];
    for (final t in all) {
      final ruleId = t.recurrenceId;
      if (ruleId == null || !ids.contains(ruleId)) continue;
      if (t.deleted) {
        if (t.status == 'pending' && t.source == 'recurrence' && t.occurrenceMonth != null) {
          kept.add(t);
        }
        continue;
      }
      if (t.status != 'pending') continue;
      final later = fromMonth != null
          ? (t.occurrenceMonth ?? monthOf(t.date)).compareTo(fromMonth) >= 0
          : t.date.compareTo(fromDate!) >= 0;
      if (later) await s.delete(RecordType.transaction, t.id);
    }
    if (!bump) return;
    for (final id in ids) {
      final rule = await s.get(RecordType.recurrence, id);
      if (rule == null) continue;
      final rev = ((rule.body['rev'] as int?) ?? 0) + 1;
      await s.put(RecordType.recurrence, id, {...rule.body, 'rev': rev});
      for (final t in kept) {
        if (t.recurrenceId != id || t.occurrenceMonth == null) continue;
        final moved = uuidv5(id, '${t.occurrenceMonth}:$rev');
        final old = await s.get(
          RecordType.transaction,
          t.id,
          const ReadOptions(includeDeleted: true),
        );
        if (old == null) continue;
        await s.put(RecordType.transaction, moved, old.body);
        await s.delete(RecordType.transaction, moved);
      }
    }
  }

  bool _inMonth(_Tx t, String month) =>
      t.date.compareTo(firstDay(month)) >= 0 && t.date.compareTo(lastDay(month)) <= 0;

  // -- /v1/me -------------------------------------------------------------------------------

  Json _meOf(_Env e) => {
    'id': profile.id,
    'email': profile.email,
    'timezone': e.settings['timezone'],
    'locale': e.settings['locale'],
    'onboardingCompletedAt': e.settings['onboardingCompletedAt'],
    'currency': e.settings['currency'],
    'isAnonymous': profile.isAnonymous,
    'encryption': profile.encryption,
  };

  Future<_Answer> _patchMe(_Env e, Object? body) async {
    final fields = _valid(updateProfileSchema, body);
    final onboardingCompleted = fields.remove('onboardingCompleted');
    final currency = fields.remove('currency');
    final next = {...e.settings};
    if (currency != null && currency != e.settings['currency']) {
      final used =
          (await e.s.list(
            RecordType.transaction,
            const ReadOptions(includeDeleted: true),
          )).isNotEmpty ||
          (await e.s.list(RecordType.recurrence)).isNotEmpty;
      if (used) {
        throw _Problem(
          409,
          'currency_locked',
          'The currency cannot change once the account has transactions or recurrences',
        );
      }
      next['currency'] = currency;
    }
    next.addAll(fields);
    if (onboardingCompleted == true) next['onboardingCompletedAt'] ??= stamp();
    await e.s.put(RecordType.settings, e.settingsId ?? newId(), next);
    return _ok(_meOf(_Env(e.s, next, e.settingsId, e.today)));
  }

  // -- /v1/summary --------------------------------------------------------------------------

  Future<Object?> _summary(_Env e, String month) async {
    await _materialize(e, [month]);
    final txs = [
      for (final t in await _txRows(e.s))
        if (_inMonth(t, month)) t,
    ];
    final used = {for (final t in txs) t.categoryId};
    final cats = [
      for (final c in stableSorted(await _rows(e.s, RecordType.category), _byOrder))
        if (c['archivedAt'] == null || used.contains(c['id'])) c,
    ];
    return monthSummary(
      SummaryInput(
        month: month,
        categories: [
          for (final c in cats)
            SummaryCategory(id: c['id']! as String, kind: CategoryKind.parse(c['kind']! as String)),
        ],
        budgets: await _budgetEntries(e.s),
        transactions: [
          for (final t in txs) SummaryTransaction(categoryId: t.categoryId, amount: t.amount),
        ],
      ),
    ).toJson();
  }

  // -- /v1/transactions ---------------------------------------------------------------------

  Future<_Answer> _listTransactions(_Env e, _Params params) async {
    final month = params.month('month');
    final search = params.search();
    final status = params.enumeration('status', ['paid', 'pending']);
    final needsReview = params.enumeration('needsReview', ['true', 'false']);
    final cursor = params.get('cursor');
    final after = cursor == null ? null : _decodeCursor(cursor);
    final limit = params.integer('limit', 1, 200, 50);
    if (month != null) await _materialize(e, [month]);
    final effective = MovementSearch(
      terms: search.terms,
      categoryIds: search.categoryIds,
      kind: search.kind,
      match: search.match,
      status: status == null ? null : TxStatus.parse(status),
    );
    final matches = stableSorted([
      for (final t in await _txRows(e.s))
        if ((month == null || _inMonth(t, month)) &&
            matchesMovementSearch(t.searchable, effective) &&
            (needsReview != 'true' || t.needsReview))
          t,
    ], _byNewest);
    // Totals cover every match, whatever the cursor.
    final totals = params.get('totals') == 'true'
        ? movementTotals([for (final t in matches) t.amount]).toJson()
        : null;
    final rest = [
      for (final t in matches)
        if (after == null ||
            t.date.compareTo(after.date) < 0 ||
            (t.date == after.date && t.id.compareTo(after.id) < 0))
          t,
    ];
    final items = rest.take(limit).toList();
    return _ok({
      'items': [for (final t in items) t.toDto()],
      'nextCursor': rest.length > limit && items.isNotEmpty ? _encodeCursor(items.last) : null,
      'totals': ?totals,
    });
  }

  /// The API's suggestions: names used before (not the category's own), with their usual category.
  Future<_Answer> _suggestions(_Env e, _Params params) async {
    final q = (params.get('q') ?? '').trim();
    if (q.length > 100) throw _invalid('q', 'At most 100 characters');
    final limit = params.integer('limit', 1, 20, 8);
    final needle = q.toLowerCase();
    final active = {
      for (final c in await _rows(e.s, RecordType.category))
        if (c['archivedAt'] == null) c['id']! as String: c,
    };
    final used = [
      for (final t in await _txRows(e.s))
        if (active[t.categoryId] case final category?
            when t.name.toLowerCase() != (category['name']! as String).toLowerCase())
          t,
    ];
    int newestFirst(_Tx x, _Tx y) {
      if (x.date != y.date) return x.date.compareTo(y.date) < 0 ? 1 : -1;
      if (x.createdAt != y.createdAt) return x.createdAt.compareTo(y.createdAt) < 0 ? 1 : -1;
      return x.id.compareTo(y.id) < 0 ? 1 : -1;
    }

    final byKey = <String, List<_Tx>>{};
    for (final t in stableSorted(used, newestFirst)) {
      byKey.putIfAbsent(t.name.toLowerCase(), () => []).add(t);
    }
    final found = stableSorted(
      [
        for (final entry in byKey.entries)
          if (needle.isEmpty || entry.key.contains(needle)) entry,
      ],
      (x, y) {
        final px = needle.isNotEmpty && x.key.startsWith(needle) ? 1 : 0;
        final py = needle.isNotEmpty && y.key.startsWith(needle) ? 1 : 0;
        return py - px != 0 ? py - px : newestFirst(x.value.first, y.value.first);
      },
    ).take(limit);
    final items = <Json>[];
    for (final entry in found) {
      final group = entry.value;
      final latest = group.first;
      // The usual category: the most uses, then the most recent.
      final counts = <String, int>{};
      for (final row in group) {
        counts[row.categoryId] = (counts[row.categoryId] ?? 0) + 1;
      }
      var usual = latest.categoryId;
      for (final row in group) {
        if ((counts[row.categoryId] ?? 0) > (counts[usual] ?? 0)) usual = row.categoryId;
      }
      items.add({'name': latest.name, 'categoryId': usual});
    }
    return _ok({'items': items});
  }

  /// The API's `idempotent` middleware: the same key and body gets the first answer back, the same
  /// key with another body is refused. With [required], a call without a key is a 400.
  Future<_Answer> _idempotent(
    String? key,
    String raw,
    Future<_Answer> Function() run, {
    bool required = false,
  }) async {
    if (key == null) {
      if (required) {
        throw _Problem(
          400,
          'idempotency_key_required',
          'Send an Idempotency-Key header with this request',
        );
      }
      return run();
    }
    final seen = _idempotency[key];
    if (seen != null) {
      if (seen.body != raw) {
        throw _Problem(
          422,
          'idempotency_key_reused',
          'This Idempotency-Key was used with a different request',
        );
      }
      return _ok(seen.payload, seen.status);
    }
    final answer = await run();
    _idempotency[key] = _Seen(raw, answer.status, answer.body);
    return answer;
  }

  /// The one insert path for single and batch create (the API's `insertTransactions`): every
  /// category is checked first, then each input is written; one with `repeat` first makes its
  /// recurrence and is saved as that rule's occurrence for its month.
  Future<List<_Tx>> _insertTransactions(_Env e, List<Json> inputs) async {
    for (final categoryId in {for (final i in inputs) i['categoryId']! as String}) {
      await _requireActiveCategory(e.s, categoryId);
    }
    final at = stamp();
    final saved = <_Tx>[];
    for (final input in inputs) {
      final categoryId = input['categoryId']! as String;
      final date = input['date']! as String;
      String? ruleId;
      final repeat = input['repeat'] as Map?;
      if (repeat != null) {
        ruleId = newId();
        await e.s.put(RecordType.recurrence, ruleId, {
          's': 1,
          'name': input['name'],
          'amount': input['amount'],
          'categoryId': categoryId,
          'frequency': repeat['frequency'],
          'dayOfMonth': int.parse(date.substring(8, 10)),
          'monthOfYear': repeat['frequency'] == 'yearly' ? int.parse(date.substring(5, 7)) : null,
          'startDate': date,
          'endDate': repeat['endDate'],
          'rev': 0,
          'createdAt': at,
        });
      }
      final id = newId();
      final record = <String, Object?>{
        's': 1,
        'name': input['name'],
        'amount': input['amount'],
        'currency': e.settings['currency'],
        'date': date,
        'status': input['status'],
        'note': input['note'],
        'categoryId': categoryId,
        'accountId': null,
        'recurrenceId': ruleId,
        'occurrenceMonth': ruleId != null ? monthOf(date) : null,
        'source': input['source'],
        'needsReview': false,
        'captureSource': null,
        'capturedAt': null,
        'captureMerchantKey': null,
        'createdAt': at,
        'updatedAt': at,
      };
      await e.s.put(RecordType.transaction, id, record);
      saved.add(_Tx(id, record));
    }
    return saved;
  }

  Future<_Answer> _createTransaction(_Env e, String raw, Object? body, String? key) =>
      _idempotent(key, raw, () async {
        final input = _valid(createTransactionSchema, body);
        final [saved] = await _insertTransactions(e, [input]);
        return _ok(saved.toDto(), 201);
      });

  /// `POST /v1/transactions/batch` (quick capture): up to 20, all or nothing, the key mandatory.
  Future<_Answer> _createBatch(_Env e, String raw, Object? body, String? key) =>
      _idempotent(key, raw, required: true, () async {
        final items = (_valid(createTransactionsBatchSchema, body)['items']! as List).cast<Json>();
        final saved = await _insertTransactions(e, items);
        return _ok({
          'items': [for (final t in saved) t.toDto()],
        }, 201);
      });

  /// `POST /v1/transactions/batch-delete`: soft-deletes the live ones among the ids, ignoring the
  /// rest without a trace.
  Future<_Answer> _deleteBatch(_Env e, Object? body) async {
    final ids = (_valid(deleteTransactionsBatchSchema, body)['ids']! as List).cast<String>();
    for (final id in ids) {
      if (await e.s.get(RecordType.transaction, id) != null) {
        await e.s.delete(RecordType.transaction, id);
      }
    }
    return const _Answer(204);
  }

  Future<_Answer> _updateTransaction(_Env e, String id, Object? body) async {
    final input = _valid(updateTransactionSchema, body);
    final found = await _findLive(e.s, id);
    final categoryId = input['categoryId'];
    if (categoryId != null) await _requireActiveCategory(e.s, categoryId as String);
    final next = {...found.body, ...input, 'updatedAt': stamp()};
    await e.s.put(RecordType.transaction, id, next);
    return _ok(_Tx(id, next).toDto());
  }

  /// `POST /v1/transactions/review`, as the API: confirms detected transactions at once, all or
  /// nothing (an unknown or deleted id is 404 and nothing changes), in request order; ids already
  /// confirmed stay as they are. The merchant memory the API learns has no record yet.
  Future<_Answer> _reviewTransactions(_Env e, Object? body) async {
    final ids = ((_valid(reviewTransactionsSchema, body)['ids']!) as List).cast<String>();
    final found = <String, Json>{};
    for (final id in ids.toSet()) {
      found[id] = (await _findLive(e.s, id)).body;
    }
    for (final id in found.keys.toList()) {
      final before = found[id]!;
      if (before['needsReview'] != true) continue;
      final next = {...before, 'needsReview': false, 'updatedAt': stamp()};
      await e.s.put(RecordType.transaction, id, next);
      found[id] = next;
    }
    return _ok({
      'items': [for (final id in ids) _Tx(id, found[id]!).toDto()],
    });
  }

  // -- /v1/categories -----------------------------------------------------------------------

  Future<_Answer> _createCategory(_Env e, Object? body) async {
    final input = _valid(createCategorySchema, body);
    await _requireUniqueName(e.s, input['name']! as String);
    final id = newId();
    final record = <String, Object?>{
      's': 1,
      'name': input['name'],
      'kind': input['kind'],
      'icon': input['icon'],
      'color': input['color'],
      'sortOrder': input['sortOrder'] ?? 0,
      'archivedAt': null,
      'systemKey': null,
      'createdAt': stamp(),
    };
    await e.s.put(RecordType.category, id, record);
    return _ok({..._categoryDto(e, _row(id, record), const []), 'currentBudget': null}, 201);
  }

  Future<_Answer> _updateCategory(_Env e, String id, Object? body) async {
    final fields = _valid(updateCategorySchema, body);
    final archived = fields.remove('archived') as bool?;
    final existing = await _findCategory(e.s, id);
    final kind = fields['kind'];
    if (kind != null && kind != existing['kind']) {
      final used = (await _txRows(
        e.s,
        const ReadOptions(includeDeleted: true),
      )).any((t) => t.categoryId == id);
      if (used) {
        throw _Problem(
          409,
          'category_has_transactions',
          'A category with transactions cannot change its kind',
        );
      }
    }
    final String? archivedAt = archived == null
        ? existing['archivedAt'] as String?
        : archived
        ? ((existing['archivedAt'] as String?) ?? stamp())
        : null;
    if (archivedAt == null) {
      await _requireUniqueName(e.s, (fields['name'] as String?) ?? existing['name']! as String, id);
    }
    final archiving = archived == true && existing['archivedAt'] == null;
    final next = {...existing, ...fields, 'archivedAt': archivedAt};
    await e.s.put(RecordType.category, id, _bodyOf(next));
    if (archiving) {
      // Its active recurrences end today, and their unpaid pending rows from today on go.
      final day = e.today;
      final stopped = [
        for (final r in await _rows(e.s, RecordType.recurrence))
          if (r['categoryId'] == id &&
              (r['endDate'] == null || (r['endDate']! as String).compareTo(day) >= 0))
            r,
      ];
      for (final rule in stopped) {
        final start = rule['startDate']! as String;
        await e.s.put(RecordType.recurrence, rule['id']! as String, {
          ..._bodyOf(rule),
          'endDate': day,
          'startDate': start.compareTo(day) > 0 ? day : start,
        });
      }
      await _dropPending(e.s, [for (final r in stopped) r['id']! as String], fromDate: day);
    }
    return _ok(_categoryDto(e, next, await _budgetEntries(e.s)));
  }

  Future<_Answer> _setBudget(_Env e, String id, Object? body) async {
    final input = _valid(setBudgetSchema, body);
    final amount = input['amount']! as int;
    final effectiveFrom = input['effectiveFrom']! as String;
    final category = await _findCategory(e.s, id);
    if (category['kind'] != 'expense') {
      throw _Problem(422, 'budget_category_not_expense', 'Only expense categories have budgets');
    }
    final entry = (await _rows(
      e.s,
      RecordType.budget,
    )).where((b) => b['categoryId'] == id && b['effectiveFrom'] == effectiveFrom).firstOrNull;
    await e.s.put(RecordType.budget, (entry?['id'] as String?) ?? newId(), {
      's': 1,
      'categoryId': id,
      'amount': amount,
      'effectiveFrom': effectiveFrom,
    });
    return _ok(_categoryDto(e, category, await _budgetEntries(e.s)));
  }

  // -- /v1/recurrences ----------------------------------------------------------------------

  Future<_Answer> _createRecurrence(_Env e, Object? body) async {
    final input = _valid(createRecurrenceSchema, body);
    await _requireActiveCategory(e.s, input['categoryId']! as String);
    final id = newId();
    final record = <String, Object?>{
      's': 1,
      'name': input['name'],
      'amount': input['amount'],
      'categoryId': input['categoryId'],
      'frequency': input['frequency'],
      'dayOfMonth': input['dayOfMonth'],
      'monthOfYear': input['monthOfYear'],
      'startDate': input['startDate'],
      'endDate': input['endDate'],
      'rev': 0,
      'createdAt': stamp(),
    };
    await e.s.put(RecordType.recurrence, id, record);
    return _ok(_recurrenceDto(_row(id, record)), 201);
  }

  Future<_Answer> _updateRecurrence(_Env e, String id, Object? body) async {
    final input = _valid(updateRecurrenceSchema, body);
    final existing = await _findRecurrence(e.s, id);
    final categoryId = input['categoryId'];
    if (categoryId != null) await _requireActiveCategory(e.s, categoryId as String);
    _valid(createRecurrenceSchema, {
      ..._recurrenceDto(existing),
      ...input,
    }, 'The recurrence is invalid');
    final next = {...existing, ...input};
    await e.s.put(RecordType.recurrence, id, _bodyOf(next));
    await _dropPending(e.s, [id], fromMonth: e.month);
    return _ok(_recurrenceDto(next));
  }

  Future<_Answer> _deleteRecurrence(_Env e, String id) async {
    await _findRecurrence(e.s, id);
    await _dropPending(e.s, [id], fromMonth: e.month, bump: false);
    await e.s.delete(RecordType.recurrence, id);
    // The rows it made stay, no longer tied to a rule (deleted ones too).
    for (final t in await e.s.list(
      RecordType.transaction,
      const ReadOptions(includeDeleted: true),
    )) {
      if (t.body['recurrenceId'] != id) continue;
      await e.s.put(RecordType.transaction, t.id, {...t.body, 'recurrenceId': null});
      if (t.deleted) await e.s.delete(RecordType.transaction, t.id);
    }
    return const _Answer(204);
  }

  // -- /v1/reports --------------------------------------------------------------------------

  Future<List<ReportCategory>> _reportCategories(StoreOps s) async => [
    for (final c in await _rows(s, RecordType.category))
      ReportCategory(
        id: c['id']! as String,
        name: c['name']! as String,
        kind: CategoryKind.parse(c['kind']! as String),
        icon: c['icon']! as String,
        color: c['color']! as String,
        archivedAt: c['archivedAt'] as String?,
      ),
  ];

  Future<_Answer> _byCategory(_Env e, _Params params) async {
    final months = _rangeParams(params);
    // Reports read their months like the screens do, as the API's reports.ts does.
    await _materialize(e, months);
    final kind = params.enumeration('kind', ['expense', 'income']) ?? 'expense';
    final status = params.enumeration('status', ['paid', 'pending']);
    return _ok(
      byCategory(
        ByCategoryInput(
          transactions: [for (final t in await _txRows(e.s)) t.report],
          categories: await _reportCategories(e.s),
          months: months,
          kind: CategoryKind.parse(kind),
          status: status == null ? null : TxStatus.parse(status),
        ),
      ).toJson(),
    );
  }

  Future<_Answer> _trend(_Env e, _Params params) async {
    final months = _rangeParams(params);
    await _materialize(e, months);
    return _ok(
      trend(
        TrendInput(
          transactions: [for (final t in await _txRows(e.s)) t.report],
          categories: await _reportCategories(e.s),
          budgets: await _budgetEntries(e.s),
          months: months,
        ),
      ).toJson(),
    );
  }

  Future<_Answer> _livingCost(_Env e, _Params params) async {
    final count = params.integer('months', 1, 24, 6);
    final to = addMonths(e.month, -1);
    final from = addMonths(to, 1 - count);
    final months = monthsBetween(from, to);
    await _materialize(e, months);
    final start = firstDay(from);
    final end = lastDay(to);
    final categories = await _rows(e.s, RecordType.category);
    return _ok(
      costOfLiving(
        CostOfLivingInput(
          months: months,
          categories: [
            for (final c in categories)
              SummaryCategory(
                id: c['id']! as String,
                kind: CategoryKind.parse(c['kind']! as String),
              ),
          ],
          fixedCategoryIds: {
            for (final r in await _rows(e.s, RecordType.recurrence))
              if (r['endDate'] == null || (r['endDate']! as String).compareTo(start) >= 0)
                r['categoryId']! as String,
          }.toList(),
          transactions: [
            for (final t in await _txRows(e.s))
              if (t.date.compareTo(start) >= 0 && t.date.compareTo(end) <= 0)
                CostOfLivingTransaction(categoryId: t.categoryId, amount: t.amount, date: t.date),
          ],
        ),
      ).toJson(),
    );
  }

  // -- Dispatch -----------------------------------------------------------------------------

  bool _isUnavailable(String method, String path) => unavailable.any(
    (u) =>
        (u.method == '*' || u.method == method) &&
        (u.prefix ? path == u.path || path.startsWith('${u.path}/') : path == u.path),
  );

  Future<_Answer> _route(
    StoreOps s,
    String method,
    String path,
    _Params params,
    String raw,
    Object? body,
    Map<String, String> headers,
  ) async {
    String idOf(RegExpMatch? match) {
      final id = match?.group(1) ?? '';
      if (!_uuid.hasMatch(id)) throw _invalid('id', 'Invalid UUID');
      return id;
    }

    final e = await _envOf(s);

    if (path == '/v1/me') {
      if (method == 'GET') return _ok(_meOf(e));
      if (method == 'PATCH') return _patchMe(e, body);
    }
    if (path == '/v1/summary' && method == 'GET') {
      return _ok(await _summary(e, params.month('month') ?? e.month));
    }
    if (path == '/v1/transactions') {
      if (method == 'GET') return _listTransactions(e, params);
      if (method == 'POST') {
        return _createTransaction(e, raw, body, headers['idempotency-key']);
      }
    }
    if (path == '/v1/transactions/suggestions' && method == 'GET') return _suggestions(e, params);
    if (path == '/v1/transactions/review' && method == 'POST') return _reviewTransactions(e, body);
    if (path == '/v1/transactions/batch' && method == 'POST') {
      return _createBatch(e, raw, body, headers['idempotency-key']);
    }
    if (path == '/v1/transactions/batch-delete' && method == 'POST') return _deleteBatch(e, body);
    var match = _txById.firstMatch(path);
    if (match != null) {
      final id = idOf(match);
      if (method == 'PATCH') return _updateTransaction(e, id, body);
      if (method == 'DELETE') {
        await _findLive(s, id);
        await s.delete(RecordType.transaction, id);
        return const _Answer(204);
      }
    }
    match = _txRestore.firstMatch(path);
    if (match != null && method == 'POST') {
      final id = idOf(match);
      final deleted = await s.get(
        RecordType.transaction,
        id,
        const ReadOptions(includeDeleted: true),
      );
      if (deleted != null && deleted.deleted) await s.put(RecordType.transaction, id, deleted.body);
      final found = deleted ?? await _findLive(s, id);
      return _ok(_Tx(id, found.body).toDto());
    }
    if (path == '/v1/categories') {
      if (method == 'GET') {
        final includeArchived = params.enumeration('includeArchived', ['true', 'false']) == 'true';
        final budgets = await _budgetEntries(s);
        final cats = [
          for (final c in await _rows(s, RecordType.category))
            if (includeArchived || c['archivedAt'] == null) c,
        ];
        return _ok([for (final c in stableSorted(cats, _byOrder)) _categoryDto(e, c, budgets)]);
      }
      if (method == 'POST') return _createCategory(e, body);
    }
    match = _categoryById.firstMatch(path);
    if (match != null && method == 'PATCH') return _updateCategory(e, idOf(match), body);
    match = _categoryBudget.firstMatch(path);
    if (match != null && method == 'PUT') return _setBudget(e, idOf(match), body);
    if (path == '/v1/recurrences') {
      if (method == 'GET') {
        final rules = stableSorted(
          await _rows(s, RecordType.recurrence),
          (x, y) => _cmp(_text(x['createdAt']), _text(y['createdAt'])),
        );
        return _ok([for (final r in rules) _recurrenceDto(r)]);
      }
      if (method == 'POST') return _createRecurrence(e, body);
    }
    match = _recurrenceById.firstMatch(path);
    if (match != null) {
      final id = idOf(match);
      if (method == 'PATCH') return _updateRecurrence(e, id, body);
      if (method == 'DELETE') return _deleteRecurrence(e, id);
    }
    if (method == 'GET' && path == '/v1/reports/by-category') return _byCategory(e, params);
    if (method == 'GET' && path == '/v1/reports/trend') return _trend(e, params);
    if (method == 'GET' && path == '/v1/reports/cost-of-living') return _livingCost(e, params);
    throw _Problem(404, 'not_found');
  }

  @override
  Future<LocalResponse?> handle(
    String method,
    String path,
    Map<String, Object> query,
    Object? body, {
    Map<String, String> headers = const {},
  }) async {
    final verb = method.toUpperCase();
    // Decided before the body is touched: an import's multipart body is not JSON, and its
    // answer is the 403, not a parse error.
    final unavailableRoute = _isUnavailable(verb, path);
    if (!unavailableRoute && !_serves(path)) return null;
    // Deleting the account is the server's: its records and key wraps cascade from the user there.
    if (verb == 'DELETE' && path == '/v1/me') return null;
    final lower = {for (final h in headers.entries) h.key.toLowerCase(): h.value};
    try {
      if (unavailableRoute) throw _Problem(403, 'demo_unavailable', 'Not in the demo');
      final (raw, decoded) = _parseBody(body);
      final params = _Params(query);
      final answer = await store.transaction(
        (s) => _route(s, verb, path, params, raw, decoded, lower),
      );
      return LocalResponse(answer.status, answer.body);
    } on _Problem catch (error) {
      return LocalResponse(error.status, {
        'type': 'about:blank',
        'title': _titles[error.status] ?? 'Error',
        'status': error.status,
        'code': error.code,
        'detail': ?error.detail,
        if (error.errors != null)
          'errors': [
            for (final i in error.errors!) {'path': i.path, 'message': i.message},
          ],
      });
    } on Object {
      // A bug here must not look like being offline: answer as the API's 500.
      return LocalResponse(500, {
        'type': 'about:blank',
        'title': _titles[500],
        'status': 500,
        'code': 'internal_error',
      });
    }
  }

  /// The body's canonical text (to compare idempotent retries) and its decoded value. Text that
  /// is not JSON is a 400, as for the API.
  (String, Object?) _parseBody(Object? body) {
    if (body == null) return ('', null);
    if (body is String) {
      if (body.isEmpty) return ('', null);
      try {
        return (body, jsonDecode(body));
      } on FormatException {
        throw _Problem(400, 'bad_request', 'Malformed JSON in request body');
      }
    }
    try {
      return (jsonEncode(body), body);
    } on JsonUnsupportedObjectError {
      throw _Problem(400, 'bad_request', 'The request body is not JSON');
    }
  }
}
