import 'dart:convert';
import 'dart:typed_data';

import '../api/auth_api.dart';
import '../api/passkeys.dart';
import 'keys_error.dart';

/// A passkey's PRF (WebAuthn `prf` extension): the 32 bytes a passkey gives for [prfSalt], which
/// open that passkey's wrap of DK. Twin of apps/web/app/local/prf.ts. They are never stored.
///
/// Providers differ: some return `prf: {}`, and a registration may return `prf: {enabled: true}`
/// without results (the PRF then needs a second touch).

/// SHA-256("wambito/v1/prf"): the same salt for every passkey (`PRF_SALT` in packages/crypto).
final Uint8List prfSalt = Uint8List.fromList([
  for (var i = 0; i < _saltHex.length; i += 2) int.parse(_saltHex.substring(i, i + 2), radix: 16),
]);
const _saltHex = '999d11fd4d3213d08d6d21fd1e08fa663b32f6c21c4d60374015461bfcfdbedb';

/// The credential that was touched (base64url, as Better Auth stores `credentialID`) and its PRF.
class PasskeyPrf {
  const PasskeyPrf({required this.credentialId, required this.prf});

  final String credentialId;
  final Uint8List prf;
}

String _b64url(Uint8List bytes) => base64Url.encode(bytes).replaceAll('=', '');

Uint8List? _fromB64url(Object? value) {
  if (value is! String) return null;
  try {
    return base64Url.decode(base64Url.normalize(value));
  } on FormatException {
    return null;
  }
}

/// The WebAuthn extension input: evaluate the PRF at [prfSalt], as the request JSON carries it.
Map<String, Object?> prfExtension() => {
  'prf': {
    'eval': {'first': _b64url(prfSalt)},
  },
};

Map<String, Object?>? _prfOf(Map<String, Object?> clientExtensionResults) {
  final prf = clientExtensionResults['prf'];
  return prf is Map ? prf.cast<String, Object?>() : null;
}

Uint8List? _firstOf(Map<String, Object?>? prf) {
  final results = prf?['results'];
  return results is Map ? _fromB64url(results['first']) : null;
}

/// `prf.results.first` from a credential's `clientExtensionResults`, only when it is 32 bytes;
/// else null (no extension, `prf: {}`, `enabled` without results, another length).
Uint8List? readPrf(Map<String, Object?> clientExtensionResults) {
  final bytes = _firstOf(_prfOf(clientExtensionResults));
  return bytes != null && bytes.length == 32 ? bytes : null;
}

/// Whether a registration's results say the passkey supports PRF but gave no output yet.
bool prfEnabledWithoutResults(Map<String, Object?> clientExtensionResults) {
  final prf = _prfOf(clientExtensionResults);
  return prf?['enabled'] == true && _firstOf(prf) == null;
}

/// A touch of one of the person's passkeys only to evaluate its PRF: [Passkeys.get] with the
/// request [optionsJson] plus the PRF extension. Null when the person cancels; `KeysError('no_prf')`
/// when the passkey gives no PRF.
Future<PasskeyPrf?> evaluatePrf(Passkeys passkeys, String optionsJson) async {
  final options = (jsonDecode(optionsJson) as Map).cast<String, Object?>();
  final extensions = {
    ...?(options['extensions'] as Map?)?.cast<String, Object?>(),
    ...prfExtension(),
  };
  final String json;
  try {
    json = await passkeys.get(jsonEncode({...options, 'extensions': extensions}));
  } on AuthFailure catch (error) {
    if (error.code == 'AUTH_CANCELLED') return null;
    rethrow;
  }
  final decoded = jsonDecode(json);
  final id = decoded is Map ? decoded['id'] : null;
  if (decoded is! Map || id is! String) throw const KeysError('bad_response');
  final credential = decoded.cast<String, Object?>();
  final results = credential['clientExtensionResults'];
  final prf = readPrf(results is Map ? results.cast<String, Object?>() : const {});
  if (prf == null) throw const KeysError('no_prf');
  return PasskeyPrf(credentialId: id, prf: prf);
}
