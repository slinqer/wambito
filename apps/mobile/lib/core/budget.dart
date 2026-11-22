// Port of packages/core/src/budget.ts.

enum CategoryKind {
  expense,
  income;

  static CategoryKind parse(String s) => values.byName(s);
}

enum TxStatus {
  paid,
  pending;

  static TxStatus parse(String s) => values.byName(s);
}

class BudgetEntry {
  const BudgetEntry({required this.categoryId, required this.amount, required this.effectiveFrom});

  factory BudgetEntry.fromJson(Map<String, dynamic> j) => BudgetEntry(
    categoryId: j['categoryId'] as String,
    amount: j['amount'] as int,
    effectiveFrom: j['effectiveFrom'] as String,
  );

  final String categoryId;
  final int amount;
  final String effectiveFrom;
}

/// The budget in force for a category in a month: the latest entry starting on or before it.
int? effectiveBudget(List<BudgetEntry> entries, String categoryId, String month) {
  BudgetEntry? best;
  for (final entry in entries) {
    if (entry.categoryId != categoryId || entry.effectiveFrom.compareTo(month) > 0) continue;
    if (best == null || entry.effectiveFrom.compareTo(best.effectiveFrom) > 0) best = entry;
  }
  return best?.amount;
}
