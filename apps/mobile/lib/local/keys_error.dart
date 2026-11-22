/// A failure of the encryption keys, by a code (twin of `KeysError` in packages/vault/src/keyring.ts).
class KeysError implements Exception {
  const KeysError(this.code, {this.status, this.retryAfter});

  final String code;
  final int? status;

  /// A 429's `retry-after`, in whole seconds above zero; null when it said nothing usable (never 0:
  /// a caller retrying "after 0 s" would hammer the server).
  final int? retryAfter;

  @override
  String toString() => 'KeysError($code${status == null ? '' : ', $status'})';
}
