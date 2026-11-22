import 'package:flutter/foundation.dart';

import '../crypto/crypto.dart';

/// The recovery verifier's hashes (spec 2026-11-15 section 6, plan decision D16): what the server
/// stores to let a recovery key sign in. Pure crypto, no network: `putRecoveryVerifier` (keys.dart)
/// sends them. Nothing here logs or keeps a secret or a derived key.

/// The test seam of `recoveryVerifier` (to check that its outputs are zeroed). Production code
/// never changes it.
@visibleForTesting
Future<RecoveryVerifier> Function(Uint8List secret) keysRecoveryVerifier = recoveryVerifier;

/// The two hashes the server stores to let a recovery key sign in (`lookup_hash`, `auth_hash`).
typedef VerifierHashes = ({Uint8List lookupHash, Uint8List authHash});

/// The verifier hashes of a 16-byte recovery secret: SHA-256 of its two HKDF outputs
/// ([recoveryVerifier], [verifierHash]). The raw outputs are zeroed before this returns; the
/// caller owns [secret] and zeroes it.
Future<VerifierHashes> verifierHashesOf(Uint8List secret) async {
  final verifier = await keysRecoveryVerifier(secret);
  try {
    return (
      lookupHash: await verifierHash(verifier.lookup),
      authHash: await verifierHash(verifier.auth),
    );
  } finally {
    verifier.lookup.fillRange(0, verifier.lookup.length, 0);
    verifier.auth.fillRange(0, verifier.auth.length, 0);
  }
}
