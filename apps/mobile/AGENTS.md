# apps/mobile: the phone app (Flutter, Dart package `wambito`)

Android and iOS, both `com.wambito.app`. No Play Services or Firebase (`scripts/check-no-google.sh`);
deps pinned, free-licensed (`scripts/check-licenses.sh`). Setup, emulator, JDK 17:
`docs/mobile/setup.md`. Release and signing: `docs/mobile/release.md`; iOS: `docs/mobile/ios.md`.
iOS is the base only (see "iOS" below): no automatic capture, widgets or voice yet.

## Dart entry points (`lib/`)

- `lib/main.dart` `bootstrap()`: `DeviceHints.read()`,
  settings, then `WambitoApp` (`lib/app.dart`). Router: `lib/router.dart` (go_router).
- One folder per feature (`lib/home/`, `lib/capture/`, `lib/budgets/`, …); Riverpod 3 providers
  sit next to their feature; tests override them.
- Interface icons: `LkIcon` (`lib/ui/lk_icons.dart`) draws `lib/ui/lk_icon_shapes.dart`, a copy of
  `docs/design/system/project/icons/icons.json` that `test/ui/lk_icon_test.dart` keeps equal to it;
  tests find them with `findIcon` (`test/support/icons.dart`). Emoji only for categories.
- `lib/capture_auto/`: Settings → "Captura automática" (switch per source, notification-access
  state, restricted-settings steps). "¿Cómo funciona?" (`how_capture_works.dart`, demos in
  `capture_demos.dart`, twin of `apps/web/app/features/capture/`): five steps in an `LkSheet`
  `PageView`, shown on the first switch on (`askAccess: true`, ends with "Activar acceso", the
  prominent disclosure) and from the section's link (ends with "Entendido"); dots, Siguiente and
  the last step's disclosure and button sit in the sheet's stuck footer (that disclosure is the
  Play prominent disclosure). Scenes `assets/wambi/capture-step1..5.webp`, byte-identical to the
  web copies (`test/tooling/capture_scenes_test.dart`). Tests: `test/l10n/capture_copy_test.dart`
  (no language words; app copy equals web copy), parity pairs in
  `test/parity/capture_how_parity_test.dart`.
  `capture_platform.dart` wraps the `wambito/capture` channel (`autoCapturePlatformProvider`; no channel ⇒ `status()` null ⇒ the section
  hides); `SessionController.signOut`/`accountDeleted` call its `clearQueue()`, and every sign-in
  (`_signedIn`) and a start the server confirms call `sendQueued(userId)` (a 401 keeps the queue); a merge passes
  `from` (`sendQueued(userId, from:)`, Kotlin `CaptureQueue.adopt(userId, mark, from)`): the captures tagged `from`
  are re-tagged and its confirms kept, never dropped (`verifyCode(keepCapturesOf:)`, `returnToGuest`).
  `CaptureHandover` (`captureHandoverProvider`) keeps `{owner, from}` in secure storage `wambito.capture.handover`
  before the new token is written, so every hand-over of that session (a restart's, `previewSyncProvider`'s) passes
  `from` until one went through. A `preview` account has
  the same switches: `previewSyncProvider` hands the queue over with `sendQueued` (never `clearQueue`), and Android's
  `SendCapturesWorker` / `ConfirmCaptureWorker` run `captureMain` (no `CaptureApi`, no network constraint). Only a
  `done`/`changed` run changes the queue (Dart's `ackQueued`); any other outcome or `timeout` keeps it and retries up to
  8 runs, then `kept`. A capture a finished run leaves unacked is counted (`CaptureQueue.refuse`, apart from the items)
  and dropped at 8, never for an engine failure. Notifications are deduped by transaction id.
  Tests fake it with
  `test/capture_auto/fakes.dart`.
- API: `lib/api/client.dart` (Dio, `WambitoApi`); headers from `lib/api/device.dart`
  (`x-wambito-timezone`, `-locale`, `-client`: `ios` on an iPhone, `android` elsewhere, the API's word for the app; `-version`: `wambito/device` `appVersion`, sent only if it matches `^[A-Za-z0-9.+_-]{1,64}$`); `lib/api/seen.dart` (`SeenPing`, watched in `app.dart`) posts `/v2/me/seen` once per local day and account on start and resume, keeping the day only after a 2xx; a headless run never calls it; server defaults to `https://app.wambito.com`,
  override `--dart-define=WAMBITO_SERVER=…` (`lib/api/server_address.dart`) or in Settings.
- Android side of `wambito/device` (`MainActivity.kt`): `timeZone`, `openUrl`, `appVersion`, `excludeFromBackup`, and the widget card's `widgetInstalled`, `widgetPinSupported`, `pinWidget` (`lib/home/widget_pin.dart`; they use the manifest's receivers, `widget/WidgetPinning.kt`, tested by `WidgetPinningTest`).
- Storage: secure storage for session and settings; widget snapshot JSON under
  `wambito.widget.snapshot` in `HomeWidgetPreferences` (`lib/home/widget_snapshot.dart`).
- `lib/home/widget_card.dart`: home's "Anota sin abrir la app" card (`WidgetCard`, key `home.widgetCard`, right after `ReviewHomeRow`). Shows on Android only, with at least one movement (on screen, or in an older month via `hasTransactionsProvider`), no Wambito widget on a home screen (`widgetOnHomeProvider`, asked again on the next app resume after a pin) and not put away ("Ahora no" keeps `wambito.widgetCard.closed` in secure storage). "Añadir widget" asks the launcher (`WidgetPin`), or opens the three-step sheet when it cannot; Settings has the same "Añadir widget" row (`settings.addWidget`) until a widget exists. Tests: `FakeWidgetPin` (`test/home/fakes.dart`, installed by default in `pumpHome` and `pumpSettingsApp`, so no card shows unless a test asks).
- `lib/review/`: the inbox of transactions detected from notifications (`needsReview`). `reviewProvider`
  (`review_controller.dart`, read once, invalidated by home on refresh/resume) feeds home's
  "N gastos por revisar" row (`ReviewHomeRow`) and `/review` (`ReviewScreen`): Bien and Confirmar
  todos call `ReviewRepository.confirm` (POST /v1/transactions/review, all or nothing); Cambiar opens
  the add sheet's edit flow, whose save adds `needsReview: false` (`TransactionPatch.confirming`) so it
  confirms and teaches in one PATCH. Rows carry the mark "por revisar · de Revolut" (`reviewMarkOf`).
  Tests fake the server with `test/review/fakes.dart` (`pumpHome`/`pumpSettingsApp` override it).
- `lib/crypto/`: the Dart port of `packages/crypto`, one file per TS file (`crypto.dart` exports them), on
  `cryptography` (pure Dart in tests) and `cryptography_flutter` (native, registers itself). The device private
  key is raw 32 bytes. `test/crypto/vectors_test.dart` must pass `packages/crypto/test-vectors.json`
  byte for byte; a format change needs a new `enc_v` and vectors on both sides. `prfSalt` lives in `wraps.dart`.
- `lib/core/`: the Dart port of `packages/core` (money, dates, budgets, summaries, movement search, reports).
  Shared-fixtures rule: the Dart tests read the TypeScript side's fixtures by relative path and never
  copy them (`packages/core/fixtures/*.json`, `reports/cases.json`, `quick-capture/cases.json`,
  `packages/crypto/test-vectors.json`); a change to a fixture changes what Dart must return, and a
  Dart-only expectation is a bug in one of the two.
- `lib/local/`: the phone's end-to-end encryption, each file the twin of one in `apps/web/app/local/`
  (`prf.dart` = `prf.ts`: the passkey PRF over the `wambito/passkeys` channel, on iOS 18+ and Android).
  `store.dart` + `memory_store.dart` (`FinanceStore`; the shared contract is `test/local/store_contract.dart`,
  run by every store), `db.dart` + `sqlite_store.dart` (`SqliteStore.open(userId)`: the vault, file
  `wambito-vault-<userId>.db` in the `vault` folder of the app support directory (Android `files/vault`), one table per record type plus `outbox`,
  `meta`, `quarantine`; schema version 2 (`vaultSchemaVersion`; `_upgrade` in `db.dart` migrates a
  real user's file in place, never by recreating it: v2 added `bodiless` to the records tables, set
  on every v1 tombstone); a local write updates record and outbox in one SQLite transaction, all
  operations go through one queue; keys are not in it, they live in secure storage; tests use
  `sqflite_common_ffi` in a temp dir via the `directory`/`factory` arguments). `backup.dart` keeps the
  vault folder out of backups: iOS via `excludeFromBackup` on `wambito/device`, Android via
  `res/xml/backup_rules.xml` + `data_extraction_rules.xml` (the `vault` folder and the secure storage
  prefs, `FlutterSecureStorageConfiguration:FlutterSecureStorage` included, and the finance prefs: the widget's,
  the due list and the capture queue `wambito.capture.queue`; tested by `BackupRulesTest`). Move the vault folder and the XML paths change together.
  `lib/debug/prf_probe_screen.dart` is the PRF probe, `/debug/prf`, registered only when `kDebugMode`: it
  creates a passkey and evaluates its PRF on a real phone, to check that the platform gives one.
  `ids.dart` = `ids.ts` (`uuidv7`, `uuidv5`; `seedNamespace`), `captures.dart` (`merchantRecordId`, `createCaptureSchema`; the save and the merchant memory of `POST /v1/captures` live in `backend.dart`, twin of the API's `services/captures.ts`: 10-minute duplicate window, learned on review and on a PATCH that confirms a `capture` row), `backend.dart` = `backend.ts` (`createLocalBackend`: the `/v1`
  finance routes over a `FinanceStore`, one store transaction per request, 422 `validation_failed`,
  403 `demo_unavailable` for `localUnavailable`; `handle` returns null for a path it does not serve) and
  `backend_interceptor.dart` (the Dio interceptor that answers those routes, `GET`/`PATCH /v1/me` and the
  quick capture's `/v1/transactions/batch` and `batch-delete` included, and sends the rest, `DELETE /v1/me`
  among it, to the network; the web's backend has no batch routes, so those are tested by hand) `test/local/backend_shapes_test.dart` compares each
  scenario (answer and the store's records after a write) of `test/fixtures/local_backend/scenarios.json` over `seed.json` with the `<scenario>.json`
  the web's backend recorded: after a change to `backend.ts` or a scenario, run
  `pnpm --filter @wambito/web record:local-backend` and keep the diff.
  `sync.dart` = `sync.ts` (`createSyncEngine`: push the outbox, pull `/v2/sync`; one run per account in
  the process; triggers: start, `AppLifecycleListener` resume, a minute in the foreground, and
  `afterLocalWrite`, which the session wires to the interceptor's `afterWrite`; tests port `sync.test.ts`
  over the fake `/v2` in `test/local/fake_sync.dart`) and `vault_session.dart` = `vault-session.ts`
  (`openVaultSession`: store, keys, local backend and sync in one session per account, exactly one
  `SqliteStore` per account in the process; `forgetVault(userId, storage)` deletes the vault file and
  every key, waiting at most `vaultCloseWait` in all for the store to close; `seedIfEmpty` makes the first
  settings and suggested categories after a complete first sync, skipped with `OpenVaultOptions.seed: false`
  when a carry fills the new vault). `merge.dart` (`carryRecords(from, into, mode:, intoUserId:)`, one
  `into.transaction`, idempotent: `adopt` copies every live record, settings re-keyed to the new user's seed id
  with `recoveryKeySavedAt` null and no `revokedDevices`; `merge` drops a phone category or `account` that
  matches the account's by `foldedName` (trim, lower case) and kind (not archived), renames same name other
  kind `"<name> 2"`, keeps the account's settings, a phone budget only where the account has none for that
  category; both re-key merchants to `merchantRecordId(intoUserId, key)` (the target's wins). `adopt` keeps every other
  id; `merge` gives each carried record `mergedId(targetUserId, oldId)` (`uuidv5(mergeNamespace, '<target>:<old>')`,
  ruling P17: the server's record ids are global and the guest already owns the old ones) and rewrites `categoryId`,
  `accountId`, `recurrenceId` through the same map; an occurrence of a carried rule is re-derived as
  `uuidv5(newRuleId, '<month>:<rev>')`, as the backend derives it; `mergedIdsOf` lists those ids; tombstones stay behind except a deleted occurrence of a carried
  rule, carried as a tombstone so the rule does not make it again; `currencyOf` for the currency stop).
  `stale_vaults.dart` =
  `stale-vaults.ts` (`deleteStaleVaults(keep)`: every other account's vault file under `vault/`, its
  `wambito.vault.<id>.*` and `wambito.encryption.<id>`, and `wambito.account` when not `keep`'s;
  `inUse` is asked again before each delete, so an account that signed in meanwhile keeps its vault;
  `holdOf` skips a vault whose `meta.hold` is set (or unreadable), see Traps).
  `rotate.dart` = `rotate.ts` (`rotateKeys`: removing a device rotates the data key; this phone never removes
  itself and its own wrap is always posted; `commit()` posts, keeps `dk.<n>` + `current` and `revokedDevices`, then
  a fresh recovery key's verifier; also `newRecoveryKey`, `checkRecoveryKey`); `rotate.dart` imports `keys.dart`,
  not the other way;
  `recovery_verifier.dart` holds the verifier hashes (pure crypto) and `keys.dart` `putRecoveryVerifier` sends them.
  `pairing.dart` = `pairing.ts` (the `/v2/pairing` relay, D21: both devices show the same 6-digit number): the new
  phone's `startPairing` (`NewDevicePairing`: id, 8-character code, QR `wambito://pair?id=…&key=…`, `number()`,
  `finish()` which enrolls the phone, `cancel()`) and the approver's `findPairing` by code or QR (`ApproverPairing`:
  `number()`, `approve()` refuses with a plain `StateError` until the number was shown). Polls every 1.5 s, stops at the
  relay's `expiresAt` capped at 10 minutes from its own start, and on `cancel()`; the ephemeral private keys and the
  opened DK are zeroed; nothing secret is logged. `PairingClock` is the test seam; `pairingOpenFromPairing` and
  `pairingSealToDevice` record what the crypto handed out. `test/local/pairing_test.dart` ports `pairing.test.ts` over
  a fake relay.
  `db.dart` `pendingChangesInVault` counts a kept vault's unsent changes from its file (Unlock and
  Locked sign out through the unsynced sheet without "Sync and sign out"). `install_marker.dart`: `clearKeysAfterReinstall` runs first in `bootstrap()` and deletes
  every `wambito.vault.*` / `wambito.encryption.*` item and the kept `wambito.account` when
  `wambito.installed` (Application Support) is missing, since the iOS Keychain outlives a reinstall;
  it then marks the session that survived (`wambito.reinstalledSession`), whose home cache and saves
  no longer prove the account `plain`.
- `lib/background/`: the headless engine's Dart side. `syncMain` / `captureMain` (in `lib/main.dart`, D22) call
  `backgroundMain(kind)` (`background_main.dart`: real deps, D14 headers `x-wambito-background: 1`), which runs
  `runBackground` (`background_run.dart`) and ends with `wambito/background` `finished {outcome, captured}`
  (`background_channel.dart`). A run: token, account (`preview` only), keys, lease, background store, the queued
  captures (`POST /v1/captures`, `Idempotency-Key` = the queue's `key`; 201 and 200 are both acked) and confirms
  (`POST /v1/transactions/review`; 404 acked) through the local backend, one sync on the lease the run holds, the
  widget and due effects (each best effort: one that throws skips neither the other nor the ack), then `ack` last
  (a crash leaves the queue; the next run merges). A run has a deadline (`BackgroundDeps.deadline`: 20 s on iOS,
  8 min on Android, inside the native budgets): past it the sync stops at its next fence, the effects are skipped,
  what was saved is acked and the lease released; `cutAtDeadline` cancels the network at it. A sync refused with
  401 `user_deleted` ends `userDeleted` (no effects, no hold, nothing adopted: only the app adopts, Review Focus 2;
  Android's `SyncWorker` retries it like `failed`); a removed device (`deviceRemoved`) ends `signedOut`. `queued_capture.dart`
  reads Kotlin's items; `AutoCapturePlatform.takeQueued/ackQueued` are on `wambito/capture`. Tests: `test/background/`.
  The vault lease (`lib/local/vault_lock.dart`, `tryLease` / `waitLease`) is what lets the app and a headless engine
  share one vault file: a lock file `wambito-vault-<userId>.db-lock` in the vault folder, holder `app` or `background`,
  TTL 10 minutes (renewed by the sync), taken over atomically once expired; the app waits at most `appLeaseWait`
  (2 s, `vault_session.dart`) for it and reports `busy` (retried like `offline`; a known phone opens, a fresh vault's
  open fails `busy` and the gate shows it as offline), a headless run that cannot take it ends `busy` and touches nothing. Tests give each phone its own folder, so its own lock.
  Native, Android `background/`: `SyncScheduler` (`wambito.sync.periodic` every 6 h with network, `wambito.sync.now`, KEEP: while an ask waits or runs, a second is dropped, so the widget's refresh jobs never chain engines;
  `AccountMode.write(mode, owner)` schedules for `preview` and cancels for `plain`/none), `SyncWorker` (runs
  `syncMain`; `busy`/`failed`/`timeout` retry up to 3 times, then `gave up`; after `done`/`changed` a non-empty
  capture queue gets `CaptureScheduler.enqueueSend`); the capture workers also send `vaultChanged` on `changed`, `HeadlessRunner` (a `FlutterEngine`
  with no activity, 9 min budget, destroyed in every case; `HeadlessHooks.runner` replaces it in tests) and
  `BackgroundChannel` (`finished` from the headless Dart; `vaultChanged` to the app's engine, D7, which
  `vaultChangedProvider` in `vault_providers.dart` turns into `VaultSession.externalChange()`).
  `capture/CaptureQueueChannel.kt` is the headless engine's `wambito/capture` (`takeQueued`, `ackQueued`): it only
  answers from the queue and removes acked keys, so a failed run keeps everything. iOS `Background/`: `SyncTask`
  (BGAppRefreshTask `wambito.sync`, registered in `didFinishLaunching`; reschedules first, 4 h, only for `preview`
  via `SyncPlan` in `WambitoNative`; a `plain` account has none waiting) runs `HeadlessRunner` (`syncMain` in a
  headless engine, 25 s budget; destroyed once on `finished` (on the next main-queue turn, never inside its own
  handler), budget or `expirationHandler`, all on the main thread) and ends with `setTaskCompleted` once (`TaskOnce`
  in `WambitoNative`: an expiration before the start keeps the engine from starting); `BackgroundChannel` hands `finished`'s outcome to it and sends
  `vaultChanged` to the app's engine (`BackgroundChannel.app`). `setEncryptionMode {mode, owner}` schedules or
  cancels it (`AccountMode.owner`, `wambito.encryption.owner`). iOS has no capture queue and sends nothing natively.
- `lib/vault/`: the gate on screen. `vault_gate.dart` is `vault-gate.ts` (state machine over injected
  deps), `vault_providers.dart` wires it (`vaultGateProvider`, `vaultSessionProvider`,
  `unlockPasskeyOfferedProvider`, `forgetVaultProvider`, `staleVaultsProvider`), `encryption_mode.dart`
  holds the account and its mode, stale-while-revalidate (`vaultAccountProvider`: what was kept for
  the session, `keptVaultAccountProvider`, at once; then `GET /v1/me`, `freshVaultAccountProvider`,
  which wins when it differs and sweeps the other accounts' vaults on each answer; with nothing kept
  the start waits for the server. A home cache or a pending-saves queue of this session proves the
  account `plain` (`VaultAccount.inferred`: routing and the offline path only; `knownPlainProvider`
  stays false, so its finance calls wait for the server's answer). The router reads
  `currentVaultAccountProvider`, never the mode provider's value). `vault_screen.dart` (route `/unlock`) switches over the gate state:
  `recovery_key_setup_view.dart` (Copy, Share through `wambito/files`, four-character check),
  `unlock_view.dart` ("Add this phone from another device"), `locked_view.dart` (why, a retry when one helps, and
  sign out), `pair_new_device_view.dart` (the `Pairing` gate state: QR with `qr_flutter`, the code in two
  groups of four, the number once known; `GatePairing` is what the gate watches, `startPairing()` / `leavePairing()`;
  a finished pairing opens like a recovery unlock, and a left, failed, expired or disposed one is cancelled, so it
  stops polling); Checking, Opening and Committing show a loading line. The gate has no guest branch (phone-first
  accounts): every `preview` account with wraps elsewhere, with or without email, gets Unlock (`LockedKind` is
  `error`, `offline`, `unsupported`; `PairingFrom` only `unlock`), while `prepareAccount(guest: isAnonymous)` still
  sets an account without email up with no key shown. The welcome (`lib/entry/entry_screen.dart`) is Wambi,
  "Start" (`entry.start`, `POST /auth/sign-in/anonymous`) and "I already have an account" (`entry.haveAccount`, a
  link to `/entry/email`). Signed out, the email screen links (`entry.useRecoveryKey`) to the recovery-key sign-in
  (`lib/entry/recovery_sign_in_screen.dart`, route `/entry/recovery`, signed out only; keys `recovery.input`,
  `recovery.submit`): `SessionController.signInWithRecoveryKey` parses the text as Unlock does
  (`keysParseRecoveryKey`; one that does not parse is `bad_recovery_key`, nothing sent), posts only `recoveryVerifier`'s
  `lookup`/`auth` (`AuthApi.recoverySignIn`, zeroed once sent; 401 `recovery_key_invalid`, 429 `retryAfter`), then
  holds the parsed 16 bytes in `signInRecoveryKeyProvider` (`SignInRecoveryKey`: memory only, one take, zeroed by a
  failed sign-in, a sign-out or an expiry; never a `String`). The gate takes it at every check
  (`VaultGateDeps.takeSignInRecoverySecret`) and tries it once through `keys.unlockWithRecoverySecret` on an account
  with wraps and no keys here, before Unlock, zeroing it either way; a failure shows `Unlock(error: …)`. Opened that
  way, the vault marks `recoveryKeySavedAt` when it was null. The other side of a pairing is
  `lib/settings/security/approve_device_screen.dart` (`ApproveDeviceScreen`, twin of `ApproveDevice.tsx`, titled
  "Approve a new device" as `vaultPairLead` tells the new phone; its entry is Settings → Security, below): type the
  code or Scan (`lib/scanner/qr_scanner.dart`: `QrScanner` over `wambito/scanner`, `qrScannerProvider`; `isAvailable`,
  `scan` → the first `wambito://pair?` QR, or null for a close or a refused permission), then the number, then
  "They match". It cancels its `ApproverPairing` (the ephemeral private key) on Cancel, "They do not match", a
  failure, back and dispose; only a finished approval lets go of it. The camera and its permission open only inside
  `scan`. Settings → Security (`lib/settings/security/`, `preview` accounts only, the same section with or without email):
  `security_api.dart` (`SecurityApi`, `liveSecurity`, `securityApiProvider` (null without an open vault), `securitySnapshotProvider`:
  wraps, own id, revoked, verified, unreadable), `security_model.dart` (`deviceRows`, `passkeyRows`, `hasPasskeyWrap`, `anyPasskeyWrap`),
  `security_section.dart` (devices, Remove, Approve, "New recovery key"), `remove_device_sheet.dart` (typed key or a new one),
  `recovery_setup_page.dart` (the new key's setup screen: shown and checked before `commit()`, no way out after a failed save).
  Remove and "New recovery key" (making it and showing it) ask `confirmSensitive` first (D17: no key is made or shown before it passes); approving a device is not guarded. After a rotation
  commit the session's `reloadKeys()` runs; a commit that fails is retried on the same `PreparedRotation` (never a new one); a
  prepared rotation or new key the person gives up is `forget()`ten (zeroes the held DK / verifier hashes). The passkeys card says
  "Opens your data" per passkey, offers "Turn on" (`evaluatePrf` + `addPasskeyWrap`) and adds a new passkey with its wrap
  (`SettingsPasskeys.add(prf:)`: PRF from the registration, else a second touch). `router.dart`: `VaultRoute` (`vaultRouteOf`): a signed-in `preview` account whose
  gate is not Ready goes to `/unlock` from every route except `/auth/verify`, `/entry*` and `/debug/*`;
  while the mode is unknown (nothing kept) the `/loading` route; a mode nobody could tell is
  Locked(offline) with a retry. Sign-out and a deleted account (`session.dart`) wipe the vault
  (`forgetVault`), the kept account and mode, before the token goes; Settings asks
  `confirmUnsyncedSignOut` (`unsynced_sheet.dart`) first, at a sign-out and before changing server.
  A 401 is told apart by its code (phone-first spec 10, `lib/api/unauthorized.dart`: `Unauthorized`
  `deviceRemoved`, `userDeleted`, `expired` = `unauthenticated` or anything else; `unauthorizedOf(code)`,
  `unauthorizedOfError(dio)`). `GET /v1/me` at start (`AuthApi.standing(token, userId:)`), in
  `freshVaultAccountProvider` and in the gate's `sessionUserId` sends `x-wambito-user` with the account kept for
  the session (ruling 17), so a deleted user answers `user_deleted`; the sync's 401 (`SyncProblemCode.userDeleted`,
  `deviceRemoved` with status 401, else `unauthorized`) and `/v2/keys`'s (`KeysError` `device_removed`,
  `user_deleted`, `unauthenticated`, status 401) carry it too, and `OpenVaultOptions.onUnauthorized(kind)` hands it
  on. Everything ends in `SessionController.sessionEnded(token:, kind:)` (`_refresh` at start, the gate's
  `signInAgain(kind)`): `expired` is `sessionExpired` (the session ends only: the vault, its keys and the kept
  account stay for the same account's next sign-in, which pushes the outbox; another account's sign-in sweeps
  them, and so does a signed-out start unless they are the account kept last, `_sweepSignedOut`);
  `deviceRemoved` wipes the vault, the home cache and the widget's figures, then signs out; `userDeleted` adopts
  the vault into a new anonymous user (`lib/local/adopt.dart`, below). A `plain` account (or one whose mode was
  never kept for the session) gets `sessionExpired` whatever the code. Only a sign-out, a removed device and an
  empty deleted account's vault wipe the vault.
  `lib/local/adopt.dart`: `adoptVaultIntoNewUser(oldVaultId, AdoptDeps)` → `AdoptStep` (`adopted`, `plainUser`,
  `waiting`), the routine Task 11 reuses: the new user's token kept first (`AdoptDeps.keptToken/keepToken`; a kept
  one is reused, so a crash never makes a second user), the hold's target = the new id, `plainUser` stops there,
  `prepareAccount(guest: true)` (a hidden recovery wrap; the nudges start over), then under the old vault's lease and
  with the app's writes into it stopped (`stopWrites` closes its open session) `carryRecords(adopt)` into the new
  user's vault (opened on its own: nothing seeded), then the old vault forgotten; offline (or a 5xx) before the carry
  is `waiting`. `adoptOrphan(oldUserId, deps)` → `AdoptOutcome` (`adopted`, `wiped`, `waiting`): holds the vault
  `orphaned` first; no data (ruling 18: no live transaction, recurrence, budget or merchant, and no capture still
  queued for that user: `hasQueuedCaptures` = `AutoCapturePlatform.hasQueued` over `takeQueued` on the app's
  `wambito/capture`, read only; a `PlatformException` counts as captures, no Android side as none) and no adoption
  under way wipes it and signs out (`onWiped`); else the routine, then `onAdopted` (the session becomes the new user's,
  taking the deleted user's queued captures over: `captureHandoverProvider.keep` then `_signedIn(capturesFrom:)`)
  and the kept token goes. `resumeAdoption(deps)` (`adoptionResumeProvider`, watched in `app.dart` before the
  merge's: at start and on resume) goes on with every `orphaned` hold of `listVaultHolds` when `mayResume` allows
  (signed out, or still in that account's session); a vault in `unreadable` is left alone. `adoptDepsProvider`
  (tests override it); adoptions run one after the other, never one in place of another
  (`SessionController._adoption`), and a 401's adoption queued behind another runs only while the session is
  still that dead token. `onAdopted` waits for `sendQueued(newUserId, from: oldUserId)` itself, so the queue is
  never left tagged to the deleted user. The gate never opens a vault held `orphaned` (`refuseAdopted`, before and
  after `openVaultSession`, through `vaultHoldReaderProvider`): it asks the adoption to go on and shows Locked
  `offline` (`adopting`), or `LockedKind.plainServer` (`vaultLockedPlainServer*`) when the adoption stopped at a
  `plain` new user (`adoptionNeedsEncryptedServer`, kept in `adoptionNeedsEncryptedServerProvider`, whose change makes
  a Locked gate check again by itself). Tests: `test/local/adopt_test.dart`. A 423 `vault_locked` save
  is retried (`canRetrySave`), never dropped. Tests of screens that are not about the vault pass
  `plainAccount()` (`test/support/plain_account.dart`) so the account is `plain`.
  What stays out for a `preview` account (export, import, assistants) shows `ComingSoonNotice` ("Próximamente con cifrado",
  `comingSoonWithEncryption`; `isPreviewProvider`, `preview.dart`) and sends or fetches nothing.
  `preview_sync.dart` (`previewSyncProvider`, watched in `app.dart`) writes the mode where native code
  reads it (`wambito/notices` `setEncryptionMode {mode, owner}`, keys `wambito.encryption.mode`: `plain`, `preview`,
  `unknown` while the account is not known, and `wambito.encryption.owner`: the user id; both cleared on sign-out; untouched while the session loads),
  tells `WidgetSync` (`modeChanged`; `vaultOpened`/`vaultChanged` follow the open `VaultSession`, `session.backend`,
  and the widget is drawn from the vault by `home/vault_widget.dart` `writeVaultWidget`: 2 s after each commit, the
  snapshot carries `owner` = the user id; until the vault is open a `preview` widget is the signed-out one, no line).
  The headless run draws it too (`background/widget_effect.dart`, even offline). `RefreshWorker` for `preview` calls
  no API: it asks `SyncScheduler.now` (`sync asked`), and a snapshot whose `owner` is not `AccountMode.owner` becomes
  the signed-out one (`owner mismatch`). `HomeWidgetPreferences.xml` and `wambito.notice.duelist.xml` are excluded
  from backups (`backup_rules.xml`, `data_extraction_rules.xml`). It also calls the capture
  channel's `clearQueue()` once. Native: Android `account/AccountMode.kt` (prefs `wambito.encryption`),
  asked first by `SendCapturesWorker`, `ConfirmCaptureWorker`, `CaptureListener`, `RefreshWorker` and
  `DueWorker` (`preview` or `unknown` ⇒ no API call (`RefreshWorker` asks the headless sync); absent = an install from before the vault ⇒ as
  before); iOS `AccountMode.swift` in `WambitoNative` (UserDefaults), asked by `DueTask`. Tests of such
  screens pass `previewOpen()` (`test/support/preview_account.dart`).
- `lib/protect/`: "Protect your data" (phone-first spec 5.2) for a `preview` account without email. `protect_status.dart`:
  `ProtectStatus` (`recoveryKey`, `passkey`, `passkeyOffered`, `passkeyWithoutPrf`, `done`, `protected`) and
  `protectStatusProvider` (null unless `preview`, anonymous and the vault open; read again on every vault commit);
  step 1 is the synced settings field `recoveryKeySavedAt` (`packages/core` `records.ts` and `lib/core/records.dart`,
  read straight from the vault with `recoveryKeySavedAt(store)`), step 2 a passkey wrap (`anyPasskeyWrap`), never the
  passkey row. `protect_actions.dart`: `protectWithRecoveryKey` (screen lock, then `newRecoveryKey` on the same key
  version, no rotation: it replaces the guest's hidden recovery wrap; `rotated_elsewhere` reloads the keys and makes
  the key again; `canLeave: false` keeps `RecoverySetupPage` until saved) then `markRecoveryKeySaved` (settings record
  in one store transaction, then a sync; Settings → Security's "New recovery key" marks it too);
  `protectWithPasskey` (`SettingsPasskeys.add(prf:)`). `afterClaim(context, ref)` (spec 7.1, ruling 20): after a
  `preview` guest's claim, `protectWithRecoveryKey(canLeave: false)` when the settings record's `recoveryKeySavedAt`
  is null (read from the vault, never `protectStatusProvider`, which is null once the account has an email), then
  `SessionController.offerPasskey()` (`offerPasskeyFor` when `PasskeyOffer.dueFor` says so): the only passkey offer
  after a claim, `confirmClaim` offers nothing. The key is owed (`KeyAfterClaimMarks`, secure storage
  `wambito.protect.<userId>.keyAfterClaim`, written just before `confirmClaim`, cleared once the key is saved): a key
  that could not be made (lock refused, offline) stops there, no offer; a kill on its page, or that, brings the page
  back when the vault opens with home there (`resumeKeyAfterClaim`, from `HomeScreen`). For a `preview` account with
  its vault open the offer page makes the passkey with `protectWithPasskey` (PRF wrap; no PRF toasts
  `protectPasskeyNoPrf`); otherwise `registerPasskey`. The email screen runs it under `claimFinishingProvider`, which keeps
  `/entry/email` open past the router's "no email screen once there is an email" (`sessionRedirect(finishingClaim:)`).
  A `preview` guest's email_taken asks `askMerge`; yes is `MergeController.begin` then `sendCode(replaceGuest: true)`,
  the code is `verifyCode(keepCapturesOf: guestUserId)`, and backing out of it ("Usar otro correo", back) is
  `MergeController.cancel()`; no changes nothing. The preview `/progress` says what an email adds
  (`protectEmailTitle`, `protectEmailLead`, `progressPreviewBody`) and has no passkey section. A `plain` guest's claim
  and email_taken are today's. Tests: `test/entry/claim_preview_test.dart`. `confirmSensitive(noKeyYet:)`: with no screen lock and no
  saved key there is nothing to type, so it goes on (ruling 3). `protect_block.dart`: `ProtectBlock` at the top of
  Settings (keys `protect.block`, `protect.count` "N of 2" while neither step is done, `protect.recovery`,
  `protect.passkey` only with passkey support, `protect.passkeyNoPrf`, `protect.email` → `/progress`); a `preview`
  guest has no `settings.saveProgress`, and no `home.saveProgress` in home's menu (ruling 21). Tests: `test/protect/`
  (`fakes.dart`: `FakeVault` on a memory store).
  `protect_card.dart`: home's nudge (`ProtectCard`, key `home.protectCard`, before `WidgetCard`, which waits while it
  shows; buttons `protect.cardGo` = step 1, `protect.cardLater`). `protectCardProvider` is true while
  `protectStatusProvider` says no step is done and `protectCardDue` says so: first after 7 days since `firstOpen`
  (written at the first evaluation) or 20 live transactions in the vault, then 14 days after the first "Not now",
  30 after the second, every 30 after that. State (`ProtectCardState`: `firstOpen`, `lastDismissed`, `dismissals`)
  is JSON in secure storage `home.protect.<userId>` (`ProtectCardStore`; tests use memory). `leaving_warning.dart`:
  `warnUnprotectedLeaving` (keys `unprotected.protectFirst`, `unprotected.signOutConfirm`, `unprotected.serverConfirm`),
  used by Settings' sign out and server change for a `preview` guest with neither step done ("Protect first" opens
  the recovery key and leaves nothing); with a step done there is no warning; with the passkey wraps unreadable
  (offline) the sheet adds a note instead of claiming there is no passkey. A `plain` guest keeps `warnGuestLeaving`.
- `lib/merge/`: merging this phone's anonymous `preview` account into an existing email account (phone-first spec
  7.2). `merge_offer.dart` `askMerge(context, email)` (the question and "this phone's recovery key stops working",
  `merge.yes`); `merge_controller.dart` `MergeController` (`mergeControllerProvider`, states `MergeIdle`,
  `MergeSigningIn`, `MergeWaitingUnlock`, `MergeCurrencyStop(phone, account)`, `MergeUploading(pending)`, `MergeDone`,
  `MergeFailed(code, carried)`): `begin(email)` keeps the anonymous token (`wambito.vault.<anonId>.mergeToken`) and
  holds its vault `merging` (target = the email) before any code is sent; the caller then signs in with
  `replaceGuest: true`. `run()` (once the account's vault is Ready, `mergeTargetProvider`): currency check
  (`currencyOf`; a difference stops before any write), `carryRecords(mode: merge)` under the old vault's lease, then
  `meta.mergeCarried` in the old vault (never carried twice: one of `mergedIdsOf`'s ids already in the account's vault
  also counts as carried, so a crash before the mark never reruns it), sync until `pendingChanges() == 0`, every carried record with a
  server version (`VaultSession.serverVersion`; one refused for good, `id_taken` or given up, is `MergeFailed('refused')`
  and nothing is deleted), then `AuthApi.deleteUser` (`DELETE /v1/me` with the kept token; 401 = done),
  `forgetVault(anonId)` and the token key. The email sign-in finds the merge through `mergeSignInProvider` and keeps the
  guest's queued captures (`MergeController.guestUserId`).
  The old vault is read on its own connection (`SqliteStore.open(id, background: true)`, no keys). `cancel()`
  (ruling 10): after the sign-in `SessionController.returnToGuest(token, guestUserId:)` (the guest session written
  first, then the email account's vault forgotten by the id learned for that session, then its server sign-out, not
  waited for), then the hold goes; refused once carried. `keepAccountOnly()` marks `meta.mergeDiscard` in the old vault,
  then deletes the anonymous user and its vault and carries nothing (a later run finishes it the same way). `mergeResumeProvider` (watched
  in `app.dart` before the seen ping) resumes from `listVaultHolds` at start, on account changes and on resume (a
  hold whose file is unreadable, or without its token, is left alone); still in the phone's own session the hold
  stays (the email's link may come). `mergeBlocksAppProvider` keeps the router on `/merge` (`MergeScreen`:
  progress, the currency stop with `merge.cancel` and `merge.keepAccount` + `merge.keepAccountConfirm`) while it
  waits for the account's vault, at the currency stop and after a failure before the carry; Unlock shows
  `unlock.mergeWaiting` and its sign-out calls the merge off. Tests: `test/merge/`.
- `lib/search/`: `/search` (`SearchScreen`, twin of `apps/web/app/features/search/`), opened by the
  magnifier in home's header (`home.search`). `searchControllerProvider` (`search_controller.dart`)
  holds the filters and results: text debounced 300 ms, kind, categories and status searched at once,
  only the latest request lands, `loadMore` waits for a pending debounce, `retry` repeats what failed
  (a page or the first page/refresh); text capped at 100 characters, categories at 20.
  `SearchRepository` (`search_repository.dart`) is `GET /v1/transactions` with `totals=true`; the
  totals line hides when the server sends none. The screen uses home's categories (archived too),
  loads the next page when the end is near, and after `openEditSheet` (replaceable in tests with
  `searchOpenEditProvider`) calls `refresh()`. Tests: `test/search/` (fake repository through the provider).
- Deep links `wambito://{add,capture,due,progress,home,review}` (`lib/launch/launch_links.dart`);
  `wambito://review` and `wambito://review/<id>` (one segment, `launchReviewIdOf`) push `/review` or
  `/review/<id>` over home, which opens that transaction in the editor.

## Android (`android/app/src/main/kotlin/com/wambito/app/`)

- `MainActivity.kt`: a `FlutterFragmentActivity` (`local_auth`'s prompt needs a `FragmentActivity`, so request codes
  must fit 16 bits: all do) that takes the launch link. The themes (`styles.xml`, `values-v31`) inherit
  `Theme.AppCompat.NoActionBar`, as `local_auth_android` asks for Android 8 and below. The screen lock is Dart only:
  `lib/security/screen_lock.dart` (`ScreenLock`, `LocalAuthScreenLock`, `screenLockProvider`, `confirmSensitive`:
  lock passed → true, closed → false, no lock → a sheet asking the current recovery key through `checkRecoveryKey`);
  `USE_BIOMETRIC` comes from `local_auth_android` and is required by `check-permissions.sh`, `USE_FINGERPRINT` is declared with
  `maxSdkVersion="28"` (androidx.biometric on Android 8 and 9, R16); iOS has `NSFaceIDUsageDescription`. Channels:
  `wambito/*`, registered in `MainActivity.kt`; names match the Dart constants (rename both at once).
- `scanner/`: `wambito/scanner` (`isAvailable`, `scan`): `ScannerChannel` asks the `CAMERA` permission at scan time
  only (a refusal answers null) and starts `ScannerActivity` (not exported): CameraX `Preview` + `ImageAnalysis`
  (keep-only-latest) feeding `decodeQr` (ZXing core on the Y plane, `QrDecodeTest`); the first `wambito://pair?` text
  goes back. CameraX 1.6.2 (camera2, lifecycle) and ZXing core 3.5.4 are pinned exactly; no `camera-view` (it brings media3
  and Guava): the preview is a `TextureView` fed by a hand-written `SurfaceProvider`; never `camera-mlkit-vision`, ML Kit or
  `mobile_scanner` (`check-no-google.sh`). camera-core's bundled libyuv has its BSD-3 notice in About. Its two words are `scanner_hint` / `scanner_close` in `strings.xml`.
- `widget/`: Glance widgets via home_widget; `notices/`: WorkManager `DueWorker`/`GuestWorker`,
  local notices only. A `preview` account's "Hoy vence…" is computed in Dart from the vault
  (`lib/notices/due_list.dart`: the app's `NoticeSync` and the headless `due` effect, `lib/background/due_effect.dart`)
  and handed over as `scheduleDueList {zone, language, owner, days}` (14 days, replaced whole);
  `DueList` keeps it in prefs `wambito.notice.duelist` (excluded from backups) with its owner, and `DueWorker`
  posts today's entry at 9:00 without asking the API, but nothing (and clears the list) when that owner is not
  `AccountMode.owner` or either is null; iOS schedules one `UNCalendarNotificationTrigger` per day
  (`DueSchedule`, ids `wambito.due.<date>`) and `cancelDue` removes them; `capture/`: the queue of captures parsed from bank notifications
  (`CaptureQueue`: each item tagged with the account id it was captured for, the prefs' `owner`
  then; `adopt(userId)` drops the items of another account or of none, old untagged items included;
  only the owner's items are sent, and only while the session mark matches `ownerMark`, which
  `sendQueued` stores), `CaptureApi` (`POST /v1/captures`, confirm) and WorkManager `SendCapturesWorker`
  (`CaptureHooks` replaces the session and the notifier in tests). The notification text is never
  queued, sent or logged. `CaptureListener` (a `NotificationListenerService`) reads only the packages
  enabled in `CaptureSettings` (prefs `wambito.capture.sources`), hands them to `BankParsers` (`RevolutParser`
  and `GoogleWalletParser`, expenses only in pt, it, en and es, one strict line per language and
  payment kind, sharing `Money` (comma or point decimal, any thousands separator); each line says
  where it comes from: seen on our phone (pt), another project's capture or tests (it, en) or nothing
  yet (es), so a new language needs a real sample; income returns null until samples exist; a parser
  that throws drops the notification) and queues
  the result; `CaptureChannel` is `wambito/capture`: `status`,
  `setSource`, `openAccessSettings`, `openAppInfo`, `clearQueue` (on sign-out: items and owner),
  `sendQueued` (`{userId}`, after a sign-in: `adopt` + send), `dismiss` (`{ids}`, confirmed in the
  app) and `keepOnly` (`{ids, before}`: `reviewProvider` sends every read under a full page; capture
  notifications of other ids posted before `before` go, so confirms on the web or by an assistant clear too). `CapturePoster` (the
  default `CaptureHooks.notifier`) posts the silent notification per detected transaction (title "Wambi", small icon
  `ic_notice` = Wambi's face cut from `ic_launcher_monochrome.xml`) on channel
  `wambito.capture` (LOW; id = `notificationId(transactionId)`, so a merged answer updates it, and one
  already confirmed (`needsReview` false) is `dismiss`ed instead; a group
  summary from 2): "Bien" is an immutable broadcast to the non-exported `ConfirmReceiver` →
  `CaptureScheduler.enqueueConfirm` → `ConfirmCaptureWorker` (one unique job per transaction,
  `wambito.capture.confirm.<id>`, KEEP; POST review, then cancels the notification; a 4xx other than
  401/408/429, 404 included, drops it; at most `MAX_ATTEMPTS` = 8 runs, then the notification stays
  for another tap), "Cambiar" opens `wambito://review/<id>` through the launch alias. Words in
  `CaptureText` (strings `capture_*`, language from `NoticeSettings`). Voice: Vosk, never Android's SpeechRecognizer
  (`voice/VoiceChannel.kt`, `wambito/voice` + `wambito/voice/events`; models kept per process by
  `ModelCache`: `VoiceModels` for Vosk, `PreciseModels` for the precise model keyed `path#language`: Canary for es/en, Parakeet for it/pt,
  told apart by its `joiner.int8.onnx` (`kindOf`)). With
  `precisePath`/`language` in the listen args the recording is kept in memory (`PcmBuffer`, 30 s max,
  never on disk, sent or logged) and `Refine` re-transcribes it on release (waits ≤ 3 s for a loading
  model): events `refining`, then `refined {text}` or `refine_failed {code: timeout|failed}`, between
  Vosk's `result`s and `done`; methods `deviceQualifies({minRamBytes?})` (Parakeet asks 5 GiB, else 3), `warmUp`/`isWarm` with `precisePath`/
  `language`, `releaseModels` frees both. `CanaryRecognizer` and `ParakeetRecognizer` are in `src/precise` only. Passkeys: androidx.credentials.

## iOS (`ios/`)

- `ios/Runner/`: one Swift folder per channel, all registered in `AppDelegate.swift`
  `registerChannels(messenger:)` (called from `didInitializeImplicitFlutterEngine`); names match the
  Dart constants, as on Android. The app uses a UIScene `SceneDelegate` (a `FlutterSceneDelegate`),
  so a link arriving on a scene reaches Dart through `LaunchSceneHandler` (in `Launch/`), not
  through `AppDelegate`.
  - `Device/`: `wambito/device` (`timeZone`, `openUrl`, `appVersion`, `excludeFromBackup`, and `widgetInstalled`/`widgetPinSupported`/`pinWidget`, always false); `Haptics/`: `wambito/haptics` (`vibrate`);
    `Sounds/`: `wambito/sounds` (`preload`, `play`); `Launch/`: `wambito/launch` (`take`, the
    `wambito://` links and the Universal Links of `app.wambito.com`); `Files/`: `wambito/files`
    (`pick`, `save`, `share`, `clearShared`: CSV import and export, share sheet);
    `Scanner/`: `wambito/scanner` (`isAvailable`, `scan`: `AVCaptureMetadataOutput` for `.qr`, full screen;
    `CameraAccess.state` in WambitoNative maps the permission; `NSCameraUsageDescription` in `InfoPlist.strings`);
    `Passkeys/`: `wambito/passkeys` (`isSupported`, `get`, `getAvailable`, `create`:
    AuthenticationServices); `Notices/`: `wambito/notices` (`scheduleDue`, `scheduleDueList`, `cancelDue`,
    `scheduleGuest`, `cancelGuest`, `permission`, `requestPermission`), local notices only
    (`UNUserNotificationCenter`; `KeychainSession` reads the session `flutter_secure_storage` keeps).
  - Words of the notices: `{es,en,it,pt}.lproj/Notices.strings`, generated from the Android
    `strings.xml` by `dart run scripts/gen-ios-strings.dart` (CI fails when stale; the scanner's two words too), so both phones say
    the same words. `InfoPlist.strings` are the permission texts. `PrivacyInfo.xcprivacy` and
    `Runner.entitlements` (Associated Domains for passkeys and links) live beside them.
  - Adding a channel: a Swift file per area under `ios/Runner/`, one `private var` and one line in
    `registerChannels`. The Runner target is not a synchronized folder group: add every new file by
    hand to `ios/Runner.xcodeproj/project.pbxproj` (file reference, group per area, build file, the
    Sources or Resources phase), IDs unique (grep first).
- `ios/WambitoNative/`: Swift package with the logic that needs no UIKit (`NoticeTimes`, `DueToday`, `DueSchedule`,
  `LaunchLinks`, `ExternalLinks`, `FileTransfer`, `HapticSpec`, `WebAuthnJSON`); the Runner imports
  it. Put new pure logic here with a test in `Tests/WambitoNativeTests/` (`swift test`); a channel
  file stays a thin wrapper. Dart twins (`launch_links.dart`, notice times) are pinned by the same
  cases.
- Signing: the team id lives only in `ios/Flutter/Signing.xcconfig` (git-ignored; copy
  `Signing.xcconfig.example`), never in the pbxproj: `scripts/check-ios-signing.sh` (tested by
  `scripts/test-check-ios-signing.sh`) fails on a team id there or a tracked `Signing.xcconfig`.
  `ios/ExportOptions.plist` is for the release; `.github/workflows/ios-release.yml` builds on a
  `mobile-v*` tag and uploads to App Store Connect (`docs/mobile/ios.md`).
- Native channels on both phones: `scripts/check-channels.sh` (repo root; CI `check`) fails when a
  channel or method Dart calls is missing from the Kotlin or the Swift side; what one phone cannot
  have is listed with a reason in `.github/channel-allowlist.txt` (`ios-impossible`, `ios-part-two`,
  `android-only`).
- iOS lacks, by design: automatic capture (`wambito/capture`, no API for it), widgets (the setting
  is hidden on iOS), and voice until part two (`wambito/voice*`). Dart hides them when the channel
  or platform is absent.
- `ios/**` is in `analysis_options.yaml`'s excludes (Flutter writes it on every `pub get` once `ios/`
  exists; keep it committed). Do not run `flutter create` again.

## Generated

- See root `AGENTS.md` (`lib/api/gen`, `tokens.g.dart`, l10n). `scripts/gen-api.sh` needs root
  `pnpm install`, JDK 17, Flutter. ARBs `lib/l10n/app_{es,en,it,pt}.arb`, es is the template.

## Commands (from `apps/mobile`, `export PATH="$HOME/development/flutter/bin:$PATH"`)

- `flutter pub get --enforce-lockfile`, `flutter analyze`, `flutter test --exclude-tags golden,stack` (CI).
- Goldens: `flutter test --tags golden` (`--update-goldens`); on macOS without PingFang set
  `PARITY_PINGFANG` to a `PingFang.ttc` (see `test/support/parity.dart`). CI skips goldens.
- Parity (`docs/mobile/parity.md`, list `test/parity/parity.json`): `pnpm --filter @wambito/web
  parity:fixtures|parity:shots [id]`, `flutter test --update-goldens test/parity`,
  `dart run tool/parity/compose.dart --max 2 [id]`. Known difference: the phone's signed-out email step
  (`signin-*` masters) ends with the "Sign in with my recovery key" link; the web's story gets it with the web
  delivery of phone-first accounts.
- Kotlin: `cd android && JAVA_HOME=<JDK 17> ./gradlew :app:testDebugUnitTest --console=plain`.
- iOS (macOS, Xcode): `swift test --package-path ios/WambitoNative`; unsigned build `flutter build ios
  --release --no-codesign`; `scripts/check-ios-signing.sh`, `scripts/test-check-ios-signing.sh`;
  `dart run scripts/gen-ios-strings.dart` after changing a notice string; `../../scripts/check-channels.sh`.
  CI's `ios` job runs the signing guard, `swift test` and the unsigned build. On a device: set
  `Signing.xcconfig`, then `xcodebuild … -destination id=<device> -allowProvisioningUpdates build`.
- Integration tests (emulator + root dev stack): `scripts/run-integration-tests.sh`.
- The vault against the real API (no emulator; root dev stack up with `cp -n .env.example .env; docker compose up -d`,
  and `docker compose up -d --build api` after the API code changed: a stale image 404s the newer routes):
  `scripts/run-vault-e2e.sh` runs two stack tests one after the other (they share the account), each after
  `seed:e2e-preview` in the api container: `test_stack/vault_e2e_test.dart` (tag `stack`: sign in with the Mailpit
  code, set up through `VaultGate`, add a movement, sync, a second empty phone unlocks with the recovery key) and
  `test_stack/vault_3b_e2e_test.dart` (stage 3b: phone B pairs through `/v2/pairing` (`startPairing`, `findPairing` +
  `approve`); `runBackground` on A saves a queued capture with its `Idempotency-Key` and B syncs and reads it; A
  removes B with `TypedRecovery`, a background sync re-seals under the new key version and B's next sync ends
  `deviceRemoved`; `newRecoveryKey` + `commit` signs in on `/v2/recovery/sign-in` and the old key gets 401
  `recovery_key_invalid`; then, on the same account and phone A, a new phone C pairs, a delete on A is restored
  on C through `POST /v1/transactions/{id}/restore` and A sees it live, and an old client's delete (pushed with
  `body: null`) is `not_found` on C). `test_stack/support.dart` holds the shared phone, gate and sign-in helpers; a vault
  session is one per process and account, so only one phone has its session open at a time. After each it checks
  with `psql` that `preview-e2e` has records (> 0), no rows in `transactions` / `categories`, and that no
  `records.body` holds the test's word (`almuerzo`, `panaderia`) in the clear (must print 0; a byte search, as a
  sealed body is not UTF-8). Each test signs in with an email code and the API allows 5 per address in 10 minutes
  (in memory): after a third run, `docker compose restart api`. CI's `mobile-build` fails when a release APK
  lists `libsqlite3.so` (sqflite uses the system SQLite; the ffi dev dependency must stay out). `test_stack/` is outside `test/`, so `flutter test`
  never runs it; CI's `mobile-e2e` job does.
- Store listing images (emulator + root dev stack; `docs/mobile/play.md`): `tool/store_shots/run.sh`, then
  `node tool/store_shots/compose.cjs`.
- F-Droid (`docs/mobile/fdroid.md` explains the whole build):
  - `scripts/build-native-deps.sh --vosk-src <dir> --jna-src <dir> --ndk <NDK 28.2.13676358>
    [--abi <one ABI>] [--work <dir>]` builds Vosk and JNA from source (Linux x86_64 only, a
    linux/amd64 container on a Mac; 46 min with `--jobs 4`, about half with `--abi`) into
    `android/third_party/m2` (git-ignored). `scripts/test-build-native-deps-args.sh` (CI) tests
    its arguments.
  - The switch `-Pwambito.nativeFromSource=true` (`flutter build apk -P ...`, or, for `gradlew` and the check scripts,
    `env 'ORG_GRADLE_PROJECT_wambito.nativeFromSource=true' scripts/check-no-google.sh`; the name has
    a dot, so `export` and a bare `NAME=value` prefix do not work) takes
    those artifacts. ARM only, so off for the x86_64 emulator. `scripts/test-native-switch.sh`
    (CI) tests it.
  - The precise model on F-Droid (arm64-v8a only): `scripts/build-sherpa-onnx.sh --ndk <NDK 28.2.13676358>
    [--srclibs <dir>] [--work <dir>]` builds onnxruntime 1.28.2 and sherpa-onnx 2.0.1's JNI library
    from 24 pinned git checkouts (no network; about 80 min emulated) into
    `android/third_party/sherpa-onnx-src` (`jniLibs/`, the AAR's Kotlin API in `kotlin/`, `SOURCES`).
    `-Pwambito.preciseFromSource=true` (only with `wambito.nativeFromSource`) compiles and packs them
    with `src/precise` instead of `src/noPrecise`; no artifact, so the lockfiles do not change.
    `scripts/test-build-sherpa-onnx-args.sh` (CI) tests its arguments and pins; `test-native-switch.sh`
    the switch.
  - `scripts/package-canary.sh [--model canary|parakeet] [--check]` builds a precise model's zip for the voice-models-v2 release from sherpa-onnx's archive (not committed; prints its size and SHA-256; publish the zip from one run and pin that hash, `--check` proves reproducibility on one machine).
  - sherpa-onnx 2.0.1 (the precise voice model's runtime) for the Play and GitHub builds:
    `scripts/fetch-sherpa-onnx.sh` downloads its AAR, checks the pinned SHA-256 and installs it in
    `android/third_party/m2`; run it before any Gradle or `flutter build` (CI and `release.sh` do).
    `scripts/test-fetch-sherpa-onnx.sh` (CI) tests it offline. Code that uses `com.k2fsa.sherpa.onnx`
    goes in `android/app/src/precise/kotlin`, never in `src/main`: the F-Droid armeabi-v7a build swaps
    that folder for `src/noPrecise/kotlin` (stand-ins), and both define `voice.PreciseRuntime.linked`. Adds ~31 MB
    to the arm64 APK. `docs/mobile/setup.md` has the details.
  - Recipe: `fdroid/com.wambito.app.yml` is the source of truth, copied to fdroiddata when
    submitting; one build per ABI, srclibs in `fdroid/srclibs/*.yml`, natives built in `build:`
    (after F-Droid's source scan). Change it together with the revisions in `build-native-deps.sh`
    and `build-sherpa-onnx.sh` (`scripts/check-fdroid-recipe.sh`, CI, fails on drift from them and
    `.flutter-version`; the arm64-v8a entry lists the 24 sherpa-onnx sources, three of them
    fdroiddata's own srclibs). After
    submission fdroiddata's copy is the live one: such changes need their own fdroiddata merge
    request before tagging (`docs/mobile/fdroid.md`).
    `UpdateCheckData` reads `pubspec.yaml`'s version at a `mobile-v*` tag (`docs/mobile/release.md`).
    The text for the merge request is `fdroid/MERGE_REQUEST.md`.
  - `scripts/fdroid-build-local.sh <commit> [--version X.Y.Z] [--abi <one ABI>]` runs `fdroid
    lint`, `fdroid build` and `fdroid scanner` in F-Droid's buildserver image against a scratch
    copy of that commit (Docker, about an hour per ABI on 4 emulated cores; nothing is pushed).
  - Gradle locks: `android/app/gradle.lockfile`, and `gradle-fdroid.lockfile` for the switch.
    After changing a dependency, rewrite the first with `./gradlew :app:dependencies --write-locks`
    and the second with the `sed` in `docs/mobile/setup.md` ("Dependency locks"; no native build; it also drops
    the sherpa-onnx line),
    and commit both. `scripts/check-gradle-locks.sh` (CI) checks the first; `scripts/check-fdroid-lock.sh`
    (CI, text only) checks that the second is the first with the two `-src` substitutions and no sherpa-onnx line.
  - The Gradle wrapper jar is committed: the official one for the version in
    `gradle-wrapper.properties`.
- Release self-tests: `scripts/test-release.sh`, `scripts/check-fastlane.sh` (the five listings: texts,
  changelog ≤500 bytes with the same version codes in all, screenshots and feature graphic), `scripts/check-permissions.sh`.
- Google Play: `scripts/release.sh --play` also builds `wambito-<version>.aab` (versionCode base × 10 + 0),
  signed with `jarsigner` by the upload key (`WAMBITO_UPLOAD_KEYSTORE`, `_KEY_ALIAS`, `_KEYSTORE_PASSWORD`,
  `_KEY_PASSWORD`), never the app key (refused); read back with `aapt2` (the base module
  as a proto APK, `release_aab_base_apk`). Play App Signing holds the app key (handed over once with PEPK), so the
  Play build shares the APK's signature. Console forms and steps: `docs/mobile/play.md`.

## Traps

- Vault holds: `meta.hold` in a vault file (`VaultHold`: `provisional`, `orphaned`, `merging`;
  `SqliteStore.hold()/setHold()`, read-only `vaultHoldOf`, `listVaultHolds` for resumes: returns `(holds:, unreadable:)`, a vault file whose hold cannot be read is listed in `unreadable`, never dropped; `hold()` throws on a malformed hold). The
  stale-vault sweep skips a held vault, file and keys; clear the hold when the work is done.
- `wambito.vault.<anonId>.mergeToken` (secure storage): the anonymous session's token while its vault is merged
  into an email account (swept with that vault's keys); and meta keys `mergeCarried` (the carry committed) and
  `mergeDiscard` (only the account's data kept) in that vault; `wambito.capture.handover` (secure storage, the
  captures a new session takes over from another account); the merge namespace `mergeNamespace` in
  `lib/local/merge.dart` (merged ids derive from it).
- `wambito.seen.<userId>` (secure storage) is the last local day the app pinged `/v2/me/seen` for that account.
- `wambito.adopt.token` (secure storage, `adoptTokenKey`): the token of the new anonymous user a deleted account's
  vault is adopted into, kept from its sign-up until the session is that user's. Outside `wambito.vault.*` on
  purpose: the old vault's keys go before the session changes, and a sweep must never take it.
- See root `AGENTS.md`: money slang, the signing key's alias, secrets (the keystore too). Here
  the slang lives in `lib/capture/parser/`, `lib/capture/engine/`, `lib/money/format.dart` and the ARBs.
- Persistent state on phones: prefs file names, WorkManager unique names (`wambito.widget.refresh`,
  `wambito.widget.midnight`, `wambito.notice.due`, `wambito.notice.guest`, `wambito.capture.send`,
  `wambito.capture.confirm.<id>`; the old shared `wambito.capture.confirm` chain is only cancelled,
  at every Bien; prefs `wambito.capture.queue`, `wambito.capture.sources`; secure-storage keys `wambito.widgetCard.closed`, `home.protect.<userId>` and `wambito.protect.<userId>.keyAfterClaim`; channel
  `wambito.capture`; listener class `com.wambito.app.capture.CaptureListener`), widget receiver classes
  (renaming removes placed widgets), the snapshot key. Changing any needs a migration. Stage 3b added:
  Dart entry points `syncMain` / `captureMain`; channels `wambito/background` and `wambito/scanner`;
  WorkManager works `wambito.sync.periodic` and `wambito.sync.now`; iOS task id `wambito.sync`
  (`BGTaskSchedulerPermittedIdentifiers`) and pending notice ids `wambito.due.<yyyy-MM-dd>`; prefs file
  `wambito.notice.duelist`; key `wambito.encryption.owner` in `wambito.encryption`; key `confirms` in
  `wambito.capture.queue`; the snapshot's `owner` field; the lock file `wambito-vault-<userId>.db-lock`; the
  merchant record id `uuidv5(uuidv5(seedNamespace, userId), "merchant:<key>")`.
- The due list (`lib/background/due_effect.dart`) belongs to the headless run for a `preview` account (14 days at
  9:00 local, written to `wambito.notice.duelist`; `DueWorker` / iOS `DueTask` only read it and never call the API),
  and the widget snapshot belongs to the vault (`writeVaultWidget`, `widget_effect.dart`), never to the `/v1` caches.
- No `gradlew` is tracked; Kotlin-only runs can skip the Flutter compile with `-x compileFlutterBuildDebug`.
- Never block on a WorkManager future (`.get()`) in code a Worker runs: deadlocks in tests.
- `test/tooling/*` reads Android files; `widget_android_test.dart` there pins Dart = Kotlin.
- `manifest_test` counts `android:host="due"` once (only `wambito://` links).
- About 55 goldens already fail on the founder's Mac: compare with the base first. Regenerated
  parity fixtures change millisecond timestamps: keep only the intended diff.
