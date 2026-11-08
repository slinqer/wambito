# End-to-end encryption, stage 1b: closing the gaps before the clients

Status: in progress. Addendum to `2026-11-08-end-to-end-encryption-design.md` (the main spec). It
settles the four items of the main spec's section 17 before stage 2 (web) and stage 3 (Dart port).
Where this addendum and the main spec differ, this addendum wins.

## 1. Pairing with a commitment (replaces main spec 7.3)

Problem: as built, the server relays the new device's public key before anything else, so a
malicious server can put its own key in front of the approving device. The 6-digit number cannot
catch that unless neither side's key can be chosen after seeing the other's.

The fix is a hash commitment in the style of ZRTP. The **new device commits first** and reveals
last. That ordering matters: the server sees only a hash when it must pick a key for the approving
device, and must pick the approver key it shows the new device before it learns that device's key.
Either way it is guessing a 6-digit number blind, a 1 in 1,000,000 chance per attempt, and each
attempt costs the person a visible failed pairing. (Section 17 of the main spec had the approving
device commit; that order still lets the server see the new device's key first, so this addendum
reverses it.)

Keys:

- `N`: the new device's X25519 key pair. Its public key is `N.pub`; its private key stays on the device.
- `A`: an ephemeral X25519 key pair the approving device makes for this pairing only.
- `commit = SHA-256("wambito/v1/pairing-commit" || N.pub)` (32 bytes).

Steps:

1. **The new device opens the request.** It makes `N` and calls `POST /v2/pairing` with
   `{ commitment }`. The server answers `{ id, code, expiresAt }`. The device shows the 8-character
   code and a QR. The QR carries `wambito://pair?id=<id>&key=<base64url N.pub>`.
2. **The approving device finds it.** It calls `GET /v2/pairing?code=` and gets
   `{ id, commitment, expiresAt }`. A QR scan gives it the id and `N.pub` directly.
3. **The approving device sends its key.** It makes `A` and calls `POST /v2/pairing/{id}/approver`
   with `{ publicKey: A.pub }`. The server accepts this once (a second call is 409
   `already_set`).
4. **The new device reveals its key.** It polls `GET /v2/pairing/{id}`. Once it sees
   `approverKey`, it calls `POST /v2/pairing/{id}/reveal` with `{ publicKey: N.pub }`. The server
   checks it against the commitment (422 `commitment_mismatch` when it does not match) and
   accepts it only after the approver key is set (409 `not_ready`).
5. **Both show the number.** The approving device polls the same GET, reads `publicKey`, and
   checks `pairingCommitment(publicKey) == commitment` itself; a mismatch stops the pairing. Then
   both devices show `pairingNumber(N.pub, A.pub)`, and the person confirms on the approving
   device that they match. After a QR scan, the approving device compares the revealed key with
   the one in the QR instead, and both skip the number.
6. **The approving device seals the data key.** It calls `POST /v2/pairing/{id}/seal` with
   `{ sealed, keyV }`. `sealed` is `sealToDevice(N.pub, ctx, DK, A)`, so its first 32 bytes are
   `A.pub`. The server checks those 32 bytes against the stored approver key (422
   `approver_mismatch`) and needs the revealed key to be set (409 `not_ready`).
7. **The new device opens it.** `GET /v2/pairing/{id}` returns `{ sealed, keyV }` and deletes
   the row. The new device opens it with `openFromPairing(N.priv, ctx, sealed, A.pub)`. That call
   refuses a blob whose ephemeral key is not the `A.pub` behind the number (`cannot_open`). The
   wrap context is `{ kind: "device", userId, keyV }`, so `keyV` travels in the clear but is
   authenticated by the associated data: a wrong `keyV` does not open.
8. **The new device registers itself.** It posts its own `device` wrap, with an attestation
   (section 2).

`GET /v2/pairing/{id}` answers both devices with
`{ commitment, approverKey, publicKey, sealed, keyV, expiresAt }`; each field is null until set.
It deletes the row when it returns `sealed`. The limits stay as they are: 10 minutes, at most 5
open requests, and assistant tokens get 403.

## 2. Attestation of device keys (main spec 7.5)

Problem: during rotation, the rotating device seals the new data key to every device public key the
server lists, so a malicious server could add its own key to that list.

- `attestKey = HKDF-SHA256(DK, salt = empty, info = "wambito/v1/device-attest")`, used as an
  HMAC-SHA256 key.
- `attestation = HMAC(attestKey, utf8(userId) || 0x00 || utf8(wrapId) || 0x00 || publicKey)`
  (32 bytes). Neither id can contain 0x00, so the encoding is unambiguous.
- Every `device` wrap stores an `attestation` (32 bytes) next to `public_key` (32 bytes).
  `PUT /v2/keys/{id}` and `POST /v2/keys/rotate` return 422 `attestation_required` for a device
  wrap without both. The server cannot check an attestation, since it has no DK; it only stores it.
- A device that unlocks with DK writes its own attestation, and the approving device needs to do
  nothing extra.
- Before rotating, the rotating device verifies each listed device wrap's attestation under the
  current DK. It leaves out, and reports, any device wrap that fails. Under the new DK it writes
  fresh attestations for the devices it keeps.
- Clients ignore a device wrap that fails verification, wherever they meet one.

## 3. A device that was away too long (replaces the 170-day rule)

The daily purge deletes tombstones older than 180 days. A device whose last pull is older than
that never learns about those deletions. The main spec had the client do a full resync after 170
days. This addendum makes the check exact instead:

- A new table `record_purges (user_id primary key, through_version bigint)`, with forced RLS,
  holds the highest version of any tombstone purged for that person.
- `GET /v2/sync?since=X` with `0 < X < through_version` answers 410 `resync_required`. The client
  then drops its local copy and pulls from 0.
- A `since` of 0 is never refused.

## 4. Testing

- New vectors in `packages/crypto/test-vectors.json`:
  - `pairingCommitment`;
  - `pairingNumber` with the new inputs; the function itself is unchanged;
  - `sealToDevice` with a given ephemeral key;
  - `deviceAttestation`.
  - In `rejects`: an `openFromPairing` call whose blob carries a different ephemeral key.
- API tests cover:
  - every state transition of the pairing and its out-of-order errors;
  - the commitment and approver checks;
  - device wraps without an attestation;
  - 410 on a stale `since`.

## 5. Migration

`0011_end_to_end_gaps.sql`. The `pairing_requests` and `key_wraps` tables have no rows in
production, since no client uses them yet, so the migration can delete from `pairing_requests` and
change its columns in place.
