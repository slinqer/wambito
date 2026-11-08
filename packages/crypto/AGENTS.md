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
- `src/recovery.ts`: recovery secret, 26 Crockford chars + mod-37 check, groups of four.
- `src/devices.ts`: X25519 device keys, `sealToDevice` / `openFromDevice`; WebCrypto X25519 when
  present, `@noble/curves` otherwise (feature-detected at first use).
- Device private keys have two forms (`DevicePrivateKey`): a non-extractable WebCrypto `CryptoKey`,
  or, only where WebCrypto lacks X25519, `{ kind: "noble-x25519", raw }`, clone-safe but a raw
  secret the web must protect. UUIDs in contexts must be lower-case (they enter the AAD verbatim).
- `src/pairing.ts`: pairing code and the 6-digit number (async: WebCrypto SHA-256).
- `src/validate.ts`: UUID, key version, nonce checks (`bad_input`).
- `src/bytes.ts`: base64url. `src/errors.ts`: `CryptoError` (`cannot_open`, `bad_recovery_key`,
  `bad_input`).

## Test

- `pnpm vitest run --project @wambito/crypto`; typecheck: `pnpm --filter @wambito/crypto typecheck`.

## Rules

- Any change to a format (infos, associated data, padding, body layout) needs a new `enc_v` and
  updated test vectors; the Dart implementation must pass the same vectors.
- No other crypto dependency without a design change (`@noble/curves` is the X25519 fallback).
