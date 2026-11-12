// Runs the shared fixtures of packages/core (fixtures/*.json and reports/cases.json) against the
// Dart port of the core rules, as packages/core/src/fixtures.test.ts and reports.test.ts do for the
// TypeScript. Results are compared as JSON would carry them (no -0, 1.0 == 1).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wambito/core/budget.dart';
import 'package:wambito/core/cost_of_living.dart';
import 'package:wambito/core/dates.dart';
import 'package:wambito/core/default_currency.dart';
import 'package:wambito/core/js_math.dart';
import 'package:wambito/core/movement_search.dart';
import 'package:wambito/core/recurrence.dart';
import 'package:wambito/core/reports.dart';
import 'package:wambito/core/summary.dart';

const _fixtures = '../../packages/core/fixtures';
const _reportCases = '../../packages/core/reports/cases.json';

Object? _json(Object? value) => jsonDecode(jsonEncode(value));

List<Map<String, dynamic>> _load(String file) {
  final doc = jsonDecode(File('$_fixtures/$file').readAsStringSync()) as Map<String, dynamic>;
  return (doc['cases'] as List).cast<Map<String, dynamic>>();
}

typedef _Fn = Object? Function(List<dynamic> input);

List<T> _list<T>(dynamic v, T Function(Map<String, dynamic>) f) =>
    (v as List).map((e) => f(e as Map<String, dynamic>)).toList();

void _run(String file, Map<String, _Fn> fns, {String? only}) {
  final cases = _load(file);
  test('has at least three cases per function', () {
    final counts = <String, int>{};
    for (final c in cases) {
      final key = only ?? c['fn'] as String;
      counts[key] = (counts[key] ?? 0) + 1;
    }
    expect(counts.keys.toList()..sort(), fns.keys.toList()..sort());
    counts.forEach((fn, n) => expect(n, greaterThanOrEqualTo(3), reason: fn));
  });
  for (final c in cases) {
    test(c['name'] as String, () {
      final fn = fns[only ?? c['fn'] as String];
      if (fn == null) throw StateError('unknown function ${c['fn']}');
      expect(_json(fn(c['input'] as List)), c['expected']);
    });
  }
}

void main() {
  _jsRoundTests();
  group('summary.json', () {
    _run('summary.json', {
      'monthSummary': (i) =>
          monthSummary(SummaryInput.fromJson(i[0] as Map<String, dynamic>)).toJson(),
    }, only: 'monthSummary');
  });

  group('budget.json', () {
    _run('budget.json', {
      'effectiveBudget': (i) =>
          effectiveBudget(_list(i[0], BudgetEntry.fromJson), i[1] as String, i[2] as String),
    }, only: 'effectiveBudget');
  });

  group('recurrence.json', () {
    _run('recurrence.json', {
      'occurrences': (i) =>
          occurrences(RecurrenceRule.fromJson(i[0] as Map<String, dynamic>), i[1] as String),
    }, only: 'occurrences');
  });

  group('cost-of-living.json', () {
    _run('cost-of-living.json', {
      'costOfLiving': (i) =>
          costOfLiving(CostOfLivingInput.fromJson(i[0] as Map<String, dynamic>)).toJson(),
    }, only: 'costOfLiving');
  });

  group('movement-search.json', () {
    _run('movement-search.json', {
      'matchesMovementSearch': (i) => matchesMovementSearch(
        SearchableMovement.fromJson(i[0] as Map<String, dynamic>),
        MovementSearch.fromJson(i[1] as Map<String, dynamic>),
      ),
      'movementTotals': (i) => movementTotals(
        (i[0] as List).map((e) => (e as Map<String, dynamic>)['amount'] as int).toList(),
      ).toJson(),
    });
  });

  group('dates.json', () {
    _run('dates.json', {
      'todayIn': (i) => todayIn(i[0] as String, DateTime.parse(i[1] as String)),
      'monthOf': (i) => monthOf(i[0] as String),
      'firstDay': (i) => firstDay(i[0] as String),
      'lastDay': (i) => lastDay(i[0] as String),
      'addMonths': (i) => addMonths(i[0] as String, i[1] as int),
      'monthsBetween': (i) => monthsBetween(i[0] as String, i[1] as String),
      'isMonth': (i) => isMonth(i[0] as String),
    });
  });

  group('reports/cases.json', () {
    final doc = jsonDecode(File(_reportCases).readAsStringSync()) as Map<String, dynamic>;
    final categories = _list(doc['categories'], ReportCategory.fromJson);
    final transactions = _list(doc['transactions'], ReportTransaction.fromJson);
    final budgets = _list(doc['budgets'], BudgetEntry.fromJson);
    for (final c in (doc['byCategory'] as List).cast<Map<String, dynamic>>()) {
      test('byCategory ${c['id']}', () {
        final report = byCategory(
          ByCategoryInput(
            transactions: transactions,
            categories: categories,
            months: (c['months'] as List).cast<String>(),
            kind: c['kind'] == null ? null : CategoryKind.parse(c['kind'] as String),
            status: c['status'] == null ? null : TxStatus.parse(c['status'] as String),
          ),
        );
        expect(_json(report.toJson()), c['expect']);
      });
    }
    for (final c in (doc['trend'] as List).cast<Map<String, dynamic>>()) {
      test('trend ${c['id']}', () {
        final result = trend(
          TrendInput(
            transactions: transactions,
            categories: categories,
            budgets: budgets,
            months: (c['months'] as List).cast<String>(),
          ),
        );
        expect(_json(result.toJson()), c['expect']);
      });
    }
  });

  group('currencies and suggestions', () {
    test('defaultCurrencyFor follows the founder rule', () {
      expect(defaultCurrencyFor('America/Bogota'), 'COP');
      expect(defaultCurrencyFor('Europe/Madrid'), 'EUR');
      expect(defaultCurrencyFor('America/New_York', 'co'), 'COP');
      expect(defaultCurrencyFor('Asia/Tokyo', 'IT'), 'EUR');
      expect(defaultCurrencyFor('America/Mexico_City'), 'USD');
    });
  });
}

void _jsRoundTests() {
  group('jsRound', () {
    test('halves round toward +infinity like Math.round', () {
      expect(jsRound(2.5), 3);
      expect(jsRound(-1.5), -1);
      expect(jsRound(-0.5), 0);
      expect(jsRound(-2.4), -2);
      expect(jsRound(0.4), 0);
    });
  });
}
