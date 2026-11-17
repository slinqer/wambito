/// A failure of the encryption keys, by a code (twin of `KeysError` in packages/vault/src/keyring.ts).
class KeysError implements Exception {
  const KeysError(this.code, {this.status});

  final String code;
  final int? status;

  @override
  String toString() => 'KeysError($code${status == null ? '' : ', $status'})';
}
