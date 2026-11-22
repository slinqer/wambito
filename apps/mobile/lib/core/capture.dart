// Port of the merchant-memory part of packages/core/src/capture.ts, plus the capture constants the
// phone's local capture save shares with apps/api/src/services/captures.ts.
import 'package:unorm_dart/unorm_dart.dart' as unorm;

/// Two captures this close in time, with the same kind, amount and currency, are one purchase.
const captureDuplicateWindow = Duration(minutes: 10);

const Map<String, ({String expense, String income})> fallbackCategoryNames = {
  'es': (expense: 'Otros gastos', income: 'Otros ingresos'),
  'en': (expense: 'Other expenses', income: 'Other income'),
  'it': (expense: 'Altre spese', income: 'Altre entrate'),
  'pt': (expense: 'Outras despesas', income: 'Outras receitas'),
};

final _marks = RegExp(r'\p{M}', unicode: true);
final _separators = RegExp(r'[^\p{L}\p{N}]+', unicode: true);
final _digits = RegExp(r'^\d+$');

/// The API's `keyOf`: the key, or null when [merchant] has no letters or digits.
String? merchantKeyOrNull(String merchant) {
  final key = unorm
      .nfd(merchant)
      .replaceAll(_marks, '')
      .toLowerCase()
      .replaceAll(_separators, ' ')
      .split(' ')
      .where((token) => token != '' && !_digits.hasMatch(token))
      .join(' ');
  return key == '' ? null : key;
}

/// Normalized merchant name used to match a merchant against past ones.
String merchantKey(String merchant) {
  final key = merchantKeyOrNull(merchant);
  if (key == null) throw const FormatException('Merchant has no letters');
  return key;
}

/// The shorter keys a learned merchant may have been saved under, longest first: the leading words
/// of [key] ("lidl casal ribeiro" -> "lidl casal", "lidl"). None when the first word is under 3
/// letters, where a short word ("el", "la") would catch unrelated merchants.
List<String> merchantKeyPrefixes(String key) {
  final words = key.split(' ');
  if (words[0].length < 3) return [];
  return [for (var n = words.length - 1; n >= 1; n--) words.sublist(0, n).join(' ')];
}
