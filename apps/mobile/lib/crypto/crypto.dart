/// The end-to-end encryption primitives, the Dart port of packages/crypto (one file per
/// TypeScript file). The shared vectors (`packages/crypto/test-vectors.json`) must pass on both.
library;

export 'attest.dart';
export 'bytes.dart';
export 'devices.dart';
export 'errors.dart';
export 'keys.dart' show RecordKeys, deriveRecordKeys, generateDataKey;
export 'links.dart';
export 'pairing.dart';
export 'records.dart';
export 'recovery.dart' show formatRecoveryKey, newRecoverySecret, parseRecoveryKey;
export 'validate.dart' show assertKeyV, assertUserId, assertUuid;
export 'wraps.dart' show WrapContext, WrapKind, prfSalt, unwrapDataKey, wrapDataKey;
