# apps/web (`@wambito/web`)

React Router 8 (framework mode, SPA + prerender): the public landing, roadmap, privacy policy and
account deletion page (prerendered, es/en/it/pt; `app/features/legal/`), the signed-in app
(`/app/*`), sign-in (`/sign-in`: the QR for the phone, a recovery key, a passkey or email;
`/create-account`), onboarding (`/welcome`), OAuth consent for assistants, and a fake-backend demo
(`/demo/*`).

## Entry points

- `app/root.tsx` (document; theme bootstrap script first in `<head>`), `app/routes.ts` (route
  table; landing-only builds drop the app layout), `react-router.config.ts` (prerender list,
  build dir `WAMBITO_BUILD_DIR` or `build`), `vite.config.ts` (mascot chunk named `mascot-*`).
- `app/routes/*` thin route modules; `app/features/<feature>/` screens, models, stories;
  `app/ui/` shared components (interface icons: `Icon.tsx` over `icon-shapes.ts`, which reads
  `docs/design/system/project/icons/icons.json`; emoji only for categories); `app/wambi/` the mascot (`app/wambi/experimental/` 3D, never on
  the landing); `app/api/` OpenAPI client; `app/auth/` session and passkeys; `app/demo/` (the seed over a memory store);
  `app/local/` the browser side of the vault; the store contract (`FinanceStore`), the memory
  store, the local backend (`createLocalBackend`: the `/v1` routes over a store, one store
  transaction per request) and the ids (UUID v7 and v5) live in `packages/vault`
  (`@wambito/vault`, contract tests from `@wambito/vault/contract`); `db.ts` (promise wrapper over IndexedDB:
  database `wambito-vault-<userId>`, one store per record type plus `outbox`, `meta`,
  `quarantine`, `keys`; `deleteVault`), `encrypted-store.ts` (`createEncryptedStore(userId)`: a
  `FinanceStore` over `db.ts`; local writes update the record and the outbox in one IndexedDB
  transaction, `origin: "remote"` writes (sync) take `{ version, keyV }` and add no outbox entry;
  also the sync helpers `readOutbox`, `ackOutbox` (records the pushed `keyV` too), `getMeta/setMeta/deleteMeta`,
  `quarantine`, `wipeRecords`, `getKey/putKey/deleteKey/keyNames`, `parkOutbox`, `abandonOutbox`,
  `adoptServerCopy`, `restoreSetAside`, `queueReseal(current, limit)` (outbox entries `reseal: true`
  for pushed records under an older `keyV`), `keyVersionsInUse()` (quarantined rows' `keyV`
  included), `quarantined()`; a remote put or delete of an id clears its quarantine rows). Subscribers fire after every commit that
  wrote, whatever its origin, and for other tabs' commits too (a BroadcastChannel
  `wambito-vault-<userId>` tells the other tabs of each commit). `close()` (or another tab deleting
  or upgrading the database) closes it for good: every later op rejects with `VaultClosedError`
  (code `vault_closed`); `isClosed()`, `onClosed(cb)` → unsubscribe. `wipeRecords` keeps the outbox
  and sets pending entries aside (`restoreSetAside` puts them back after the full download,
  merging the touched fields); `resetAll` (the switch day's retry) clears records, quarantine,
  the whole outbox and the cursors and keeps keys and other meta; remote writes take
  `skipIfPending` / `ifSeq`. The seeded ids' namespace is `SETTINGS_SEED_NAMESPACE`
  (`@wambito/vault`).
  `sync.ts` (now `packages/vault/src/sync.ts`, imported from `@wambito/vault`; `createSyncEngine({ store, fetch, userId, keyring, refreshKeys, onError })` → `run()` /
  `start()`: push the outbox, then pull `/v2/sync`; field-by-field conflict merge, quarantine,
  `410` resync that keeps pending edits (set aside, then re-applied); the design notes are at the
  top of the file; tests run against a fake `/v2` in `sync.test.ts`). A run holds a Web Lock
  `wambito-sync-<userId>` (one sync per user across tabs). A failing outbox entry is parked
  (back-off 1 min doubling to 6 h; a local write to it clears the park) and never blocks the pull
  of other ids; its own id stays blocked while it retries, and on the fifth failure it is given up
  on (`abandoned`, reported in `dropped`): never pushed again, pulls apply the id again (the
  conflict's copy at once, else the next server edit or a resync) and the entry goes once the
  server's copy lands; a local write retries it;
  a whole-batch 413/422 is bisected, other 4xx park the batch and the pull still runs; a create
  conflict takes the server copy (plus the fields the person changed after the create, if they
  wrote while it was in flight). Results carry `parked` (ids; problem `parked`) and a closed
  store ends a run with `{ ok: false, error: "closed" }` (problem `closed`). Every `/v2` call
  (`sync.ts`, `keys.ts`) sends `x-wambito-user: <vault's user id>`; a 409 `session_changed` (the
  cookie is now another account's) stops the run and `start()`'s triggers (problem
  `session_changed`; `KeysError("session_changed")` in `keys.ts`). Key versions: a record opens
  with the keys of its own `keyV`, every change is sealed under `keyring.current`; a record under a
  newer `keyV`, or a per-change `key_version_mismatch` (pushed again once, re-sealed under the
  current version, also when the refresh went past the refused one), calls `refreshKeys` (again
  when a version above the last refresh's result is needed, at most once per distinct version per
  run; still unknown: quarantine `unknown_key_version`, with the row's `keyV`); when the keyring's
  current version grows, and on the engine's first pull, the pull retries those quarantine rows
  (pages again from the oldest one's version, only those ids); after each pull the
  upgrade pass re-seals records under an older `keyV` through the outbox (`reseal` entries: unchanged
  body, `baseVersion` = its version, at most 500 per run, a conflict takes the server's copy) and
  drops an old version's keys once no local record uses it; `refreshKeys` throwing `device_removed`
  stops the run and the triggers (`{ ok: false, error: "device_removed", problem: "device_removed" }`);
  `refreshKeys` throwing `tampered` does the same as `key_unverified` (`problem: "key_unverified"`),
  the outbox untouched (a change refused at the stale `keyV` is neither parked nor dropped).
  `keys.ts` (no React; injected `fetch`, `/api`): `prepareAccount({ userId, guest })` → `{
  recoveryKey, commit() }` (DK + recovery secret + device key pair, all in memory; nothing is sent
  until `commit()`, which the setup screen calls only after the four characters are typed back:
  PUT the recovery wrap first, then the attested device wrap (label `deviceLabel(userAgent)` from
  `device-label.ts`: `"Firefox on macOS"`, else `"Web"`), then keep only the non-extractable
  record/dedupe keys (`record:<v>`, `dedupe:<v>`) and the device private key (`device`) in the
  vault's `keys` store, plus meta `keyV` (current), `deviceWrapId` and `devicePublicKey`;
  retry-safe, the same ids on a retry, DK zeroed after success; `recoveryKey` is `null` for a
  guest, whose recovery secret is never shown and who commits at once; `KeysError("already_set_up")`
  when the account has wraps, and from `commit()` when another setup won the race: the recovery
  wrap goes with `If-None-Match: *`, so the server keeps one data key; the losing DK is zeroed;
  a shown key (`guest: false`) also gets its sign-in verifier between the recovery wrap and the
  device wrap (`PUT /v2/recovery/verifier`, `putRecoveryVerifier(options, secret)`: the SHA-256 of
  `recoveryVerifier(secret)`'s `lookup` and `auth`; made before the secret is zeroed, sent again
  with the same bytes on a retry; a guest's hidden key never gets one); `unlockWithRecovery` puts
  it too, best effort (a failed PUT never fails the unlock);
  `KeysError("unsupported_browser")` before anything is sent when WebCrypto lacks X25519, whose
  noble fallback would keep a raw private key: the web never stores one), `unlockWithRecovery({ userId, text })` (`bad_recovery_key` /
  `wrong_recovery_key`; enrolls this device, the caller then runs a full sync), `enrollDevice(options,
  dataKey, keyV, { ephemeral? })` (the same enroll for pairing and the QR sign-in; `ephemeral:
  true` sets the vault's meta `ephemeral`, `false` deletes it (a vault the person asked to keep is
  never swept), absent leaves it; the caller zeroes DK). Key links (spec
  2026-11-10): `listKeys(call)` → `{ wraps, links: Map<keyV, bytes> }` (an undecodable link is
  missing; `listWraps` wraps it); `chainDown(userId, top, links, floor, strict)` → the data keys
  `top.keyV - 1` down to `floor` (strict: a missing or failing link is `tampered`; else it stops
  there; zeroes what it opened on a throw). The trusted ways in (recovery, passkey, pairing) keep
  the older versions the links reach, from version 1 down, not strict. With a vault held here:
  a recovery or passkey key (authenticated by the person's secret; spec 2026-11-10 section 5)
  still walks not strict, a chain that stops or ends at another key is no error, and the held
  versions are never replaced (`keepLocally` skips them); pairing walks strictly down to the held
  current version, whose key must match (`sameDataKey`), else `tampered`; for all three a trusted
  version below the held current one is `tampered` (a replay), before anything is sent or kept.
  With a vault held, once the new device wrap is kept, `DELETE /v2/keys/{previous deviceWrapId}`
  (the server never ends the caller's own session); best effort: a failure never fails the
  unlock, it is `console.warn`ed with its code only and the old wrap stays listed in Settings. `loadLocalKeys(userId)` →
  `{ keyring: { current, byVersion: Map<keyV, RecordKeys> } }` (`null` = locked or no keys for
  `current`; a 2a vault's `record`/`dedupe` load as version `keyV` and are renamed;
  `currentRecordKeys(local)`; the sync engine takes the keyring), `withDataKey(options, fn)`
  (DK from this browser's own device wrap: found by `deviceWrapId`, its `publicKey` must equal
  `devicePublicKey`, opened with `openFromDevice`; `fn(dk, keyV)`, DK zeroed after;
  `KeysError("device_removed")` otherwise; a 2a browser without `deviceWrapId` tries each device
  wrap and keeps the one that opens; when this browser already holds the wrap's `keyV`, DK must
  be the one its `record:<v>` came from (a random canary sealed with the kept key opens with the
  key derived from DK), else `KeysError("tampered")`, DK zeroed and `fn` never runs; a wrap below
  the held current version must be at a version this browser holds and pass the same check, else
  `tampered` (versions only grow; a server that withheld the links at an unlock cannot hand it a
  key there); a wrap above
  the held current version is accepted only when its links lead strictly down to it and reach the
  held key, else `tampered`, every opened key zeroed: every caller
  (rotation, pairing approve, attestation marks, passkey wraps, `refreshKeys`) gets the check),
  `withDataKeyFrom(options, source, fn)` (`source`: `{ device: true }` is `withDataKey`; a
  `PasskeySecret` or `{ recovery: text }` opens that wrap only, enrolling, storing and sending
  nothing; DK zeroed after; `no_passkey_wrap`, `bad_recovery_key`, `wrong_recovery_key`; the
  consent page's way to an assistant's key),
  `refreshKeys(options)` (a device wrap at a higher `keyV` n, verified as `withDataKey`, adds
  every version from the current c + 1 to n to the keyring and makes n current, old versions kept;
  `tampered` keeps nothing; one below the current version changes nothing only when it is a held
  version that passes the check (an unheld one is `tampered`), and a held version is never
  overwritten), `dropKeyVersion(userId, keyV)`,
  `forgetDevice(userId)` (sign-out: `deleteVault`). The recovery secret is zeroed
  in a `finally`. A 409 `key_version_mismatch` from `/v2/keys` is `KeysError("rotated_elsewhere")`;
  `api`, `listWraps`, `putJson` and `WrapDto` are exported for `rotate.ts`.
  Passkeys: `unlockWithPasskey({ userId, credentialId, prf })` opens the passkey wrap whose `ref` is
  the credential (base64url, Better Auth's `credentialID`) and enrolls this browser
  (`KeysError("no_passkey_wrap")` when none opens); `addPasskeyWrap({ userId, credentialId, prf })`
  PUTs `kind: "passkey"`, `ref`, at the current `keyV`, DK from `withDataKey` (the touch is the
  confirmation; an existing wrap of that credential keeps its id; a credential not the account's is
  the server's 422, `KeysError("unknown_passkey")`, nothing stored). The caller zeroes the PRF.
  `prf.ts`: `prfExtension()` (`PRF_SALT`), `readPrf(clientExtensionResults)` (a copy of
  `prf.results.first` only when 32 bytes, the browser's bytes zeroed: `prf: {}` from Proton Pass /
  1Password is null),
  `evaluatePrf(credentialIds?)` (a raw `navigator.credentials.get`, random challenge, `rpId` =
  hostname, `userVerification: "required"`; nothing goes to the server; null on cancel,
  `KeysError("no_prf")`), and the one-shot stash `keepSignInPrf({ userId, credentialId, prf })` /
  `takeSignInPrf(userId)` (another account's is zeroed, null) / `clearSignInPrf` (module memory
  only, never storage; cleared by `liveSignOut`, by the `/app` and
  `/welcome` loaders of a plain account and once the vault is open). The passkey sign-in (also
  autofill, `features/sign-in/auth.ts`) and `auth/passkey.ts` `addPasskey(prf?)` ask for the
  extension with `returnWebAuthnResponse: true`; a registration that says `prf.enabled` without
  results gets one second touch (`evaluatePrf([newId])`, explained first by a toast
  `vault.passkey_second_touch`) only for an encrypted account. `PasskeyPrfUse.onNoPrf` is told
  when the new passkey itself gave no PRF (the registration without `prf.enabled`, or the second
  touch's `no_prf`), never for a cancelled or failed second touch nor a PRF whose `keep` failed
  (the phone's twin: `passkeys_settings.dart` `onNoPrf`). The passkey offer
  (`offerPrfUse`) stashes the new passkey's PRF for that user's gate, and knows the account is
  encrypted from the profile the sign-in cached (`queryKeys.me()`; no request, a reload counts as
  plain); Settings (mode `local`, `PasskeysSection` `vaultUserId`) adds the wrap
  at once. A new passkey that gives no PRF on an encrypted account (told by `onNoPrf`: Settings'
  `VaultPasskeyHooks.onNoPrf`, the offer's `PasskeyOfferApi.add` hook `onNoPrf`) is
  kept, and the screen says so at once in text that stays (`role="status"`, never a toast;
  `settings.passkeys.add_no_prf`): Settings until the next add or leaving, the offer with a
  "Continue" (`passkey_offer.continue`) instead of moving on by itself. A second touch that was
  cancelled or failed gets the usual "added" toast (its row says it does not open the data). In Settings, a PRF whose wrap could
  not be saved is kept too, with the generic `turn_on_failed` toast (never the password-manager
  line); its row's "Turn on" tries again. e2e: `addVirtualAuthenticator(page, { prf })` (default
  no PRF, as Chromium's) picks which path the offer takes.
  `rotate.ts` (two steps, like `prepareAccount`; a new key's verifier is put after its wrap, by
  `newRecoveryKey` and by `rotateKeys` with `{ fresh: true }`, never with the typed key): `rotateKeys({ userId, remove, recovery: { text }
  | { fresh: true }, passkey?: { credentialId, prf } })` → `{ recoveryKey, commit() → { keyV,
  dropped } }`: the typed key must open the current recovery wrap first (`wrong_recovery_key`,
  nothing made); then `refreshKeys`, so this browser holds every version up to the account's
  current one; DK from `withDataKey`; device wraps in `remove` (`removed`), in
  `settings.revokedDevices` (`revoked`) or whose attestation fails under the old DK
  (`attestation`) are left out and reported; a new DK at `keyV + 1` wraps the recovery secret (the
  same one, or a new one shown as `recoveryKey`), every kept device (same id/ref/label, sealed to
  its public key, fresh attestation; this browser's own with its kept public key) and the touched
  passkey (same wrap id; other passkeys lose theirs); DK, the new DK, the secret and the PRF are
  zeroed before it returns. The key link (old DK sealed under the new one, `sealKeyLink`) is made in `withDataKey` and kept in the prepared object. `commit()` POSTs `/v2/keys/rotate` with `{ keyV, wraps, link }` (retry-safe, the same link; a post that ended
  `offline` or `rotated_elsewhere` counts as ours when `GET /v2/keys` shows this browser's prepared
  wrap at the new `keyV`), keeps
  `record:<v>`/`dedupe:<v>` (a `record:<v>` already held, from a refresh or a half-done earlier try, is kept when it is the
  prepared key, checked by a canary; another key is `tampered`, nothing written) (after `migrateLegacyKeys` for a 2a vault) and meta `keyV`, and adds the removed ids to `settings.revokedDevices`
  (a local write); the caller then calls the session's `reloadKeys()`. `newRecoveryKey(options)` →
  `{ recoveryKey, commit() }`: a new secret wraps DK at the current `keyV`, PUT on commit (replaces
  the recovery wrap; retry-safe, the same id; a PUT whose answer was lost counts as saved when
  `GET /v2/keys` shows the prepared wrap, `landed()`). Also exported for Settings: `checkRecoveryKey({ userId, text })` (resolves when
  the typed key opens the current recovery wrap; `bad_` / `wrong_recovery_key`; nothing sent),
  `attested(userId, dk, wrap)` and `revokedDevices(userId)`. `relay.ts`: what `pairing.ts` and `signin.ts` share (`PairingClock`, which `pairing.ts`
  re-exports, `realClock`, `deferred<T>()`, `zeroPrivate(key)`, `sameBytes`, `key32(text, onBad)`, `problemCode(response)`
  (the problem body's `code`), `retryAfter(response)` (`retry-after` in whole seconds above 0, else undefined: no header is
  never 0)).
  `pairing.ts` (stage 1b spec section 1, both roles; injected `clock`
  `{ now, sleep }` for tests, polls every 1.5 s, both stop at `expiresAt` capped at 10 minutes from this device's start (the
  request, or the approver's lookup) → `expired` and on
  `cancel()` → `cancelled`): `startPairing(options)` → `{ id, code, qr, expiresAt, number(),
  finish(), cancel() }` (the new device: an ephemeral pair `N`, separate from the device key pair,
  posts its commitment; `qr` is `wambito://pair?id=<id>&key=<base64url N.pub>`; polling pins the
  first `approverKey` and reveals `N.pub`, then `number()` resolves; `finish()` picks up, opens
  with `openFromPairing` against the pinned key and enrolls with `enrollDevice`, the opened DK
  zeroed); `findPairing({ ...options, code } | { ...options, qr })` → `{ number(), approve(),
  cancel() }` (the approving device: pins the commitment from `?code=`, or the QR key's own
  commitment after checking it against `GET /v2/pairing/{id}`, then posts its ephemeral `A.pub`;
  `number()` after a revealed key that matches the pinned commitment (and the QR key);
  `approve()` (a plain `Error("approve before number")`, nothing sent, unless `number()` resolved
  on that object) seals DK from `withDataKey` from `A` at its `keyV`, then waits for the pickup's
  404). `PairingError` codes `expired` (404 or the clock), `tampered` (any relayed value that does
  not match a pin, a 422, a second approver), `bad_code` (a code that cannot be one or finds
  nothing, a QR not exactly that string), `offline`, `server`, `cancelled`; `session_changed` and
  `rotated_elsewhere` stay `KeysError`s. `signin.ts` (spec 2026-11-15 section 8, the browser's
  half of `/v2/signin`; signed out: plain `fetch` to `/api/v2/signin…`, `credentials:
  "same-origin"`, never `x-wambito-user`; the poll secret only in the closure, sent as
  `x-wambito-poll`): `startSignin({ remember, label, clock?, fetch? })` → `WebSignin { id, code, qr,
  expiresAt, number(), ready(), finish(), cancel() }` (`ready()`: the relay said the phone sealed, before the pickup) (an ephemeral `N`, posts `{ commitment, remember,
  label }`; `qr` is `wambito://signin?id=<id>&key=<base64url N.pub>`; polling every 1.5 s
  (`SIGNIN_POLL_MS`) from the first `number()` or `finish()` pins the first `approverKey`, reveals
  `N.pub` (409 `not_ready` looks again; `already_set` is its own lost answer), then `number()` is
  `pairingNumber(N.pub, A.pub)`; on `ready`, `finish()` picks up (the response sets the session
  cookie), opens with `openFromPairing(N.priv, { kind: "device", userId, keyV }, sealed, A.pub)`,
  runs `deleteStaleVaults(userId)`, then `enrollDevice({ userId }, dk, keyV, { ephemeral: !remember })`
  → `{ userId, keys }`; DK and `N.priv` zeroed in a `finally`; once the pickup was sent (its answer may
  set the cookie), `cancel()` no longer stops it or the enroll). A 201 whose `id` is not a UUID, `code` not 8 code characters,
  `pollSecret` not base64url or `expiresAt` not a date is `server`, `N.priv` zeroed. Stops 2 minutes (`SIGNIN_TTL_MS`) from the start on this browser's clock, never at the
  server's `expiresAt` (another clock: one behind would end every request at once). `SigninError` codes `expired` (404 or the clock), `tampered` (a
  second approver key, `ready` before the reveal, a 422, a blob that does not open), `offline`,
  `server`, `cancelled`, `too_many` (429, `retryAfterS` from `retry-after`), `suspended` (403);
  the enroll's `KeysError`s go through. `stale-vaults.ts` `deleteStaleVaults(keepUserId)`: deletes every
  `wambito-vault-*` database but the signed-in person's (all when null; `indexedDB.databases()`,
  nothing where the browser lacks it), on sign-in (`useFinishSignIn`) and on every signed-out load
  of the live guards (`GuardDeps.onSignedOut` in `auth/session.ts`): a vault outlives a session that
  ended outside the sign-out (signed-in loads sweep other users' `ephemeral` vaults,
  `local/ephemeral.ts`). `recovery-signin.ts` `signInWithRecoveryKey(text, { fetch? })` →
  `{ userId, keys }` (signed out like `signin.ts`: plain `fetch`, `credentials: "same-origin"`, no
  `x-wambito-user`): parses the typed text once (`parseRecoverySecret`, exported from `keys.ts`),
  derives `recoveryVerifier(secret)`, posts `{ lookup, auth }` base64url to
  `/api/v2/recovery/sign-in` (the response sets the session cookie), then `deleteStaleVaults(userId)`
  and `unlockWithRecovery({ userId, text })` (which also writes the verifier); the secret, `lookup`
  and `auth` zeroed in a `finally`, never logged or stored. `KeysError`s: `bad_recovery_key`
  (nothing sent), `recovery_key_invalid` (401), `account_suspended` (403), `too_many_requests` (429,
  `retryAfterS`), `offline`, `server`; a failed unlock throws its own error and the caller signs
  out.
  `vault-session.ts` (`markRecoveryKeySaved(session, now)`: one local write of
  `settings.recoveryKeySavedAt`, then a sync): a preview account's open vault, one per tab, shared by `/welcome` and
  `/app`: `openVaultSession({ profile, keys, fresh })` opens the store, runs a full sync (must
  succeed when `fresh`; a known browser opens offline), seeds an empty account (settings record
  from the server profile, currency EUR, and the suggested categories, through the local backend),
  then `start()`s the engine; it seeds only after a complete first sync with no set-aside changes
  waiting. A 409 `session_changed` fails the opening (`VaultOpenError`, even for a known browser)
  or, later, closes the session and calls `onSessionChanged`. The engine's `refreshKeys` is
  `keys.ts` `refreshKeys` over the session's network; `device_removed` fails the opening
  (`VaultOpenError("device_removed")`) or, later, stops the sync, deletes the vault and calls
  `session.onRemoved(cb)` listeners (`VaultGate` routes them to `gate.removed()`: Unlock with the
  notice `vault.removed`). A device wrap stays linked to the session that first PUT it, and a
  removal ends only that session: with `sessionId` (`VaultGate`: Better Auth's `get-session` id) a
  kept vault opening under a session not yet in meta `boundSession` runs `keys.ts` `bindDeviceWrap`
  first (`GET /v2/keys`; its own wrap, by meta `deviceWrapId`, PUT back unchanged so the server
  links it to this session; missing = `VaultOpenError("device_removed")` and the vault goes). A
  fresh open only records the id; offline or any failure is silent and retried at the next open.
  `key_unverified` (a new key version whose links do
  not lead back to the held key) fails the opening (`VaultOpenError("key_unverified")`) or, later,
  stops the sync, closes the session and calls `session.onUnverified(cb)` listeners; the vault and
  its outbox are kept (never `forgetDevice`). `VaultGate` routes them to `gate.unverified()`
  (the opening's error the same way): Unlock with the notice `vault.unverified`.
  The unlock there (recovery key, passkey, pairing) keeps the vault, replaces the device wrap and
  opens a new session fresh, whose first sync pushes what waited; a recovery key or passkey
  unlocks it even when the links do not reach the held key (a version made before links). `session.reloadKeys()`
  gives the engine the keyring the vault now holds (`engine.useKeyring`, only a higher or equal
  `current`) and runs a sync; called after a rotation commits. Its `fetch` is the local backend plus `DELETE /v1/me` and `/v1/me/assistants*`
  (list, revoke) sent to the API; `LOCAL_UNAVAILABLE` (export, imports) answers 403. `forgetVault()` stops the
  sync, closes the store and deletes the vault (sign-out via `liveSignOut`, and a 401 from sync).
  `forgetOwnDeviceWrap()` runs first in `liveSignOut`: `DELETE /v2/keys/{meta deviceWrapId}` (best effort, 3 s, never rejects)
  so Settings > Devices keeps no row for a signed-out browser.
  If the store closes under it (another tab), the session stops its sync, drops itself and calls
  `onClosed`; the gate then checks again (`gate.closed()`: reopen with kept keys, else Unlock).
  The local backend also serves `POST /v1/transactions/review` (all or nothing, 404 on an unknown
  or deleted id; no merchant memory). The server refuses a preview account's `/v1` finance routes
  (426 `update_required`, `errors.update_required`: reload): only `GET`/`PATCH /v1/me` (locale on sign-in), `DELETE /v1/me` and the
  assistants go live.
  Any 426 is `ApiProblem("update_required")` whatever its body (`api/errors.ts`
  `problemFromResponse`).
  Switch day (E2E stage 5, spec `docs/superpowers/specs/2026-11-19-e2e-stage-5-switch-design.md`
  section 3): `auth/encryption.ts` `accountGate(onMe?)` → `{ vault, migration }` from `GET /v1/me`
  (`migrationOf(me)`: `available` | `in_progress` | null). A profile with `migration` (a migrating
  account answers `preview` too) is the flow's, never `VaultGate`'s: `/app` (no `requireOnboarded`)
  and `/welcome` (even onboarded) render `features/migration/MigrationScreen.tsx` `MigrationGate`;
  `/oauth/consent` sends `in_progress` to `/app` (an assistant connected then is revoked by
  `finish`), `available` consents as plain. `previewProfile()` is `accountGate().vault`. The flow:
  `migration-flow.ts` `createMigrationFlow(deps)` (pure, unit-tested with a fake world of reloads;
  states `checking`, `intro`, `keys {recoveryKey, busy}` (the `RecoveryKeySetup` screen), `unlock`
  (the account already has keys: `Unlock` with `migration.unlock_lead`), `copying {done, total}`,
  `finishing`, `done`, `failed {problem: count_mismatch | offline | server | taken_over, retrying}`,
  `noLocalVault {busy}`): intro → `start` → keys (`prepareAccount({ guest: false })`, skipped when
  `loadLocalKeys` finds keys; `already_set_up` → unlock) → commit → `resetAll`, `source`
  (`recordsFromSource`; the settings record gets `recoveryKeySavedAt` = when the key was confirmed)
  → `write` → `sync` → `finish(countsOf(records))` → done, whose "Continue" reloads (the gate then
  opens the kept keys; `seedIfEmpty` is a no-op). Resume: vault meta `migrationStep` (`keys` before
  the key is made, `copying` once kept, `finishing` once the outbox is empty; deleted at done) and
  `migrationKeySavedAt`; an `in_progress` load with keys here runs `start` (takes the move over for
  this tab), then at `finishing` source, sync, finish, else cancel, `resetAll`, from `start`; no keys
  but step `keys`: `start` and a new key (nothing was committed); else `noLocalVault`, whose
  "Start again here" runs start, cancel, resetAll, start. A retry: a failed commit commits the same
  keys; anything else cancel, resetAll, from `start` (`taken_over`: `start` first, "Continue here").
  `resetAll` runs only after a cancel that went through (204): a cancel answered `not_migrating` or
  a `start` answered `not_migratable` (a finish whose answer was lost, another tab of this browser
  that finished) re-reads `GET /v1/me` (`accountState`): encrypted reloads into the vault, anything
  else is the `server` failure, whose retry reloads.
  `session_changed` reloads. Live deps `local/migration.ts` `liveMigrationDeps({ userId, migration })`:
  `/v2/migration/*` with `x-wambito-user` (`MigrationError` codes `count_mismatch`,
  `migration_in_progress`, `session_changed`, `not_migrating`, `not_migratable`, `offline`, else
  `server`; its `reload` closes its store connection first), `write` = one store transaction (`put` all, then `delete` the deleted
  ones: tombstones with body), `sync` = its own `createSyncEngine` run until `readOutbox(1)` is
  empty (progress from each push's results; a 409 `migration_in_progress` push is `taken_over`; a
  run that leaves entries parked fails, never loops). It never opens the vault session nor the local
  backend (`seedIfEmpty` would add starter categories, `materialize` recurring payments); the source
  and sync bodies are never logged. Stories `Migration/Screen`, copy `migration.*` (+ `errors.*` for
  the migration codes).
  Preview switch: `auth/encryption.ts` `previewProfile()` reads `GET /v1/me` `encryption` in the
  `/app` and `/welcome` loaders; for `preview` they render `features/vault/VaultGate.tsx`
  (its live deps in `gateFor`, wiring-tested in `VaultGate.test.ts` with mocked modules; state
  machine `vault-gate.ts`, unit-tested with fakes: checking → setup | unlock | open →
  ready; a setup committed in this browser goes through `install` first (`InstallApp`: Wambi, the
  Android APK and release links, a store button only for a non-null `PLAY_HREF`/`FDROID_HREF`/`APP_STORE_HREF`
  in `landing/links.ts` `STORE_LINKS`; `gate.installDone()` opens the vault; never after an unlock, a
  pairing or a known browser; story `Vault/Install app`, copy `vault.install.*`), else `Locked` with a retry of the failed step; an account with keys elsewhere first tries
  the stashed sign-in PRF (`takeSignInPrf`), and a passkey that opens nothing (stashed, or touched
  from Unlock's passkey button, `gate.unlockWithPasskey()`, which offers only the account's
  passkeys from Better Auth's list (`auth/passkey.ts` `accountPasskeyIds`), none: `no_passkey_wrap`
  without a touch) gets its wrap once the vault is
  unlocked by the recovery key or set up; a known browser zeroes the stash; Unlock's "From another
  device" enters `pairing` (`gate.pair()`;
  `gate.startPairing()` makes the request, again for "Start again", cancelling the previous one;
  the latest call wins: an older one answering later cancels its own request;
  its `finish()` opens the vault like a recovery unlock: pending passkey wrap, full sync; a failed
  pairing stays on its screen; `gate.leavePairing()` cancels and goes back to Unlock, with the
  gate's last known means: a `no_prf` touch there sets `noPrfHere`, a passkey that opens the data
  clears it); `gate.removed()` / `gate.unverified()` show Unlock at once with the last known means
  and refine them once read (a read that comes back after another change of state changes
  nothing);
  before making or unlocking keys, when the
  open vault closes, and on `session_changed` (`gate.sessionChanged()`), it reads who is signed in
  (live `GET /v1/me`) and, when it is another account or none, reloads the app at `/app`, so
  nothing runs for the old id; Locked kinds `error`, `offline`,
  `unsupported` (no X25519: no retry). There is no guest branch: an account made by the phone (no
  email, `isAnonymous`) whose keys are elsewhere gets Unlock like any encrypted account (recovery
  key, passkey, "From another device"); only `prepareAccount({ guest })` still hides its first
  recovery key; a 401 from `/v2/keys` signs in again) and then `<ApiProvider mode="local">`;
  the onboarding flag is the vault's (`LocalOnboardingRoute`), not the server's. `ApiMode` is
  `live | demo | local`: demo-only behaviour checks `=== "demo"`, live-only `=== "live"`
  (import); settings shows `settings.local_off` under import and export in `local` (the
  assistants list and revoke there; only the demo leaves the list out); the welcome skips its import step there. Screens in
  `app/features/vault/`: `RecoveryKeySetup` (key in groups of four, copy, `.txt`, then type four
  characters back, each named "group N, character M"; `onCancel` instead of `onSignOut` in Settings,
  `busy` and `problem` for Settings' commit), `Unlock` (`notice: "removed" | "unverified"` shows `vault.removed` / `vault.unverified`; `onUnlock(text) → UnlockError |
  null`, `onPasskey() → UnlockError | null` with the `no_prf` / `no_passkey_wrap` copy; no passkey
  where `passkeysSupported()` is false or without `onPasskey`; `onPair` "From another device";
  `title`, `lead` (null: none; by default `lead` when the key leads, else `lead_other`) and
  `exitLabel` for the consent page's unlock step). Its layout (spec 2026-11-20 section 1) comes
  from `unlock-layout.ts` `unlockLayout({ noPrfHere, passkeyWrap, passkeysSupported, canPair })`
  over `means` (`UnlockMeans`, default `{ noPrfHere: false, passkeyWrap: true }`; the gate's
  unlock state carries it, read by `readMeans()`: `local/unlock-hint.ts` `passkeyGaveNoPrf(userId)`,
  a `wambito.unlock.no-prf.<userId>` boolean set by a passkey touch here without PRF (sign-in
  `keepPrfOf`, unlock and the consent page, only when the touch was limited to the account's
  passkeys) and cleared when a passkey's PRF opens the data, kept by sign-out, removed
  with the account; and `keys.ts` `hasPasskeyWrap`, true when the wraps cannot be read, a 401
  included: never wrapped in `signInAgainOn401`, since a removal ends the session and its notice
  must show): the
  recovery key first with the line `vault.unlock.no_prf_line` (no PRF here; "Use another passkey"
  under "More options" when a passkey could work), "Open with my passkey" first (a passkey wrap and
  passkeys here), or "From another device" first; the pairing below a first passkey or key; the
  rest under "More options" (`vault.unlock.more`, a ghost button with `aria-expanded`, closed by
  default, opening by itself when the passkey above it answers `no_prf` or `no_passkey_wrap`); with
  nothing else (the consent page without a wrap, the migration) the field leads alone. No passkey
  prompt without a tap. The field is `RecoveryKeyField` (`recovery-key-input.ts`
  `groupRecoveryKey`, `isFullRecoveryKey`: groups of four while typing, any pasted shape, a
  "Paste" button where the clipboard can be read); the submit waits for a full key. The consent
  route reads the same `means` in its loader (`ConsentKeys.means`, only without a vault here);
  its keys come from `features/assistants/consent-keys.ts` `consentKeysOf` (the touch offers only
  the account's passkeys and notes or clears the hint as the gate does; unit-tested with fakes).
  Stories `Vault/Unlock` (`KeyFirst`, `PasskeyFirst`, `PairFirst`, `PasskeyFails`,
  `ConsentNoPairing`, …)), `Locked` (retry or sign-out only); all three have `onSignOut` (the gate passes `useSignOut`,
  which wipes the vault); `PairNewDevice` (`start() → request`, `onBack`, `timeZone` (the profile's, for the expiry): the QR as `uqr`
  `renderSVG` in an `<img>` data URL, alt = the code, the code as `ABCD EFGH`, the expiry, the
  number once `number()` resolves, done after `finish()`; expired / offline / server offer "Start
  again", tampered only back; `cancelled` shows nothing); `ApproveDevice` (`keys: PairingOptions`,
  injected `findPairing` and `scanSupported`, `onDone`; Task 8 mounts it in Settings → Security:
  type the code, or scan where `BarcodeDetector` exists (a `getUserMedia` video, stopped on a
  `wambito://pair?` hit, on cancel and on unmount), then the number with "They match" (only once
  shown; disabled while `approve()` runs) and "They do not match" (cancels: nothing shared));
  `vault-context.ts` `VaultSessionContext` / `useVaultSession()`: the gate provides the open
  session beside `<ApiProvider mode="local">` (null elsewhere), so Settings reaches its keys.
  Settings → Security (`features/settings/`, mode `local`; every encrypted account gets the
  whole section, an anonymous one too):
  `security.ts` `SecurityApi` (`load()` → wraps, `ownId`, `revoked`, `verified` (attestations under
  DK from `withDataKey`), `unreadable` (`quarantineCount()`); `rotate`, `checkRecoveryKey`,
  `newRecoveryKey`, `reloadKeys`, `evaluatePrf`, `addPasskeyWrap`, `settings()` (the settings
  record's `recoveryKeySavedAt`), `markRecoveryKeySaved()`, `pairing`), `liveSecurity(session)`
  the default, `Settings`' `security` prop (and `HomeStage`'s) for stories; react-query key
  `SECURITY_KEY`; `security-model.ts` (`deviceRows`: this browser marked and never removable,
  revoked ids left out, "Not verified" when the attestation fails; `passkeyRows`: joined to passkey
  wraps by credential id, `PasskeyItem.credentialId`); `SecuritySection.tsx` (devices, "Approve a new
  device" (`ApproveDevice` in a full-screen `Takeover`), "New recovery key" (the current key typed
  or a passkey touch, `no_prf` counts and a cancel does not; with no passkeys (list ready and
  empty) also "Lost it? Make a new one without it", the type-back confirming it; with passkeys
  this browser cannot touch, only the typed key, and the copy says why; then `RecoveryKeySetup`,
  `commit()` after the four characters), "Could not read N items" only when N > 0). A failed
  commit of a new recovery key may have
  been saved: the setup stays with the same key, says `settings.security.maybe_saved`, hides
  Cancel, and Continue retries the same `commit()`; only `rotated_elsewhere` goes back, reloading
  the keys and invalidating `SECURITY_KEY`; "New recovery key" waits for the passkey list
  (`PasskeyList`: disabled while loading, hidden with a retry when it failed; with passkeys but no
  WebAuthn here, only the typed key); `RemoveDeviceSheet.tsx` is confirm-only: one tap calls
  `SecurityApi.removeDevice(id)` (`DELETE /v2/keys/{id}`: the wrap goes and that device's session
  ends; no rotation, no recovery key, the keys do not change; a 404 counts as done; offline shows
  `vault.unlock.error_offline` and keeps the row, any other failure `remove_sheet.failed`), then
  `SecuritySection` toasts `removed_done` and invalidates `SECURITY_KEY` (the sheet's file also
  keeps the shared `Takeover`, `RecoveryKeyField`, `PasskeyList`, `keyErrorOf` and `problemOf`); the
  web's "Change keys" (`ChangeKeysSheet`) still rotates; a
  `Takeover` makes the rest of the page `inert`); `PasskeysSection` with
  `security` shows "Opens your data" / "Does not open your data" and "Turn on" (`evaluatePrf([id])`
  then `addPasskeyWrap`; `no_prf` names the recovery key and another device). Stories
  `Settings/Security`, web-only, not in parity.json; copy under `settings.security.*`.
  "Protect your data" (spec 2026-11-15 section 5.2; `ProtectSection.tsx`, above the passkeys,
  only for a `local` account whose profile `isAnonymous`): `protect-model.ts` `protectStatus({
  anonymous, recoveryKeySavedAt, passkeyWrap, passkeyWithoutWrap, passkeysSupported })` (null with
  an email; "N of 2" (`show`) until step 1 or 2 is done (`protected`), then a quiet list with
  "Done"). Step 1 "Save a recovery key" asks nothing (web ruling 16): `newRecoveryKey()`,
  `RecoveryKeySetup`, `commit()` (a failed commit keeps the setup, as in Security), then
  `markRecoveryKeySaved()` and `protectSettingsKey(userId)` (`security.ts`, per user) refetched. Step 2 (only where
  `passkeys.supported()`): `PasskeysApi.add({ userId, explainSecondTouch, keep })`, `keep` =
  `SecurityApi.addPasskeyWrap`; done only when a passkey wrap exists, never the passkey row; a
  passkey without one shows `settings.protect.no_prf`, or `settings.protect.link_failed` when its
  PRF came but the wrap could not be saved (`keep` threw; `addPasskey` swallows it). Step 3 "Create account (add an email)":
  opens `AddEmail` in a `Takeover` from `Settings` (its `onAddEmail` prop, and `HomeStage`'s,
  replaces the opening for stories). `add-email.ts` `claimEmail(api)` → `{ send(email), verify(email,
  code) }` over `/v1/me/claim-email/send|verify`, rejecting with `ClaimError.key` (sign-in's
  `errors.*` keys; 409 `email_taken` is `settings.add_email.taken`: the web never merges, it says
  to bring the data in from the phone, ruling 5). `AddEmail({ claim, onDone, onCancel? })`: email,
  then sign-in's `CodeInput`, then `queryKeys.me()` invalidated (the profile shows the email, the
  Protect block goes; the user id and keys do not change). With `security` and no
  `recoveryKeySavedAt`, the key setup follows the email with no way out (spec 7.1), sharing step 1's
  `recovery-key-step.ts` `useRecoveryKeyStep(security, onSaved)` with `ProtectSection`). `HomeStage` `claim: "ok" | "taken"`
  fakes the routes (code 123456). Stories `Settings/Protect` and `Settings/Add email`, web-only,
  not in parity.json; copy under `settings.protect.*` and `settings.add_email.*`.
  `uqr` is in `vitest.config.ts` `optimizeDeps.include` like every dependency a story imports; pure UI,
  callbacks as props; stories `Vault/*`, web-only, not in parity.json; copy under `vault.*`. A
  recurrence's occurrences have ids `uuidv5(ruleId, "<month>:<rev>")`; editing or archiving a rule
  bumps its `rev`.
  Known limit of `app/local/` (spec 2026-11-10 section 2.4): a malicious server together with a
  stolen device that still holds DK(v-1) can forge a version whose link leads back to it, for a
  browser that has not seen the real one yet. A server that withholds a link (or a whole rotation)
  leaves browsers stuck in the `unverified` state until a passkey or the recovery key unlocks
  them (pairing stays strict): denial of service only, nothing is revealed.
  `app/feedback/` sounds, vibration, `Celebration`; `app/theme/`; `app/site/` origins/build env;
  `app/admin/` the admin panel (`/admin/*`, layout `routes/admin.tsx`): `useAdmin`/`adminFetch`
  (a 401 `admin_verification_required` waits for the passkey, then retries), `AdminGate` (the layout's gate), `VerifyScreen`, `HomeScreen` (metrics, `ActivityBlocks`: daily actives, cohorts, installs, versions; audit, look-up; the cards say "Without email"),
  `AccountScreen` + `ActionSheet` (`/admin/users/:id`: the account and its actions; a sheet's
  fields live in the component, so a reason survives re-verification). Stories `Admin/*`,
  web-only, not in parity.json.
- `/automatic-capture` (+ `/en|it|pt/automatic-capture`; `routes.ts`, prerendered like the privacy
  pages; paths in `app/site/paths.ts`: `AUTOMATIC_CAPTURE_PATH`, SitePage `automaticCapture`): how
  automatic capture works. `app/features/capture/`: `CaptureSteps.tsx` (`CAPTURE_STEPS`,
  `CaptureStepView`, `CaptureSteps`), `CaptureDemos.tsx` (`MainPicture` with `income`,
  `ChipsDemo`, `NoticeDemo`, `LearnDemo`), `CapturePage.tsx`, `capture.css`; scenes
  `public/wambi/capture-step1..5.webp`. The landing leads with it in `#capture`, right under the
  hero (`features/landing/AutomaticCapture.tsx`); then come the feature grid `#how`
  (`HowItWorks.tsx`) and the agent demo `#agent` (`AgentDemo.tsx`, a chat that plays once in view
  and prerenders its final state). Copy under `landing.capture.*`; `messages.test.ts` forbids
  naming a language in it. `Capture/Step` and `Capture/MainPicture` (night) are parity stories in
  `apps/mobile/test/parity/parity.json`; `Capture/Steps` is web-only (the Flutter twin is
  `apps/mobile/lib/capture_auto/`).
- The QR sign-in (`features/sign-in/`, web plan rulings 8–10): `signin-model.ts`
  `createQrSignin({ start, label, clock, visible(), onVisibility(cb) })` → `{ state(), subscribe,
  setRemember, remember(), retry(), stop() }`, pure and unit-tested with a fake `startSignin`,
  clock and page. `QrState`: `opening` → `showing` (QR, no phone yet) → `approved` (`number()`
  resolved: never replaced, runs to its end) → `finishing` (`ready()`) → `done { userId }`; `failed
  { code, retryAt? }`; `paused` (hidden page whose request ran out). One request at a time, every
  dropped one `cancel()`ed. A `showing` request is replaced at its end on this browser's clock (`SIGNIN_TTL_MS` from its opening, never the server's `expiresAt`: a fast client clock would renew in a loop) while visible; hidden,
  it stops there and opens one new request when visible again (also when a throttled timer is
  late: an expired QR is never shown). `remember()` starts true; `setRemember` cancels the shown QR
  at once and opens a new one after `REMEMBER_DELAY_MS` (500 ms) without another change (`paused` if hidden by then); ignored
  from `approved` on. `too_many` retries by itself at `retryAt` (`retry-after`, else 60 s);
  `expired` renews by itself when visible; other codes (a non-`SigninError`, such as the enroll's
  `KeysError`, is `server`) wait for `retry()`. `stop()`: cancel, no more requests. `QrSignIn.tsx`
  `QrSignIn({ model, onSignedIn, timeZone })`: a `<section>` (no screen frame; the page places it)
  with the QR (`uqr` `renderSVG` in an `<img>`, alt = the code), the code `ABCD EFGH`, the box
  "Keep me signed in on this browser" (disabled from `approved`; unticked adds the "Nothing stays"
  line), the quiet number line (ruling 8), "Opening your data…", the failures with "Try again"
  (none for `too_many`, which shows the retry time in `timeZone`, nor `suspended`); `onSignedIn`
  once on `done` (the page navigates and handles a failed finish). Stories `Sign-in/QR`, web-only,
  not in parity.json; copy under `sign_in.qr.*`.
- `/sign-in` and `/create-account` (`routes/sign-in.tsx`, `routes/create-account.tsx`, both under
  the app layout with `redirectIfSignedIn`; web plan rulings 1, 3, 12–14): `SignIn({ auth, mode =
  "sign-in" | "create", qr? })` (`qr`: a `QrFactory(page) → QrSignin`, `liveQrFactory(auth)` by
  default, faked in stories). `sign-in` (in every build, no flag): the screen's own width decides
  (`WIDE_PX` 768, measured on the screen root, starting from `document.documentElement.clientWidth` so a computer's first render is already wide: moving the email field later ends Chrome's passkey autofill request): wide puts the QR panel first and "Other ways to sign
  in" beside it (fingerprint button, the email form, "More options" with the recovery key), narrow puts the other ways
  first and the QR under "Signing in on a computer? Scan it with your phone"; both are keyed, so the
  model survives a change of layout. `QrArea` makes the model only once the panel is on screen
  (`IntersectionObserver`), and its `visible()` is "tab shown and panel on screen", so an off-screen
  QR is not renewed; it is stopped only on unmount, and while it is `finishing`/`done` the other
  ways (and leaving the email step) wait. `RecoveryKeySignIn` ("More options", `vault.unlock.more`: a
  ghost button with `aria-expanded`, closed by default, that shows the recovery-key field directly; copy `sign_in.recovery.*`, errors from `vault.unlock.error_*` and
  `errors.recovery_key_invalid` / `account_suspended`; a 429 waits out `retryAfterS`). `create`:
  the email code form under "Create your account" (`sign_in.create.*`) with "Already have an
  account? Sign in" (`/sign-in` with the same query); no QR, recovery or fingerprint button.
  `auth.ts`: `SignInAuth.signInWithRecoveryKey(text) → RecoveryResult` (`{ userId }` or `{ error,
  retryAfterS? }`) and `startQrSignin` (= `startSignin`), both from `createSessionSafeAuth`, which
  watches the `fetch` for the 200 that sets the cookie (`/v2/recovery/sign-in`, the pickup) and,
  when the unlock or the enroll fails after it, signs out (`liveSignOut`, then
  `deleteStaleVaults(null)`) before the error reaches the screen: never a session without keys.
  `useFinishSignIn({ method: "email" | "passkey" | "qr" | "recovery" })`: only `email` may offer a
  passkey (`offersPasskey(method, destination)` in `auth.ts`); a QR or recovery sign-in passes only
  the user id. `local/ephemeral.ts` `wipeForeignEphemeralVaults(signedInUserId)`: deletes every
  vault whose meta `ephemeral` is true but the signed-in user's (all when null), opening each
  database without a version (never upgrading it); never throws. It runs on every signed-in load of
  the live guards (`GuardDeps.onSignedIn` in `auth/session.ts`), not in a layout loader: a loader on
  `app-layout.tsx` would replace every child's `HydrateFallback` and add a session request. Stories
  in `Sign-in/SignIn`: `Phone first`, `Recovery key`, `Recovery key signs in`, `Create account`,
  `Phone` (web-only; the parity stories there now show the recovery button and the QR below the
  email form on a phone).
- `/oauth/consent` (`routes/oauth.consent.tsx`, `features/assistants/Consent.tsx`,
  `consent-api.ts`, `consent-model.ts`, `consent-keys.ts`): an assistant asks to connect. A plain account posts the
  consent. An encrypted one (`accountGate().vault` in the loader; `device` when `loadLocalKeys` finds
  its vault here) shows `consent.encrypted_note`, and "Allow" takes DK through `withDataKeyFrom`:
  this browser's device wrap with no touch, else the unlock step (`ConsentUnlock`: a passkey's PRF
  or the recovery key, nothing kept); `allowAssistant` then makes `S` and the `assistant` wrap,
  posts the consent with `wk`, PUTs the wrap (`x-wambito-user` named), zeroes `S`. A refused PUT
  shows `ConsentWrapFailed`; "Try again" revokes the consent first and gives a new `S` (the API gives
  a fresh code for the same signed query: `apps/mcp/test/vault-end-to-end.test.ts`). The whole
  chain, API to tools, runs in that test; stage 4 design `docs/superpowers/specs/2026-11-16-e2e-stage-4-mcp-design.md`.
- `/confirm-email?token=…` (`routes/confirm-email.tsx`, `features/confirm-email/`, under the app
  layout, public): the page of an admin-started email change. It posts the token only when the
  person taps the button (a mail scanner opening the link spends nothing), then sends them to
  sign-in (every session was closed). Copy in `confirm_email.*` in all four languages; story
  `ConfirmEmail`, web-only, not in parity.json.
- Daily seen call: `app/auth/seen.ts` `markSeenToday(userId, timeZone)`, called unawaited from the `/app`
  loader (`accountGate(onMe)`, every account), once per local day (`wambito.seen.<userId>`), stored
  after a 204; `x-wambito-version` = `BUILD_ID` (`VITE_BUILD_ID`, set by `deploy/personal/up.sh`, else
  `dev`).
- Storage: only `readStored/writeStored/removeStored` in `app/lib/stored.ts` (keys
  `wambito.<name>`, `sessionArea()` for session data).
  Exception: `app/local/` talks to IndexedDB directly (`db.ts`), because the vault needs
  transactions and CryptoKeys; nothing else in the app touches IndexedDB.
- i18n: `app/i18n/messages/{es,en,it,pt}.json` public pages, `app.{es,en,it,pt}.json` the rest.
  `messages.test.ts` enforces parity, ICU, PT-PT, no slang in it/pt, no old names. The admin
  panel: `admin.{es,en}.json` only (namespace `admin`, `AdminMessages`; it/pt read en); codes only
  `/v1/admin/*` answers are `ADMIN_ONLY_CODES` there, with text in `admin.errors.*`.

## Talks to

- API at `/api` on the same origin (Vite proxies it in dev). Types: `app/api/schema.d.ts`
  (generated; commands for it and `tokens.css`: root `AGENTS.md`).

## Commands (repo root)

- Dev: `pnpm --filter @wambito/web dev` (needs the root stack: `docker compose up -d`).
- Unit + Storybook tests: `pnpm vitest run apps/web`; one project
  `--project "@wambito/web (unit)"` or `"@wambito/web (storybook)"` (Chromium).
- Storybook: `pnpm --filter @wambito/web storybook` (:6006). OG images: `pnpm --filter @wambito/web og`.
- The landing's phone screen ("See where it goes" in `#how`): `pnpm --filter @wambito/web
  landing-screens` (`scripts/landing-screens.ts`, needs the dev server; `--url` for another origin)
  shoots `/demo/insights` per language and theme into `public/landing/insights-*.webp` (the screen
  without the donut's ring) and `donut-*.webp` (the ring alone, which CSS sweeps in over it), and
  writes the ring's place to `app/features/landing/app-screen.gen.ts`. Generated: never edit them.
- e2e: `E2E_NOW=2026-10-21T15:00:00Z NEW_USERS_ENCRYPTED=true docker compose up -d --build`
  (the clock from `e2e/helpers.ts`; every new user born encrypted, as CI runs it), then `pnpm --filter @wambito/web e2e` | `e2e:landing` | `e2e:landing-only` |
  `e2e:landing-only-app` | `e2e:landing-analytics`. Afterwards `docker compose stop` (never `down -v`).
- `e2e:landing-analytics` (`e2e/landing-analytics.spec.ts`, no stack needed): a landing-only build
  with `VITE_POSTHOG_KEY=phc_e2e` and the fake host `posthog.example.test`, the real posthog-js,
  every PostHog request answered by the test. posthog-js drops events from an automated browser,
  so the spec hides `navigator.webdriver`; it proves a negative with `settle()` (the fake clock runs
  the batch timers, then a sentinel round trip), never `networkidle` after a client-side move. The
  posthog-js chunk is `module-*.js` (found by its content, not its name).
- e2e accounts seeded in the API container: `docker compose exec -T api pnpm --filter @wambito/api
  seed:admin` (`dev-admin`, admin spec), `seed:e2e-plain-user <email> [lang]` (a plain user,
  not onboarded, with the starter data; `signUpNewUser` runs it through `seedPlainUser` before
  its email sign-in, so the plain-app specs test the plain app and need `docker` on the PATH; `encrypted-sign-up.spec.ts` covers
  the born-encrypted web sign-up) and `seed:e2e-preview` (`preview-e2e`,
  preview@wambito.test, the encrypted-preview account; `E2E_PREVIEW_USER_IDS` defaults to it in
  `docker-compose.yml`). `vault.spec.ts` runs `seed:e2e-preview` itself in `beforeAll`, which
  deletes and recreates the user (no records, key wraps or finance rows), so it needs the stack up
  and `docker` on the PATH; it runs on the desktop project only (one shared account; the file is skipped on the phone and
  its `beforeAll` returns there). CI seeds it
  too. `seed:e2e-migrate` (`migrate-e2e`, migrate@wambito.test, `plain`, onboarded, in COP; the
  compose's `MIGRATION_OPEN_USER_IDS` default opens the migration to it) deletes and recreates the
  user with every kind of row (an archived category with transactions, budget months, a yearly
  and a monthly recurrence with a dismissed month, a deleted transaction, a capture and its
  merchant rule). `migration.spec.ts` (serial, desktop only) runs it before each test through
  `seedMigrateUser()`, migrates through the flow, compares the plain API's answers with the
  vault's (`vaultFetch`: the tab's open session, from `/app/local/vault-session.ts`, the module
  the app loaded from the dev server) and checks the database with `psql(sql)` (`helpers.ts`,
  `docker compose exec -T postgres psql`): no row of the account left in the eight plaintext tables.
- `e2e/signin.spec.ts` (serial, desktop only): the QR sign-in the phone approves, the recovery-key
  sign-in and the unticked box (no cookie expiry, no `wambito-vault-*` once the cookie is gone).
  Node plays the phone: `e2e/phone.ts` `approveSignin({ request, userId, code, recoveryKey })`
  (the real `@wambito/crypto` over the API, with the session of the browser where the account was
  born). Its account is a fresh web sign-up (born encrypted with `NEW_USERS_ENCRYPTED=true`), not
  `preview-e2e`, so it never meets `vault.spec.ts`'s reseeds.
- e2e trap: `pinClock`'s clock keeps running across a page load, while a new page's animation
  clock starts at zero, so a sheet (Motion) stays off-screen after a `goto` in a long-lived
  context for as long as the context had lived; long tests move with in-app links instead.

## Landing builds

- Normal `build/` (landing + app). `VITE_LANDING_ONLY=true` via `scripts/build-landing.ts`
  (`build:landing`): landing + 404 for the Worker. `VITE_APP_URL` points the CTA at the app origin;
  `VITE_SITE_URL` sets canonical/sitemap (default `https://wambito.test`). The VPS builds with
  `WAMBITO_BUILD_DIR=build-personal`.
- The landing's doors (`features/landing/links.ts`): `appLinkProps(locale, door, landingOnly?,
  appOrigin?)` with `door` `"create"` (`/create-account?lang=`: the hero's and the closing's
  primary "Crear cuenta" / "Create account" and the agent's "connect" button) or `"sign-in"`
  (`/sign-in?lang=`: the header's "Entrar"); "Demo" stays beside the hero's primary. The same in
  every build. Landing-only: `VITE_APP_URL` prefixes the origin; without it both lead to GitHub
  (coming soon, labels `cta_soon` / `sign_in_soon`). Labels: `landing.hero.cta`, `landing.nav.sign_in`.

- Landing analytics (`app/features/analytics/`, PostHog, only with consent): `consent.ts` is the
  consent model (stored choice, withdrawal); `config.ts` `SITE_ANALYTICS_CONFIG` reads
  `VITE_POSTHOG_KEY` / `VITE_POSTHOG_HOST` (build time); `posthog.ts` loads posthog-js with a
  dynamic import only after consent (`startAnalytics` / `stopAnalytics`); `use-analytics-consent.ts`
  is the hook; `ConsentBanner` is mounted from the public `Footer` (with the preferences link).
  Keyless build (no `VITE_POSTHOG_KEY`) means off: no banner, no request, the old privacy policy.
  Only the landing-only build honours the key (`siteAnalyticsConfig`), so `pnpm dev` and the VPS
  full build never load PostHog. The hook calls `stopAnalytics` on every refusal and on mount
  when the choice is not `granted` (safe when nothing started: it only clears `ph_*` storage).
  While the banner is open it sets `--lk-consent-h` on `<html>` so the footer can scroll clear
  of it. Go-live: `docs/deploy/landing.md`.

## Traps

- Money slang (see root `AGENTS.md`) is in the Spanish copy.
  `app/features/landing/money-words.ts` / `MoneyHeadline.tsx` hold money words per language: edit
  with care.
- The landing header must fit one row at 320px in every language (e2e checks it).
- The landing's copy is repeated outside the page: `landing.meta` (title and description, the
  `<title>` and the share text, `features/landing/seo.ts`), and the share images
  `public/og-{es,en,it,pt}.png`, drawn by `scripts/og/og.html` from `landing.hero.headline` and
  `landing.hero.description`. When the hero or what the landing promises changes, rewrite
  `landing.meta` in all four languages and run `pnpm --filter @wambito/web og` (it fails on a
  key the template reads that is gone); look at the four images before committing.
- Landing HTML must not link files named after the mascot module (hence `mascot-*`).
- Storybook story titles are the parity ids in `apps/mobile/test/parity/parity.json`.
- Built e2e suites run without JavaScript by default; the dev e2e fails in global-setup without
  the pinned `E2E_NOW` in the API.
