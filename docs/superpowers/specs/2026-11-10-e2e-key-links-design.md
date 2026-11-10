# End-to-end encryption: authenticated key versions (addendum)

Date: 2026-11-10. Status: approach A chosen in conversation; written addendum under review.
Amends `2026-11-08-end-to-end-encryption-design.md` (sections 3, 5.2, 6, 7.5) and
`2026-11-08-e2e-stage-1b-design.md`. Comes before stage 3 (the Dart port), which builds it into the
phone from the start; the web (stage 2b, already built) is changed to match.

## 1. Problems

1. **A forged key version.** A `device` wrap is an anonymous sealed box to the device's public key,
   which the server knows. Today a browser that sees a `device` wrap above its current `keyV`
   accepts the data key inside it (`refreshKeys`; `withDataKey` checks only versions it already
   holds). A malicious server can seal its own data key as "version v+1": the browser then seals
   every new record under a key the server holds.
2. **A device that missed two rotations.** A rotation replaces every wrap. A browser at version v
   that comes back when the account is at v+2 gets DK(v+2) from its device wrap, but nothing
   gives it DK(v+1), so records still under v+1 (resealing not finished) stay unreadable.
3. **A removed device keeps its session.** Removing a device deletes its wrap and rotates, but
   its Better Auth session stays valid until it expires (60 days), so it can still pull
   ciphertext and see metadata.

## 2. Key links

Each key version after the first carries a **link**: the previous data key, sealed under a key
derived from the new one.

```
linkKey(v) = HKDF-SHA256(DK(v), salt = empty, info = "wambito/v1/link")   → AES-256-GCM
link(v)    = nonce (12 bytes) || AES-256-GCM(linkKey(v), DK(v-1))          for v ≥ 2
associated data: "wambito/v1/link/<user id>/<v>"
```

- Whoever holds DK(v) can walk down to every older version. Nobody can walk up: a removed device
  holding DK(v-1) learns nothing about DK(v), so rotation still locks it out.
- The server cannot make a link without DK(v-1), so it cannot make a new version that leads back to
  a key a device already holds.
- `packages/crypto` gains `sealKeyLink(newKey, oldKey, { userId, keyV })` → bytes and
  `openKeyLink(newKey, { userId, keyV }, link)` → the 32-byte older key (throws on a wrong key,
  version or account), with test vectors in `test-vectors.json` for the TypeScript and Dart
  implementations.

### 2.1 Server

- A new table, forced RLS like `key_wraps`:

  ```sql
  create table key_links (
    user_id    text not null,      -- Better Auth's id; RLS
    key_v      smallint not null,  -- the version whose key seals the link (v ≥ 2)
    link       bytea not null,     -- 60 bytes: nonce, sealed 32-byte key, tag
    created_at timestamptz not null,
    primary key (user_id, key_v)
  );
  ```

  Links are kept for the life of the account (one row per rotation) and deleted with it.
- `POST /v2/keys/rotate` takes `link` (base64url) next to `keyV` and `wraps`, and stores it in the
  same transaction. It is required when the account already has a key version (422
  `link_required`), and refused on the first one (422 `link_unexpected`). The server only checks
  the length (60 bytes, else 422 `invalid_link`); it cannot open a link.
- `GET /v2/keys` answers `{ wraps, links: [{ keyV, link }] }`, links ordered by `keyV`. The
  assistant route (`GET /v2/keys/assistant`) is unchanged: an assistant is disconnected by every
  rotation, and its reads start at the current version.

### 2.2 Accepting a new version (every client)

A device that holds versions up to `c` (its current one) and meets a data key DK(n) with `n > c`
from its `device` wrap accepts it only when the links lead back to the key it holds:

1. For `i` from `n` down to `c + 1`: `DK(i-1) = openKeyLink(DK(i), { userId, keyV: i }, link(i))`.
2. DK(c) must be the key this device holds for `c`: the web checks it with the canary it already
   uses (`sameDataKey` against `record:<c>`); the phone compares it with its stored DK in constant
   time.
3. On success it keeps the record and dedupe keys of every version from `c + 1` to `n` (the web as
   non-extractable `record:<v>`/`dedupe:<v>`; the phone keeps the data keys) and makes `n` current.
   Versions no local record uses are dropped later, as today (`dropKeyVersion`).
4. A missing link, a link that does not open, or a chain that ends at another key: refused as
   `tampered`. Every data key opened on the way is zeroed and nothing is kept. The device keeps
   working under `c`; the server will refuse its writes (409 `key_version_mismatch`), so it shows
   the "could not verify the new key" state and offers to unlock with a passkey or the recovery key
   (section 2.3).

The web applies this in `refreshKeys` and in `withDataKey`: an operation that opens DK from the
device wrap at a version above the browser's current one verifies the chain first, with the same
result. "A new version is not checked against the old one" is no longer true.

### 2.3 Ways in that need no chain

- **Passkey and recovery wraps** are sealed under secrets the server does not have, so a key opened
  from one is trusted as it is. When the device already holds an older version, it still walks the
  links down to it as in 2.2 and treats a mismatch as `tampered`. It also opens older versions it
  does not hold, so a newly unlocked device can read records not yet resealed.
- **Pairing** hands over DK(n) authenticated by the 6-digit number (stage 1b). The new device holds
  nothing older and walks the links only to read records under older versions.
- **The rotating device** made DK(n) itself and seals `link(n)` from the DK(n-1) it opened.

### 2.4 Limits

- A server that withholds a link (or the whole rotation) stops devices from moving up: they get
  stuck at the old version and see the `tampered` state. That denies service but reveals nothing.
- **A malicious server together with a stolen device** that still holds DK(v-1) can forge a
  version v+1 whose link leads back to DK(v-1). Devices that already accepted the real v+1 never
  replace it (versions only grow and a held version is never overwritten), so only a device that
  has not seen the real one yet can be fooled. Closing this needs signatures by a trusted set of
  devices (approach C in the conversation), left for later. Main spec section 3 gains this line.

## 3. Ending the removed device's session

- `key_wraps` gains `session_id text references session(id) on delete set null`. A `PUT
  /v2/keys/{id}` of a `device` wrap stores the caller's session id (cookie or bearer). Other kinds
  store null.
- `POST /v2/keys/rotate` copies each new device wrap's `session_id` from the old device wrap with the
  same `ref` (the device id), read before the old rows are deleted.
- When a device wrap goes away, the server deletes its session in the same transaction:
  - `DELETE /v2/keys/{id}` of a device wrap;
  - a rotation, for each old device wrap whose `ref` is not among the new wraps.

  It never deletes the caller's own session. Better Auth keeps no cookie cache here, so the next
  request with that session gets 401.
- The removed device then sees a sign-in screen. Its local copy (data it already had) stays on its
  disk until it signs in again and learns `device_removed` (which deletes the vault), or signs out.
  A device wrap stored before this change has no session id, and nothing is revoked for it.
- The copy that asks to sign out on the removed device (`settings.security.remove_sheet.done_lead`) says
  instead that the device was signed out.

## 4. Testing

- `packages/crypto`: vectors for `sealKeyLink`/`openKeyLink`. Opening fails for a wrong key, wrong
  version, wrong account and a flipped byte.
- API, against Postgres:
  - rotate with and without `link`, first and later versions, a bad length;
  - links listed in order and kept across rotations;
  - RLS on `key_links`;
  - `session_id` stored on a device PUT, copied by a rotation, null for other kinds;
  - the removed device's session is deleted by DELETE and by a rotation that leaves it out, and its
    next call gets 401;
  - the caller's session is never deleted.
- Web unit tests (`keys.ts`):
  - a forged v+1 (sealed to this browser's public key, no link or a link to another key) is
    `tampered`, keeps nothing and zeroes the keys;
  - a browser at v reaching v+2 keeps v+1 and v+2 and opens a record under v+1;
  - the same through `withDataKey`;
  - a passkey unlock at v+2 on a browser holding v walks down and refuses a mismatch;
  - `rotateKeys` posts a link that opens to the old DK.
- Web e2e (`vault.spec.ts`):
  - A removes B; B's next request is 401 and B, signed in again, shows the removed notice;
  - A rotates twice while C is closed; C opens and reads a record still under the middle version.

## 5. Migration

Encryption is still behind the preview switch, which lists nobody, so no real account has rotated.
An account that rotated before this change has versions without links. A device holding an older
version refuses them (`tampered`) and unlocks again with a passkey or the recovery key, which
starts it at the current version. No backfill.

## 6. Changes to existing docs

- Root `CHANGELOG.md`, under Unreleased:
  - `POST /v2/keys/rotate` requires `link`;
  - `GET /v2/keys` returns `links`;
  - removing a device ends its session.
- `packages/crypto/AGENTS.md`, `apps/api/AGENTS.md`, `apps/web/AGENTS.md` (the "Known limits" lines
  for the unauthenticated version, the browser two rotations behind, and the removed session go
  away; the collusion limit of 2.4 replaces them).
