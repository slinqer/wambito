// Port of packages/core/src/cost-of-living.ts.
import 'budget.dart';
import 'dates.dart';
import 'js_math.dart';
import 'summary.dart' show SummaryCategory;

class CostOfLivingTransaction {
  const CostOfLivingTransaction({
    required this.categoryId,
    required this.amount,
    required this.date,
  });

  factory CostOfLivingTransaction.fromJson(Map<String, dynamic> j) => CostOfLivingTransaction(
    categoryId: j['categoryId'] as String,
    amount: j['amount'] as int,
    date: j['date'] as String,
  );

  final String categoryId;
  final int amount;
  final String date;
}

class CostOfLivingInput {
  const CostOfLivingInput({
    required this.months,
    required this.categories,
    required this.fixedCategoryIds,
    required this.transactions,
  });

  factory CostOfLivingInput.fromJson(Map<String, dynamic> j) => CostOfLivingInput(
    months: (j['months'] as List).cast<String>(),
    categories: [
      for (final c in j['categories'] as List) SummaryCategory.fromJson(c as Map<String, dynamic>),
    ],
    fixedCategoryIds: (j['fixedCategoryIds'] as List).cast<String>(),
    transactions: [
      for (final t in j['transactions'] as List)
        CostOfLivingTransaction.fromJson(t as Map<String, dynamic>),
    ],
  );

  /// The complete months to average over.
  final List<String> months;
  final List<SummaryCategory> categories;

  /// Expense categories that recur (subscriptions, rent...); every other expense is variable.
  final List<String> fixedCategoryIds;

  /// Non-deleted transactions; the ones outside [months] are ignored.
  final List<CostOfLivingTransaction> transactions;
}

enum CostType { fixed, variable }

class CostOfLivingCategory {
  const CostOfLivingCategory({required this.categoryId, required this.average, required this.type});

  final String categoryId;

  /// Average net spent per month, in positive cents.
  final int average;
  final CostType type;

  Map<String, dynamic> toJson() => {
    'categoryId': categoryId,
    'average': average,
    'type': type.name,
  };
}

class CostOfLiving {
  const CostOfLiving({
    required this.months,
    required this.total,
    required this.fixed,
    required this.variable,
    required this.categories,
  });

  final int months;
  final int total;
  final int fixed;
  final int variable;
  final List<CostOfLivingCategory> categories;

  Map<String, dynamic> toJson() => {
    'months': months,
    'total': total,
    'fixed': fixed,
    'variable': variable,
    'categories': [for (final c in categories) c.toJson()],
  };
}

CostOfLiving costOfLiving(CostOfLivingInput input) {
  final window = input.months.toSet();
  final fixedIds = input.fixedCategoryIds.toSet();
  final spent = <String, int>{};
  for (final tx in input.transactions) {
    if (!window.contains(monthOf(tx.date))) continue;
    spent[tx.categoryId] = (spent[tx.categoryId] ?? 0) - tx.amount;
  }

  final categories = <CostOfLivingCategory>[];
  var fixed = 0;
  var variable = 0;
  if (input.months.isNotEmpty) {
    for (final category in input.categories) {
      if (category.kind != CategoryKind.expense) continue;
      final average = jsRound((spent[category.id] ?? 0) / input.months.length);
      if (average == 0) continue;
      final type = fixedIds.contains(category.id) ? CostType.fixed : CostType.variable;
      if (type == CostType.fixed) {
        fixed += average;
      } else {
        variable += average;
      }
      categories.add(CostOfLivingCategory(categoryId: category.id, average: average, type: type));
    }
  }

  return CostOfLiving(
    months: input.months.length,
    total: fixed + variable,
    fixed: fixed,
    variable: variable,
    categories: stableSorted(categories, (x, y) => y.average.compareTo(x.average)),
  );
}
