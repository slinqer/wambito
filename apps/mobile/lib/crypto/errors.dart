/// Why a crypto call failed. Twin of packages/crypto/src/errors.ts: the codes are
/// `cannot_open`, `bad_recovery_key` and `bad_input`.
class CryptoError implements Exception {
  const CryptoError(this.code, [String? message]) : message = message ?? code;

  final String code;
  final String message;

  @override
  String toString() => 'CryptoError($code): $message';
}
