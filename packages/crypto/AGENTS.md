# packages/crypto (`@wambito/crypto`)

End-to-end encryption primitives, WebCrypto only (`globalThis.crypto.subtle`, Node 22): the data
key, record keys, record sealing and dedupe tags. Design: section 4 of
`docs/superpowers/specs/2026-11-08-end-to-end-encryption-design.md`. Used by the web, the MCP and the
API tests.

## Entry points

- `src/index.ts` re-exports everything.
- `src/keys.ts`: `generateDataKey`, `deriveRecordKeys` (HKDF-SHA256, empty salt, infos
  `wambito/v1/record` and `wambito/v1/dedupe`; non-extractable by default).
- `src/records.ts`: `sealRecord` / `openRecord` (AES-256-GCM, associated data
  `wambito/v1/record/<user id>/<type>/<id>/<key_v>`, JSON padded to 64 bytes), `dedupeTag`.
- `src/wraps.ts`: `wrapDataKey` / `unwrapDataKey` (kinds passkey, recovery, assistant; HKDF info
  `wambito/v1/wrap/<kind>`, AAD `wambito/v1/wrap/<kind>/<user id>/<key_v>`), `PRF_SALT`.
- `src/recovery.ts`: recovery secret, 26 Crockford chars + a Luhn mod 32 check character over the
  Crockford alphabet, groups of four.
- `src/devices.ts`: X25519 device keys, `sealToDevice` (optional fixed ephemeral pair) / `openFromDevice` / `openFromPairing` (also checks the
  blob starts with the approver key); WebCrypto X25519 when
  present, `@noble/curves` otherwise (feature-detected at first use).
- Device private keys have two forms (`DevicePrivateKey`): a non-extractable WebCrypto `CryptoKey`,
  or, only where WebCrypto lacks X25519, `{ kind: "noble-x25519", raw }`, clone-safe but a raw
  secret the web must protect. `userId` is the account's exact id (Better Auth: `/^[A-Za-z0-9_-]{1,128}$/`, case kept, no `/`); record `id`s are lower-case UUIDs. Both enter the AAD verbatim.
- `src/pairing.ts`: pairing code, the 6-digit number and `pairingCommitment`
  (SHA-256(`wambito/v1/pairing-commit` || key); async: WebCrypto SHA-256). The API uses
  `pairingCode` in production (`apps/api/src/services/pairing.ts`), not only in tests.
- `src/attest.ts`: `deviceAttestation` / `verifyDeviceAttestation` (HMAC under HKDF info
  `wambito/v1/device-attest`; design: stage 1b spec section 2).
- `src/links.ts`: `sealKeyLink` / `openKeyLink`, `LINK_BYTES` = 60: `nonce (12) || AES-256-GCM(older data
  key)` under HKDF-SHA256(newer key, empty salt, info `wambito/v1/link`), AAD
  `wambito/v1/link/<user id>/<newer key_v>` (`keyV` >= 2). Design: the 2026-11-10 addendum
  (`docs/superpowers/specs/2026-11-10-e2e-key-links-design.md`, section 2).
- `src/validate.ts`: user id, UUID, key version, nonce checks (`bad_input`).
- `src/bytes.ts`: base64url, `timingSafeEqual`. `src/errors.ts`: `CryptoError` (`cannot_open`, `bad_recovery_key`,
  `bad_input`).

## Test

- `test-vectors.json` is shared with the Dart port (stage 3); never edit it by hand. Regenerate with
  `pnpm --filter @wambito/crypto vectors` (`scripts/gen-vectors.ts`, fixed inputs, deterministic: a
  rerun must leave `git diff --exit-code packages/crypto/test-vectors.json` clean). `test/vectors.test.ts`
  checks it. Its `rejects` section lists inputs every implementation must refuse, with the error code.
- `pnpm vitest run --project @wambito/crypto`; typecheck: `pnpm --filter @wambito/crypto typecheck`.

## Rules

- Any change to a format (infos, associated data, padding, body layout) needs a new `enc_v` and
  updated test vectors; the Dart implementation must pass the same vectors.
- No other crypto dependency without a design change (`@noble/curves` is the X25519 fallback).
- Pairing clients must pin values, or the server can still grind a matching number (stage 1b spec
  section 1). The approving device keeps the `commitment` it read from `GET /v2/pairing?code=`,
  read before it posts its key, and never re-reads it. The new device keeps the first
  `approverKey` it sees, uses that one in `pairingNumber` and `openFromPairing`, and aborts if a
  later poll shows another. Both devices always compare the number, QR or not.
