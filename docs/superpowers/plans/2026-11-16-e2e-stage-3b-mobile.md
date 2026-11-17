# E2E Stage 3b (the rest of the phone) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Everything 3a left as "Coming soon with encryption" on the phone works for a `preview`
account, with no finance field ever sent in clear: Android automatic capture, the home widget, due
notices, background sync, QR pairing both ways, Settings → Security, and the screen lock for
sensitive operations.

**Architecture:** Background work runs the same Dart code as the app. Android workers and the iOS
`BGAppRefreshTask` start a headless Flutter engine on a Dart entry point (`syncMain`,
`captureMain`) that opens the vault through a second SQLite connection, takes a lease file in the
vault folder (one sync at a time across the app and the workers), writes through the 3a local
backend, syncs once, then writes the widget snapshot and the due-notice list that the native side
only reads. Rotation, new recovery key and pairing are ports of `apps/web/app/local/rotate.ts` and
`pairing.ts`; Settings → Security is the twin of the web's `features/settings/security*.ts`.

**Tech Stack:**
- Flutter and Dart, Riverpod 3, Dio, go_router; 3a's `lib/local`, `lib/crypto`, `lib/core`, `lib/vault`;
- new Dart packages: `local_auth` (screen lock), `qr_flutter` (draws the pairing QR), `unorm_dart`
  (NFD for `merchantKey`);
- Android: WorkManager, a headless `FlutterEngine`, CameraX + ZXing core (`com.google.zxing:core`)
  for scanning;
- iOS: `BGTaskScheduler`, a headless `FlutterEngine`, AVFoundation for scanning,
  `UNCalendarNotificationTrigger` for due notices.

**Spec:**
- `docs/superpowers/specs/2026-11-12-e2e-stage-3-mobile-design.md`, section 7 (delivery 3b), with
  sections 8 and 9;
- `docs/superpowers/specs/2026-11-15-phone-first-accounts-design.md`, only what it asks of 3b:
  section 11 (3b in full, the sealed `merchant` record with `merchantKeyPrefixes`), section 6 (the
  recovery verifier whenever a recovery wrap is made or replaced) and section 5.2 (a passkey
  protects only with a wrap).

## Global Constraints

- **Branch and PR:** branch `feat/e2e-stage-3b-mobile` from `main`, one PR. Merging deploys the
  server, so merge only on the founder's yes.
- **Scope:** a `plain` account behaves exactly as today; every existing test stays green unchanged
  unless a task names it. Nothing of phone-first delivery 2 (see Decisions, D20).
- **Port rule (as 3a):** each Dart file mirrors its TypeScript twin; same behaviour, same error
  codes, same test case names. When the TS and this plan disagree, the TS wins; write the ruling
  in the PR body.
- **Never in clear:** for a `preview` account no native code calls `/v1` finance routes
  (`CaptureApi`, `SummaryFetcher`, `NoticeApi.dueToday`), and no background Dart sends a finance
  field outside a sealed `/v2/sync` body.
- **Money:** integer cents (`int` in Dart, `Long` in Kotlin), never a float. Fixtures invented.
- **New persistent names** (never renamed later without a migration):
  - Dart entry points `syncMain`, `captureMain` (in `lib/main.dart`);
  - channels `wambito/background` (both phones), `wambito/scanner` (both phones);
  - WorkManager unique works `wambito.sync.periodic` (every 6 h, network) and `wambito.sync.now`
    (one-off, no constraint);
  - iOS `BGTaskSchedulerPermittedIdentifiers` entry `wambito.sync`;
  - prefs file `wambito.notice.duelist` (Android); prefs key `wambito.encryption.owner` in the
    existing `wambito.encryption` file / UserDefaults; key `confirms` in the existing
    `wambito.capture.queue` prefs;
  - widget snapshot field `owner` (snapshot stays `v: 3`);
  - lock file `wambito-vault-<userId>.db-lock` in the vault folder;
  - iOS pending notification ids `wambito.due.<yyyy-MM-dd>`;
  - merchant record id `uuidv5(uuidv5(seedNamespace, userId), "merchant:<merchantKey>")`.
- **Existing persistent names stay:** `wambito.encryption.mode`, `wambito.widget.snapshot`,
  `HomeWidgetPreferences`, `wambito.capture.send`, `wambito.capture.confirm.<id>`,
  `wambito.notice.due`, widget receiver classes, `com.wambito.app.capture.CaptureListener`.
- **Crypto:** any new derivation goes through `hkdfKey` / `hkdfBytes` (`lib/crypto/keys.dart`,
  32-zero-byte salt, because Android's native HMAC refuses an empty key). Bytes are `Uint8List`,
  base64url without padding. Secrets and data keys are zeroed in `finally`.
- **Timings:** background engine budget 9 minutes on Android (WorkManager's limit is 10), 25 seconds
  on iOS; lease TTL 10 minutes; the app waits at most 30 seconds for a lease; due list covers 14
  days at 9:00 local; pairing polls every 1.5 s and lives 10 minutes; capture duplicate window 10
  minutes.
- **Dependencies:** pinned exactly (no `^`), latest stable when added; `scripts/check-no-google.sh`,
  `scripts/check-licenses.sh`, `scripts/check-gradle-locks.sh`, `scripts/check-fdroid-lock.sh` and
  `scripts/check-permissions.sh` pass. After a Gradle change: rewrite `gradle.lockfile`, then
  `gradle-fdroid.lockfile` with the `sed` of `docs/mobile/setup.md`, and regenerate
  `assets/licenses/android-libraries.json` with `dart run scripts/gen-android-licenses.dart`.
- **Channels:** every new `wambito/*` channel and method exists in Kotlin and Swift
  (`scripts/check-channels.sh`); only `wambito/capture` stays allowlisted (`ios-impossible`).
- **iOS files:** each new Swift file is added by hand to `ios/Runner.xcodeproj/project.pbxproj`
  (unique ids); pure logic goes in `ios/WambitoNative` with a `swift test`.
- **Copy:** words come from the web (`apps/web/app/i18n/messages/*`, Security and vault keys) into
  `lib/l10n/app_{es,en,it,pt}.arb` (es is the template); native notice words in Android
  `strings.xml`, then `dart run scripts/gen-ios-strings.dart`; permission texts in
  `ios/Runner/*.lproj/InfoPlist.strings`. Money slang rule of the root `AGENTS.md` applies.
- **No API change:** the routes 3b uses exist (`/v2/keys`, `/v2/keys/rotate`, `/v2/pairing*`,
  `/v2/recovery/verifier`). No `CHANGELOG.md` line and no `lib/api/gen` regeneration. A task that
  finds it needs one stops and adds the line with that change.
- **Commits:** `feat(mobile): …`, `feat(android): …`, `feat(ios): …`, `test(core): …`, `docs: …`,
  a lowercase sentence; stage by path; never a `Co-Authored-By` line.
- **Commands:**
  - `apps/mobile`, with `export PATH="$HOME/development/flutter/bin:$PATH"`: `flutter analyze`,
    `flutter test --exclude-tags golden,stack`;
  - Kotlin: `cd apps/mobile/android && JAVA_HOME=<JDK 17> ./gradlew :app:testDebugUnitTest --console=plain`;
  - Swift: `swift test --package-path apps/mobile/ios/WambitoNative`;
  - root: `pnpm lint`, `pnpm test`, `scripts/check-channels.sh`.
- **Merge gate (manual, not a task step):** Task 1's report shows the shared vectors passing on a
  real iPhone with the native implementation, and the PRF spike run on the founder's Android phone
  and iPhone; then a `preview` pass on both phones (checklist in Task 17).

## Decisions

What the specs leave open or the code forces, decided here (one line each):

- **D1 Capture parsing.** Spec 7.1 says `captureMain` "parses with the same parser", but Kotlin
  already queues parsed `ParsedCapture`s (the notification text is never stored): Dart reads the
  parsed items and does not parse again.
- **D2 Capture save.** `captureMain` writes through a new phone-only local route
  `POST /v1/captures`, a port of `apps/api/src/services/captures.ts` `saveCapture` (10-minute
  duplicate window, merchant memory, fallback category) answering the API's `CaptureResult` shape,
  so Kotlin's notification code reads it unchanged.
- **D3 Merchant memory.** The sealed `merchant` record (phone-first 11), id
  `uuidv5(uuidv5(seedNamespace, userId), "merchant:<key>")` so devices converge on one record; it is
  learned where the API learns (`learn`: review, and a PATCH that confirms a `capture` row), and
  read with `[key, ...merchantKeyPrefixes(key)]`, longest first. The web backend gets the same
  rule in stage 4; this plan pins it with a shared fixture.
- **D4 NFD in Dart.** Dart has no Unicode normalization: `unorm_dart` (MIT, pure Dart) gives NFD;
  marks are stripped with `RegExp(r'\p{M}', unicode: true)`.
- **D5 One sync at a time across engines.** A headless engine runs in the app's process, where
  POSIX record locks (`RandomAccessFile.lock`) do not exclude another isolate, so the lock file is a
  lease made with `File.create(exclusive: true)` holding `{holder, expiresAt}`; an expired lease is
  taken over by an atomic `rename` to a unique name, then a new exclusive create.
- **D6 Second connection.** Android sqflite keeps single-instance databases in a static map shared
  by every engine in the process, so a background `close()` would close the app's database: the
  background engine opens with `singleInstance: false`, and both connections set
  `PRAGMA busy_timeout = 5000`.
- **D7 App told of background writes.** When a headless run ends with `changed`, native code calls
  `vaultChanged` (native → Dart) on `wambito/background` of the app's engine if it is alive; the
  open `VaultSession` re-notifies its listeners and schedules a sync.
- **D8 Capture queue for `preview`.** 3a's `CaptureListener` early return for `preview` and
  `previewSyncProvider`'s one-time `clearQueue()` go; `preview` uses `sendQueued(userId)` as
  `plain` does (the queue is owner-tagged). The headless engine reads and acknowledges the queue
  over `wambito/capture` (`takeQueued`, `ackQueued`), which stays Android-only.
- **D9 Bien for `preview`.** `ConfirmCaptureWorker` appends the id to the queue's `confirms` and
  runs `captureMain`, which posts `/v1/transactions/review` locally; a 404 is dropped (as the 4xx
  rule today).
- **D10 Widget ownership.** The snapshot gains `owner` (the user id; v stays 3, readers ignore
  unknown fields) and `setEncryptionMode` gains `owner`; a native reader that finds
  `snapshot.owner != AccountMode.owner` writes the signed-out snapshot.
- **D11 Widget refresh.** For `preview`, `RefreshWorker` (periodic and midnight) asks
  `wambito.sync.now` and makes no API call; `syncMain` recomputes the snapshot from the vault even
  offline.
- **D12 Due list.** Dart sends `scheduleDueList {zone, language, days: [{date, names}]}` on
  `wambito/notices`, 14 days, replaced whole each time (never merged). Android stores it in prefs
  `wambito.notice.duelist` and `DueWorker` posts today's entry at 9:00; iOS removes every pending
  `wambito.due.*` request and adds one `UNCalendarNotificationTrigger` per day at 9:00.
- **D13 Backups.** `HomeWidgetPreferences.xml` and `wambito.notice.duelist.xml` join the excluded
  paths in `backup_rules.xml` and `data_extraction_rules.xml`: for `preview` they hold figures and
  payment names.
- **D14 Background network.** The headless Dio sends `x-wambito-background: 1` (never counts as
  activity), `x-wambito-client` as `lib/api/device.dart` says, and `x-wambito-user` on `/v2`.
- **D15 Removal and the recovery wrap.** A rotation needs the recovery secret or a fresh one, and the
  phone keeps neither: after the screen lock, the removal sheet offers "Type your recovery key"
  (re-wrapped, kept) or "Make a new recovery key" (shown with 3a's setup view), as the web's
  `RemoveDeviceSheet`. The screen lock replaces the web's passkey touch as confirmation.
- **D16 Verifier.** The server deletes the verifier when a recovery wrap is replaced and keeps it on
  a rotation, so the phone `PUT`s `/v2/recovery/verifier` after: a non-guest `prepareAccount`
  commit, `newRecoveryKey`, a rotation with a fresh key, and (best effort) every successful
  `unlockWithRecovery` (phone-first 6: accounts made before it get one). A guest's hidden key never
  gets one.
- **D17 "Showing" the recovery key** (spec 7.7). The phone never keeps the secret, so the only
  showing is a new key's setup screen; the screen lock is asked before it appears.
- **D18 Screen lock.** `local_auth` as the spec says; it needs `FlutterFragmentActivity` (today
  `MainActivity` extends `FlutterActivity`) and `USE_BIOMETRIC`, which the manifest removes today
  (`tools:node="remove"`): both change in Task 15.
- **D19 Camera and QR.** Scanning is an in-house `wambito/scanner` channel: Android CameraX
  (`androidx.camera:camera-camera2`, `camera-lifecycle`, `camera-view`, Apache-2.0) with
  `com.google.zxing:core` (Apache-2.0, plain Java on Maven Central) decoding the luminance plane;
  iOS `AVCaptureMetadataOutput` (system). Why: `mobile_scanner` uses ML Kit (`com.google.mlkit`,
  banned by `check-no-google.sh` and F-Droid); `flutter_zxing` adds a C++ build to the F-Droid
  recipe; CameraX's ML Kit analyzer (`camera-mlkit-vision`) is banned. `com.google.zxing` matches no
  `BANNED` pattern, and the typed code stays as fallback. Drawing the QR uses `qr_flutter`
  (BSD-3, pure Dart).
- **D20 Phone-first delivery 2 is not here.** Left to it: first run, nudges and the home card,
  adding an email and the merge, recovery-key sign-in, the web-QR (`/v2/signin`) approval screen
  and sign-in notice, the `user_deleted` adoption. 3b provides for it: `newRecoveryKey` with the
  verifier (its step 1), `putRecoveryVerifier`, `hasPasskeyWrap` (its step 2 check), the scanner
  channel and `ApproveDeviceScreen` pattern, background sync, and Settings → Devices (which will
  list browsers).
- **D21 Pairing number.** As the web's `pairing.ts`: both devices show the 6-digit number, QR or not.
- **D22 Entry points.** `syncMain` and `captureMain` live in `lib/main.dart` with
  `@pragma('vm:entry-point')` (the default library both engines resolve); their bodies are in
  `lib/background/`.
- **D23 Engine failure.** A headless run that ends in anything but `done`/`changed` (or times out)
  leaves the queue as it was; `SendCapturesWorker` returns `Result.retry()` up to `MAX_ATTEMPTS`
  (8), then `success("kept")` with the items still queued (the next capture, app start or sync
  enqueues it again). Never dropped, never sent.

## Review Focus

1. **The headless engine fails or is killed mid-capture.** The capture stays queued and is retried;
   it is never dropped and never posted to `/v1/captures` on the server. Pinned in Task 5 (ack only
   after the store commit) and Task 7 (worker never calls `CaptureApi` for `preview`).
2. **Two syncs at once between the app and a worker** (app open while the periodic job fires).
   Exactly one holds the lease; the other reports `busy` and touches neither outbox nor cursor; the
   app's database survives the worker's close. Pinned in Task 4.
3. **The widget shows another account's figures** (sign-out and another sign-in while a worker
   runs, or a snapshot left from the previous owner). Pinned in Task 9 (Dart writes only for the
   current owner; Kotlin blanks a snapshot whose `owner` differs).
4. **A due notice for a rule deleted on this phone or synced as deleted.** The list is replaced
   whole after every local write and sync; a deleted rule's name is gone from the next 9:00. Pinned
   in Task 10.
5. **A device removal that locks out this phone** (removing itself, the server not listing this
   phone's wrap, an answer lost after the server committed). This phone's wrap is always in the
   rotation and a lost answer is recognised as ours. Pinned in Task 12.

---

### Task 1: Native crypto on an iPhone, and the PRF spike

**Files:**
- Create: `apps/mobile/test/crypto/vector_cases.dart` (the assertions of `vectors_test.dart`, moved);
  `apps/mobile/integration_test/crypto_vectors_test.dart`; `apps/mobile/scripts/run-native-vectors.sh`.
- Modify: `apps/mobile/test/crypto/vectors_test.dart` (calls `defineVectorTests`).
- Report: `docs/superpowers/reports/2026-11-16-e2e-mobile-native-checks.md`.

**Interfaces:**
- Produces: `void defineVectorTests(Map<String, Object?> vectors)` in `test/crypto/vector_cases.dart`.

- [ ] **Step 1: Move the assertions.** `vectors_test.dart` loads the JSON by relative path as today
  and calls `defineVectorTests(json)`. Run `flutter test test/crypto/vectors_test.dart`. Expected:
  PASS, the same test names as before.
- [ ] **Step 2: Write the device test.** `crypto_vectors_test.dart` calls
  `FlutterCryptography.enable()`, decodes `const String.fromEnvironment('WAMBITO_VECTORS')`
  (base64 of the file; fails with "WAMBITO_VECTORS not set" when empty) and calls
  `defineVectorTests`. The vectors are passed at run time, never copied into the repo.
- [ ] **Step 3: Write `run-native-vectors.sh <device-id>`:** runs
  `flutter test integration_test/crypto_vectors_test.dart -d "$1" --dart-define=WAMBITO_VECTORS=$(base64 < ../../packages/crypto/test-vectors.json | tr -d '\n')`.
  Run it on the iOS simulator. Expected: PASS.
- [ ] **Step 4: Commit:** `test(mobile): run the shared crypto vectors on a device`.
- [ ] **Step 5: Founder checkpoint (do not wait; go on with Task 2).** Ask the founder to run the
  script on the iPhone and the Android phone, and the `/debug/prf` probe (3a Task 1) on both. Write
  the report: device, OS version, vectors PASS/FAIL, PRF stable across two reads, equal to the
  web's fingerprint. Commit it as `docs: report the native crypto and prf checks`. A PRF failure on
  one platform does not block 3b (spec 3), but is a merge-gate item.

### Task 2: Merchant key and prefixes in Dart, with a shared fixture

**Files:**
- Create: `packages/core/fixtures/merchant-memory.json`; `apps/mobile/lib/core/capture.dart`.
- Modify: `packages/core/src/fixtures.test.ts`; `apps/mobile/pubspec.yaml`, `pubspec.lock`
  (`unorm_dart`); `apps/mobile/test/core/fixtures_test.dart`.

**Interfaces:**
- Produces (`lib/core/capture.dart`, twin of the used part of `capture.ts`):
  - `String merchantKey(String merchant)`, throws `FormatException` for a merchant with no letters
    or digits;
  - `String? merchantKeyOrNull(String merchant)` (the API's `keyOf`);
  - `List<String> merchantKeyPrefixes(String key)`;
  - `const Map<String, ({String expense, String income})> fallbackCategoryNames` (es, en, it, pt);
  - `const captureDuplicateWindow = Duration(minutes: 10)`.

- [ ] **Step 1: Write the fixture and its TS test.** At least 10 `merchantKey` cases (accents
  `"Café Ñandú"` → `"cafe nandu"`, digits-only tokens dropped `"LIDL 0423 Casal Ribeiro"` →
  `"lidl casal ribeiro"`, punctuation, `"   "` → `{"throws": true}`) and 5 `merchantKeyPrefixes`
  cases (`"lidl casal ribeiro"` → `["lidl casal","lidl"]`, `"el corte ingles"` → `[]`, a one-word
  key → `[]`). Values from running the TS functions.
- [ ] **Step 2: Run** `pnpm --filter @wambito/core test`. Expected: PASS.
- [ ] **Step 3: Add the Dart group** in `fixtures_test.dart` reading the same file. Run
  `flutter test test/core/fixtures_test.dart`. Expected: FAIL (no `lib/core/capture.dart`).
- [ ] **Step 4: Implement `lib/core/capture.dart`** (NFD from `unorm_dart`, D4).
- [ ] **Step 5: Run** the Dart test, then `scripts/check-no-google.sh`. Expected: PASS, exit 0.
- [ ] **Step 6: Commit:** `feat(mobile): port the merchant key and its prefixes to dart`.

### Task 3: Local capture save and the merchant memory

**Files:**
- Modify: `apps/mobile/lib/local/backend.dart` (route `POST /v1/captures`; `learn` in
  `_reviewTransactions` and `_updateTransaction`); `apps/mobile/lib/local/backend_interceptor.dart`
  (serves the route); `apps/mobile/lib/local/ids.dart` (`seedNamespace`, moved from
  `vault_session.dart`'s `_seedNamespace`, same value).
- Create: `apps/mobile/lib/local/captures.dart`.
- Test: `apps/mobile/test/local/captures_test.dart`.

**Interfaces:**
- Consumes: Task 2.
- Produces:
  - `const seedNamespace` in `lib/local/ids.dart`;
  - `String merchantRecordId(String userId, String merchantKey)` in `lib/local/captures.dart`;
  - `POST /v1/captures` on the local backend, body as `createCaptureSchema`
    (`kind`, `amount` cents > 0, `currency`, `merchant`, `capturedAt`, `source`), answers
    `{result: "created"|"merged", transaction, category: {name, fallback}}` with 201 / 200, 422
    `validation_failed` otherwise.

- [ ] **Step 1: Write the failing tests,** porting the cases of `apps/api/test/captures.test.ts`
  that do not involve auth: created row has `source: "capture"`, `needsReview: true`,
  `captureMerchantKey`, signed amount (`-1250000` for an expense of `1250000`); a second capture of
  the same amount, currency and note within 10 minutes is `merged` (200, same id); outside the
  window it is `created`; a foreign currency puts `"12.50 USD"` in the note; the fallback category
  `"Otros gastos"` (`systemKey: "other"`) is created once; a learned `"lidl"` gives
  `"lidl casal ribeiro"` its category; an archived learned category falls back. Learning:
  `POST /v1/transactions/review` of a capture row writes a `merchant` record with id
  `merchantRecordId(userId, key)` and `{s: 1, merchantKey, categoryId}`; a fallback or archived
  category is not learned; a PATCH with `needsReview: false` and a new `categoryId` learns that
  category.
- [ ] **Step 2: Run** `flutter test test/local/captures_test.dart`. Expected: FAIL (404 from
  `handle`).
- [ ] **Step 3: Implement** the route and `learn` in `backend.dart`, one store transaction per
  request as the other routes; the `merchant` writes go through the store's normal `put` (outbox).
- [ ] **Step 4: Run** `flutter test test/local`. Expected: PASS, `backend_shapes_test.dart`
  unchanged.
- [ ] **Step 5: Commit:** `feat(mobile): save captures and learn merchants in the vault`.

### Task 4: The vault lease and the background connection

**Files:**
- Create: `apps/mobile/lib/local/vault_lock.dart`.
- Modify: `apps/mobile/lib/local/db.dart` (`openVault` `singleInstance`, `busy_timeout`,
  `deleteVault` deletes the lock file); `apps/mobile/lib/local/sqlite_store.dart`
  (`SqliteStore.open(userId, {background})`, `notifyExternalChange()`);
  `apps/mobile/lib/local/sync.dart` (lease around a run, `SyncProblemCode.busy`);
  `apps/mobile/lib/local/stale_vaults.dart` (`_vaultFile` also matches `-lock`);
  `apps/mobile/lib/local/vault_session.dart` (`externalChange()`).
- Test: `apps/mobile/test/local/vault_lock_test.dart`, `test/local/sqlite_two_connections_test.dart`,
  additions to `test/local/sync_test.dart` and `test/local/stale_vaults_test.dart`.

**Interfaces:**
- Produces:
  - `String vaultLockFileName(String userId)` = `'wambito-vault-$userId.db-lock'`;
  - `abstract interface class VaultLease { Future<void> release(); }`;
  - `Future<VaultLease?> tryLease(String userId, {required String holder, String? directory, Duration ttl = const Duration(minutes: 10), DateTime Function()? now})`;
  - `Future<VaultLease?> waitLease(String userId, {required String holder, Duration wait = const Duration(seconds: 30), String? directory})`;
  - `SyncProblemCode.busy` (wire `busy`): the run did nothing because another holder has the lease;
    the triggers retry it like `offline`;
  - `SyncEngineOptions.lease`: `Future<VaultLease?> Function()?` (null option = no lease, as tests
    of 3a);
  - `Future<SqliteStore> SqliteStore.open(String userId, {String? directory, DatabaseFactory? factory, bool background = false})`
    (`background` opens with `singleInstance: false`);
  - `void SqliteStore.notifyExternalChange()` and `void VaultSession.externalChange()` (notify
    subscribers, then `afterLocalWrite`).

- [ ] **Step 1: Write the failing lease tests.** `two isolates race for one lease`: two
  `Isolate.run` calls `tryLease` on one temp folder at once; exactly one gets a lease.
  `an expired lease is taken over once`: a lease file with `expiresAt` in the past; two takers;
  exactly one wins. `release deletes the file` and `a live lease is not taken`.
- [ ] **Step 2: Write the failing connection test.** Two `SqliteStore.open(..., background: true)`
  and one default on the same file (ffi): concurrent `transaction` writes on both, no
  `database is locked`; closing the background one leaves the other usable (a read after it).
- [ ] **Step 3: Write the failing sync test.** `a run while another holder has the lease is busy`:
  `lease` returns null; the result is `ok: false, error: busy`; the outbox and `meta` cursor are
  unchanged and no `/v2` call left (fake `/v2` counts zero).
- [ ] **Step 4: Run** `flutter test test/local/vault_lock_test.dart test/local/sqlite_two_connections_test.dart test/local/sync_test.dart`.
  Expected: FAIL.
- [ ] **Step 5: Implement** (D5, D6). The app's `openVaultSession` passes
  `lease: () => waitLease(userId, holder: 'app')`; `_locked` stays inside it for the process.
  `stale_vaults` sweeps the lock file with its vault; `deleteVault` deletes it.
- [ ] **Step 6: Run** `flutter test test/local`. Expected: PASS.
- [ ] **Step 7: Commit:** `feat(mobile): one vault sync at a time across engines`.

### Task 5: The background run in Dart (`syncMain`, `captureMain`)

**Files:**
- Create: `apps/mobile/lib/background/background_run.dart`, `lib/background/background_main.dart`,
  `lib/background/background_channel.dart`, `lib/background/queued_capture.dart`.
- Modify: `apps/mobile/lib/main.dart` (the two entry points); `lib/capture_auto/capture_platform.dart`
  (`takeQueued`, `ackQueued`).
- Test: `apps/mobile/test/background/background_run_test.dart`, `test/background/queued_capture_test.dart`.

**Interfaces:**
- Consumes: Tasks 3, 4; 3a `EncryptionStore.recall`, `loadLocalKeys`, `createSyncEngine`,
  `createLocalBackend`, `refreshKeys`.
- Produces:
  - `enum BackgroundOutcome { done, changed, signedOut, notPreview, locked, busy, failed }` (wire =
    `.name`);
  - `class QueuedCapture { key, kind, amount (int cents), currency, merchant, capturedAt, source }`
    with `fromJson` reading the keys of Kotlin's `ParsedCapture.toJson()` plus `key`;
  - `class BackgroundDeps { Future<String?> Function() token; Future<VaultAccount?> Function(String token) recall; Future<LocalKeys?> Function(String userId) loadKeys; Future<SqliteStore> Function(String userId) openStore; Dio Function(String token) network; Future<VaultLease?> Function(String userId) lease; DateTime Function() now; }`;
  - `class BackgroundEffects { Future<void> Function(String userId, LocalBackend backend) widget; Future<void> Function(String userId, LocalBackend backend) due; }`;
  - `class BackgroundReport { BackgroundOutcome outcome; List<Map<String, Object?>> captured; }`
    (`captured`: the local `POST /v1/captures` answers, for Kotlin's notifications);
  - `Future<BackgroundReport> runBackground(BackgroundDeps deps, BackgroundEffects effects, {List<QueuedCapture> captures = const [], List<String> confirms = const [], Future<void> Function(List<String> keys, List<String> confirms)? ack})`;
  - `Future<void> backgroundMain(String kind)` (`'sync'` | `'capture'`), which builds the real deps
    (D14), calls `runBackground` and then `wambito/background` `finished {outcome, captured}`;
  - `AutoCapturePlatform.takeQueued(String userId)` → `({List<QueuedCapture> captures, List<String> confirms})`
    and `ackQueued(List<String> keys, List<String> confirms)` over `wambito/capture`;
  - `lib/main.dart`: `@pragma('vm:entry-point') Future<void> syncMain() => backgroundMain('sync');`
    and the same for `captureMain` / `'capture'`.

- [ ] **Step 1: Write the failing tests** (fake deps, memory-backed `SqliteStore` through ffi):
  - `saves each capture, then acks it`: two captures → two transactions in the store, `ack` called
    once with both keys after the commit, outcome `changed`, `captured` has two answers;
  - `a store that fails to open acks nothing`: `openStore` throws → outcome `failed`, `ack` never
    called;
  - `a crash after the save acks nothing`: `effects.widget` throws after the save → the save
    stands, `ack` not called, outcome `failed` (the next run merges the duplicate, 200);
  - `not preview`: `recall` gives `plain` → `notPreview`, store never opened;
  - `signed out`: `token` null → `signedOut`; `no keys`: `loadKeys` null → `locked`;
  - `busy`: `lease` null → `busy`, nothing saved or acked;
  - `syncs once and writes the widget and due list for this account`: one `/v2/sync` pull, effects
    called with the recalled user id;
  - `a confirm posts review locally; an unknown id is acked and dropped`.
- [ ] **Step 2: Run** `flutter test test/background`. Expected: FAIL.
- [ ] **Step 3: Implement.** Order: token → recall (must be `preview`) → keys → lease → store
  (`background: true`) → captures and confirms through `backend.handle` → `ack` → one engine
  `run()` → effects → close store → release lease (in `finally`).
- [ ] **Step 4: Run** `flutter test test/background test/capture_auto`. Expected: PASS.
- [ ] **Step 5: Commit:** `feat(mobile): run captures and sync from a background engine`.

### Task 6: Android headless engine and background sync

**Files:**
- Create: `android/app/src/main/kotlin/com/wambito/app/background/HeadlessRunner.kt`,
  `background/BackgroundChannel.kt`, `background/SyncWorker.kt`, `background/SyncScheduler.kt`,
  `capture/CaptureQueueChannel.kt` (the headless engine's `wambito/capture`: `takeQueued`,
  `ackQueued`), `ios/Runner/Background/BackgroundChannel.swift`.
- Modify: `account/AccountMode.kt` (`owner`); `notices/NoticesChannel.kt` (`setEncryptionMode`
  takes `owner`; schedules or cancels sync; activity optional for the headless engine);
  `MainActivity.kt` (registers `BackgroundChannel` for `vaultChanged`); `lib/vault/preview_sync.dart`
  (`NativeEncryptionMode.write(mode, owner)`); `lib/vault/vault_providers.dart` (`vaultChanged` →
  `VaultSession.externalChange()`).
- Test: `android/app/src/test/kotlin/com/wambito/app/background/SyncWorkerTest.kt`,
  `account/AccountModeTest.kt`, `test/vault/preview_sync_test.dart`.

**Interfaces:**
- Consumes: Task 5 (`syncMain`, `finished`).
- Produces:
  - `object HeadlessRunner { suspend fun run(context: Context, entrypoint: String, timeout: Duration = Duration.ofMinutes(9)): HeadlessResult }`,
    `data class HeadlessResult(val outcome: String, val captured: List<String>)` (`"timeout"` on
    timeout; the engine is destroyed in every case); `HeadlessHooks.runner` replaces it in tests;
  - `BackgroundChannel.NAME = "wambito/background"`; Dart → native `finished {outcome, captured}`;
    native → Dart `vaultChanged`;
  - `object SyncScheduler { const val PERIODIC = "wambito.sync.periodic"; const val NOW = "wambito.sync.now"; fun schedule(context: Context); fun now(context: Context); fun cancel(context: Context) }`;
  - `AccountMode.owner: String?` under `wambito.encryption.owner`.

- [ ] **Step 1: Write the failing Gradle tests.** `SyncWorkerTest`: `plain` → no runner call,
  outcome `not preview`; `preview` → runner called with `"syncMain"`; runner `failed` → retry
  until `runAttemptCount` 3, then success `gave up`; runner `changed` with the app engine alive →
  `vaultChanged` sent. `AccountModeTest`: owner written and cleared with the mode;
  `setEncryptionMode(preview, u1)` schedules `wambito.sync.periodic`, `plain` or null cancels both
  sync works (WorkManager test helper).
- [ ] **Step 2: Run** the Gradle tests. Expected: FAIL.
- [ ] **Step 3: Write the failing Dart test.** `preview_sync_test.dart`: the native write carries
  the owner id; signed out writes `(null, null)`.
- [ ] **Step 4: Implement** (D7, D22). `HeadlessRunner` creates the engine on the main looper,
  runs `DartEntrypoint(flutterLoader.findAppBundlePath(), entrypoint)`, registers
  `BackgroundChannel`, `CaptureQueueChannel` and `NoticesChannel(context, activity = null, …)`
  (plugins register themselves), and waits for `finished`.
- [ ] **Step 5: Add the Swift side of the channel now** (`ios/Runner/Background/BackgroundChannel.swift`,
  `finished` answered, registered in `AppDelegate.registerChannels`, added to `project.pbxproj`),
  so the guard stays green; Task 8 uses it.
- [ ] **Step 6: Run** the Gradle tests, `flutter test test/vault`, `scripts/check-channels.sh`.
  Expected: PASS, guard clean.
- [ ] **Step 7: Commit:** `feat(android): sync the vault in the background`.

### Task 7: Android automatic capture for `preview`

**Files:**
- Modify: `capture/CaptureListener.kt` (queue for `preview`), `capture/CaptureWorkers.kt`
  (`SendCapturesWorker`, `ConfirmCaptureWorker` preview path), `capture/CaptureQueue.kt`
  (`confirms`), `capture/CaptureApi.kt` (extract `parseCaptureAnswer(json: String): CaptureAnswer?`),
  `lib/vault/preview_sync.dart` (no `clearQueue()` on becoming `preview`; D8),
  `lib/capture_auto/auto_capture_section.dart` (switches for `preview`, no `ComingSoonNotice`).
- Test: `CaptureWorkersTest.kt`, `CaptureListenerTest.kt`, `CaptureQueueTest.kt`,
  `test/capture_auto/auto_capture_section_test.dart`, `test/vault/preview_sync_test.dart`.

**Interfaces:**
- Consumes: Task 6 (`HeadlessRunner`), Task 5 (`captureMain`, `captured`).
- Produces: `CaptureQueue.addConfirm(id: String)`, `CaptureQueue.confirms(): List<String>`,
  `CaptureQueue.ack(keys: List<String>, confirms: List<String>)`.

- [ ] **Step 1: Write the failing Gradle tests.**
  - `preview capture never reaches the api`: mode `preview`, owner-bound queue of 2, fake runner
    `changed` with two answers → `CaptureApi.send` called 0 times, two notifications shown with
    the answers' ids, queue empty (the Dart side acked).
  - `engine failure keeps the queue`: runner `failed` → `Result.retry()`, queue still 2, 0 API calls;
    at attempt 8 → success `kept`, queue still 2.
  - `timeout keeps the queue`: runner `timeout` → same as failure.
  - `Bien on preview`: `ConfirmCaptureWorker` with mode `preview` → id in `confirms`, runner called
    with `captureMain`, `CaptureApi.confirm` 0 calls.
  - `listener queues for preview` (was: ignored); `unknown` still queues and waits.
- [ ] **Step 2: Run** them. Expected: FAIL.
- [ ] **Step 3: Write the failing Dart tests:** becoming `preview` calls `sendQueued(userId)`, never
  `clearQueue()`; Settings shows the capture switches for `previewOpen()`.
- [ ] **Step 4: Implement** (D1, D8, D9, D23).
- [ ] **Step 5: Run** the Gradle tests and `flutter test test/capture_auto test/vault`. Expected: PASS.
- [ ] **Step 6: Commit:** `feat(android): capture bank notifications into the vault`.

### Task 8: iOS background sync

**Files:**
- Create: `ios/Runner/Background/SyncTask.swift`, `ios/Runner/Background/HeadlessRunner.swift`,
  `ios/WambitoNative/Sources/WambitoNative/SyncPlan.swift`,
  `ios/WambitoNative/Tests/WambitoNativeTests/SyncPlanTests.swift`.
- Modify: `ios/Runner/AppDelegate.swift` (register `SyncTask` in `didFinishLaunching`),
  `ios/Runner/Background/BackgroundChannel.swift` (from Task 6: `vaultChanged` to the app's engine),
  `ios/Runner/Notices/NoticesChannel.swift` (`owner`; schedules or cancels
  `SyncTask`), `WambitoNative/AccountMode.swift` (`owner` under `wambito.encryption.owner`),
  `ios/Runner/Info.plist` (`wambito.sync` in `BGTaskSchedulerPermittedIdentifiers`),
  `project.pbxproj`.

**Interfaces:**
- Consumes: Task 5 (`syncMain`, `finished`).
- Produces:
  - `SyncTask.identifier = "wambito.sync"`, `SyncTask.register()`, `SyncTask.schedule(now:)`,
    `SyncTask.cancel()`;
  - `public enum SyncPlan { static func earliestBegin(mode: String?, now: Date) -> Date?; static func succeeded(_ outcome: String) -> Bool }`
    (4 hours after `now` for `preview`, nil otherwise; `done`/`changed`/`busy` succeed);
  - `HeadlessRunner.run(entrypoint: String, budget: TimeInterval = 25, completion: (String) -> Void)`:
    `FlutterEngine(name: "wambito.background")`, `run(withEntrypoint:)`,
    `GeneratedPluginRegistrant.register(with:)`, `BackgroundChannel` and `NoticesChannel` on its
    messenger; destroyed on `finished`, on budget, or from the task's `expirationHandler`.

- [ ] **Step 1: Write the failing Swift tests.** `SyncPlanTests`: `preview` → now + 4 h; `plain`,
  `unknown`, nil → nil; `succeeded("busy") == true`, `succeeded("failed") == false`.
  `AccountModeTests`: owner written and cleared.
- [ ] **Step 2: Run** `swift test --package-path apps/mobile/ios/WambitoNative`. Expected: FAIL.
- [ ] **Step 3: Implement.** The handler reschedules first, then runs the engine, then
  `setTaskCompleted(success: SyncPlan.succeeded(outcome))`.
- [ ] **Step 4: Run** `swift test`, `flutter build ios --release --no-codesign` (in `apps/mobile`)
  and `scripts/check-channels.sh`. Expected: PASS, guard clean.
- [ ] **Step 5: Commit:** `feat(ios): sync the vault in the background`.

### Task 9: The widget written by Dart

**Files:**
- Create: `apps/mobile/lib/home/vault_widget.dart`.
- Modify: `lib/home/widget_snapshot.dart` (`owner`), `lib/home/widget_sync.dart` (`preview` writes
  figures; the "Coming soon" line goes), `lib/background/background_main.dart` (effect `widget`),
  `android/.../widget/WidgetSnapshot.kt` (`owner`), `widget/RefreshWorker.kt` (D10, D11),
  `res/xml/backup_rules.xml`, `res/xml/data_extraction_rules.xml` (D13).
- Test: `test/home/vault_widget_test.dart`, `test/home/widget_sync_test.dart`,
  `test/tooling/widget_android_test.dart`, `RefreshWorkerTest.kt`, `WidgetModelTest.kt`,
  `local/BackupRulesTest.kt`.

**Interfaces:**
- Consumes: Tasks 5, 6.
- Produces:
  - `signedInSnapshot(..., String? owner)` (adds `'owner'` when given);
  - `Future<bool> writeVaultWidget({required String userId, required LocalBackend backend, required WidgetStore store, required bool hideAmount, required String theme, required String locale, required DateTime now, required Future<bool> Function() stillOwner})`
    (reads `GET /v1/summary` through `backend.handle`; returns false when not written);
  - `WidgetSnapshot.owner: String?` in Kotlin.

- [ ] **Step 1: Write the failing Dart tests.**
  - `writes the vault's figures with the owner`: seeded store, spent `-5000000` cents this month →
    snapshot `spent: 5000000`, `owner: "u1"`, `signedIn: true`;
  - `writes nothing when the owner changed meanwhile`: `stillOwner` false → store untouched;
  - `WidgetSync` for a `preview` session writes after a commit (debounce 2 s, fake clock) and after
    a sync; sign-out writes the signed-out snapshot with no figure.
- [ ] **Step 2: Write the failing Kotlin tests.** `RefreshWorkerTest`: `preview` → fetcher 0 calls,
  `wambito.sync.now` enqueued, outcome `sync asked`; snapshot `owner` `u1` with `AccountMode.owner`
  `u2` → signed-out snapshot written, outcome `owner mismatch`. `BackupRulesTest`: both XML files
  exclude `sharedpref/HomeWidgetPreferences.xml` and `sharedpref/wambito.notice.duelist.xml`.
- [ ] **Step 3: Run** both suites. Expected: FAIL.
- [ ] **Step 4: Implement.** `widget_android_test.dart` pins the new field on both sides.
- [ ] **Step 5: Run** `flutter test test/home test/tooling` and the Gradle tests. Expected: PASS.
- [ ] **Step 6: Commit:** `feat(mobile): draw the widget from the vault`.

### Task 10: Due notices computed in Dart

**Files:**
- Create: `apps/mobile/lib/notices/due_list.dart`, `android/.../notices/DueList.kt`,
  `ios/WambitoNative/Sources/WambitoNative/DueSchedule.swift`,
  `ios/WambitoNative/Tests/WambitoNativeTests/DueScheduleTests.swift`.
- Modify: `lib/notices/notice_platform.dart` (`scheduleDueList`), `lib/notices/notice_sync.dart`
  (`preview` path), `lib/background/background_main.dart` (effect `due`), `notices/NoticesChannel.kt`,
  `notices/NoticeWorkers.kt` (`DueWorker` preview), `ios/Runner/Notices/NoticesChannel.swift`,
  `lib/settings/settings_screen.dart` (due switch for `preview`; `settings.dueNotice.comingSoon` goes).
- Test: `test/notices/due_list_test.dart`, `test/notices/notice_sync_test.dart`,
  `NoticeWorkersTest.kt`, `DueListTest.kt`, `DueScheduleTests.swift`.

**Interfaces:**
- Consumes: Task 5, 3a `LocalBackend`.
- Produces:
  - `class DueDay { final String date; final List<String> names; }` with `toJson`;
  - `Future<List<DueDay>> dueDays(LocalBackend backend, {required String today, int days = 14})`:
    `GET /v1/transactions?status=pending&month=<m>` for each month the window touches, keeps rows
    with a `recurrenceId` and a date in the window, names in `createdAt` order, grouped by date;
  - `NoticePlatform.scheduleDueList({required String zone, required String language, required List<DueDay> days})`
    → `wambito/notices` `scheduleDueList`; `cancelDue` also clears the list on both phones;
  - Kotlin `object DueList { fun replace(context: Context, zone: String, language: String?, days: List<Pair<String, List<String>>>); fun namesOn(context: Context, date: LocalDate): List<String>; fun clear(context: Context) }`;
  - Swift `public enum DueSchedule { static func requests(days: [(date: String, names: [String])], zone: TimeZone, now: Date) -> [(id: String, fire: DateComponents, names: [String])] }`.

- [ ] **Step 1: Write the failing Dart tests.**
  - `a rule due on the 3rd and the 17th gives both days in a window crossing the month end`;
  - `a deleted rule disappears`: delete it through `DELETE /v1/recurrences/{id}` → its name absent
    from the next `dueDays`;
  - `NoticeSync` for `preview`, switch on and permission granted, calls `scheduleDueList` with that
    list and never `scheduleDue`; after a local write that deletes the rule, the next call's list
    lacks it; switch off → `cancelDue`.
- [ ] **Step 2: Write the failing Kotlin tests.** `DueListTest`: `replace` twice keeps only the
  second list. `NoticeWorkersTest`: `preview` at 9:05 with today's entry `["Arriendo"]` → posted,
  `NoticeApi` 0 calls, next run enqueued (`keepGoing`); no entry → `nothing due today`.
- [ ] **Step 3: Write the failing Swift test.** `DueScheduleTests`: today 08:00 → today's request at
  09:00; today 10:00 → today skipped; ids `wambito.due.2026-11-17`; names kept in order.
- [ ] **Step 4: Run** the three suites. Expected: FAIL.
- [ ] **Step 5: Implement** (D12). iOS removes pending ids with prefix `wambito.due.` before adding;
  the words are those of `NoticePoster`'s due notice (`Notices.strings`).
- [ ] **Step 6: Run** all three and `scripts/check-channels.sh`. Expected: PASS.
- [ ] **Step 7: Commit:** `feat(mobile): schedule due notices from the vault`.

### Task 11: Recovery verifier and a new recovery key

**Files:**
- Create: `apps/mobile/lib/local/rotate.dart` (this task: the recovery part).
- Modify: `lib/local/keys.dart` (`prepareAccount` non-guest commit and `unlockWithRecovery` send the
  verifier, D16); `test/local/fake_keys.dart` (records `PUT /v2/recovery/verifier`; deletes the
  verifier on a recovery wrap with other bytes, as the server).
- Test: `apps/mobile/test/local/rotate_recovery_test.dart`, `test/local/keys_setup_test.dart`.

**Interfaces:**
- Produces:
  - `Future<void> putRecoveryVerifier(KeysOptions options, ({Uint8List lookupHash, Uint8List authHash}) hashes)`
    → `PUT /v2/recovery/verifier {lookupHash, authHash}` (base64url, as `recovery.ts` reads them);
  - `Future<({Uint8List lookupHash, Uint8List authHash})> verifierHashesOf(Uint8List secret)` (from
    `recoveryVerifier` and `verifierHash` in `lib/crypto/recovery.dart`);
  - `class NewRecoveryKey { final String recoveryKey; final Future<void> Function() commit; }`;
  - `Future<NewRecoveryKey> newRecoveryKey(KeysOptions options)` (port of `rotate.ts`
    `newRecoveryKey`; commit = wrap PUT, then verifier PUT; retry-safe; `landed()` on a lost answer);
  - `Future<void> checkRecoveryKey(KeysOptions options, String text)` (`bad_recovery_key` /
    `wrong_recovery_key`).

- [ ] **Step 1: Port the TS cases** of `rotate.test.ts` for `newRecoveryKey` and `checkRecoveryKey`
  (same names), and add:
  - `the verifier follows the wrap`: calls are `PUT /v2/keys/<id>` then `PUT /v2/recovery/verifier`,
    and the hashes equal `verifierHashesOf(parseRecoveryKey(recoveryKey))`;
  - `a lost wrap answer that landed still sends the verifier`;
  - `rotated_elsewhere sends no verifier`;
  - `a non-guest setup sends the verifier after the device wrap; a guest setup sends none`;
  - `a recovery unlock sends the verifier; its failure does not fail the unlock`.
- [ ] **Step 2: Run** `flutter test test/local/rotate_recovery_test.dart test/local/keys_setup_test.dart`.
  Expected: FAIL.
- [ ] **Step 3: Implement.** The secret is zeroed before `newRecoveryKey` returns; only the wrapped
  bytes and the two hashes are kept for `commit`.
- [ ] **Step 4: Run** `flutter test test/local`. Expected: PASS.
- [ ] **Step 5: Commit:** `feat(mobile): make a new recovery key and keep its verifier`.

### Task 12: Removing a device rotates the data key

**Files:**
- Modify: `apps/mobile/lib/local/rotate.dart`; `lib/local/key_storage.dart` (nothing new expected:
  `writeDataKey`, `setCurrent`).
- Test: `apps/mobile/test/local/rotate_test.dart`.

**Interfaces:**
- Consumes: Task 11; 3a `withDataKey`, `refreshKeys`, `listWraps`, `KeyStorage`, `FinanceStore`.
- Produces:
  - `class DroppedWrap { final String id; final String? label; final String reason; }` (`removed` |
    `revoked` | `attestation`);
  - `class RotateResult { final int keyV; final List<DroppedWrap> dropped; }`;
  - `sealed class RotateRecovery`, `final class TypedRecovery(String text)`, `final class FreshRecovery()`;
  - `class PreparedRotation { final String? recoveryKey; final Future<RotateResult> Function() commit; }`;
  - `Future<PreparedRotation> rotateKeys(KeysOptions options, {required FinanceStore store, required List<String> remove, required RotateRecovery recovery, PasskeyPrf? passkey})`;
  - `Future<bool> attested(String userId, Uint8List dataKey, WrapDto wrap)`;
  - `Future<List<String>> revokedDevices(FinanceStore store)`.

- [ ] **Step 1: Port the TS cases** of `rotate.test.ts` for `rotateKeys` (same names: kept devices
  re-sealed with fresh attestations, removed and revoked ids left out and reported, forged
  attestation dropped, the link opens to the old key, lost answer and `landed()`, refresh first,
  `rotated_elsewhere`, never overwrite a held version, zeroing). Add:
  - `this phone cannot remove itself`: `remove: [ownId]` → `ArgumentError`, no `/v2` write;
  - `this phone missing from the server's list is device_removed, nothing sent`;
  - `this phone's wrap is always in the posted body` (with 3 other devices, 1 removed);
  - `a fresh rotation sends the new key's verifier after the rotate; a typed one sends none`.
- [ ] **Step 2: Run** `flutter test test/local/rotate_test.dart`. Expected: FAIL.
- [ ] **Step 3: Implement** the port. `keepRotated` writes `dk.<nextV>` and `current` through
  `KeyStorage` (another key already held at `nextV` → `KeysError('tampered')`), and adds the removed
  ids to the `settings` record's `revokedDevices` through the store. The caller then calls
  `VaultSession.reloadKeys()`.
- [ ] **Step 4: Run** `flutter test test/local`. Expected: PASS.
- [ ] **Step 5: Commit:** `feat(mobile): remove a device and rotate the data key`.

### Task 13: Pairing, and "Add this phone from another device"

**Files:**
- Create: `apps/mobile/lib/local/pairing.dart`, `lib/vault/pair_new_device_view.dart` (twin of
  `PairNewDevice.tsx`).
- Modify: `lib/vault/vault_gate.dart` (`Pairing` state), `lib/vault/vault_providers.dart`
  (`startPairing` dep), `lib/vault/unlock_view.dart` and `locked_view.dart` (the entry),
  `lib/vault/vault_screen.dart`, `pubspec.yaml` (`qr_flutter`), ARBs.
- Test: `apps/mobile/test/local/pairing_test.dart`, `test/vault/vault_gate_test.dart`,
  `test/vault/vault_screen_test.dart`.

**Interfaces:**
- Consumes: 3a `enrollDevice`, `withDataKey`, crypto `pairingCommitment`, `pairingNumber`,
  `openFromPairing`, `sealToDevice`.
- Produces (`lib/local/pairing.dart`, twin of `pairing.ts`):
  - `class PairingError implements Exception { final String code; }` (`expired`, `tampered`,
    `bad_code`, `offline`, `server`, `cancelled`);
  - `const pairingPoll = Duration(milliseconds: 1500)`, `const pairingTtl = Duration(minutes: 10)`;
  - `abstract interface class PairingClock { DateTime now(); Future<void> sleep(Duration d); }`;
  - `class NewDevicePairing { String id; String code; String qr; String expiresAt; Future<String> number(); Future<LocalKeys> finish(); void cancel(); }`;
  - `class ApproverPairing { Future<String> number(); Future<void> approve(); void cancel(); }`;
  - `String normalizePairingCode(String input)`;
  - `Future<NewDevicePairing> startPairing(KeysOptions options, {PairingClock? clock})`;
  - `Future<ApproverPairing> findPairing(KeysOptions options, {String? code, String? qr, PairingClock? clock})`;
  - gate: `final class Pairing<S>` with `from` (`unlock` | `guest`), `VaultGateDeps.startPairing`,
    `VaultGate.startPairing()` and `leavePairing()`.

- [ ] **Step 1: Port** `pairing.test.ts` (12 cases, same names) over a fake `/v2/pairing` relay, and
  the pairing cases of `vault-gate.test.ts`.
- [ ] **Step 2: Write the failing widget tests:** Unlock shows "Add this phone from another device";
  the pairing view shows the QR (`wambito://pair?id=…&key=…`), the 8-character code under it, the
  number once known, and Back calls `leavePairing`.
- [ ] **Step 3: Run** `flutter test test/local/pairing_test.dart test/vault`. Expected: FAIL.
- [ ] **Step 4: Implement** (D21). A finished pairing opens like a recovery unlock (fresh sync).
- [ ] **Step 5: Run** the same. Expected: PASS. Run `scripts/check-no-google.sh`. Expected: exit 0.
- [ ] **Step 6: Commit:** `feat(mobile): pair this phone from another device`.

### Task 14: The QR scanner and approving a device

**Files:**
- Create: `android/.../scanner/ScannerChannel.kt`, `scanner/ScannerActivity.kt`,
  `scanner/QrDecode.kt`; `ios/Runner/Scanner/ScannerChannel.swift`,
  `ios/Runner/Scanner/ScannerViewController.swift`;
  `ios/WambitoNative/Sources/WambitoNative/CameraAccess.swift` + test;
  `apps/mobile/lib/scanner/qr_scanner.dart`; `lib/settings/security/approve_device_screen.dart`
  (twin of `ApproveDevice.tsx`).
- Modify: `android/app/build.gradle(.kts)` (CameraX, ZXing core, exact versions),
  `AndroidManifest.xml` (`CAMERA`, `<uses-feature android:name="android.hardware.camera" android:required="false"/>`,
  the activity, not exported), `scripts/check-permissions.sh` (`CAMERA` required and allowed),
  `gradle.lockfile`, `gradle-fdroid.lockfile`, `assets/licenses/android-libraries.json`,
  `MainActivity.kt`, `AppDelegate.swift`, `Info.plist` (`NSCameraUsageDescription`),
  `*.lproj/InfoPlist.strings`, `project.pbxproj`.
- Test: `android/.../scanner/QrDecodeTest.kt`, `CameraAccessTests.swift`,
  `test/settings/approve_device_screen_test.dart`.

**Interfaces:**
- Consumes: Task 13 `findPairing`.
- Produces:
  - channel `wambito/scanner`: `isAvailable` → bool, `scan` → `String?` (null = cancelled or no
    permission), on both phones;
  - Kotlin `fun decodeQr(luminance: ByteArray, width: Int, height: Int, rowStride: Int): String?`;
  - Swift `public enum CameraAccess { static func state(_ status: Int) -> String }` (`granted`,
    `ask`, `denied`, from `AVAuthorizationStatus` raw values);
  - Dart `abstract interface class QrScanner { Future<bool> isAvailable(); Future<String?> scan(); }`,
    `qrScannerProvider`;
  - `ApproveDeviceScreen` (Scan when available, else and always "Type the code"; then the number,
    then Approve).

- [ ] **Step 1: Write the failing tests.** `QrDecodeTest`: a QR of
  `wambito://pair?id=…&key=…` drawn by ZXing's `QRCodeWriter` into a luminance buffer with
  `rowStride > width` decodes to that text; noise decodes to null. `CameraAccessTests`: the four
  raw statuses. `approve_device_screen_test`: scanner unavailable → code field only; a scanned
  text goes to `findPairing(qr:)`; `bad_code` shows the web's message; Approve is enabled only once
  the number shows.
- [ ] **Step 2: Run** the three suites. Expected: FAIL.
- [ ] **Step 3: Implement** (D19). Android: CameraX `Preview` + `ImageAnalysis` (keep-only-latest)
  feeding `decodeQr`; the activity returns the first decode. iOS: `AVCaptureMetadataOutput` with
  `.qr`, presented full screen.
- [ ] **Step 4: Run** the suites, then from `apps/mobile`: `scripts/check-no-google.sh`,
  `scripts/check-gradle-locks.sh`, `scripts/check-fdroid-lock.sh`,
  `dart run scripts/gen-android-licenses.dart --check`, `../../scripts/check-channels.sh`. Expected:
  all exit 0.
- [ ] **Step 5: Commit:** `feat(mobile): scan a pairing qr on both phones`.

### Task 15: The screen lock for sensitive operations

**Files:**
- Create: `apps/mobile/lib/security/screen_lock.dart`.
- Modify: `pubspec.yaml` (`local_auth`), `MainActivity.kt` (extends `FlutterFragmentActivity`),
  `AndroidManifest.xml` (drop the `USE_BIOMETRIC` removal; keep `USE_FINGERPRINT` removed),
  `scripts/check-permissions.sh` (`USE_BIOMETRIC` required and allowed), `Info.plist`
  (`NSFaceIDUsageDescription`), `*.lproj/InfoPlist.strings`, Gradle locks, licence list.
- Test: `apps/mobile/test/security/screen_lock_test.dart`.

**Interfaces:**
- Consumes: Task 11 `checkRecoveryKey`.
- Produces:
  - `enum LockCheck { passed, cancelled, noLock }`;
  - `abstract interface class ScreenLock { Future<LockCheck> confirm(String reason); }`,
    `LocalAuthScreenLock` (`isDeviceSupported()`, then `authenticate` with biometrics or PIN),
    `screenLockProvider`;
  - `Future<bool> confirmSensitive(BuildContext context, WidgetRef ref, {required String reason, required Future<void> Function(String text) checkRecoveryKey})`:
    `passed` → true; `cancelled` → false; `noLock` → a sheet asking the current recovery key
    (D15, spec 7.7).

- [ ] **Step 1: Write the failing tests:** `passed` returns true and shows no sheet; `cancelled`
  false; `noLock` shows the recovery-key sheet, a wrong key shows "That key does not open this
  account" and stays, the right key returns true.
- [ ] **Step 2: Run** `flutter test test/security`. Expected: FAIL.
- [ ] **Step 3: Implement** (D18). Check by hand that passkey sign-in, voice and file pick still
  work on the emulator after the activity change (note it in the PR).
- [ ] **Step 4: Run** `flutter test --exclude-tags golden,stack`, the Gradle tests,
  `scripts/check-no-google.sh`, and after `flutter build apk --release`,
  `scripts/check-permissions.sh`. Expected: PASS, exit 0.
- [ ] **Step 5: Commit:** `feat(mobile): ask the screen lock before sensitive operations`.

### Task 16: Settings → Security

**Files:**
- Create: `apps/mobile/lib/settings/security/security_api.dart` (twin of `security.ts`),
  `security_model.dart` (twin of `security-model.ts`), `security_section.dart` (twin of
  `SecuritySection.tsx`), `remove_device_sheet.dart` (twin of `RemoveDeviceSheet.tsx`).
- Modify: `lib/settings/settings_screen.dart` (the section for `preview`; the passkeys section
  shows "Unlocks your data" per row), `lib/settings/passkeys_section.dart` (add with a wrap when PRF
  works: `addPasskeyWrap`), ARBs.
- Test: `test/settings/security/security_model_test.dart`, `security_section_test.dart`,
  `remove_device_sheet_test.dart`.

**Interfaces:**
- Consumes: Tasks 11–15.
- Produces:
  - `class SecuritySnapshot { List<WrapDto> wraps; String? ownId; List<String> revoked; Set<String> verified; int unreadable; }`;
  - `abstract interface class SecurityApi { Future<SecuritySnapshot> load(); Future<PreparedRotation> rotate({required List<String> remove, required RotateRecovery recovery, PasskeyPrf? passkey}); Future<void> checkRecoveryKey(String text); Future<NewRecoveryKey> newRecoveryKey(); Future<void> reloadKeys(); Future<PasskeyPrf?> evaluatePrf(List<String>? ids); Future<void> addPasskeyWrap(PasskeyPrf passkey); Future<ApproverPairing> findPairing({String? code, String? qr}); }`,
    `SecurityApi liveSecurity(VaultSession session, KeysOptions options)`, `securityApiProvider`;
  - `List<DeviceRow> deviceRows(...)`, `List<PasskeyRow> passkeyRows(...)` as the TS;
  - `bool hasPasskeyWrap(List<WrapDto> wraps, String credentialId)` and
    `bool anyPasskeyWrap(List<WrapDto> wraps)` (phone-first 5.2, for delivery 2).

- [ ] **Step 1: Port** `security-model.test.ts`; add `a passkey without a wrap is not protection`.
- [ ] **Step 2: Write the failing widget tests** (fake `SecurityApi`, fake `ScreenLock`):
  - devices list marks "This phone" and "Not verified"; this phone has no Remove;
  - Remove → screen lock `cancelled` → nothing called; `passed` → choice sheet; typed key →
    `rotate(remove: [id], recovery: TypedRecovery(text))` → `commit` → `reloadKeys`; "Make a new
    recovery key" → setup view with the four-character check → `commit` → `reloadKeys`;
  - `rotated_elsewhere` shows the web's message and reloads the list;
  - New recovery key → screen lock → setup view → `commit`; the key is not on screen before the
    lock passes (D17);
  - "Add a device" opens `ApproveDeviceScreen`;
  - "N records could not be read" shows when `unreadable > 0`.
- [ ] **Step 3: Run** `flutter test test/settings`. Expected: FAIL.
- [ ] **Step 4: Implement,** with the UI kit (`lib/ui/`) and the web's words.
- [ ] **Step 5: Run** `flutter analyze && flutter test --exclude-tags golden,stack`. Expected: PASS.
- [ ] **Step 6: Commit:** `feat(mobile): settings security for encrypted accounts`.

### Task 17: End to end against the real API, CI, docs

**Files:**
- Create: `apps/mobile/test_stack/vault_3b_e2e_test.dart` (tag `stack`).
- Modify: `apps/mobile/scripts/run-vault-e2e.sh` (runs both stack files; a second `psql` check),
  `apps/mobile/AGENTS.md`, root `AGENTS.md` (the `mobile-e2e` line names both files),
  `docs/mobile/ios.md` (the `wambito.sync` task, camera and Face ID texts), `docs/mobile/fdroid.md`
  (CameraX and ZXing), `.github/workflows/ci.yml` only if the job's command changes.

**Interfaces:**
- Consumes: every earlier task, the root stack with the `preview` seed (`seed:e2e-preview`).

- [ ] **Step 1: Write the test.** On the real stack, with ffi stores and in-memory `KeyStorage`:
  1. phone A signs in and sets up (keeps the recovery key);
  2. phone B pairs through `/v2/pairing` (`startPairing` on B, `findPairing(code:)` + `approve`
     on A) and opens its vault;
  3. `runBackground` on A with a queued capture `{merchant: "panaderia e2e", amount: 1250000}`;
     B syncs and reads it;
  4. A removes B with `TypedRecovery`; B's next sync ends `deviceRemoved`;
  5. A makes a new recovery key; `POST /v2/recovery/sign-in` with the new key's `lookup`/`auth`
     is 200, with the old key's is 401 `recovery_key_invalid`.
- [ ] **Step 2: Extend `run-vault-e2e.sh`** with
  `select count(*) from records where convert_from(body,'UTF8') ilike '%panaderia%'`, which must
  print `0`.
- [ ] **Step 3: Run** from the root: `cp -n .env.example .env; docker compose up -d`, then
  `apps/mobile/scripts/run-vault-e2e.sh`. Expected: PASS and `0`.
- [ ] **Step 4: Update the docs.** `apps/mobile/AGENTS.md`: `lib/background/`, the lease and lock
  file, the two entry points, `wambito/background` and `wambito/scanner`, the due list and widget
  ownership, `lib/settings/security/`, `lib/security/`, the new persistent names in Traps, and that
  3a's "Coming soon" now covers only export, import and assistants.
- [ ] **Step 5: Final check.** From the root: `pnpm lint && pnpm typecheck && pnpm test`,
  `scripts/check-old-name.sh`, `scripts/check-channels.sh`; in `apps/mobile`: `flutter analyze`,
  `flutter test --exclude-tags golden,stack`, the Gradle tests, `swift test --package-path ios/WambitoNative`,
  `scripts/check-no-google.sh`, `scripts/check-fdroid-recipe.sh`, `scripts/check-fdroid-lock.sh`.
  All exit 0.
- [ ] **Step 6: Commit:** `test(mobile): run pairing, removal and background sync against the api`.
  Open the PR with a manual list for the founder, on the Android phone and the iPhone with a
  `preview` account: a Revolut capture lands while the app is closed and "Bien" confirms it
  (Android); the widget shows the vault's figures and blanks after sign-out (Android); a due notice
  at 9:00; background sync after a web edit; pair the phone from the web and the web from the
  phone (scan and typed code); remove a device; a new recovery key signs in on the web; the screen
  lock appears for the three operations. Plus Task 1's report.
