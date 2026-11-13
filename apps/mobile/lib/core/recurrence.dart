// Port of packages/core/src/recurrence.ts.
import 'dates.dart';

enum RecurrenceFrequency {
  monthly,
  yearly;

  static RecurrenceFrequency parse(String s) => values.byName(s);
}

class RecurrenceRule {
  const RecurrenceRule({
    required this.frequency,
    required this.dayOfMonth,
    required this.monthOfYear,
    required this.startDate,
    required this.endDate,
  });

  factory RecurrenceRule.fromJson(Map<String, dynamic> j) => RecurrenceRule(
    frequency: RecurrenceFrequency.parse(j['frequency'] as String),
    dayOfMonth: j['dayOfMonth'] as int,
    monthOfYear: j['monthOfYear'] as int?,
    startDate: j['startDate'] as String,
    endDate: j['endDate'] as String?,
  );

  final RecurrenceFrequency frequency;
  final int dayOfMonth;
  final int? monthOfYear;
  final String startDate;
  final String? endDate;
}

/// Dates (0 or 1) on which [rule] falls within [month]; days past the month's end clamp to its
/// last day.
List<String> occurrences(RecurrenceRule rule, String month) {
  if (rule.frequency == RecurrenceFrequency.yearly &&
      int.parse(month.substring(5, 7)) != rule.monthOfYear) {
    return const [];
  }
  final dim = daysInMonth(month);
  final day = rule.dayOfMonth < dim ? rule.dayOfMonth : dim;
  final date = '$month-${day.toString().padLeft(2, '0')}';
  if (date.compareTo(rule.startDate) < 0) return const [];
  final end = rule.endDate;
  if (end != null && date.compareTo(end) > 0) return const [];
  return [date];
}
