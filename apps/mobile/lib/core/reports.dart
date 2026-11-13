// Port of packages/core/src/reports.ts.
import 'budget.dart';
import 'dates.dart';
import 'js_math.dart';

class ReportTransaction {
  const ReportTransaction({
    required this.categoryId,
    required this.amount,
    required this.date,
    required this.status,
  });

  factory ReportTransaction.fromJson(Map<String, dynamic> j) => ReportTransaction(
    categoryId: j['categoryId'] as String,
    amount: j['amount'] as int,
    date: j['date'] as String,
    status: TxStatus.parse(j['status'] as String),
  );

  final String categoryId;

  /// Signed cents: expenses negative, income positive.
  final int amount;
  final String date;
  final TxStatus status;
}

class ReportCategory {
  const ReportCategory({
    required this.id,
    required this.name,
    required this.kind,
    required this.icon,
    required this.color,
    required this.archivedAt,
  });

  factory ReportCategory.fromJson(Map<String, dynamic> j) => ReportCategory(
    id: j['id'] as String,
    name: j['name'] as String,
    kind: CategoryKind.parse(j['kind'] as String),
    icon: j['icon'] as String,
    color: j['color'] as String,
    archivedAt: j['archivedAt'] as String?,
  );

  final String id;
  final String name;
  final CategoryKind kind;
  final String icon;
  final String color;
  final String? archivedAt;
}

class ByCategoryItem {
  const ByCategoryItem({
    required this.categoryId,
    required this.name,
    required this.icon,
    required this.color,
    required this.total,
    required this.share,
  });

  final String categoryId;
  final String name;
  final String icon;
  final String color;
  final int total;
  final double share;

  Map<String, dynamic> toJson() => {
    'categoryId': categoryId,
    'name': name,
    'icon': icon,
    'color': color,
    'total': total,
    'share': share,
  };
}

class ByCategoryReport {
  const ByCategoryReport({required this.total, required this.items});

  final int total;
  final List<ByCategoryItem> items;

  Map<String, dynamic> toJson() => {
    'total': total,
    'items': [for (final i in items) i.toJson()],
  };
}

class ByCategoryInput {
  const ByCategoryInput({
    required this.transactions,
    required this.categories,
    required this.months,
    this.kind,
    this.status,
  });

  /// Live (not deleted) transactions.
  final List<ReportTransaction> transactions;

  /// In the order the items tie-break in.
  final List<ReportCategory> categories;

  /// The range's months, ascending and consecutive.
  final List<String> months;
  final CategoryKind? kind;
  final TxStatus? status;
}

/// Spending (or income) per category over a range of months, biggest first.
ByCategoryReport byCategory(ByCategoryInput input) {
  final kind = input.kind ?? CategoryKind.expense;
  final status = input.status;
  final from = firstDay(input.months.first);
  final to = lastDay(input.months.last);
  final sums = <String, int>{};
  for (final t in input.transactions) {
    if (t.date.compareTo(from) < 0 ||
        t.date.compareTo(to) > 0 ||
        (status != null && t.status != status)) {
      continue;
    }
    sums[t.categoryId] = (sums[t.categoryId] ?? 0) + t.amount;
  }
  final sign = kind == CategoryKind.expense ? -1 : 1;
  final items = stableSorted(
    input.categories
        .where((c) => c.kind == kind && sums.containsKey(c.id))
        .map((c) => (c: c, total: sign * (sums[c.id] ?? 0)))
        .where((i) => i.total != 0),
    (x, y) => y.total.compareTo(x.total),
  );
  final total = items.fold<int>(0, (acc, i) => acc + i.total);
  return ByCategoryReport(
    total: total,
    items: [
      for (final i in items)
        ByCategoryItem(
          categoryId: i.c.id,
          name: i.c.name,
          icon: i.c.icon,
          color: i.c.color,
          total: i.total,
          share: total == 0 ? 0 : jsRound(i.total / total * 10000) / 10000,
        ),
    ],
  );
}

class TrendMonth {
  const TrendMonth({
    required this.month,
    required this.income,
    required this.expenses,
    required this.budget,
  });

  final String month;
  final int income;
  final int expenses;
  final int budget;

  Map<String, dynamic> toJson() => {
    'month': month,
    'income': income,
    'expenses': expenses,
    'budget': budget,
  };
}

class TrendResult {
  const TrendResult(this.months);

  final List<TrendMonth> months;

  Map<String, dynamic> toJson() => {
    'months': [for (final m in months) m.toJson()],
  };
}

class TrendInput {
  const TrendInput({
    required this.transactions,
    required this.categories,
    required this.budgets,
    required this.months,
  });

  final List<ReportTransaction> transactions;
  final List<ReportCategory> categories;
  final List<BudgetEntry> budgets;
  final List<String> months;
}

/// Income, expenses and budget per month. The budget counts archived categories only if used.
TrendResult trend(TrendInput input) {
  final kindOf = {for (final c in input.categories) c.id: c.kind};
  return TrendResult([for (final month in input.months) _trendMonth(input, kindOf, month)]);
}

TrendMonth _trendMonth(TrendInput input, Map<String, CategoryKind> kindOf, String month) {
  final start = firstDay(month);
  final end = lastDay(month);
  final txs = input.transactions
      .where((t) => t.date.compareTo(start) >= 0 && t.date.compareTo(end) <= 0)
      .toList();
  final used = {for (final t in txs) t.categoryId};
  var income = 0;
  var expenses = 0;
  for (final t in txs) {
    if (kindOf[t.categoryId] == CategoryKind.income) {
      income += t.amount;
    } else {
      expenses -= t.amount;
    }
  }
  final budget = input.categories
      .where((c) => c.kind == CategoryKind.expense && (c.archivedAt == null || used.contains(c.id)))
      .fold<int>(0, (acc, c) => acc + (effectiveBudget(input.budgets, c.id, month) ?? 0));
  return TrendMonth(month: month, income: income, expenses: expenses, budget: budget);
}
