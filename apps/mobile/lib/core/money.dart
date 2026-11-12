// Port of packages/core/src/money.ts: integer minor units, never floats.

class InvalidAmountError implements Exception {
  const InvalidAmountError(this.input);
  final String input;

  @override
  String toString() => 'Invalid amount: ${_quote(input)}';
}

String _quote(String s) => '"${s.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';

final _decimal = RegExp(r'^(-?)(\d+)(?:\.(\d{1,2}))?$');

/// Parses a dot-decimal string ("-30.70") into integer minor units (-3070) without floats.
int parseDecimalToMinor(String input) {
  final match = _decimal.firstMatch(input.trim());
  if (match == null) throw InvalidAmountError(input);
  final whole = match.group(2) ?? '0';
  final fraction = (match.group(3) ?? '').padRight(2, '0');
  final minor = int.tryParse(whole) == null ? null : int.parse(whole) * 100 + int.parse(fraction);
  // 2^53 - 1, the safe integer bound the TypeScript holds to.
  if (minor == null || minor > 9007199254740991) throw InvalidAmountError(input);
  return match.group(1) == '-' ? -minor : minor;
}

/// Formats minor units as a dot-decimal string with two decimals (-3070 → "-30.70").
String formatMinorAsDecimal(int minor) {
  final abs = minor.abs();
  return '${minor < 0 ? '-' : ''}${abs ~/ 100}.${(abs % 100).toString().padLeft(2, '0')}';
}
