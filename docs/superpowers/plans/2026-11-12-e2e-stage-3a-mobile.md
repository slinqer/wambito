# E2E Stage 3a (the phone's core) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A `preview` account works in the Flutter app on Android and iOS. The app holds the data key,
keeps the finances in a local SQLite vault, syncs sealed records through `/v2`, and never sends a
finance field in clear.

**Architecture:** A Dart port of the web's `apps/web/app/local/` and of `packages/crypto` and
`packages/core`. A Dio interceptor answers the `/v1` finance routes from the local backend, so
repositories and screens stay as they are. A Dart port of the web's vault gate decides between
setup, unlock, locked and ready, and the router sends a `preview` account to `/unlock` until the gate
is ready.

**Tech Stack:**
- Flutter and Dart, Riverpod 3, Dio, go_router;
- `cryptography` and `cryptography_flutter`;
- `sqflite`, with `sqflite_common_ffi` in tests;
- `flutter_secure_storage`;
- Swift (`ios/WambitoNative`) and Kotlin for the PRF and backup bits.

**Spec:** `docs/superpowers/specs/2026-11-12-e2e-stage-3-mobile-design.md`, sections 1–6, 8 and 9 (3a
only; section 7 is 3b's plan).

## Global Constraints

- **Branch and PR:** work on branch `feat/e2e-stage-3a-mobile` from `main`, and open one PR. Merging
  to `main` deploys, so merge only on the founder's yes.
- **Scope:** only `plain` vs `preview` (`GET /v1/me` → `encryption`). A `plain` account must behave
  exactly as today: every existing test stays green unchanged.
- **Port rule:** each Dart file mirrors its TypeScript twin (spec section 2 table). Same behaviour,
  same error codes, same names in lowerCamelCase. The Dart test ports the TypeScript test's cases
  (same names, same values). When the TS and the plan disagree, the TS wins; ledger the ruling.
- **Bytes and money:**
  - bytes are `Uint8List`;
  - base64url without padding, as `packages/crypto/src/bytes.ts` does;
  - money is integer cents, never `double`.
- **New dependencies:**
  - `cryptography`, `cryptography_flutter`, `sqflite`, `path`, plus dev `sqflite_common_ffi`;
  - each pinned to an exact version (no `^`), the latest stable when added;
  - `apps/mobile/scripts/check-licenses.sh` and `scripts/check-no-google.sh` pass;
  - the Gradle locks are rewritten as `apps/mobile/AGENTS.md` says.
- **Secure storage keys:**
  - `wambito.vault.<userId>.dk.<v>` holds the DK of version v, base64url;
  - `wambito.vault.<userId>.current` holds the current version;
  - `wambito.vault.<userId>.device` holds the X25519 private key, base64url;
  - `wambito.encryption.<userId>` holds `plain` | `preview`.

  All of them are on the iOS Keychain with `first_unlock_this_device`.
- **Vault file:** `wambito-vault-<userId>.db` in `getApplicationSupportDirectory()`.
- **Copy:**
  - the vault screens take the web's words: `apps/web/app/i18n/messages/*`, the vault keys;
  - the ARBs are `lib/l10n/app_{es,en,it,pt}.arb`, with es as the template;
  - add no new words beyond the spec's: "Coming soon with encryption", "That key does not open this
    account", and "You have N changes not synced yet";
  - the money slang rule of the root `AGENTS.md` applies.
- **Commits:** Conventional (`feat(mobile): …`, `test(core): …`), a lowercase sentence. Stage by
  path; never a `Co-Authored-By` line.
- **No API change:** no `CHANGELOG.md` line, and `apps/mobile/lib/api/gen` is not regenerated (it
  already has `Profile.encryption`).
- **Commands:**
  - from `apps/mobile`, with `export PATH="$HOME/development/flutter/bin:$PATH"`:
    - `flutter analyze`;
    - `flutter test --exclude-tags golden,stack`;
  - from the repo root: `pnpm lint`, `pnpm test`, `scripts/check-channels.sh`.

## Review Focus

1. **iOS keeps Keychain items after the app is deleted.** A reinstall finds a DK, maybe of a device
   since removed, and no vault file. It must start clean: no stale keys, no crash. Pinned in Task 12.
2. **The process dies between a record write and its outbox entry.** Both commit or neither does.
   Pinned in Task 7.
3. **Two syncs at once** (resume, plus the after-write trigger, plus pull-to-refresh). Exactly one
   runs; the others join it or queue one more run. Pinned in Task 12.
4. **Sign-out while a sync is in flight.** The vault and keys end deleted, and the late sync writes
   nothing back. Pinned in Task 12.
5. **Account switch on one phone.** Keys and vault of account A are never loaded for account B.
   Pinned in Task 9.

---

### Task 1: Passkey PRF on both phones, and the spike

**Files:**
- Modify:
  - `apps/mobile/ios/WambitoNative/Sources/WambitoNative/WebAuthnJSON.swift`: parse
    `extensions.prf.eval.first` from the request; write `clientExtensionResults.prf` in the response;
  - `apps/mobile/ios/Runner/Passkeys/PasskeyChannel.swift`: pass the PRF input to
    `ASAuthorizationPublicKeyCredentialPRFAssertionInput` and `…PRFRegistrationInput` on iOS 18+;
  - `apps/mobile/lib/api/passkeys.dart`: no change to the channel; the helpers below wrap the JSON.
- Create:
  - `apps/mobile/lib/local/prf.dart`;
  - `apps/mobile/lib/debug/prf_probe_screen.dart`, a debug-only route `/debug/prf`, registered
    only when `kDebugMode`.
- Test:
  - `apps/mobile/ios/WambitoNative/Tests/WambitoNativeTests/WebAuthnJSONPrfTests.swift`;
  - `apps/mobile/test/local/prf_test.dart`;
  - Android: `android/app/src/test/.../passkeys/PasskeyJsonTest.kt`, if the pass-through needs a
    change.
- Report: `docs/superpowers/reports/2026-11-12-e2e-mobile-prf-spike.md`.

**Interfaces:**
- Produces (`lib/local/prf.dart`, twin of `apps/web/app/local/prf.ts`):
  - `Map<String, Object?> prfExtension()` returns `{'prf': {'eval': {'first': <base64url of PRF_SALT>}}}`;
  - `Uint8List? readPrf(Map<String, Object?> clientExtensionResults)`;
  - `bool prfEnabledWithoutResults(Map<String, Object?> clientExtensionResults)`;
  - `class PasskeyPrf { final String credentialId; final Uint8List prf; }`;
  - `Future<PasskeyPrf?> evaluatePrf(Passkeys passkeys, String optionsJson)` adds the extension,
    calls `get`, and reads the result.

- [ ] **Step 1: Write the failing Swift test.** `testPrfInputIsParsed`: a request JSON with
  `extensions.prf.eval.first = "mZ0R_U0yE9CNbSH9HgjqZjsy9sIcTWA3QBVGG_z9vts"` (PRF_SALT in base64url)
  yields a PRF input of those 32 bytes. `testPrfOutputIsWritten`: a 32-byte output becomes
  `clientExtensionResults.prf.results.first` in base64url; with no output,
  `clientExtensionResults == [:]` as today.
- [ ] **Step 2: Run it and see it fail.** Run:
  `swift test --package-path apps/mobile/ios/WambitoNative --filter WebAuthnJSONPrfTests`. Expected:
  FAIL (no PRF parsing).
- [ ] **Step 3: Implement the parsing and writing** in `WebAuthnJSON.swift`, and the iOS 18
  `#available` mapping in `PasskeyChannel.swift`. On older iOS the input is ignored and the results
  carry no `prf`.
- [ ] **Step 4: Write the failing Dart test.** `prf_test.dart` ports `apps/web/app/local/prf.test.ts`'s
  cases for `prfExtension`, `readPrf` and `prfEnabledWithoutResults`, and adds a case where
  `evaluatePrf`, with a fake `Passkeys` returning a response JSON with `prf.results.first`, returns
  those bytes.
- [ ] **Step 5: Implement `lib/local/prf.dart`.** Then run `flutter test test/local/prf_test.dart`.
  Expected: PASS.
- [ ] **Step 6: Android.** Read `PasskeyChannel.kt`. If it builds the Credential Manager request from
  the JSON unchanged and returns `clientExtensionResults` unchanged, write that finding in the
  report and change nothing. Otherwise make it pass `extensions` and `clientExtensionResults`
  through, with a Kotlin unit test.
- [ ] **Step 7: Build the debug probe** `/debug/prf`. It has two buttons:
  - "Create passkey with PRF": `create`, with the extension and `eval`;
  - "Read PRF": `get`, with the extension.

  Each shows `SHA-256(prf)` as hex and whether two reads in a row match.
- [ ] **Step 8: Commit.**
  ```bash
  git add apps/mobile/ios/WambitoNative apps/mobile/ios/Runner/Passkeys apps/mobile/lib/local/prf.dart apps/mobile/lib/debug apps/mobile/lib/router.dart apps/mobile/test/local/prf_test.dart
  git commit -m "feat(mobile): read the passkey prf on android and ios"
  ```
- [ ] **Step 9: Spike checkpoint.** Tell the founder: build a debug app on the Android phone and the
  iPhone, open `wambito://…` → `/debug/prf`, and report whether both hashes match across reads, and
  whether they match the web for the same passkey (the web's console shows the same hash from
  `prf.ts` in dev).
  - Do not wait: go on with Task 2.
  - When the answer comes, write `docs/superpowers/reports/2026-11-12-e2e-mobile-prf-spike.md` with
    the device, OS version, result and conclusion, and commit it as
    `docs: report the mobile prf spike`.
  - A failing phone does not block the plan: PRF stays optional (spec section 3).

### Task 2: Dart crypto passing the shared vectors

**Files:**
- Modify: `apps/mobile/pubspec.yaml`, `pubspec.lock` (add `cryptography`, `cryptography_flutter`),
  and the licence list (`scripts/check-licenses.sh` input).
- Create: `apps/mobile/lib/crypto/{bytes,errors,keys,records,wraps,devices,links,attest,pairing,recovery,validate}.dart`
  and `lib/crypto/crypto.dart`, which exports them. They mirror `packages/crypto/src/*.ts` one to
  one.
- Test: `apps/mobile/test/crypto/vectors_test.dart`, plus one test file per TS test
  (`records_test.dart`, `wraps_test.dart`, …).

**Interfaces:**
- Produces, mirroring the TS signatures; the parameter order is that of the TS file:
  - `class CryptoError implements Exception { final String code; }`, with the codes `cannot_open`,
    `bad_recovery_key` and `bad_input`;
  - `String toBase64Url(Uint8List)`, `Uint8List fromBase64Url(String)`,
    `bool timingSafeEqual(Uint8List, Uint8List)`;
  - `Uint8List generateDataKey()`;
  - `class RecordKeys { final SecretKey record; final SecretKey dedupe; }`, and
    `Future<RecordKeys> deriveRecordKeys(Uint8List dataKey)`;
  - `enum RecordType { transaction, category, budget, recurrence, merchant, settings, account }` (the
    wire name is `.name`);
  - `class RecordContext { userId, type, id, keyV }`;
  - `Future<Uint8List> sealRecord(RecordKeys, RecordContext, Object? value, {Uint8List? nonce})`,
    `Future<Object?> openRecord(RecordKeys, RecordContext, Uint8List body)`, and
    `Future<String> dedupeTag(RecordKeys, String text)`;
  - `enum WrapKind { passkey, recovery, device, assistant }` and `class WrapContext { kind, userId, keyV }`;
  - `final Uint8List prfSalt`, the 32 bytes of `PRF_SALT`;
  - `wrapDataKey` and `unwrapDataKey`;
  - `class DeviceKeyPair { Uint8List publicKey; Uint8List privateKey; }`,
    `Future<DeviceKeyPair> generateDeviceKeyPair()`, `sealToDevice`, `openFromDevice` and
    `openFromPairing`;
  - `const linkBytes = 60`, `class LinkContext`, `sealKeyLink` and `openKeyLink`;
  - `deviceAttestation` and `verifyDeviceAttestation`;
  - `pairingCode`, `pairingNumber` and `pairingCommitment`;
  - `newRecoverySecret`, `formatRecoveryKey` and `parseRecoveryKey`.

  The device private key is raw 32 bytes in Dart (the TS "noble" shape).

- [ ] **Step 1: Write the failing vector test.** `vectors_test.dart` loads
  `../../packages/crypto/test-vectors.json` (relative to `apps/mobile`). For every entry of every
  section (`records`, `wraps`, `recovery`, `devices`, `pairing`, `approvals`, `attestations`,
  `links`, `rejects`) it asserts what `packages/crypto/test/vectors.test.ts` asserts:
  - byte-equal outputs for the given nonce;
  - opening gives the input back;
  - each `rejects` entry throws `CryptoError` with its `code`.
- [ ] **Step 2: Run it and see it fail.** Run: `flutter test test/crypto/vectors_test.dart`. Expected:
  FAIL (no library).
- [ ] **Step 3: Add the dependencies,** pinned exactly. Initialise `FlutterCryptography.enable()` in
  `bootstrap()` (`lib/main.dart`). Tests use the pure-Dart implementation.
- [ ] **Step 4: Implement `lib/crypto/*`,** file by file from the TS. Keep:
  - the AAD strings (for example `wambito/v1/record/<userId>/<type>/<id>/<keyV>`);
  - the HKDF infos (`wambito/v1/record`, `wambito/v1/dedupe`, `wambito/v1/link`, and the wrap
    kinds' infos from `wraps.ts`);
  - padding to 64 bytes.
- [ ] **Step 5: Port the per-file TS tests** (`packages/crypto/test/*.test.ts`) into
  `test/crypto/*_test.dart`, with the same case names.
- [ ] **Step 6: Run the tests.** Run `flutter test test/crypto` and expect PASS. Then run
  `scripts/check-licenses.sh && scripts/check-no-google.sh` (from `apps/mobile`) and expect exit 0.
- [ ] **Step 7: Commit:** `feat(mobile): port the e2e crypto to dart`. Stage
  `apps/mobile/lib/crypto`, `apps/mobile/test/crypto`, `pubspec.*`, `lib/main.dart`, the licence
  file, and the Gradle locks if they changed.

### Task 3: Shared fixtures for the rest of `packages/core`

**Files:**
- Create (each a JSON array of `{ name, input, expected }`, with a `$comment` header like
  `reports/cases.json`):
  - `packages/core/fixtures/summary.json`: `monthSummary`;
  - `packages/core/fixtures/budget.json`: `effectiveBudget`;
  - `packages/core/fixtures/recurrence.json`: `occurrences`;
  - `packages/core/fixtures/cost-of-living.json`: `costOfLiving`;
  - `packages/core/fixtures/movement-search.json`: `matchesMovementSearch` and `movementTotals`;
  - `packages/core/fixtures/dates.json`: `todayIn`, `monthOf`, `firstDay`, `lastDay`, `addMonths`,
    `monthsBetween` and `isMonth`.
- Test: `packages/core/src/fixtures.test.ts`, which runs every file against the TS functions.
- Modify: `packages/core/AGENTS.md` (the fixtures folder and the rule that Dart reads it).

**Interfaces:**
- Produces: the six fixture files above, read by Task 4.

- [ ] **Step 1: Write the test.** `fixtures.test.ts` has one `describe` per file. Each case is
  `expect(fn(...input)).toEqual(expected)`. The cases cover:
  - month boundaries in `America/Bogota` and `Europe/Madrid` at 23:30 local;
  - a budget with and without an override;
  - a monthly recurrence on day 31 across February;
  - a search by text, kind, category and status;
  - every function listed above, at least three cases each.

  Take the values from running the TS functions: the fixtures pin today's behaviour.
- [ ] **Step 2: Run it.** Run: `pnpm --filter @wambito/core test`. Expected: PASS. The fixtures
  record today's outputs, so if one fails, the fixture is wrong, not the code.
- [ ] **Step 3: Commit:** `test(core): add shared fixtures for the dart port`.

### Task 4: `lib/core/` in Dart

**Files:**
- Create: `apps/mobile/lib/core/{money,dates,budget,summary,reports,recurrence,cost_of_living,movement_search,currencies,default_currency,suggested_categories}.dart`.
  They mirror `packages/core/src/*.ts`; `capture.ts`, `capture-sources.ts` and `wambi-message.ts`
  are not ported.
- Move: `lib/recurring/recurring_model.dart`'s date logic into `lib/core/recurrence.dart`. Update its
  imports; its existing tests keep passing.
- Test: `apps/mobile/test/core/fixtures_test.dart`, which reads `packages/core/reports/cases.json`
  and the six files of Task 3.

**Interfaces:**
- Consumes: Task 3's fixtures.
- Produces: Dart twins with the same names, for example
  `MonthSummary monthSummary(...)`, `int effectiveBudget(...)`,
  `List<String> occurrences(...)`, `byCategory`, `trend`, `costOfLiving`,
  `bool matchesMovementSearch(...)`, `movementTotals`, `todayIn`, `monthOf`, `firstDay`, `lastDay`,
  `addMonths`, `monthsBetween` and `isMonth`.
  - Months are `String` `YYYY-MM`.
  - Dates are `String` `YYYY-MM-DD`.
  - Time zones go through the `timezone` package (already a dependency).

- [ ] **Step 1: Write the failing test.** `fixtures_test.dart` has one group per fixture file, and
  each case asserts `deepEquals(fn(input), expected)` after JSON round-trip.
- [ ] **Step 2: Run it.** Run `flutter test test/core`. Expected: FAIL.
- [ ] **Step 3: Implement** each file from its TS twin.
- [ ] **Step 4: Run the tests.** Run `flutter test test/core test/recurring`. Expected: PASS.
- [ ] **Step 5: Commit:** `feat(mobile): port the core rules to dart with shared fixtures`.

### Task 5: Record bodies and request validation

**Files:**
- Create:
  - `apps/mobile/lib/core/records.dart`, the twin of `packages/core/src/records.ts`: loose
    validation of each record type's body; unknown fields are kept;
  - `apps/mobile/lib/core/schemas.dart`, the twin of `schemas.ts`: the request validators the local
    backend uses (`createTransactionSchema`, `updateTransactionSchema`, `createCategorySchema`,
    `updateCategorySchema`, `setBudgetSchema`, `createRecurrenceSchema`, `updateRecurrenceSchema`,
    `reviewTransactionsSchema`, `updateProfileSchema`, and whatever else `backend.ts` imports).
- Test: `apps/mobile/test/core/records_test.dart` and `schemas_test.dart`, which port
  `records.test.ts` and the schema cases the API tests use.

**Interfaces:**
- Produces:
  - `typedef Json = Map<String, Object?>`;
  - `Json parseRecordBody(RecordType type, Object? value)`, which throws
    `RecordBodyError(type, path)`;
  - `ValidationResult<T> validate<T>(Schema<T> schema, Object? body)`, where the failure carries
    `List<Issue> { path, message }`.

  Task 11 turns a failure into the same 400 problem body the API sends; read
  `apps/web/app/local/backend.ts` for its shape.

- [ ] **Step 1: Write the failing tests** (ported cases).
- [ ] **Step 2: Run them.** Expected: FAIL.
- [ ] **Step 3: Implement.** No codegen: plain Dart validators.
- [ ] **Step 4: Run the tests.** Run `flutter test test/core`. Expected: PASS.
- [ ] **Step 5: Commit:** `feat(mobile): validate record bodies and requests in dart`.

### Task 6: `FinanceStore`, the memory store and the store contract

**Files:**
- Create:
  - `apps/mobile/lib/local/store.dart`;
  - `apps/mobile/lib/local/memory_store.dart`;
  - `apps/mobile/test/local/store_contract.dart`, which exports
    `void runStoreContract(String name, Future<FinanceStore> Function() open)`;
  - `apps/mobile/test/local/memory_store_test.dart`.

**Interfaces:**
- Produces:
  ```dart
  class StoredRecord { final String id; final Json body; final bool deleted; }
  class ReadOptions { final bool includeDeleted; }
  class WriteOptions { final String origin; /* 'local' | 'remote' */ final int? version; final int? keyV; final bool skipIfPending; final int? ifSeq; }
  abstract interface class StoreOps {
    Future<StoredRecord?> get(RecordType type, String id, [ReadOptions opts]);
    Future<List<StoredRecord>> list(RecordType type, [ReadOptions opts]); // first-write order
    Future<void> put(RecordType type, String id, Json body, [WriteOptions opts]);
    Future<void> delete(RecordType type, String id, [WriteOptions opts]);
  }
  abstract interface class FinanceStore implements StoreOps {
    Future<R> transaction<R>(Future<R> Function(StoreOps tx) fn);
    void Function() subscribe(void Function() listener);
  }
  ```

- [ ] **Step 1: Port the cases** of `apps/web/app/local/store-contract.ts` into `runStoreContract`.
  `memory_store_test.dart` calls it.
- [ ] **Step 2: Run** `flutter test test/local/memory_store_test.dart`. Expected: FAIL.
- [ ] **Step 3: Implement** `store.dart` (types only) and `memory_store.dart`, the twin of
  `memory-store.ts`.
- [ ] **Step 4: Run the tests.** Expected: PASS.
- [ ] **Step 5: Commit:** `feat(mobile): add the finance store contract and memory store`.

### Task 7: The SQLite vault

**Files:**
- Modify: `pubspec.yaml`, `pubspec.lock`, the licence list, and the Gradle locks (add `sqflite`,
  `path`, and dev `sqflite_common_ffi`).
- Create:
  - `apps/mobile/lib/local/db.dart`, the twin of `db.ts`: schema and open/delete;
  - `apps/mobile/lib/local/sqlite_store.dart`, the twin of `encrypted-store.ts`.
- Test: `apps/mobile/test/local/sqlite_store_test.dart`.

**Interfaces:**
- Consumes: Task 6's types.
- Produces:
  - `String vaultFileName(String userId) => 'wambito-vault-$userId.db'`;
  - `Future<void> deleteVault(String userId, {String? directory, DatabaseFactory? factory})`;
  - `class SqliteStore implements FinanceStore`, opened with
    `static Future<SqliteStore> open(String userId, {String? directory, DatabaseFactory? factory})`.
  - It also has the sync helpers, with the names and meaning of `encrypted-store.ts` (read its
    `EncryptedStore` interface for each one's arguments and result): `readOutbox`, `ackOutbox`,
    `getMeta`, `setMeta`, `quarantine`, `quarantined`, `wipeRecords`, `restoreSetAside`,
    `parkOutbox`, `abandonOutbox`, `adoptServerCopy`, `queueReseal(int current, int limit)`,
    `keyVersionsInUse()`, `rawRecord(type, id)`, `close()`, `isClosed`, `onClosed`, and
    `VaultClosedError` (code `vault_closed`).
- Schema:
  - one table per `RecordType` with `id TEXT PRIMARY KEY`, `seq INTEGER` (the first-write order),
    `body TEXT`, `deleted INTEGER`, `version INTEGER`, `key_v INTEGER`;
  - `transaction` also has indexed `date TEXT`, `category_id TEXT` and `amount INTEGER`, filled from
    the body;
  - `outbox`, `meta (key TEXT PRIMARY KEY, value TEXT)` and `quarantine`, with the columns of
    `db.ts`'s `OutboxEntry` and `QuarantineEntry`.

  Keys are not stored here.

- [ ] **Step 1: Write the failing tests.**
  - `sqlite_store_test.dart` calls `runStoreContract('sqlite', …)` over `databaseFactoryFfi` in a
    temp dir.
  - It ports `encrypted-store.test.ts`'s cases (outbox, remote writes, `skipIfPending`, `ifSeq`,
    park and abandon, set aside and restore, reseal, quarantine, close).
  - It adds `writeAndOutboxAreAtomic`: inside `transaction`, a `put` and then a throw. After it,
    both `get` and `readOutbox` are empty, also after reopening the file (Review Focus 2).
- [ ] **Step 2: Run** `flutter test test/local/sqlite_store_test.dart`. Expected: FAIL.
- [ ] **Step 3: Implement.** A local write updates the record and the outbox in one `db.transaction`.
  Subscribers fire after commit. A single in-process queue makes transactions never overlap.
- [ ] **Step 4: Run the tests.** Expected: PASS. Then run the licence and no-Google checks; expect
  exit 0.
- [ ] **Step 5: Commit:** `feat(mobile): add the sqlite vault store`.

### Task 8: Keep the vault and keys out of backups

**Files:**
- Modify:
  - `apps/mobile/android/app/src/main/AndroidManifest.xml`: `android:dataExtractionRules` and
    `android:fullBackupContent`;
  - create `android/app/src/main/res/xml/data_extraction_rules.xml` and `backup_rules.xml`. They
    exclude the `database` domain file `wambito-vault-*` (the sqflite default path), the
    `sharedpref` file `FlutterSecureStorage.xml`, and, on API 31+, the whole `cloud-backup` for
    those two.
  - `apps/mobile/ios/Runner/Device/DeviceChannel.swift`: a new method `excludeFromBackup`
    (`{path}`) that sets `URLResourceValues.isExcludedFromBackup = true`;
  - `MainActivity.kt`'s `wambito/device` handler: the same method, returning `true` (Android
    excludes by XML).
- Create: `apps/mobile/lib/local/backup.dart`, with
  `Future<void> excludeVaultFromBackup(String path)`, which calls the channel and ignores
  `MissingPluginException`.
- Test:
  - `android/app/src/test/.../BackupRulesTest.kt`, which parses both XML files and asserts the two
    exclusions;
  - `test/local/backup_test.dart`, which checks that the channel gets the vault path once per open
    (fake channel).

- [ ] **Step 1: Write the failing tests.**
- [ ] **Step 2: Run them.** Run
  `cd android && JAVA_HOME=<JDK 17> ./gradlew :app:testDebugUnitTest --console=plain --tests '*BackupRulesTest*'`
  and `flutter test test/local/backup_test.dart`. Expected: FAIL.
- [ ] **Step 3: Implement.** Call `excludeVaultFromBackup` from `SqliteStore.open` (an injectable
  callback; tests pass a fake).
- [ ] **Step 4: Run the tests and the guard.** Run them and `scripts/check-channels.sh` (root).
  Expected: PASS.
- [ ] **Step 5: Commit:** `feat(mobile): keep the vault and keys out of backups`.

### Task 9: Key storage and key acceptance

**Files:**
- Create:
  - `apps/mobile/lib/local/key_storage.dart`: secure storage, with the key names of Global
    Constraints;
  - `apps/mobile/lib/local/keys.dart`, the twin of `keys.ts`. This task covers the loading and
    acceptance half: `Keyring`, `LocalKeys`, `KeysError`, `KeysApi` (the `/v2/keys` calls),
    `listKeys`, `listWraps`, `chainDown`, `loadLocalKeys`, `refreshKeys`, `dropKeyVersion` and
    `forgetDevice`.
- Test: `apps/mobile/test/local/keys_refresh_test.dart`.

**Interfaces:**
- Consumes: Task 2's crypto.
- Produces:
  - `class Keyring { int current; Map<int, RecordKeys> byVersion; }`;
  - `class LocalKeys { Keyring keyring; }`;
  - `class KeysError implements Exception { String code; int? status; }`, with the codes of
    `keys.ts`'s `KeysErrorCode`;
  - `class KeysOptions { String userId; Dio dio; KeyStorage storage; }`, where `dio` is the network
    client, without the local interceptor;
  - `Future<LocalKeys?> loadLocalKeys(String userId, KeyStorage storage)`;
  - `Future<LocalKeys> refreshKeys(KeysOptions)`;
  - `Future<void> dropKeyVersion(String userId, int keyV, KeyStorage)`;
  - `Future<void> forgetDevice(String userId, KeyStorage)`, which deletes every
    `wambito.vault.<userId>.*` key;
  - `class KeyStorage` over `FlutterSecureStorage`, with `readDataKey(userId, v)`,
    `writeDataKey(userId, v, bytes)`, `current(userId)`, `setCurrent`, `devicePrivateKey(userId)`,
    `setDevicePrivateKey`, `versions(userId)` and `deleteAll(userId)`. Tests use an in-memory fake.

- [ ] **Step 1: Write the failing tests.** Port `keys.test.ts`'s cases for refresh, links, strict
  device wraps, non-strict passkey and recovery wraps, `tampered`, `device_removed`,
  `session_changed` and dropping a version. Mock the server with a Dio `HttpClientAdapter` fake.
  Add `keysOfAnotherAccountAreNeverLoaded`: storage holds A's keys, and
  `loadLocalKeys('B', storage)` returns `null` (Review Focus 5).
- [ ] **Step 2: Run** `flutter test test/local/keys_refresh_test.dart`. Expected: FAIL.
- [ ] **Step 3: Implement.** Keep the raw DK per version in secure storage. `Keyring.byVersion` is
  derived with `deriveRecordKeys` at load. On `tampered`, zero every key in memory and keep the
  storage as `keys.ts` does.
- [ ] **Step 4: Run the tests.** Expected: PASS.
- [ ] **Step 5: Commit:** `feat(mobile): load and accept data keys like the web`.

### Task 10: Account setup and unlock

**Files:**
- Modify: `apps/mobile/lib/local/keys.dart`. This task adds the setup half: `enrollDevice`,
  `PreparedAccount`, `prepareAccount`, `unlockWithRecovery`, `unlockWithPasskey` and
  `addPasskeyWrap`, plus `firstKeyV = 1`.
- Test: `apps/mobile/test/local/keys_setup_test.dart`.

**Interfaces:**
- Produces:
  - `class PreparedAccount { String? recoveryKey; Future<LocalKeys> Function() commit; }`
    (`recoveryKey` is null for a guest);
  - `Future<PreparedAccount> prepareAccount(KeysOptions o, {required bool guest})`;
  - `Future<LocalKeys> unlockWithRecovery(KeysOptions o, String text)`;
  - `Future<LocalKeys> unlockWithPasskey(KeysOptions o, PasskeyPrf p)`;
  - `Future<void> addPasskeyWrap(KeysOptions o, PasskeyPrf p)`.

  Each of these that ends unlocked calls `enrollDevice`: an X25519 key pair, its private key stored,
  and a device wrap with attestation uploaded.

- [ ] **Step 1: Write the failing tests.** Port `keys.test.ts`'s setup and unlock cases:
  `already_set_up`, `bad_recovery_key`, `wrong_recovery_key`, `no_passkey_wrap`, `unknown_passkey`,
  `rotated_elsewhere`, and the guest without a recovery wrap. Add
  `unlockWithRecoveryAcceptsSloppyInput`: the key in lower case, with spaces and dashes, O for 0 and
  I/L for 1, unlocks.
- [ ] **Step 2: Run them.** Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `flutter test test/local`. Expected: PASS.
- [ ] **Step 5: Commit:** `feat(mobile): set up and unlock the data key`.

### Task 11: Local backend and the interceptor

**Files:**
- Create:
  - `apps/mobile/lib/local/ids.dart`, the twin of `ids.ts`: `String uuidv7([int? nowMs])` and
    `String uuidv5(String namespace, String name)`;
  - `apps/mobile/lib/local/backend.dart`, the twin of `backend.ts`;
  - `apps/mobile/lib/local/backend_interceptor.dart`.
- Test:
  - `apps/mobile/test/local/ids_test.dart`, which ports `ids.test.ts`;
  - `apps/mobile/test/local/backend_test.dart`, which ports `backend.test.ts`;
  - `apps/mobile/test/local/backend_shapes_test.dart`;
  - `apps/mobile/test/fixtures/local_backend/*.json`, recorded API answers.

**Interfaces:**
- Consumes: Tasks 4–6.
- Produces:
  - `class UnavailableRoute { String method; String path; bool prefix; }`;
  - `const localUnavailable = [UnavailableRoute('*', '/v1/me/export'), UnavailableRoute('*', '/v1/imports', prefix: true), UnavailableRoute('*', '/v1/me/assistants', prefix: true)]`;
  - `class LocalResponse { int status; Object? body; }`;
  - `class LocalBackend` with `Future<LocalResponse?> handle(String method, String path, Map<String, String> query, Object? body)`.
    It returns `null` for a path it does not serve (the interceptor then lets it go to the
    network).
  - `LocalBackend createLocalBackend({required FinanceStore store, required DateTime Function() now, required List<UnavailableRoute> unavailable, required String timezone})`;
  - `class LocalBackendInterceptor extends Interceptor`, with
    `LocalBackendInterceptor(LocalBackend backend, {void Function()? afterWrite})`. It strips the
    `/api` base path, and calls `afterWrite` after a 2xx POST, PATCH, PUT or DELETE.
- Routes: exactly those `backend.ts` `route()` serves today (spec section 5.1). `DELETE /v1/me`
  always goes to the network. An unavailable route answers 403 `demo_unavailable`, with the problem
  body `backend.ts` uses.

- [ ] **Step 1: Write the failing tests.**
  - Port `backend.test.ts`.
  - `backend_shapes_test.dart`: for each route, seed the memory store with the data of
    `test/fixtures/local_backend/seed.json`, then compare the local answer with
    `<route>.json`. Record those files once against the dev stack with a `plain` account seeded the
    same way. Record them with `tool/record_local_backend_fixtures.dart` (create it: it signs in,
    seeds, calls each route, and writes the JSON with ids and timestamps replaced by the seed's).
  - Add `interceptorLetsAuthAndV2Through`: `/v1/me` GET and `/v2/sync` reach the adapter, and
    `/v1/transactions` does not.
- [ ] **Step 2: Run** `flutter test test/local/backend_test.dart test/local/backend_shapes_test.dart test/local/ids_test.dart`.
  Expected: FAIL.
- [ ] **Step 3: Implement.** One store transaction per request, as `backend.ts` does.
- [ ] **Step 4: Run the tests.** Expected: PASS.
- [ ] **Step 5: Commit:** `feat(mobile): answer the v1 finance routes from the vault`.

### Task 12: Sync engine and vault session

**Files:**
- Create:
  - `apps/mobile/lib/local/sync.dart`, the twin of `sync.ts`;
  - `apps/mobile/lib/local/vault_session.dart`, the twin of `vault-session.ts`;
  - `apps/mobile/lib/local/install_marker.dart`.
- Test:
  - `apps/mobile/test/local/sync_test.dart`, which ports `sync.test.ts` with a fake `/v2` (port the
    TS fake);
  - `apps/mobile/test/local/vault_session_test.dart`, which ports `vault-session.test.ts`.

**Interfaces:**
- Consumes: Tasks 7, 9, 11.
- Produces:
  - `SyncEngine createSyncEngine(SyncEngineOptions o)`, where `SyncEngineOptions { SqliteStore store; Dio dio; String userId; Keyring Function() keyring; Future<LocalKeys> Function() refreshKeys; void Function(SyncProblem) onError; }`;
  - `SyncEngine { Future<SyncResult> run(); void start(); void stop(); }`;
  - `SyncResult`, `SyncProblem`, and `SyncProblemCode` with the codes of `sync.ts`;
  - `class VaultSession { String userId; Interceptor interceptor; void Function() subscribe(void Function()); onClosed; onRemoved; onUnverified; Future<void> sync(); Future<void> reloadKeys(); Future<int> pendingChanges(); Future<void> close(); }`;
  - `Future<VaultSession> openVaultSession(OpenVaultOptions o)`, with
    `OpenVaultOptions { VaultProfile profile; LocalKeys keys; bool fresh; Dio network; KeyStorage storage; DateTime Function()? now; void Function()? onUnauthorized; void Function()? onSessionChanged; Future<SqliteStore> Function(String userId)? openStore; }`;
  - `Future<void> forgetVault(String userId, KeyStorage storage)`, which deletes the vault file
    and every key;
  - `abstract interface class InstallMarker { Future<bool> exists(); Future<void> write(); }`,
    implemented by `FileInstallMarker`: a file `wambito.installed` in Application Support. App files
    go with the app on both platforms; Keychain items do not.
  - `Future<void> clearKeysAfterReinstall(KeyStorage storage, InstallMarker marker)`. If the marker
    is missing, it deletes every `wambito.vault.*` and `wambito.encryption.*` key, then writes the
    marker. This needs `KeyStorage.deleteAllVaultKeys()`, which Task 12 adds.
- The lock: one run per user in the process. A second `run()` while one runs returns the same future
  and, if it was asked after a local write, schedules exactly one more run.
- Triggers: `start()` subscribes to the app lifecycle resume (`AppLifecycleListener`) and to store
  commits of origin `local`. Pull-to-refresh calls `session.sync()`.

- [ ] **Step 1: Write the failing tests.**
  - Port `sync.test.ts` and `vault-session.test.ts`.
  - Add `concurrentTriggersRunOnce` (Review Focus 3): three `run()` calls at once lead to one
    `/v2/sync` push and pull, plus at most one follow-up run.
  - Add `signOutDuringSyncLeavesNothing` (Review Focus 4): the fake `/v2` holds a pull until
    `forgetVault` completes. Then the vault file does not exist, `KeyStorage` is empty, and the run
    ends `closed`.
  - Add `reinstallClearsOldKeys` (Review Focus 1): storage has keys, the marker is missing, and
    after `clearKeysAfterReinstall` the storage is empty and the marker is set.
- [ ] **Step 2: Run** `flutter test test/local/sync_test.dart test/local/vault_session_test.dart`.
  Expected: FAIL.
- [ ] **Step 3: Implement.** Call `clearKeysAfterReinstall` in `bootstrap()` before anything reads
  secure storage.
- [ ] **Step 4: Run the tests.** Expected: PASS.
- [ ] **Step 5: Commit:** `feat(mobile): sync the vault through v2`.

### Task 13: Vault gate and vault model

**Files:**
- Create:
  - `apps/mobile/lib/vault/vault_gate.dart`, the twin of
    `apps/web/app/features/vault/vault-gate.ts`;
  - `apps/mobile/lib/vault/vault_model.dart`, the twin of `vault-model.ts`: `groupPosition`,
    `confirmationMatches`, and the random positions;
  - `apps/mobile/lib/vault/encryption_mode.dart`.
- Test: `apps/mobile/test/vault/vault_gate_test.dart` and `vault_model_test.dart`, which port the TS
  tests.

**Interfaces:**
- Consumes: Tasks 1, 9, 10, 12.
- Produces:
  - `sealed class VaultGateState`, with the subclasses `Checking`, `Setup(String recoveryKey)`,
    `Committing`, `Unlock({String? notice})` (`notice` is `removed` | `unverified`),
    `Opening`, `Ready(VaultSession session)` and `Locked(LockedKind kind, bool retrying)`, where
    `LockedKind` is `error`, `offline`, `unsupported` or `guest`. `Pairing` is left out until 3b.
  - `class VaultGate` with `state`, `subscribe`, `start()`, `confirmSetup()`,
    `Future<String?> unlock(String text)` (an error code or null),
    `Future<String?> unlockWithPasskey()`, `retry()`, `closed()`, `sessionChanged()`, `removed()`
    and `unverified()`;
  - `VaultGateDeps` as in TS, minus the pairing members;
  - `enum EncryptionMode { plain, preview }`;
  - `final encryptionModeProvider = FutureProvider<EncryptionMode?>(…)`. It is `null` when signed
    out. It reads `getMe().encryption` and caches it under `wambito.encryption.<userId>`, so an
    offline start knows the mode (the web's `rememberPreviewAccount`).
  - `final vaultGateProvider = Provider<VaultGate?>(…)`. It is `null` for `plain`, and is built
    with deps wired to Tasks 9–12.
  - `final vaultSessionProvider = Provider<VaultSession?>(…)`. It is the session when the gate is
    `Ready`.
- `apiClientProvider` (`lib/api/session.dart`) adds `vaultSessionProvider`'s interceptor to the Dio
  when present. `KeysOptions.dio` and `OpenVaultOptions.network` get a client without it.

- [ ] **Step 1: Port the TS cases.** Port `vault-gate.test.ts` and `vault-model.test.ts` (minus
  pairing).
- [ ] **Step 2: Run them.** Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `flutter test test/vault test/api`. Expected: PASS, and the existing `test/api`
  tests are unchanged.
- [ ] **Step 5: Commit:** `feat(mobile): add the vault gate`.

### Task 14: Unlock, recovery key and locked screens, router, sign-out

**Files:**
- Create:
  - `apps/mobile/lib/vault/vault_screen.dart`, route `/unlock`. It renders the gate state:
    - `Setup` shows `RecoveryKeySetupView`;
    - `Unlock` shows `UnlockView`;
    - `Locked` shows `LockedView`;
    - `Checking`, `Opening` and `Committing` show the app's loading view.
  - `lib/vault/recovery_key_setup_view.dart`, `lib/vault/unlock_view.dart`,
    `lib/vault/locked_view.dart`. They mirror `RecoveryKeySetup.tsx`, `Unlock.tsx` and
    `Locked.tsx`. Recovery setup has Copy and Share (system share sheet, through `wambito/files`
    `share`) instead of Download, and the four-character confirmation.
  - New ARB keys in all four languages.
- Modify:
  - `apps/mobile/lib/router.dart`: when signed in, `encryptionModeProvider` is `preview`, and the
    gate is not `Ready`, every path except `/auth/verify`, `/entry*` and `/debug/*` redirects to
    `/unlock`; `/unlock` once `Ready` redirects to `/`.
  - `apps/mobile/lib/api/session.dart`:
    - `signOut` and `accountDeleted` call `forgetVault` for the signed-in user (awaited, before the
      token goes);
    - before a sign-out of a `preview` account with `pendingChanges() > 0`, the caller shows the
      confirm sheet "You have N changes not synced yet", with "Sync and sign out" (sync, then sign
      out) and "Sign out anyway".
  - The guest notice copy: add the sentence that deleting the app loses the data. Also update the
    Android `strings.xml` and regenerate the iOS strings with `dart run scripts/gen-ios-strings.dart`.
  - "Save your progress" (claiming the email) for a guest in `preview`: after the claim succeeds,
    the gate runs `prepareAccount(guest: false)`-style recovery wrap creation and shows `Setup`.
    Port how `vault-gate.ts` handles a guest becoming a real account.
- Test:
  - `test/vault/vault_screen_test.dart`: widget tests per state, with a fake gate. They check:
    - the four-character confirmation enables Continue;
    - a wrong recovery key shows "That key does not open this account";
    - the passkey button shows only when PRF is supported and the account has a passkey wrap.
  - `test/navigation/router_vault_test.dart`: the redirects above.
  - `test/api/session_vault_test.dart`: sign-out deletes the vault and keys; the unsynced warning
    shows with N = 2.
  - `test/l10n`: the new keys exist in all four ARBs.

- [ ] **Step 1: Write the failing tests.**
- [ ] **Step 2: Run them.** Expected: FAIL.
- [ ] **Step 3: Implement.** Use the existing UI kit (`lib/ui/`) and tokens; no new components unless
  the web's screen needs one.
- [ ] **Step 4: Run** `flutter analyze && flutter test --exclude-tags golden,stack`. Expected: PASS.
- [ ] **Step 5: Commit:** `feat(mobile): unlock and set up the vault on the phone`.

### Task 15: "Coming soon with encryption" for what 3a leaves out

**Files:**
- Modify:
  - `lib/capture_auto/` (the settings section): for `preview`, the section shows the notice instead
    of the switches, and the app calls the capture channel's `clearQueue()` once when the mode
    becomes `preview`, so nothing queued goes out. The server would refuse it anyway with 403
    `encrypted_account`.
  - `lib/home/widget_sync.dart`: for `preview`, write the snapshot with no figures, with "Coming soon
    with encryption" as its line, and never call the API.
  - `lib/notices/` (Dart side of `wambito/notices`): for `preview`, `cancelDue` and no
    `scheduleDue`.
  - `lib/settings/export_settings.dart`, `lib/import/`, `lib/settings/assistants_section.dart`: for
    `preview`, show the notice instead of the action.
- Test: one widget or unit test per item above, under the matching `test/` folder, each asserting the
  notice text and that no API or channel call leaves (fake client or channel records zero calls).

- [ ] **Step 1: Write the failing tests.**
- [ ] **Step 2: Run them.** Expected: FAIL.
- [ ] **Step 3: Implement,** reading `encryptionModeProvider`.
- [ ] **Step 4: Run** `flutter test --exclude-tags golden,stack`. Expected: PASS.
- [ ] **Step 5: Commit:** `feat(mobile): show what waits for encryption on preview accounts`.

### Task 16: End-to-end against the real API, CI, docs

**Files:**
- Create:
  - `apps/mobile/test_stack/vault_e2e_test.dart`, tagged `stack`. It is plain `flutter test` with
    `sqflite_common_ffi` and the in-memory `KeyStorage`; it needs no emulator.
  - `apps/mobile/scripts/run-vault-e2e.sh`.
- Modify:
  - `.github/workflows/ci.yml`: a new job `mobile-e2e`, with the same path filter as `mobile` plus
    `apps/api/**` and `packages/{crypto,core,db}/**`.
  - `apps/mobile/AGENTS.md`: the map of `lib/crypto/`, `lib/core/`, `lib/local/` and `lib/vault/`;
    the shared-fixtures rule; `run-vault-e2e.sh`; the PRF probe.
  - root `AGENTS.md`: the `mobile-e2e` line under "What CI runs".
  - `packages/core/AGENTS.md`: if Task 3 did not already add the fixtures.

**Interfaces:**
- Consumes: every earlier task. The test signs in as `preview@wambito.test` the way
  `apps/web/e2e/helpers.ts` `signInExisting` does: an email code read from Mailpit's API on
  `:8025`, then the app's own `AuthApi` for the bearer token.

- [ ] **Step 1: Write the test.** `vault_e2e_test.dart`:
  1. Sign in.
  2. Set up the account through `VaultGate` with deps on the real stack, and keep the recovery key.
  3. Through the interceptor, POST `/v1/transactions` with description `"almuerzo e2e"` and amount
     `-1250000` cents.
  4. Run `session.sync()`.
  5. Fetch `/v2/sync` raw and assert that no record body, decoded as UTF-8, contains `almuerzo`.
  6. Open a second vault (new temp dir, empty `KeyStorage`) and `unlock` it with the recovery key.
  7. GET `/v1/transactions` through the second session; it returns the description and amount.
- [ ] **Step 2: Write `run-vault-e2e.sh`.** It assumes the root stack is up, runs
  `seed:e2e-preview` in the api container, then runs
  `flutter test --tags stack test_stack/vault_e2e_test.dart`. Finally it runs
  `docker compose exec -T postgres psql -U wambito -tAc "select count(*) from records where convert_from(body,'UTF8') ilike '%almuerzo%'"`,
  which must print `0`. If the psql user, table or column differ, read `packages/db` and
  `.env.example` and use those.
- [ ] **Step 3: Run it locally.** From the root, run `cp -n .env.example .env; docker compose up -d`,
  then `apps/mobile/scripts/run-vault-e2e.sh`. Expected: the test passes and psql prints `0`.
- [ ] **Step 4: Add the job.** `mobile-e2e` installs Flutter as the `mobile` job does, starts the
  stack as the `e2e` job does, and runs the script.
- [ ] **Step 5: Update the three `AGENTS.md` files.**
- [ ] **Step 6: Final check.** From the root, run:
  - `pnpm lint && pnpm typecheck && pnpm test`;
  - `scripts/check-old-name.sh && scripts/check-channels.sh`;
  - in `apps/mobile`: `flutter analyze`, `flutter test --exclude-tags golden,stack`, the Gradle unit
    tests, and `swift test --package-path ios/WambitoNative`.

  All exit 0.
- [ ] **Step 7: Commit:** `ci: run the phone vault end to end against the api`, staging the files
  above. Then open the PR against `main`, with the body ending in the Claude Code line, and a manual
  check list for the founder: a `preview` account on the Android phone and on the iPhone, set up,
  add, sync, sign out, and unlock with the recovery key.
