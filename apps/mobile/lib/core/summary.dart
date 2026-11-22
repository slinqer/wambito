// Port of packages/core/src/summary.ts.
import 'budget.dart';

const nearLimitRatio = 0.8;

class SummaryCategory {
  const SummaryCategory({required this.id, required this.kind});

  factory SummaryCategory.fromJson(Map<String, dynamic> j) =>
      SummaryCategory(id: j['id'] as String, kind: CategoryKind.parse(j['kind'] as String));

  final String id;
  final CategoryKind kind;
}

class SummaryTransaction {
  const SummaryTransaction({required this.categoryId, required this.amount});

  factory SummaryTransaction.fromJson(Map<String, dynamic> j) =>
      SummaryTransaction(categoryId: j['categoryId'] as String, amount: j['amount'] as int);

  final String categoryId;
  final int amount;
}

class SummaryInput {
  const SummaryInput({
    required this.month,
    required this.categories,
    required this.budgets,
    required this.transactions,
  });

  factory SummaryInput.fromJson(Map<String, dynamic> j) => SummaryInput(
    month: j['month'] as String,
    categories: [
      for (final c in j['categories'] as List) SummaryCategory.fromJson(c as Map<String, dynamic>),
    ],
    budgets: [
      for (final b in j['budgets'] as List) BudgetEntry.fromJson(b as Map<String, dynamic>),
    ],
    transactions: [
      for (final t in j['transactions'] as List)
        SummaryTransaction.fromJson(t as Map<String, dynamic>),
    ],
  );

  final String month;
  final List<SummaryCategory> categories;
  final List<BudgetEntry> budgets;

  /// That month's non-deleted transactions, paid and pending.
  final List<SummaryTransaction> transactions;
}

enum BudgetState { ok, near, over }

class CategorySummary {
  const CategorySummary({
    required this.categoryId,
    required this.budget,
    required this.spent,
    required this.remaining,
    required this.ratio,
    required this.state,
  });

  final String categoryId;
  final int? budget;
  final int spent;
  final int? remaining;
  final double? ratio;
  final BudgetState state;

  Map<String, dynamic> toJson() => {
    'categoryId': categoryId,
    'budget': budget,
    'spent': spent,
    'remaining': remaining,
    'ratio': ratio,
    'state': state.name,
  };
}

class MonthSummary {
  const MonthSummary({
    required this.month,
    required this.budgetTotal,
    required this.spent,
    required this.remaining,
    required this.income,
    required this.balance,
    required this.categories,
  });

  final String month;
  final int budgetTotal;
  final int spent;
  final int remaining;
  final int income;
  final int balance;
  final List<CategorySummary> categories;

  Map<String, dynamic> toJson() => {
    'month': month,
    'budgetTotal': budgetTotal,
    'spent': spent,
    'remaining': remaining,
    'income': income,
    'balance': balance,
    'categories': [for (final c in categories) c.toJson()],
  };
}

CategorySummary _categorySummary(String categoryId, int? budget, int spent) {
  if (budget == null) {
    return CategorySummary(
      categoryId: categoryId,
      budget: null,
      spent: spent,
      remaining: null,
      ratio: null,
      state: BudgetState.ok,
    );
  }
  if (budget == 0) {
    return CategorySummary(
      categoryId: categoryId,
      budget: 0,
      spent: spent,
      remaining: -spent,
      ratio: null,
      state: spent > 0 ? BudgetState.over : BudgetState.ok,
    );
  }
  final ratio = spent / budget;
  final state = ratio > 1
      ? BudgetState.over
      : ratio >= nearLimitRatio
      ? BudgetState.near
      : BudgetState.ok;
  return CategorySummary(
    categoryId: categoryId,
    budget: budget,
    spent: spent,
    remaining: budget - spent,
    ratio: ratio,
    state: state,
  );
}

MonthSummary monthSummary(SummaryInput input) {
  final totals = <String, int>{};
  for (final tx in input.transactions) {
    totals[tx.categoryId] = (totals[tx.categoryId] ?? 0) + tx.amount;
  }

  var budgetTotal = 0;
  var spent = 0;
  var income = 0;
  final categories = <CategorySummary>[];

  for (final category in input.categories) {
    final total = totals[category.id] ?? 0;
    if (category.kind == CategoryKind.income) {
      income += total;
      continue;
    }
    final budget = effectiveBudget(input.budgets, category.id, input.month);
    budgetTotal += budget ?? 0;
    spent -= total;
    categories.add(_categorySummary(category.id, budget, 0 - total));
  }

  return MonthSummary(
    month: input.month,
    budgetTotal: budgetTotal,
    spent: spent,
    remaining: budgetTotal - spent,
    income: income,
    balance: income - spent,
    categories: categories,
  );
}
