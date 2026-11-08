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
- `src/bytes.ts`: base64url. `src/errors.ts`: `CryptoError` (`cannot_open`, `bad_recovery_key`,
  `bad_input`).

## Test

- `pnpm vitest run --project @wambito/crypto`; typecheck: `pnpm --filter @wambito/crypto typecheck`.

## Rules

- Any change to a format (infos, associated data, padding, body layout) needs a new `enc_v` and
  updated test vectors; the Dart implementation must pass the same vectors.
- No other crypto dependency without a design change.
