// Port of packages/core/src/movement-search.ts.
import 'budget.dart';

/// Accented letters the text search folds, and what they fold to (Spanish, Italian, Portuguese).
const foldFrom = 'áàâãäéèêëíìîïóòôõöúùûüñç';
const foldTo = 'aaaaaeeeeiiiiooooouuuunc';

final Map<int, String> _fold = {
  for (var i = 0; i < foldFrom.runes.length; i++)
    foldFrom.runes.elementAt(i): String.fromCharCode(foldTo.runes.elementAt(i)),
};

/// Lower case without accents, so "almuerzo" finds "Almuérzo".
String foldText(String text) =>
    text.toLowerCase().runes.map((r) => _fold[r] ?? String.fromCharCode(r)).join();

enum MatchMode { all, any }

class MovementSearch {
  const MovementSearch({this.terms, this.categoryIds, this.kind, this.status, this.match});

  factory MovementSearch.fromJson(Map<String, dynamic> j) => MovementSearch(
    terms: (j['terms'] as List?)?.cast<String>(),
    categoryIds: (j['categoryIds'] as List?)?.cast<String>(),
    kind: j['kind'] == null ? null : CategoryKind.parse(j['kind'] as String),
    status: j['status'] == null ? null : TxStatus.parse(j['status'] as String),
    match: j['match'] == null ? null : MatchMode.values.byName(j['match'] as String),
  );

  final List<String>? terms;
  final List<String>? categoryIds;
  final CategoryKind? kind;
  final TxStatus? status;

  /// How terms and categories combine; kind and status always apply. Default all.
  final MatchMode? match;
}

class SearchableMovement {
  const SearchableMovement({
    required this.name,
    required this.note,
    required this.categoryId,
    required this.amount,
    required this.status,
  });

  factory SearchableMovement.fromJson(Map<String, dynamic> j) => SearchableMovement(
    name: j['name'] as String,
    note: j['note'] as String?,
    categoryId: j['categoryId'] as String,
    amount: j['amount'] as int,
    status: TxStatus.parse(j['status'] as String),
  );

  final String name;
  final String? note;
  final String categoryId;
  final int amount;
  final TxStatus status;
}

bool matchesMovementSearch(SearchableMovement tx, MovementSearch s) {
  if (s.kind == CategoryKind.expense && tx.amount >= 0) return false;
  if (s.kind == CategoryKind.income && tx.amount <= 0) return false;
  if (s.status != null && tx.status != s.status) return false;

  final terms = (s.terms ?? const <String>[])
      .map((t) => foldText(t.trim()))
      .where((t) => t != '')
      .toList();
  final categoryIds = s.categoryIds ?? const <String>[];
  final checks = <bool>[];
  if (terms.isNotEmpty) {
    final haystack = '${foldText(tx.name)}\n${foldText(tx.note ?? '')}';
    checks.add(terms.any(haystack.contains));
  }
  if (categoryIds.isNotEmpty) checks.add(categoryIds.contains(tx.categoryId));
  if (checks.isEmpty) return true;
  return s.match == MatchMode.any ? checks.any((c) => c) : checks.every((c) => c);
}

class MovementTotals {
  const MovementTotals({required this.count, required this.expense, required this.income});

  final int count;
  final int expense;
  final int income;

  Map<String, dynamic> toJson() => {'count': count, 'expense': expense, 'income': income};
}

/// Totals of signed [amounts]: expenses (negative) and income (positive), both as positive cents.
MovementTotals movementTotals(List<int> amounts) {
  var expense = 0;
  var income = 0;
  for (final amount in amounts) {
    if (amount < 0) {
      expense += -amount;
    } else {
      income += amount;
    }
  }
  return MovementTotals(count: amounts.length, expense: expense, income: income);
}
