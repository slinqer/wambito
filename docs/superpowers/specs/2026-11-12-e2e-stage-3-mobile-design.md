# E2E stage 3: the phone app (Android and iOS)

Status: design, agreed section by section in chat on 2026-11-12. Builds on
`2026-11-08-end-to-end-encryption-design.md` (the "E2E design"), `2026-11-08-e2e-stage-1b-design.md`
and `2026-11-10-e2e-key-links-design.md`. Same switch as the web: an account is in the new format only
when `GET /v1/me` says `encryption: "preview"` (`E2E_PREVIEW_USER_IDS` in `apps/api/src/config.ts`).
Accounts in `plain` keep today's app, untouched.

## 1. Goal and scope

The Flutter app (`apps/mobile`) works with a `preview` account on Android and iOS: it holds the data
key, keeps the finances in a local database, syncs sealed records through `/v2`, and never sends a
finance field to the server in clear. It is the phone counterpart of the web's `app/local/`.

Two deliveries, each its own plan and PR:

- **3a, the core:**
  - Dart crypto passing `packages/crypto/test-vectors.json`;
  - the local store on SQLite and the `/v2` sync engine;
  - the local backend answering `/v1`, and the core rules ported to Dart with shared fixtures;
  - unlock by passkey PRF or recovery key, recovery key setup for a new account, and guests;
  - applying another device's rotation (links, `tampered`);
  - sign-out and the device-removed 401 wipe everything local;
  - automatic capture, the home widget and the due notices show "Coming soon with encryption" for
    `preview` accounts.
- **3b, the rest of the phone:**
  - Android automatic capture through a headless Dart engine;
  - the widget written by Dart only;
  - due notices computed in Dart and scheduled by the native side on both platforms;
  - background sync;
  - QR pairing both ways;
  - Settings → Security: passkeys, devices, removal with rotation, a new recovery key;
  - the device screen lock for sensitive operations.

Out of stage 3:
- export, import and the AI assistants (stage 4);
- the migration of `plain` accounts (stage 5);
- an app lock to open Wambito (a separate decision).

The screens of those features show "Coming soon with encryption" for `preview` accounts.

## 2. Approach

A Dio interceptor answers the `/v1` finance routes from a local backend over SQLite, the way the web's
`createLocalBackend` (`apps/web/app/local/backend.ts`) answers them over IndexedDB. The generated client
(`lib/api/gen`), the repositories and the screens keep calling `/v1` and do not know where the answer
came from.

Two alternatives were rejected:
- rewriting every repository against a local store, which means many more changes and two code paths
  per screen;
- running the TypeScript backend in a JS engine on the phone, which adds a native runtime that
  F-Droid would have to build.

The Dart code mirrors the web's file layout, so a change on one side has an obvious counterpart:

| Web (`apps/web/app/local/`) | Phone (`apps/mobile/lib/`) |
|---|---|
| `packages/crypto/src` | `crypto/` |
| `store.ts`, `store-contract.ts`, `memory-store.ts` | `local/store.dart`, `test/local/store_contract.dart`, `local/memory_store.dart` |
| `db.ts`, `encrypted-store.ts` | `local/db.dart`, `local/sqlite_store.dart` |
| `sync.ts` | `local/sync.dart` |
| `keys.ts`, `prf.ts`, `vault-session.ts` | `local/keys.dart`, `local/prf.dart`, `local/vault_session.dart` |
| `rotate.ts`, `pairing.ts` (3b) | `local/rotate.dart`, `local/pairing.dart` |
| `backend.ts`, `ids.ts` | `local/backend.dart`, `local/ids.dart` |
| `packages/core/src` | `core/` |

## 3. Crypto and keys

**Library:** `cryptography` plus `cryptography_flutter` (Apache-2.0). They provide:
- HKDF-SHA256 and X25519;
- AES-256-GCM through the platform (Android `javax.crypto`, iOS CryptoKit);
- a pure-Dart fallback.

Neither pulls in Google libraries. Versions are pinned exactly, like the rest of `pubspec.yaml`, and
both get a line in the licence list.

**`lib/crypto/`** implements exactly what `packages/crypto` does:
- record sealing and opening with the AAD of the E2E design;
- dedupe tags;
- device wraps (X25519 + HKDF + AES-GCM) and passkey and recovery wraps;
- key links `link(v)` and the attestation HMAC;
- the PRF salt `SHA-256("wambito/v1/prf")`;
- the recovery key in Crockford base32: parsing accepts lower case and dashes, and reads O as 0 and
  I/L as 1.

A Dart test reads `packages/crypto/test-vectors.json` (by relative path from `apps/mobile/test/`) and
must pass every vector. A new vector in TypeScript therefore fails the Dart suite until it is ported.

**Where keys live:** `flutter_secure_storage`, which uses the Keystore on Android and the Keychain on
iOS with `first_unlock_this_device`, so keys never go to iCloud or another phone. It holds:
- the DK of each held key version;
- the X25519 device private key;
- the user id these belong to.

The phone keeps the DK itself, so opening the app never asks for anything once the phone is unlocked.

**Acceptance rules (as on the web; tests share the web's cases):**
- **Device wraps are strict:**
  - a version above the current one needs a link chain from a held version and a valid canary;
  - a version below the current one must already be held.
- **Passkey and recovery wraps are non-strict:**
  - they never overwrite a held version;
  - a version below the current one means `tampered`.
- **`tampered`:**
  - stops sync with `key_unverified`;
  - shows the Unlock notice, which opens `/unlock`.
- **A 401 because this device was removed** wipes the vault (section 6.4).

**Passkey PRF on the native side:**
- **Android:** `PasskeyChannel.kt` passes the WebAuthn JSON to Credential Manager. The `prf` extension
  most likely goes through unchanged, and the result comes back in `clientExtensionResults`.
- **iOS:** `PasskeyChannel.swift` maps it to `ASAuthorizationPublicKeyCredentialPRFAssertionInput`
  (iOS 18+); older iOS reports PRF as unsupported.

**Task 1 of the 3a plan is a spike** run on the founder's Android phone and iPhone: create a passkey
with PRF, read the PRF output twice, and check that it is identical and matches the web for the same
passkey. The result goes in `docs/superpowers/reports/`.

Where PRF does not work, that phone unlocks with the recovery key (and with QR pairing from 3b). The
design does not depend on PRF.

## 4. Local store and sync

### 4.1 Database

The store uses `sqflite` (system SQLite: no native library to build, fine for F-Droid). It keeps one
file per account, `wambito-vault-<userId>.db`, in the app's private directory, with the same layout
as the web's `db.ts`:
- **one table per record type** (`transaction`, `category`, `budget`, `recurrence`, `merchant`,
  `settings`, `account`: `RECORD_TYPES` in `packages/core/src/records.ts`). Each row keeps:
  - `id`, `version`, `key_v` and `deleted`;
  - the body as JSON;
  - indexed columns for what the backend filters and sorts on (date, category id, amount in cents).
- **`outbox`:** pending local changes, with the web's fields: base version, parked-until, attempts,
  `abandoned`, `reseal`, set-aside;
- **`meta`:** sync cursor, current key version, `tampered`, last refresh;
- **`quarantine`:** records that could not be opened, with the reason and their `key_v`.

Keys are not in this database; they stay in secure storage (section 3).

A test runs against the store contract that both stores share, `test/local/store_contract.dart`. The
memory store passes it, and so does the SQLite store through `sqflite_common_ffi`. That contract is
the Dart translation of `store-contract.ts`.

### 4.2 At rest

Rows hold the opened records, as the web's IndexedDB vault does. Sealing each row would protect
nothing more:
- the database is in the app's private directory, and the OS encrypts the disk;
- the DK lives on the same phone, so whoever can read the database while the phone is unlocked can
  also use the key.

Sealing each row would also rule out filtering and summing in SQL.

What is added: the vault and the keys never leave the phone in a backup.
- **Android:** `dataExtractionRules` (API 31+) and `fullBackupContent` (older) exclude the database
  directory and the secure-storage prefs.
- **iOS:** the vault file is marked `isExcludedFromBackup`, and the Keychain items are
  `ThisDeviceOnly`.

A test on each platform checks the exclusion rules name those paths.

### 4.3 Sync engine

`local/sync.dart` is a port of `sync.ts`, with the same behaviour and the same test cases, run against
a fake `/v2`. It covers:
- **Push the outbox, then pull `/v2/sync` from the cursor.**
- **Conflicts:**
  - the field-by-field conflict merge;
  - a create conflict takes the server copy plus the fields changed after the create.
- **Failed pushes:**
  - a failing entry is parked (back-off from 1 minute, doubling, up to 6 hours) and never blocks the
    pull of other ids;
  - on the fifth failure the entry is abandoned;
  - a whole-batch 413/422 is bisected.
- **Key versions:**
  - a record opens with the keys of its own `keyV`; every change is sealed under the current version;
  - a newer version, or `key_version_mismatch`, refreshes the keys;
  - a version that is still unknown quarantines the record as `unknown_key_version`; it is retried
    when the current version grows and on the engine's first pull.
- **Upgrade pass:** records under an older `keyV` get re-sealed through `reseal` outbox entries, at
  most 500 per run. An old version's key is dropped once no local record uses it.
- **`410`:** a full resync that sets pending edits aside and re-applies them after the download.
- **Problems that stop the run:**
  - `tampered`, with `key_unverified`;
  - 409 `session_changed`;
  - a closed store.
- **Account header:** every `/v2` call sends `x-wambito-user`.
- **One run at a time per user:** a Dart lock in the main isolate. In 3b, the headless engine takes a
  lock file in the vault directory instead (section 7.5).

**When it runs (3a):**
- on app start;
- on return to the foreground;
- after every local write;
- on pull-to-refresh.

Background sync comes in 3b.

## 5. Local backend and core rules

### 5.1 The interceptor

`LocalBackendInterceptor` is a Dio interceptor, added when `/v1/me` says `preview` and the vault is
open:
- **Answered locally:** the `/v1` finance routes the web's `backend.ts` serves:
  - `/v1/summary`;
  - `/v1/transactions`, `/v1/transactions/{id}` and its `restore`, `suggestions`, `review`;
  - `/v1/categories`, `/v1/categories/{id}` and its `budget` (budgets are set per category);
  - `/v1/recurrences` and `/v1/recurrences/{id}`;
  - `/v1/reports/by-category`, `/trend`, `/cost-of-living`;
  - the finance fields of `/v1/me`.

  The list is the web backend's at the time the plan is written; the plan copies it from
  `backend.ts`.

  The answers have the same JSON shape as the API. One test per route compares the local answer with
  a recorded API answer for the same data.
- **Goes to the network:** auth, the rest of `/v1/me`, `/v2/*`, and every route that is not the
  user's finance data.
- **Turned-off routes** (`/v1/me/export`, `/v1/imports/*`, `/v1/me/assistants/*`: the web's
  `LOCAL_UNAVAILABLE` in `vault-session.ts`) answer 403 `demo_unavailable` locally, the code the web's backend gives them. The
  screen shows "Coming soon with encryption" instead of failing quietly. Deleting the account still
  goes to the server.

### 5.2 Writes

A local POST, PATCH or DELETE does two things in one SQLite transaction:
1. it updates the record table;
2. it queues an outbox entry.

Then it triggers a sync. The answer is immediate, with or without network.

The ids are UUID v7, and v5 for deterministic records, as in `ids.ts`.

The current `lib/offline/pending_saves.dart` queue stays for `plain` accounts only. A `preview`
account's outbox replaces it.

### 5.3 Core rules in Dart (`lib/core/`)

The rules the server computed and the app now needs, ported from `packages/core/src`:
- **money:** integer cents and rounding;
- **dates:** month boundaries in the user's zone;
- **budgets:** spent, left, alerts;
- **reports:** by category, trend, cost of living;
- **the summary;**
- **recurrence:** next dates. `lib/recurring/recurring_model.dart` moves here and is completed;
- **the record schemas:** loose validation of the bodies.

The quick-capture parser is already in Dart (`lib/capture/parser/`) and already reads
`packages/core/quick-capture/cases.json`.

**Shared fixtures:**
- The Dart tests read `packages/core/reports/cases.json`, `quick-capture/cases.json` and the new
  fixture files by relative path.
- Where a rule has no fixture yet (budgets, recurrence, summary), the plan first adds one in
  `packages/core`, used by the TypeScript test, then the Dart test reads it.
- A rule change in TypeScript fails the Dart suite until it is ported.

## 6. Unlock, recovery key, guests, sign-out

### 6.1 When the app asks

Only when this phone holds no DK for the account:
- signing in to a `preview` account that already has keys;
- after `tampered`.

### 6.2 `/unlock`, "Unlock your data"

The router requires it before home while the DK is missing. It offers:
- **"Use your passkey":** the primary action when the phone reports PRF support and the account has a
  passkey wrap. It opens the DK without typing.
- **"Use your recovery key":** a field with the parsing of section 3. A wrong key says "That key does
  not open this account" and nothing more.
- **"Add this phone from another device" (3b):** shows the pairing QR.

After an unlock, the phone registers its X25519 device key and uploads its own device wrap. From then
on it does not need the recovery key again.

### 6.3 A new `preview` account created on the phone (first device)

1. The phone creates the DK.
2. The recovery key screen shows the key in groups and offers three ways to keep it:
   - Copy;
   - Share, through the system sheet, for example to a password manager;
   - writing it down.
3. To go on, the person types back four characters of it at positions chosen at random, as on the
   web (`apps/web/app/features/vault/vault-model.ts`, `confirmationMatches`).
4. If PRF works, the app then offers to create a passkey with a wrap.

### 6.4 Guests (E2E design, section 10)

- A guest gets the DK and a device key, but no recovery key and no passkey wrap.
- "Save your progress" (turning the guest into a real account) requires the recovery key screen
  before it finishes.
- The existing local guest notice gains one sentence: deleting the app loses the data.

### 6.5 Sign-out and device removed

Sign-out, and a 401 that says this device was removed, both delete:
- the vault file;
- the keys in secure storage;
- the home cache (`home_cache.dart`) and the widget snapshot.

Before a sign-out, if the outbox holds changes not yet pushed, a confirm sheet says "You have N
changes not synced yet" and offers to sync first.

## 7. Delivery 3b

### 7.1 Android automatic capture

Today the chain is `CaptureListener` → `CaptureQueue` → `SendCapturesWorker`, which posts text to the
API; `ConfirmCaptureWorker` confirms.

For a `preview` account:
- Kotlin only queues.
- `SendCapturesWorker` starts a headless Flutter engine on a Dart entry point `captureMain`, which
  1. reads the queue;
  2. parses with the same parser;
  3. writes through the local backend;
  4. syncs.
- `ConfirmCaptureWorker` takes the same path.

The worker learns the account's mode from a flag that the Dart side writes after `/v1/me`. A Gradle
unit test covers that decision.

If the engine fails, the capture stays queued and is retried. It is never dropped and never sent in
clear.

iOS has no notification capture, so this part is Android only.

### 7.2 Widget

For a `preview` account only Dart writes the snapshot (`lib/home/widget_snapshot.dart`): after every
sync and every local write. `RefreshWorker` and `SummaryFetcher` stop calling the API for such
accounts and only re-read the snapshot. A periodic refresh starts the headless engine (section 7.5).

### 7.3 Due notices

`DueWorker` (Android) and `DueTask.swift` (iOS) fetch from the API today. For a `preview` account:
- Dart computes the next due items with the ported recurrence rules;
- it hands the list to the native schedulers over the existing notice channel;
- those schedule the "Due today…" notice at 9:00 without calling the API.

The list is refreshed after every sync. No new notification plugin is added.

### 7.4 Pairing by QR

Pairing uses the stage 1 relay, with the commitment and the verification code (E2E design). It works
both ways:
- the phone shows a QR for another device to scan;
- the phone scans the web's QR.

The camera library must have no Google dependency. The plan picks one that passes `check-fdroid`;
the fallback is typing the pairing code shown under the QR.

### 7.5 Background sync

- **Android:** a periodic WorkManager job.
- **iOS:** `BGAppRefreshTask`.

Both start the headless engine on a `syncMain` entry point. It and `captureMain` share a lock file in
the vault directory, so only one sync runs at a time across the app and the workers.

### 7.6 Settings → Security

The same set as the web:
- **Passkeys:** list, add (with a wrap if PRF works), remove.
- **Devices:** list, with this phone marked. Removing a device rotates the DK and re-seals the wraps
  of the remaining devices, as `rotate.ts` does; the records follow through the upgrade pass.
- **A new recovery key:** replaces the recovery wrap and shows the key-saving screen of section 6.3.

### 7.7 Sensitive operations

Three operations ask for the phone's screen lock (fingerprint, face or PIN) through `local_auth`,
which uses only the system APIs:
- removing a device;
- creating a new recovery key;
- showing it.

A phone without a screen lock asks for the current recovery key instead.

## 8. Testing and CI

**Dart unit tests** (`flutter test`, in the existing `mobile` job):
- crypto against `test-vectors.json`;
- key acceptance (strict, non-strict, `tampered`) with the web's cases;
- the core rules against the shared fixtures;
- the store contract on both stores;
- sync against a fake `/v2`: push, pull, conflict, park and abandon, quarantine and retry, `410`,
  `tampered`, `session_changed`;
- one test per local backend route against a recorded API answer.

**Integration against the real API** (new `mobile-e2e` job, only when mobile paths or the `/v2` API
change). It starts the root stack with a test account in `E2E_PREVIEW_USER_IDS`, then runs as a
Dart test without an emulator:
1. creates the account and its recovery key;
2. writes a transaction through the local backend;
3. syncs;
4. checks in Postgres that the record holds only ciphertext;
5. on a second, empty vault, unlocks with the recovery key and reads the transaction back.

**Native tests:**
- Gradle unit tests for the capture worker's choice (`plain` or `preview`) and the backup exclusion
  rules;
- `swift test` for the PRF mapping and the backup flag.

**Guards:**
- the channel guard covers the new channels (PRF results, the headless entry points, the due list);
- `check-fdroid` confirms that no Google dependency enters. `cryptography_flutter`, `sqflite` and
  `local_auth` use only system APIs.

**Manual:** the PRF spike (task 1 of 3a), and a pass on the founder's Android phone and iPhone with a
`preview` account before each delivery's PR is merged.

## 9. Documentation

- `apps/mobile/AGENTS.md` gets the `lib/local/`, `lib/crypto/` and `lib/core/` map and the rule that
  Dart and TypeScript share fixtures.
- The root `AGENTS.md` names the `mobile-e2e` job.
- The API does not change in stage 3, so the `CHANGELOG.md` gets no line. If the plan finds a missing
  API piece, it adds the line with that change.
