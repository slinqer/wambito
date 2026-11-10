# E2E stage 2b (web, second half) implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** a preview account on the web unlocks with a passkey (PRF) or with another device's
approval, and manages its keys in Settings → Security:
- passkeys that unlock;
- devices, with remove and rotate;
- a new recovery key;
- a count of unreadable items.

**Architecture:** 2a left one data key version per browser and a recovery-only Unlock. This plan
adds:
- a keyring (record keys per `keyV`), plus a way to open the data key DK from this browser's own
  `device` wrap;
- a sync engine that follows a rotation instead of quarantining what it cannot open;
- a PRF module over WebAuthn;
- a pairing client for both roles;
- a rotation module.

The screens stay pure UI with callbacks, as in 2a. The server gains one rule: a push whose `keyV`
is not the account's current one is refused per change.

**Tech Stack:** React Router 8, TanStack Query, IndexedDB (`app/local/db.ts`), `@wambito/crypto`
(WebCrypto), `@better-auth/passkey` 1.7.11 client (SimpleWebAuthn 13.3.0), Hono API, Vitest,
Playwright (Chromium virtual authenticator with `hasPrf`).

**Spec:**
- `docs/superpowers/specs/2026-11-08-end-to-end-encryption-design.md`, sections 4.1, 7.1–7.5, 8.1,
  8.2, 10 and 13;
- the addendum `docs/superpowers/specs/2026-11-08-e2e-stage-1b-design.md`, which wins where they
  differ (pairing order, attestation, revoked list);
- the 2a plan, `docs/superpowers/plans/2026-11-08-e2e-stage-2a-web.md`, for what exists.

## Rulings (decided here, recorded for review)

1. **Where DK comes from.** Operations that need DK use this browser's own `device` wrap: adding
   a passkey wrap, approving a device, rotating, and a new recovery key. The browser opens that
   wrap with its non-extractable private key (`openFromDevice`), as spec 7.5 already does for a
   new `keyV`. DK lives in memory for that one operation and is zeroed in a `finally`.
   - Spec 7.4's "ask again" is kept as a confirmation before rotation and before a new recovery
     key: the recovery key, typed, or a touch of any of the person's passkeys.
   - Adding a passkey wrap needs no extra confirmation: the touch on that passkey is the
     confirmation.
   - Approving a device is confirmed by the number comparison.
2. **What a rotation can re-wrap.** A rotation needs a recovery wrap (the server requires exactly
   one), and a passkey wrap needs that passkey's PRF. So removing a device asks for one of two
   things:
   - **the recovery key, typed:** the same key is re-wrapped and the person writes nothing new
     down;
   - **"make a new recovery key":** the `RecoveryKeySetup` flow. A passkey touch confirms it when
     the account has passkeys.

   Passkey wraps behave like this:
   - the passkey touched during the operation, if it returned PRF, is re-wrapped;
   - the others lose their wrap until they are next used. They show as "does not unlock" with a
     "Turn on" button (Task 8).
   - Assistants have no wraps on the web yet (stage 4), so nothing is dropped for them.
3. **The server refuses stale keys.** A pushed change whose `keyV` is not the account's current
   key version gets the per-change result `{ id, error: "key_version_mismatch", keyV: <current> }`.
   This applies only when the account has wraps; an account without wraps accepts any `keyV`.
   - It stops a removed browser, which still holds a session and the old DK, from writing under
     the old key.
   - It makes every device re-seal its pending edits under the new key.
   - Ending the removed browser's session is out of scope (later).
4. **Who re-encrypts.** Any unlocked device, not only the one that rotated. After each pull, the
   sync engine re-seals the records whose `keyV` is lower than the current one, at most 500 per
   run. These go through the outbox with an unchanged body, so a closed tab never leaves a
   rotation half done. A browser keeps old record keys until no local record uses that `keyV`.
5. **QR codes.** One new dependency: `uqr` (MIT, no dependencies) draws the pairing QR as SVG.
   - Scanning uses the browser's `BarcodeDetector` where it exists (Chromium). Elsewhere there is
     no camera button and the 8-character code is the way. Spec 7.3 offers both, so the code alone
     is complete.
   - No QR decoder library.
6. **Device labels.** A device wrap's label is `"<browser> on <OS>"` from `navigator.userAgent`
   (`Firefox on macOS`, `Chrome on Android`), falling back to `"Web"`.
7. **The revoked list.** `settings` gains `revokedDevices: string[]`, the wrap ids of removed
   devices (default `[]`). Every rotation leaves out the union of that list and the ids being
   removed now, whatever the server lists (addendum section 2).
8. **Guests.**
   - Settings → Security is hidden for guests.
   - The guest `Locked` screen gains "Approve from another device", because pairing works without
     a recovery key.

## Global Constraints

- Follow the root `AGENTS.md` and `apps/web/AGENTS.md`.
  - Copy goes in `app.{es,en,it,pt}.json` (`messages.test.ts`).
  - New screens are web-only stories titled `Vault/*` or `Settings/Security*`, not in
    `parity.json`.
- **Secrets:**
  - Never log, send or store plaintext, DK, a PRF output, a recovery secret or a private key
    outside the browser.
  - IndexedDB keeps only non-extractable `CryptoKey`s plus meta (spec 7.4).
  - PRF outputs and DK are zeroed after use.
- **Fixed values:**
  - PRF salt: `PRF_SALT` from `@wambito/crypto` (spec 4.1).
  - Pairing: the code is 8 characters and a request lives 10 minutes; the number is
    `pairingNumber(N.pub, A.pub)`; the QR is `wambito://pair?id=<id>&key=<base64url N.pub>`
    (addendum 1).
- **Pinning (addendum 1, `packages/crypto/AGENTS.md`):** the approver pins the `commitment` from
   `GET /v2/pairing?code=` (or from the QR's key). The new device pins the first `approverKey` it
   sees and aborts if a later poll shows another.
- Every `/v2` call sends `x-wambito-user: <vault user id>`; a 409 `session_changed` behaves as
  in 2a.
- An API change gets a CHANGELOG line under "Unreleased" and regenerated types: web `api:types`,
  mcp `api:types`, and `apps/mobile/scripts/gen-api.sh`. The mobile Profile fixtures that broke
  CI on 2a show why the mobile regeneration matters.
- Money in integer cents; ids are lower-case UUID v7; write the failing test first; one commit
  per task.

## Review Focus

1. **A browser that missed a rotation** (closed during it) opens and pulls records at `keyV + 1`.
   It must refresh its keys from its device wrap and open them; it must not quarantine them.
   *Test: Task 3, "a record under a newer keyV refreshes the keys, then applies".*
2. **A removed browser with an open tab edits offline,** then reconnects:
   - the push is refused (`key_version_mismatch`);
   - the key refresh finds no device wrap of its own;
   - the vault is deleted and Unlock shows "This browser was removed".

   Its pending edits are lost, and the copy says so.
   *Tests: Task 2 (refresh), Task 3 (push), Task 9 (e2e).*
3. **A rotation interrupted** after `POST /v2/keys/rotate`, before every record is re-sealed.
   Another device finishes the re-seal, and no one loses access to old records meanwhile.
   *Test: Task 3, "the upgrade pass re-seals old records and drops the old key when none is left".*
4. **A passkey whose provider gives no PRF** (the Proton Pass and 1Password extensions). Unlock
   says so, offers the other two ways, and creates no wrap.
   *Test: Task 5, "a passkey without PRF results is `no_prf`, and nothing is sent".*
5. **A pairing tampered with or expired:**
   - an approver key that changes between polls aborts the new device;
   - a revealed key that does not match the commitment, or the QR key, aborts the approver;
   - a 404 or expiry on either side ends with "This request expired" and a way to start again;
   - a typed code in lower case or with spaces still works.

   *Tests: Task 6.*

---

### Task 1: the server refuses a stale `keyV`; `revokedDevices` in settings

**Files:**
- Modify: `apps/api/src/services/sync.ts` (`PushResult`, `applyChange`), `apps/api/src/routes/sync.ts` (result schema)
- Modify: `packages/core/src/records.ts` (`settingsRecord`)
- Test: `apps/api/test/sync.test.ts` (or the existing sync route test file), `packages/core/src/records.test.ts`
- Modify: `CHANGELOG.md`; regenerate `apps/web/app/api/schema.d.ts`, `apps/mcp/src/api/schema.d.ts`, `apps/mobile/lib/api/gen`

**Interfaces:**
- Produces:
  - `PushResult` gains `{ id: string; error: "key_version_mismatch"; keyV: number }`;
  - `SettingsRecord.revokedDevices: string[]` (default `[]`).

- [ ] **Step 1: Write the failing tests**
  - `a change under an old keyV is refused with the current one`: the account's wraps are at
    keyV 2; push `{ keyV: 1 }` → result `{ id, error: "key_version_mismatch", keyV: 2 }`; no row
    written.
  - `a change under a future keyV is refused too`: keyV 3 → same error, `keyV: 2`.
  - `an account without wraps accepts any keyV`: keyV 7 → `{ id, version }`.
  - `one stale change does not stop the batch`: one change at keyV 1 and one at keyV 2 → one
    error and one version.
  - core: `settings without revokedDevices parses to []`; `revokedDevices keeps lower-case uuids`;
    `a non-uuid in revokedDevices fails`.
- [ ] **Step 2: Run them and see them fail**
  - `pnpm vitest run apps/api -t "keyV"`
  - `pnpm vitest run packages/core -t revokedDevices`
- [ ] **Step 3: Implement.**
  - Read `currentKeyV(tx, userId)` once per push (it is in `services/keys.ts`) and check it before
    `applyChange`.
  - Add `revokedDevices: z.array(z.uuid()).default([])` to `settingsRecord`.
- [ ] **Step 4: Regenerate the types, then run the tests.**
  - Regenerate: `pnpm --filter @wambito/web api:types --file`,
    `pnpm --filter @wambito/mcp api:types`, `apps/mobile/scripts/gen-api.sh`.
  - Run `pnpm vitest run apps/api packages/core` → PASS.
  - Run `flutter test --exclude-tags golden test/api`, from `apps/mobile` → PASS.
- [ ] **Step 5: CHANGELOG** line under "Unreleased": `/v2/sync` push refuses a change whose
  `keyV` is not the current one (`key_version_mismatch`).
- [ ] **Step 6: Commit** `feat(api): refuse pushes under a stale key version`

### Task 2: the keyring and DK from this browser's device wrap

**Files:**
- Modify: `apps/web/app/local/keys.ts`, `apps/web/app/local/encrypted-store.ts` (key names)
- Create: `apps/web/app/local/device-label.ts`
- Test: `apps/web/app/local/keys.test.ts`, `apps/web/app/local/device-label.test.ts`

**Interfaces:**
- Produces:
  - `type Keyring = { current: number; byVersion: Map<number, RecordKeys> }`;
  - `LocalKeys` becomes `{ keyring: Keyring }`, and its callers in `vault-session.ts`,
    `sync.ts` and `VaultGate.tsx` are updated;
  - `loadLocalKeys(userId): Promise<LocalKeys | null>`;
  - `withDataKey<T>(options: KeysOptions, fn: (dk: Uint8Array, keyV: number) => Promise<T>): Promise<T>`;
  - `refreshKeys(options: KeysOptions): Promise<LocalKeys>`, which throws
    `KeysError("device_removed")`;
  - `dropKeyVersion(userId, keyV): Promise<void>`;
  - `deviceLabel(userAgent: string): string`.
- New stored values:
  - in the `keys` store: `record:<v>` and `dedupe:<v>`. 2a's names `record` and `dedupe` are read
    as version `meta.keyV` and rewritten under the new names on first load.
  - in `meta`: `deviceWrapId` and `devicePublicKey` (base64url), written by every enroll.

- [ ] **Step 1: Write the failing tests** (`fake-indexeddb`, real crypto, a fake `/v2/keys`)
  - `enroll keeps the device wrap id and public key`.
  - `a 2a vault's keys load as version keyV and move to the versioned names`.
  - `withDataKey opens this browser's device wrap and zeroes DK after`: the bytes passed to `fn`
    are all 0 once it returns.
  - `withDataKey throws device_removed when no device wrap has this browser's id`.
  - `refreshKeys adds the new version and keeps the old one`: the server's device wrap for this
    id is at keyV 2, sealed to this browser's public key, so
    `keyring.byVersion` has the keys 1 and 2 and `current` is 2.
  - `refreshKeys refuses a device wrap whose public key is not this browser's` (`device_removed`).
  - `dropKeyVersion removes record:1 and dedupe:1 only`.
  - `deviceLabel`: Firefox on macOS, Chrome on Android, Safari on iOS, Edge on Windows, and an
    unknown agent gives "Web".
- [ ] **Step 2: Run** `pnpm vitest run apps/web/app/local/keys.test.ts apps/web/app/local/device-label.test.ts` → FAIL.
- [ ] **Step 3: Implement.** `withDataKey` finds the device wrap by `meta.deviceWrapId`, checks
  that its `publicKey` equals `meta.devicePublicKey`, and opens it with `openFromDevice` under
  `{ kind: "device", userId, keyV: wrap.keyV }`.
- [ ] **Step 4: Run them** → PASS. Also run the 2a suites `sync.test.ts`, `vault-session.test.ts`
  and `vault-gate.test.ts` → PASS.
- [ ] **Step 5: Commit** `feat(web): a keyring per key version, and DK from the device wrap`

### Task 3: the sync engine follows key versions

**Files:**
- Modify: `apps/web/app/local/sync.ts`, `apps/web/app/local/vault-session.ts`
- Test: `apps/web/app/local/sync.test.ts` (extend the fake `/v2` with key wraps and the Task 1 rule)

**Interfaces:**
- Consumes: Task 2 (`Keyring`, `refreshKeys`, `dropKeyVersion`).
- Produces:
  - `createSyncEngine` takes `keyring` in place of `keys` and `keyV`, plus
    `refreshKeys: () => Promise<Keyring>`;
  - a run's result may carry `problem: "device_removed"`;
  - `VaultSession.onRemoved(cb)`.

- [ ] **Step 1: Write the failing tests**
  - `a record under a newer keyV refreshes the keys, then applies`: the record is not in
    quarantine, and `refreshKeys` was called once.
  - `a record under a keyV no refresh can open goes to quarantine`.
  - `a push refused with key_version_mismatch refreshes, re-seals at the new keyV and pushes again`.
  - `the upgrade pass re-seals old records and drops the old key when none is left`: three
    records at keyV 1 with current 2 end at keyV 2 on the server; `record:1` is gone.
  - `the upgrade pass does at most 500 per run`.
  - `device_removed stops the engine and reports it`; the session then deletes the vault and
    calls `onRemoved`.
  - `pending edits are sealed under the current keyV, never an old one`.
- [ ] **Step 2: Run** `pnpm vitest run apps/web/app/local/sync.test.ts` → FAIL.
- [ ] **Step 3: Implement.**
  - **Opening:** choose the key by `rec.keyV`.
  - **An unknown version:** call `refreshKeys` once per run. If the version is still unknown
    after that, quarantine the record.
  - **The upgrade pass:** after the pull, for records whose `keyV` is below the current one, add
    an outbox entry `{ reseal: true }` with the record's full body and its version as
    `baseVersion`. A conflict on a reseal takes the server's copy.
  - **The old key:** drop it when the local stores hold no record under it.
- [ ] **Step 4: Run** → PASS, with the 2a sync cases still passing.
- [ ] **Step 5: Commit** `feat(web): sync follows key rotations and re-seals old records`

### Task 4: rotation, the revoked list and a new recovery key

**Files:**
- Create: `apps/web/app/local/rotate.ts`
- Test: `apps/web/app/local/rotate.test.ts`

**Interfaces:**
- Consumes: Task 2 (`withDataKey`, `deviceLabel`), Task 1 (`revokedDevices`), and the existing
  `prepareAccount`-style two-step pattern.
- Produces:
  - `rotateKeys(options: KeysOptions & { remove: string[]; recovery: { text: string } | { fresh: true }; passkey?: { credentialId: string; prf: Uint8Array } }): Promise<{ recoveryKey: string | null; commit(): Promise<RotateResult> }>`;
  - `RotateResult = { keyV: number; dropped: { id: string; label: string | null; reason: "removed" | "revoked" | "attestation" }[] }`;
  - `newRecoveryKey(options: KeysOptions): Promise<{ recoveryKey: string; commit(): Promise<void> }>`;
  - errors `KeysError("wrong_recovery_key" | "rotated_elsewhere" | "device_removed")`.
  - `rotated_elsewhere` is the 409 `key_version_mismatch` from `/v2/keys/rotate`.

- [ ] **Step 1: Write the failing tests** (fake `/v2/keys` that keeps the posted wraps and
  `settings` in the local store)
  - `a typed recovery key that does not open the current recovery wrap is wrong_recovery_key, before anything is made`.
  - `rotation keeps the other devices, sealed to their public keys with fresh attestations under the new DK, same ids and labels`.
  - `the removed ids and the settings' revokedDevices are left out, and reported`.
  - `a device wrap whose attestation fails under the old DK is left out and reported as attestation`.
  - `{ fresh: true } shows a new key and sends nothing until commit`.
  - `the touched passkey is re-wrapped; other passkeys lose their wrap`.
  - `after commit the keyring has the new version and settings.revokedDevices holds the removed ids` (an outbox write at the new keyV).
  - `a 409 key_version_mismatch from rotate is rotated_elsewhere and leaves the local keys untouched`.
  - `newRecoveryKey replaces the recovery wrap at the current keyV (PUT, same kind) only on commit`.
  - `DK, the new DK and the recovery secret are zeroed after commit or failure`.
- [ ] **Step 2: Run** `pnpm vitest run apps/web/app/local/rotate.test.ts` → FAIL.
- [ ] **Step 3: Implement** with the order spec 7.5 and addendum section 2 fix:
  1. open the old DK;
  2. verify the attestations and apply the revoked set;
  3. make the new DK and `keyV + 1`;
  4. build the wraps: one recovery, the kept devices, the touched passkey;
  5. `POST /v2/keys/rotate`;
  6. add the new version to the keyring locally;
  7. write `settings.revokedDevices`;
  8. trigger a sync, whose upgrade pass re-seals.
- [ ] **Step 4: Run** → PASS.
- [ ] **Step 5: Commit** `feat(web): rotate the data key when a device is removed`

### Task 5: passkey PRF (sign-in, Unlock, wraps)

**Files:**
- Create: `apps/web/app/local/prf.ts`
- Modify:
  - `apps/web/app/local/keys.ts` (`unlockWithPasskey`, `addPasskeyWrap`);
  - `apps/web/app/features/sign-in/auth.ts` (passkey sign-in passes the extension);
  - `apps/web/app/auth/passkey.ts` (registration asks for PRF);
  - `apps/web/app/features/vault/vault-gate.ts` and `VaultGate.tsx` (try the sign-in's PRF first);
  - `apps/web/app/features/vault/Unlock.tsx` (the "Use a passkey" button);
  - copy.
- Test: `apps/web/app/local/prf.test.ts`, `keys.test.ts`, `vault-gate.test.ts`, `Unlock.stories.tsx` play tests

**Interfaces:**
- Produces:
  - `prfExtension(): { prf: { eval: { first: Uint8Array } } }`, built with `PRF_SALT`;
  - `readPrf(clientExtensionResults: unknown): Uint8Array | null`, which takes
    `prf.results.first` only when it is 32 bytes;
  - `evaluatePrf(credentialIds?: string[]): Promise<{ credentialId: string; prf: Uint8Array } | null>`:
    a raw `navigator.credentials.get` with a random challenge, `allowCredentials` from the ids,
    and `userVerification: "required"`. It returns `null` when the person cancels, and throws
    `KeysError("no_prf")` when the touch gives no PRF. Nothing goes to the server: the PRF
    evaluation is local.
  - `keepSignInPrf(v)` and `takeSignInPrf(): { credentialId; prf } | null`: memory only, one
    read, cleared on sign-out;
  - `unlockWithPasskey(options & { credentialId; prf }): Promise<LocalKeys>`, with
    `KeysError("no_passkey_wrap")` when no passkey wrap has that `ref`;
  - `addPasskeyWrap(options & { credentialId; prf }): Promise<void>`, through `withDataKey`; it
    is a PUT `kind: "passkey"`, `ref: credentialId`, at the current `keyV`.

- [ ] **Step 1: Write the failing tests**
  - `readPrf` returns null:
    - with no `prf`;
    - with `prf: {}` (the Proton Pass shape);
    - with 16 bytes;
    - with `results.first` as an ArrayBuffer of 32 bytes.

    It copies the bytes.
  - `a passkey without PRF results is no_prf, and nothing is sent`, for `evaluatePrf` with a
    stubbed `navigator.credentials`.
  - `unlockWithPasskey opens the wrap whose ref is the credential and enrolls this browser`.
  - `unlockWithPasskey with an unknown credential is no_passkey_wrap`.
  - `addPasskeyWrap PUTs a wrap that unlockWithPasskey opens`.
  - The gate:
    - `a stashed sign-in PRF that opens a wrap unlocks without showing Unlock`;
    - `one that opens nothing shows Unlock, and after a recovery unlock the wrap for that credential is added`;
    - `no stash shows Unlock`.
  - Unlock story play tests:
    - `Use a passkey` calls `onPasskey`;
    - the `no_prf` copy names the two other ways;
    - the button is hidden when `passkeysSupported()` is false.
- [ ] **Step 2: Run** them → FAIL.
- [ ] **Step 3: Implement.**
  - **Sign-in:** call `authClient.signIn.passkey` with `extensions: prfExtension()` and
    `returnWebAuthnResponse: true`. If `readPrf(webauthn.clientExtensionResults)` gives bytes,
    stash them with `keepSignInPrf` (the extensions pass through, checked in
    `@better-auth/passkey` `client.mjs` and SimpleWebAuthn `startAuthentication`).
  - **Registration:** the offer and Settings pass the same extension. If the vault is open and
    the result has PRF, call `addPasskeyWrap`. If it has `prf.enabled` without results, call
    `evaluatePrf([newId])` once, which is a second touch, and explain why.
  - **The unlocked screen** zeroes the stash.
- [ ] **Step 4: Run** → PASS.
- [ ] **Step 5: Commit** `feat(web): unlock with a passkey's PRF`

### Task 6: the pairing client (both roles)

**Files:**
- Create: `apps/web/app/local/pairing.ts`
- Test: `apps/web/app/local/pairing.test.ts` (a fake relay with the addendum's state machine and
  error codes, plus fake timers)

**Interfaces:**
- Consumes: `pairingCommitment`, `pairingNumber`, `sealToDevice`, `openFromPairing`,
  `generateDeviceKeyPair` from `@wambito/crypto`; Task 2's `withDataKey`, and `enrollDevice` exported from `keys.ts`.
- Produces:
  - `startPairing(options: KeysOptions): Promise<NewDevicePairing>`, where `NewDevicePairing`
    has `{ id; code; qr: string /* wambito://pair?… */; expiresAt; number(): Promise<string> /* resolves after reveal */; finish(): Promise<LocalKeys>; cancel(): void }`;
  - `findPairing(options: KeysOptions & ({ code: string } | { qr: string })): Promise<ApproverPairing>`,
    where `ApproverPairing` has `{ number(): Promise<string>; approve(): Promise<void>; cancel(): void }`;
  - `PairingError` with the codes `expired | tampered | bad_code | offline | server`.
  - Polling runs every 1.5 s; both roles stop at `expiresAt`.

- [ ] **Step 1: Write the failing tests**
  - `the happy path`: the new device's `finish()` returns keys that open a record sealed under
    the account's DK; both sides' `number()` are equal; the relay row is gone.
  - `the approver pins the commitment from ?code=`: a later GET with another commitment, then a
    reveal matching that one, is `tampered`.
  - `the new device pins the first approverKey`: a later poll with another key is `tampered`,
    and no reveal is sent.
  - `a QR whose key is not the revealed key is tampered`.
  - `a sealed blob from another ephemeral key does not open` (`tampered`).
  - `a code is normalised`: `" abcd efgh "` is looked up as `ABCDEFGH`.
  - `404 or expiresAt passing is expired on both sides`.
  - `approve() takes DK from this browser's device wrap, seals with keyV, and zeroes DK`.
  - `cancel() stops polling`, with no further requests after it.
- [ ] **Step 2: Run** `pnpm vitest run apps/web/app/local/pairing.test.ts` → FAIL.
- [ ] **Step 3: Implement** the addendum's steps 1–8 in that order. After `finish()` opens DK,
  the new device enrolls with an attestation (addendum step 8).
- [ ] **Step 4: Run** → PASS.
- [ ] **Step 5: Commit** `feat(web): pairing client for a new and an approving device`

### Task 7: pairing screens

**Files:**
- Create:
  - `apps/web/app/features/vault/PairNewDevice.tsx`: the QR, the code in two groups of four, the
    number once known, the expiry and a restart;
  - `apps/web/app/features/vault/ApproveDevice.tsx`: type the code (or scan where
    `BarcodeDetector` exists), the number with "They match" and "They do not match", and done;
  - stories `Vault/PairNewDevice`, `Vault/ApproveDevice`.
- Modify:
  - `Unlock.tsx`, where "From another device" opens `PairNewDevice`;
  - `Locked.tsx`, where a guest gets "Approve from another device";
  - `vault-gate.ts`, which gains a `pairing` state;
  - copy;
  - `apps/web/package.json`, which adds `uqr`.
- Test: the stories' play tests, `vault-gate.test.ts`

**Interfaces:**
- Consumes: Task 6.
- Produces: `<ApproveDevice keys={…} onDone />`, which Task 8 mounts in Settings → Security.

- [ ] **Step 1: Write the failing tests**
  - `PairNewDevice shows the code as ABCD EFGH and an SVG QR`.
  - `the number appears only after number() resolves`.
  - `expired shows the restart button, which calls startPairing again`.
  - `ApproveDevice: "They do not match" cancels and says nothing was shared`.
  - `"They match" calls approve once`, with the button disabled while it runs.
  - `the camera button exists only when BarcodeDetector does`.
  - gate: `pairing → open after finish()`.
  - `a tampered pairing shows the "stop, someone may be interfering" copy, with a way back to Unlock`.
- [ ] **Step 2: Run** the storybook project for these stories → FAIL.
- [ ] **Step 3: Implement.** The QR is `renderSVG(qr)` from `uqr` in an `<img>` with a data URL,
  and the alt text is the code.
- [ ] **Step 4: Run** → PASS.
- [ ] **Step 5: Commit** `feat(web): approve a new device with a QR or a code`

### Task 8: Settings → Security

**Files:**
- Create:
  - `apps/web/app/features/settings/SecuritySection.tsx`;
  - `apps/web/app/features/settings/security-model.ts` (rows from `GET /v2/keys`, the local
    keyring and the passkey list);
  - `apps/web/app/features/settings/RemoveDeviceSheet.tsx`;
  - stories `Settings/Security*`.
- Modify:
  - `Settings.tsx`, which shows the section only in `mode === "local"` and not for guests;
  - `PasskeysSection.tsx`, where each passkey row shows "Unlocks" or "Does not unlock", plus
    "Turn on", which calls `evaluatePrf([id])` then `addPasskeyWrap`;
  - copy.
- Test: `security-model.test.ts`, the stories' play tests

**Interfaces:**
- Consumes: Tasks 2, 4, 5, 7; the quarantine count from `encrypted-store.ts` (count the
  `quarantine` store).
- Produces: nothing for later tasks.

- [ ] **Step 1: Write the failing tests**
  - model:
    - `this browser's device is marked and cannot be removed here`;
    - `a device whose attestation fails is shown as "Not verified" with remove only`;
    - `revoked ids are not listed`;
    - `passkeys join their wrap by credential id`.
  - sheet:
    - `remove asks for the recovery key or a new one`;
    - `a wrong key keeps the sheet with the error`;
    - `rotated_elsewhere says to try again after the refresh`;
    - `success lists what was dropped`.
  - `New recovery key`: a confirmation (the recovery key or a passkey touch), then the
    `RecoveryKeySetup` flow, and `commit()` only after the four characters are typed back.
  - `"Could not read N items" shows only when N > 0`.
- [ ] **Step 2: Run** → FAIL.
- [ ] **Step 3: Implement.** The section lists:
  - this browser and the other devices (label, added date);
  - "Approve a new device" (Task 7);
  - "New recovery key";
  - the unreadable count.

  The removed-browser state from Task 3 (`onRemoved`) routes to Unlock with the notice
  `vault.removed`.
- [ ] **Step 4: Run** → PASS.
- [ ] **Step 5: Commit** `feat(web): Settings → Security for encrypted accounts`

### Task 9: e2e

**Files:**
- Modify: `apps/web/e2e/vault.spec.ts` (new tests in the same file, desktop project only, after the
  2a test; each begins with `seed:e2e-preview`)

- [ ] **Step 1: Write the tests**
  - `a second browser unlocks by pairing`:
    1. context A is set up with the recovery key;
    2. context B signs in, and Unlock → "From another device" shows the code;
    3. A opens Settings → Security → "Approve a new device" and types the code;
    4. both show the same number, and A confirms;
    5. B opens on the movements A added.
  - `a passkey unlocks with PRF`:
    1. A adds a passkey through Settings, with the CDP
       `WebAuthn.addVirtualAuthenticator({ protocol: "ctap2", transport: "internal", hasResidentKey: true, hasUserVerification: true, isUserVerified: true, hasPrf: true })`;
    2. the passkey row shows "Unlocks";
    3. B, sharing that authenticator's credential (`WebAuthn.getCredentials` then
       `addCredential`), signs in with the passkey and lands on the movements without Unlock.
  - `a conflict merges field by field`:
    1. A and B are both unlocked;
    2. both go offline;
    3. A changes the note of movement M and B changes its amount;
    4. both go online and reload;
    5. both show A's note and B's amount.
  - `a removed browser locks`:
    1. A removes B with the recovery key;
    2. B, on its next sync, shows Unlock with "This browser was removed";
    3. B's IndexedDB is empty;
    4. A's movements still open after a reload, now at `keyV` 2.
- [ ] **Step 2: Run** `E2E_NOW=2026-10-21T15:00:00Z docker compose up -d --build`, then
  `npx playwright test e2e/vault.spec.ts` in `apps/web` → FAIL before Tasks 1–8, PASS after.
  If `hasPrf` is missing from this Chromium's CDP, mark only that test `fixme`, with the reason
  in the test.
- [ ] **Step 3: Commit** `test(web): e2e for pairing, passkey unlock, merge and removal`

## Final

- Run `pnpm lint && pnpm typecheck && pnpm test`, the full web e2e, `scripts/check-old-name.sh`,
  and `flutter test --exclude-tags golden` in `apps/mobile` (Task 1's regenerated client).
- Update the maps:
  - `apps/web/AGENTS.md`: `app/local/` keyring, `prf.ts`, `pairing.ts`, `rotate.ts`,
    `device-label.ts`; the vault screens; Settings → Security;
  - `packages/core/AGENTS.md`: `revokedDevices`.
- Get a whole-branch review, then open the PR.
