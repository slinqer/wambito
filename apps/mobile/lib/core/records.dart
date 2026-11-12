// Port of packages/core/src/records.ts: the plaintext bodies of the encrypted records (spec 4.2,
// 5.1). What gets sealed is `{ s: 1, ...fields }`; `id`, `version` and `deleted` live in the
// envelope, never here. The objects are loose (zod `.loose()`): known fields are checked and
// filled with their defaults, unknown keys are kept, so a newer client's extra fields survive an
// older one's edits. `s` is the schema version and is required.
import '../crypto/records.dart' show RecordType;
import 'currencies.dart';
import 'dates.dart';
import 'schemas.dart';

export 'schemas.dart' show Json;

/// The capture sources (`CAPTURE_SOURCES` of capture-sources.ts).
const captureSources = ['revolut', 'google_wallet'];

final _text = fString();
final _timestamp = fString();
final _s = fLiteral(1);
final _frequency = fEnum(['monthly', 'yearly']);
final _uuid = fUuid();

Field _nullableDefaultNull(Field inner) => fDefault(fNullable(inner), null);

final _transaction = ObjectSchema({
  's': _s,
  'name': _text,
  'amount': amountField,
  'currency': _text,
  'date': isoDateField,
  'status': fEnum(['paid', 'pending']),
  'note': _nullableDefaultNull(_text),
  'categoryId': _uuid,
  'accountId': _nullableDefaultNull(_uuid),
  'recurrenceId': _nullableDefaultNull(_uuid),
  // The month a recurrence generated it for; one per rule and month, deleted or not.
  'occurrenceMonth': _nullableDefaultNull(monthField),
  'source': fEnum(['app', 'web', 'widget', 'mcp', 'import', 'recurrence', 'capture']),
  'needsReview': fDefault(fBool(), false),
  'captureSource': _nullableDefaultNull(fEnum(captureSources)),
  'capturedAt': _nullableDefaultNull(_timestamp),
  'captureMerchantKey': _nullableDefaultNull(_text),
  'createdAt': fOptional(_timestamp),
  // Set on create and on every edit; an older record has none (read `createdAt`).
  'updatedAt': fOptional(_timestamp),
}, loose: true);

final _category = ObjectSchema({
  's': _s,
  'name': _text,
  'kind': fEnum(['expense', 'income']),
  'icon': _text,
  'color': _text,
  'sortOrder': fInt(),
  'archivedAt': _nullableDefaultNull(_timestamp),
  'systemKey': _nullableDefaultNull(_text),
  'createdAt': fOptional(_timestamp),
}, loose: true);

/// One entry of the budget history: the amount applies from `effectiveFrom` until a later entry.
final _budget = ObjectSchema({
  's': _s,
  'categoryId': _uuid,
  'amount': budgetAmountField,
  'effectiveFrom': monthField,
}, loose: true);

final _recurrence = ObjectSchema({
  's': _s,
  'name': _text,
  'amount': amountField,
  'categoryId': _uuid,
  'frequency': _frequency,
  'dayOfMonth': fInt(min: 1, max: 31),
  'monthOfYear': fDefault(fNullable(fInt(min: 1, max: 12)), null),
  'startDate': isoDateField,
  'endDate': _nullableDefaultNull(isoDateField),
  // The rule's revision: an occurrence's id is the UUID v5 of the rule id and `<month>:<rev>`;
  // dropping the pending occurrences (an edit, an archive) bumps it so they come back new.
  'rev': fDefault(fInt(min: 0), 0),
  'createdAt': fOptional(_timestamp),
}, loose: true);

/// The merchant memory: the category last chosen for a merchant (`merchantKey` of its name).
final _merchant = ObjectSchema({
  's': _s,
  'merchantKey': fString(min: 1),
  'categoryId': _uuid,
}, loose: true);

/// The profile preferences (one per account).
final _settings = ObjectSchema({
  's': _s,
  'name': _nullableDefaultNull(_text),
  'currency': fEnum(supportedCurrencies),
  'locale': fEnum(supportedLocales),
  'timezone': fString(refine: isValidTimeZone, refineMessage: 'Unknown time zone'),
  'onboardingCompletedAt': _nullableDefaultNull(_timestamp),
  // Wrap ids of the devices removed from the vault; every rotation leaves them out.
  'revokedDevices': fDefaultWith(fArray(_uuid), () => <Object?>[]),
}, loose: true);

final _account = ObjectSchema({
  's': _s,
  'name': _text,
  'currency': _text,
  'isDefault': fDefault(fBool(), false),
}, loose: true);

final Map<RecordType, ObjectSchema> recordSchemas = {
  RecordType.transaction: _transaction,
  RecordType.category: _category,
  RecordType.budget: _budget,
  RecordType.recurrence: _recurrence,
  RecordType.merchant: _merchant,
  RecordType.settings: _settings,
  RecordType.account: _account,
};

/// What `parseRecordBody` throws: `path` is the first failing path ("" for the body itself) and
/// `message` lists every issue as `path: message; ...` like `parseRecord`'s error.
class RecordBodyError implements Exception {
  const RecordBodyError(this.type, this.path, [this.message = '']);

  final RecordType type;
  final String path;
  final String message;

  @override
  String toString() => 'Invalid ${type.name} record${message.isEmpty ? '' : ': $message'}';
}

/// The result of `parseRecord`: the validated body, or the issues as one string.
class ParsedRecord {
  const ParsedRecord._(this.value, this.error, this.issues);

  final Json? value;
  final String? error;
  final List<Issue> issues;

  bool get ok => value != null;
}

/// Validates a decrypted body. Never throws: a bad record is `ok == false`.
ParsedRecord parseRecord(RecordType type, Object? json) {
  final result = recordSchemas[type]!.parse(json);
  return switch (result) {
    Valid<Json>(:final data) => ParsedRecord._(data, null, const []),
    Invalid<Json>(:final issues) => ParsedRecord._(null, issues.join('; '), issues),
  };
}

/// Validates a decrypted body and returns it with its defaults filled and unknown keys kept.
Json parseRecordBody(RecordType type, Object? value) {
  final parsed = parseRecord(type, value);
  if (parsed.ok) return parsed.value!;
  throw RecordBodyError(type, parsed.issues.first.path, parsed.error!);
}
