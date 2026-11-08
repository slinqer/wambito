export {
  type DeviceAttestationInput,
  deviceAttestation,
  verifyDeviceAttestation,
} from "./attest.ts";
export { fromBase64Url, toBase64Url } from "./bytes.ts";
export {
  type DevicePrivateKey,
  generateDeviceKeyPair,
  importDevicePrivateKey,
  openFromDevice,
  openFromPairing,
  sealToDevice,
} from "./devices.ts";
export { CryptoError, type CryptoErrorCode } from "./errors.ts";
export { deriveRecordKeys, generateDataKey, type RecordKeys } from "./keys.ts";
export { pairingCode, pairingCommitment, pairingNumber } from "./pairing.ts";
export {
  dedupeTag,
  openRecord,
  type RecordContext,
  type RecordType,
  sealRecord,
} from "./records.ts";
export {
  formatRecoveryKey,
  newRecoverySecret,
  parseRecoveryKey,
} from "./recovery.ts";
export {
  PRF_SALT,
  unwrapDataKey,
  type WrapContext,
  type WrapKind,
  wrapDataKey,
} from "./wraps.ts";
