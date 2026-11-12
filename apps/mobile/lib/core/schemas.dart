// Port of packages/core/src/schemas.ts (the request validators) and the `reviewTransactionsSchema`
// of capture.ts. Plain Dart, no codegen: a small field combinator set that reports the same paths
// and messages as zod 4, because the local backend sends them in its 422 `errors` (Task 11 builds
// that body from `Invalid.issues`: `path` is already dot-joined, "" for the body itself).
//
// What mirrors zod: type errors, an invalid enum value and a non-integer stop the cross-field
// refinements ("aborting" issues); a failed check (length, bound, format) does not. Unknown keys
// are stripped unless the object is loose. A JSON number with no fraction (5.0) is the integer 5.
import 'currencies.dart';
import 'dates.dart';

typedef Json = Map<String, Object?>;

class Issue {
  const Issue(this.path, this.message);

  /// Dot-joined (`repeat.endDate`, `ids.0`), `""` for the body itself.
  final String path;
  final String message;

  @override
  String toString() => '${path.isEmpty ? '(body)' : path}: $message';

  @override
  bool operator ==(Object other) =>
      other is Issue && other.path == path && other.message == message;

  @override
  int get hashCode => Object.hash(path, message);
}

sealed class ValidationResult<T> {
  const ValidationResult();
}

class Valid<T> extends ValidationResult<T> {
  const Valid(this.data);
  final T data;
}

class Invalid<T> extends ValidationResult<T> {
  const Invalid(this.issues);
  final List<Issue> issues;
}

abstract class Schema<T> {
  ValidationResult<T> parse(Object? value);
}

ValidationResult<T> validate<T>(Schema<T> schema, Object? body) => schema.parse(body);

// -- Field combinators ------------------------------------------------------------------------

/// The value of a key that is not in the body (zod's `undefined`).
class _Absent {
  const _Absent();
}

const absent = _Absent();

class Ctx {
  final List<Issue> issues = [];
  bool aborted = false;

  void add(String path, String message, {bool abort = false}) {
    issues.add(Issue(path, message));
    if (abort) aborted = true;
  }
}

/// Parses one value. Returns the value to keep, or `absent` to leave the key out.
typedef Field = Object? Function(Object? value, String path, Ctx ctx);

String _join(String path, String key) => path.isEmpty ? key : '$path.$key';

String _received(Object? v) {
  if (identical(v, absent)) return 'undefined';
  if (v == null) return 'null';
  if (v is String) return 'string';
  if (v is bool) return 'boolean';
  if (v is num) return 'number';
  if (v is List) return 'array';
  if (v is Map) return 'object';
  return v.runtimeType.toString();
}

void _typeError(Ctx ctx, String path, String expected, Object? v) =>
    ctx.add(path, 'Invalid input: expected $expected, received ${_received(v)}', abort: true);

const _maxSafe = 9007199254740991;

/// A string; `trim` trims before the length checks; `refine` is a format check.
Field fString({
  bool trim = false,
  int? min,
  int? max,
  bool Function(String)? refine,
  String? refineMessage,
}) => (v, path, ctx) {
  if (v is! String) {
    _typeError(ctx, path, 'string', v);
    return absent;
  }
  final s = trim ? v.trim() : v;
  if (min != null && s.length < min) {
    ctx.add(path, 'Too small: expected string to have >=$min characters');
  }
  if (max != null && s.length > max) {
    ctx.add(path, 'Too big: expected string to have <=$max characters');
  }
  if (refine != null && !refine(s)) ctx.add(path, refineMessage ?? 'Invalid input');
  return s;
};

/// `z.number().int()` with optional `.min`/`.max` and refinements (checked in this order).
Field fInt({
  int? min,
  int? max,
  List<(bool Function(int), String)> refinements = const [],
}) => (v, path, ctx) {
  if (v is! num) {
    _typeError(ctx, path, 'number', v);
    return absent;
  }
  if (v.isNaN || v.isInfinite || v != v.truncateToDouble()) {
    ctx.add(path, 'Invalid input: expected int, received number', abort: true);
    return absent;
  }
  // Beyond 2^53 every message below is the same whatever the exact value, so clamp for Dart's int.
  final n = v is int ? v : (v.abs() > 1e18 ? (v < 0 ? -1 << 62 : 1 << 62) : v.toInt());
  if (n > _maxSafe) ctx.add(path, 'Too big: expected int to be <=$_maxSafe');
  if (n < -_maxSafe) ctx.add(path, 'Too small: expected int to be >=-$_maxSafe');
  if (min != null && n < min) ctx.add(path, 'Too small: expected number to be >=$min');
  if (max != null && n > max) ctx.add(path, 'Too big: expected number to be <=$max');
  for (final (ok, message) in refinements) {
    if (!ok(n)) ctx.add(path, message);
  }
  return n;
};

Field fBool() => (v, path, ctx) {
  if (v is! bool) {
    _typeError(ctx, path, 'boolean', v);
    return absent;
  }
  return v;
};

/// `z.literal(1)`, `z.literal(true)`, `z.literal(false)`.
Field fLiteral(Object expected) => (v, path, ctx) {
  final matches = expected is num ? (v is num && v == expected) : v == expected;
  if (!matches) {
    ctx.add(path, 'Invalid input: expected $expected', abort: true);
    return absent;
  }
  return expected;
};

Field fEnum(List<String> values) => (v, path, ctx) {
  if (v is! String || !values.contains(v)) {
    final options = values.map((o) => '"$o"').join('|');
    ctx.add(path, 'Invalid option: expected one of $options', abort: true);
    return absent;
  }
  return v;
};

// zod 4's `z.uuid()`: any version 1-8 and the nil/max uuids are not special-cased in the app's data.
final _uuid = RegExp(
  r'^([0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}'
  r'|00000000-0000-0000-0000-000000000000|ffffffff-ffff-ffff-ffff-ffffffffffff)$',
  caseSensitive: false,
);

Field fUuid() => (v, path, ctx) {
  if (v is! String) {
    _typeError(ctx, path, 'string', v);
    return absent;
  }
  if (!_uuid.hasMatch(v)) ctx.add(path, 'Invalid UUID');
  return v;
};

Field fArray(Field item, {int? min, int? max}) => (v, path, ctx) {
  if (v is! List) {
    _typeError(ctx, path, 'array', v);
    return absent;
  }
  if (min != null && v.length < min) {
    ctx.add(path, 'Too small: expected array to have >=$min items');
  }
  if (max != null && v.length > max) {
    ctx.add(path, 'Too big: expected array to have <=$max items');
  }
  return [
    for (var i = 0; i < v.length; i++)
      if (item(v[i], _join(path, '$i'), ctx) case final out when !identical(out, absent)) out,
  ];
};

Field fNullable(Field inner) =>
    (v, path, ctx) => v == null ? null : inner(v, path, ctx);

Field fOptional(Field inner) =>
    (v, path, ctx) => identical(v, absent) ? absent : inner(v, path, ctx);

/// `.default(value)`: only a missing key is replaced (a `null` is the inner schema's to judge).
Field fDefault(Field inner, Object? value) =>
    (v, path, ctx) => identical(v, absent) ? value : inner(v, path, ctx);

/// A cross-field check on a body whose fields all passed their type checks.
typedef Refine = void Function(Json value, Ctx ctx);

/// `z.object(shape)`: strips unknown keys, or keeps them when `loose` (`.loose()`).
/// `partial` makes every field optional (`.partial()`).
class ObjectSchema implements Schema<Json> {
  ObjectSchema(
    Map<String, Field> shape, {
    this.loose = false,
    bool partial = false,
    this.refinements = const [],
  }) : shape = partial ? {for (final e in shape.entries) e.key: fOptional(e.value)} : shape;

  final Map<String, Field> shape;
  final bool loose;
  final List<Refine> refinements;

  /// This object as a field of another one.
  Field get field =>
      (v, path, ctx) => _parse(v, path, ctx);

  Object? _parse(Object? v, String path, Ctx ctx) {
    if (v is! Map) {
      _typeError(ctx, path, 'object', v);
      return absent;
    }
    final out = <String, Object?>{};
    for (final e in shape.entries) {
      final present = v.containsKey(e.key);
      final value = e.value(present ? v[e.key] : absent, _join(path, e.key), ctx);
      if (!identical(value, absent)) out[e.key] = value;
    }
    if (loose) {
      for (final e in v.entries) {
        final key = e.key.toString();
        if (!shape.containsKey(key)) out[key] = e.value;
      }
    }
    return out;
  }

  @override
  ValidationResult<Json> parse(Object? value) {
    final ctx = Ctx();
    final out = _parse(value, '', ctx);
    if (!ctx.aborted && out is Map<String, Object?>) {
      for (final refine in refinements) {
        refine(out, ctx);
      }
    }
    if (ctx.issues.isNotEmpty) return Invalid(ctx.issues);
    return Valid(out as Json);
  }
}

const _atLeastOne = 'Provide at least one field';

void _requireOne(Json value, Ctx ctx) {
  if (value.isEmpty) ctx.add('', _atLeastOne);
}

// -- Shared fields ----------------------------------------------------------------------------

final monthField = fString(refine: isMonth, refineMessage: 'Expected a month as YYYY-MM');
final isoDateField = fString(refine: isIsoDate, refineMessage: 'Expected a date as YYYY-MM-DD');

/// `amountSchema`: a non-zero safe integer, in cents.
final amountField = fInt(
  refinements: [
    ((n) => n.abs() <= _maxSafe, 'Amount is too large'),
    ((n) => n != 0, 'Amount cannot be zero'),
  ],
);

/// `budgetAmountSchema`: a non-negative safe integer.
final budgetAmountField = fInt(
  min: 0,
  refinements: [((n) => n.abs() <= _maxSafe, 'Invalid input')],
);

final _kind = fEnum(['expense', 'income']);
final _status = fEnum(['paid', 'pending']);
final _frequency = fEnum(['monthly', 'yearly']);
final _name = fString(trim: true, min: 1, max: 120);
final _note = fNullable(fString(max: 1000));
final supportedLocales = ['es', 'en', 'it', 'pt'];

// -- Request schemas --------------------------------------------------------------------------

/// "Repetir" on a new transaction.
final _repeat = ObjectSchema({
  'frequency': _frequency,
  'endDate': fOptional(fNullable(isoDateField)),
}).field;

final createTransactionSchema = ObjectSchema(
  {
    'name': _name,
    'amount': amountField,
    'categoryId': fUuid(),
    'date': isoDateField,
    'status': fDefault(_status, 'paid'),
    'note': fOptional(_note),
    'source': fDefault(fEnum(['app', 'web', 'widget', 'mcp']), 'app'),
    'repeat': fOptional(_repeat),
  },
  refinements: [
    (value, ctx) {
      final repeat = value['repeat'];
      final endDate = repeat is Map ? repeat['endDate'] : null;
      final date = value['date'];
      if (endDate is String &&
          endDate.isNotEmpty &&
          date is String &&
          endDate.compareTo(date) < 0) {
        ctx.add('repeat.endDate', 'endDate must be on or after date');
      }
    },
  ],
);

final updateTransactionSchema = ObjectSchema(
  {
    'name': _name,
    'amount': amountField,
    'categoryId': fUuid(),
    'date': isoDateField,
    'status': _status,
    'note': _note,
    'needsReview': fLiteral(false),
  },
  partial: true,
  refinements: [_requireOne],
);

final _categoryFields = <String, Field>{
  'name': fString(trim: true, min: 1, max: 40),
  'icon': fString(min: 1, max: 40),
  'color': fString(min: 1, max: 40),
  'sortOrder': fInt(),
};

final createCategorySchema = ObjectSchema({
  ..._categoryFields,
  'kind': _kind,
  'sortOrder': fOptional(_categoryFields['sortOrder']!),
});

final updateCategorySchema = ObjectSchema(
  {..._categoryFields, 'kind': _kind, 'archived': fBool()},
  partial: true,
  refinements: [_requireOne],
);

final setBudgetSchema = ObjectSchema({'amount': budgetAmountField, 'effectiveFrom': monthField});

final _recurrenceFields = <String, Field>{
  'name': _name,
  'amount': amountField,
  'categoryId': fUuid(),
  'frequency': _frequency,
  'dayOfMonth': fInt(min: 1, max: 31),
  'monthOfYear': fOptional(fNullable(fInt(min: 1, max: 12))),
  'startDate': isoDateField,
  'endDate': fOptional(fNullable(isoDateField)),
};

void _checkRecurrence(Json value, Ctx ctx) {
  if (value['frequency'] == 'yearly' && value['monthOfYear'] == null) {
    ctx.add('monthOfYear', 'Yearly recurrences need monthOfYear');
  }
  final start = value['startDate'];
  final end = value['endDate'];
  if (start is String && start.isNotEmpty && end is String && end.isNotEmpty) {
    if (end.compareTo(start) < 0) {
      ctx.add('endDate', 'endDate must be on or after startDate');
    }
  }
}

final createRecurrenceSchema = ObjectSchema(_recurrenceFields, refinements: [_checkRecurrence]);

// Cross-field rules are checked on the merged recurrence by the caller, since a patch may rely on
// stored values.
final updateRecurrenceSchema = ObjectSchema(
  _recurrenceFields,
  partial: true,
  refinements: [_requireOne],
);

final updateProfileSchema = ObjectSchema(
  {
    'timezone': fString(refine: isValidTimeZone, refineMessage: 'Unknown time zone'),
    'locale': fEnum(supportedLocales),
    'currency': fEnum(supportedCurrencies),
    'onboardingCompleted': fLiteral(true),
  },
  partial: true,
  refinements: [_requireOne],
);

/// `{ ids: uuid[] 1..50 }` (capture.ts).
final reviewTransactionsSchema = ObjectSchema({'ids': fArray(fUuid(), min: 1, max: 50)});
