// The date rules now live in lib/core (recurrence.dart, dates.dart); this keeps the Recurrence-typed
// wrappers. What the web's recurring payments decide, apart from how they look: apps/web/app/features/
// recurring/recurring-model.ts (`nextOccurrence`), core's `occurrences` and date helpers
// (packages/core/src/recurrence.ts and dates.ts), and RecurringForm.tsx's `recurrenceProblem`.
import '../api/gen/wambito_api.dart';
import '../core/dates.dart';
import '../core/recurrence.dart' as core;

export '../core/dates.dart' show addMonths, daysInMonth, monthOf;

/// A yearly rule comes round within 12 months of any month, so 13 months always find it.
const _lookaheadMonths = 13;

/// Dates (0 or 1) on which [rule] falls within [month] (core's `occurrences`).
List<String> occurrences(Recurrence rule, String month) => core.occurrences(_ruleOf(rule), month);

core.RecurrenceRule _ruleOf(Recurrence rule) => core.RecurrenceRule(
  frequency: rule.frequency == RecurrenceFrequencyEnum.yearly
      ? core.RecurrenceFrequency.yearly
      : core.RecurrenceFrequency.monthly,
  dayOfMonth: rule.dayOfMonth,
  monthOfYear: rule.monthOfYear,
  startDate: rule.startDate,
  endDate: rule.endDate,
);

/// The next date a recurrence falls on, today included (or its start, if later), or null once it
/// has ended. The dates come from [occurrences] (the rule the API materializes with): for a monthly
/// rule this month or the next, for a yearly one the next time its month comes round.
String? nextOccurrence(Recurrence rule, String today) {
  final from = rule.startDate.compareTo(today) > 0 ? rule.startDate : today;
  for (var step = 0; step < _lookaheadMonths; step++) {
    final dates = occurrences(rule, addMonths(monthOf(from), step));
    if (dates.isNotEmpty && dates.first.compareTo(from) >= 0) return dates.first;
  }
  return null;
}

/// The fields of the form that can carry an error (the web's `Field`).
enum RecurrenceField { amount, name, category, month, start, end }

/// What the form holds, for [recurrenceProblem].
class RecurrenceDraft {
  const RecurrenceDraft({
    required this.cents,
    required this.name,
    required this.categoryId,
    required this.frequency,
    required this.monthOfYear,
    required this.startDate,
    required this.endDate,
  });

  final int cents;
  final String name;
  final String? categoryId;
  final RecurrenceFrequencyEnum frequency;
  final int? monthOfYear;
  final String startDate;

  /// Empty when there is none.
  final String endDate;
}

/// The first error of a draft, by field, or null when it can be sent (the web's
/// `recurrenceProblem`).
RecurrenceField? recurrenceProblem(RecurrenceDraft draft) {
  if (draft.cents <= 0) return RecurrenceField.amount;
  if (draft.name.trim().isEmpty) return RecurrenceField.name;
  if (draft.categoryId == null) return RecurrenceField.category;
  if (draft.frequency == RecurrenceFrequencyEnum.yearly && draft.monthOfYear == null) {
    return RecurrenceField.month;
  }
  if (draft.startDate.isEmpty) return RecurrenceField.start;
  if (draft.endDate.isNotEmpty && draft.endDate.compareTo(draft.startDate) < 0) {
    return RecurrenceField.end;
  }
  return null;
}
