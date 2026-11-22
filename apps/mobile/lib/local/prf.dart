import 'dart:convert';
import 'dart:typed_data';

import '../api/auth_api.dart';
import '../api/passkeys.dart';
import '../crypto/wraps.dart' show prfSalt;
import 'keys_error.dart';

/// A passkey's PRF (WebAuthn `prf` extension): the 32 bytes a passkey gives for `prfSalt`
/// (lib/crypto/wraps.dart, the one source), which open that passkey's wrap of DK. Twin of
/// apps/web/app/local/prf.ts. They are never stored.
///
/// Providers differ: some return `prf: {}`, and a registration may return `prf: {enabled: true}`
/// without results (the PRF then needs a second touch).

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

/// The WebAuthn extension input: evaluate the PRF at `prfSalt`, as the request JSON carries it.
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

/// The request [optionsJson] with the PRF extension added (any other extension kept), so the
/// assertion it asks for carries the passkey's PRF: Unlock's touch and the passkey sign-in share it.
String withPrfExtension(String optionsJson) {
  final options = (jsonDecode(optionsJson) as Map).cast<String, Object?>();
  final extensions = {
    ...?(options['extensions'] as Map?)?.cast<String, Object?>(),
    ...prfExtension(),
  };
  return jsonEncode({...options, 'extensions': extensions});
}

/// The credential id and PRF of an assertion's JSON (`id`, `clientExtensionResults.prf`); null
/// without an id or without a 32-byte PRF, or when the JSON is not an assertion. The caller owns
/// the returned bytes and zeroes them.
PasskeyPrf? prfOfAssertion(String assertionJson) {
  final Object? decoded;
  try {
    decoded = jsonDecode(assertionJson);
  } on FormatException {
    return null;
  }
  if (decoded is! Map) return null;
  final id = decoded['id'];
  final results = decoded['clientExtensionResults'];
  final prf = readPrf(results is Map ? results.cast<String, Object?>() : const {});
  if (prf == null) return null;
  if (id is! String) {
    prf.fillRange(0, prf.length, 0);
    return null;
  }
  return PasskeyPrf(credentialId: id, prf: prf);
}

/// A touch of one of the person's passkeys only to evaluate its PRF: [Passkeys.get] with the
/// request [optionsJson] plus the PRF extension. Null when the person cancels; `KeysError('no_prf')`
/// when the passkey gives no PRF.
Future<PasskeyPrf?> evaluatePrf(Passkeys passkeys, String optionsJson) async {
  final String json;
  try {
    json = await passkeys.get(withPrfExtension(optionsJson));
  } on AuthFailure catch (error) {
    if (error.code == 'AUTH_CANCELLED') return null;
    rethrow;
  }
  final decoded = jsonDecode(json);
  if (decoded is! Map || decoded['id'] is! String) throw const KeysError('bad_response');
  final passkey = prfOfAssertion(json);
  if (passkey == null) throw const KeysError('no_prf');
  return passkey;
}
