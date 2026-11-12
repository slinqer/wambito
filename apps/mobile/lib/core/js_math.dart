// JavaScript's rounding, which the TypeScript rules use and Dart's `round()` does not match.

/// `Math.round`: halves round toward +infinity (-1.5 → -1, 2.5 → 3); Dart's `round()` rounds them
/// away from zero. -0 comes back as 0.
int jsRound(num x) => (x + 0.5).floor();

/// A stable sort (JavaScript's `Array.prototype.sort` is; Dart's `List.sort` is not).
List<T> stableSorted<T>(Iterable<T> items, int Function(T a, T b) compare) {
  final indexed = items.toList().asMap().entries.toList();
  indexed.sort((a, b) {
    final c = compare(a.value, b.value);
    return c != 0 ? c : a.key.compareTo(b.key);
  });
  return [for (final e in indexed) e.value];
}
