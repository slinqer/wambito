import 'dart:math';

/// The pure parts of the recovery-key screens: the twin of
/// apps/web/app/features/vault/vault-model.ts.

/// How many characters the person types back (spec 7.1).
const confirmCount = 4;

/// The 26 data characters; the 27th is the check character, left out of the quiz.
const _dataChars = 26;

String _compact(String key) => key.replaceAll('-', '').toUpperCase();

/// Four distinct 1-based positions among the key's data characters, ascending.
List<int> pickPositions([Random? random]) {
  final source = random ?? Random.secure();
  final picked = <int>{};
  while (picked.length < confirmCount) {
    picked.add(source.nextInt(_dataChars) + 1);
  }
  return picked.toList()..sort();
}

/// The characters of [key] at 1-based [positions], dashes ignored.
List<String> charsAt(String key, List<int> positions) {
  final chars = _compact(key);
  return [for (final n in positions) n >= 1 && n <= chars.length ? chars[n - 1] : ''];
}

/// The key is shown in groups of four: where 1-based [position] is, as a group and a character in
/// it.
({int group, int char}) groupPosition(int position) =>
    (group: (position / 4).ceil(), char: (position - 1) % 4 + 1);

/// Same reading as the parser: case-blind, I and L are 1, O is 0.
String _normalize(String c) =>
    c.trim().toUpperCase().replaceAll(RegExp('[IL]'), '1').replaceAll('O', '0');

bool confirmationMatches(String key, List<int> positions, List<String> typed) {
  final want = charsAt(key, positions);
  for (var i = 0; i < want.length; i++) {
    final got = _normalize(i < typed.length ? typed[i] : '');
    if (got.length != 1 || got != _normalize(want[i])) return false;
  }
  return true;
}

/// The kept file: the key, one line about it and the date. No account data.
String recoveryFileText({
  required String title,
  required String key,
  required String line,
  required String date,
}) => '$title\n\n$key\n\n$line\n$date\n';
