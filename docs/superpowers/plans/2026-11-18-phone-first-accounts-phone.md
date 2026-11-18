# Phone-first accounts, delivery 2 (the phone) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The phone side of phone-first accounts: a welcome with "Start" that asks for nothing
(online and offline), "Protect your data" and its nudges, adding an email with the merge into an
existing account, recovery-key sign-in, approving a web sign-in QR and the sign-in notice, and the
re-upload after a deleted user. A `plain` account behaves exactly as today.

**Architecture:** Everything rides on what 3a/3b built: the vault gate, `lib/local/keys.dart`
(`prepareAccount(guest:)`, `newRecoveryKey`, the verifier), the sync engine, the pairing relay. Three
new shared pieces carry the rest: a **vault hold** (a mark in a vault's `meta` that the stale-vault
sweep respects), **record carrying** (`lib/local/merge.dart`: copy one vault's live records into
another as new local writes, as-is for adoption and the offline start, by the merge rules for a
merge), and the **sign-in approver** (`lib/local/signin_approval.dart`, on a relay client extracted
from `pairing.dart`). Every new path is reached only for a `preview` account (`GET /v1/me`
`encryption`), except the welcome itself, which shows before the mode is known.

**Tech Stack:** Flutter/Dart (Riverpod 3, go_router, Dio, `sqflite`, `flutter_secure_storage`,
`cryptography`), the generated client `lib/api/gen`, Kotlin (CameraX/ZXing scanner, manifest),
Swift (`WambitoNative`, Runner), `flutter_test`, `sqflite_common_ffi`, Gradle unit tests,
`swift test`, the `stack` e2e against the root dev stack.

**Spec:** `docs/superpowers/specs/2026-11-15-phone-first-accounts-design.md`, section 16 item 2
(sections 4, 5, 6, 7, 8.1, 8.3, 8.4, 10, 11, 15). Read with
`docs/superpowers/specs/2026-11-12-e2e-stage-3-mobile-design.md` (sections 6.3–6.5, 7.4) and the API
delivery's plan `docs/superpowers/plans/2026-11-15-phone-first-accounts-api.md` (its routes and
codes are fixed; this plan adds no API).

## Answered by the founder (2026-11-18)

1. **Offline first run while the server still makes `plain` users:** "Start" needs the network
   until the switch; no movement is ever sent to a plain account (ruling 8).
2. **"Cancel" at the merge's currency stop:** back to the session without email with its data, and
   this phone signed out of the email account (ruling 10, confirmed).
3. **The sign-in notice** fires for any new device, phones added by pairing too (ruling 16,
   confirmed).

## Global Constraints

- **Branch and PR:** `feat/phone-first-accounts-phone` from `main`, one PR. Merge only on the
  founder's yes (merging deploys the server; the app ships by `mobile-v*` tag).
- **The switch:** the phone decides from `GET /v1/me` `encryption` (`EncryptionMode.preview` in
  `lib/vault/encryption_mode.dart`, already read since 3a). A `plain` account, guest or not, sees
  today's screens, warnings, notices and `/progress`; every task names how it keeps that, and its
  tests include a `plainAccount()` (`test/support/plain_account.dart`) case that stays green. The
  welcome is the one exception (it shows before any account exists): "Start" calls the same
  `POST /auth/sign-in/anonymous` as today's "Probar sin correo".
- **API, exactly as built** (no new route, field or code in this delivery):
  - `POST /auth/sign-in/anonymous`; `POST /v1/me/claim-email/send|verify` (409 `email_taken`);
    `DELETE /v1/me`; `GET /v1/me`;
  - `PUT /v2/recovery/verifier` (`putRecoveryVerifier`, already sent by `keys.dart`);
    `POST /v2/recovery/sign-in` `{ lookup /* 16 B */, auth /* 32 B */ }` (base64url) → 200
    `{ userId }` + `set-auth-token`; 401 `recovery_key_invalid`; 429 with `retry-after`;
    403 `account_suspended`;
  - `GET /v2/signin?code=` → `{ id, commitment, label, expiresAt }`; `GET /v2/signin/{id}` (session)
    → `{ id, commitment, label, expiresAt, publicKey }`; `POST /v2/signin/{id}/approver`
    `{ publicKey }` (204; 409 `already_set`); `POST /v2/signin/{id}/seal` `{ sealed, keyV }` (204;
    409 `not_ready` | `already_sealed` | `key_version_mismatch`; 422 `approver_mismatch`); 404 once
    picked up or expired;
  - `POST /v2/me/seen` (204; `x-wambito-background: 1` changes nothing); header `x-wambito-version`
    (1–64 of `[A-Za-z0-9.+_-]`);
  - 401 codes `device_removed`, `user_deleted` (needs `x-wambito-user`), `unauthenticated`.
- **Exact values from the spec:** QR `wambito://signin?id=<id>&key=<base64url N.pub>`; code
  8 characters (`normalizePairingCode`); request lifetime 2 minutes; commitment
  `SHA-256("wambito/v1/pairing-commit" || N.pub)` (`pairingCommitment`); the 6-digit number only
  after a typed code (`pairingNumber`); home card first after **7 days or 20 movements**, then
  after dismissals **14, 30, then every 30** days; "N of 2"; merge category matching by the
  existing uniqueness folding; settings "the account's win"; anonymous user deleted only after the
  outbox is empty.
- **Copy:** every string in `lib/l10n/app_{es,en,it,pt}.arb` (es is the template;
  `test/l10n/arb_parity_test.dart` keeps the four equal), Wambi's voice. Exact wording is the
  builder's (spec 17) except the sentences the spec fixes, which are translated faithfully: the
  approval "Sign in on **{label}**?" and "Only scan a code you see on **{host}**"; the notice "A
  session was opened on {label}" / "That wasn't me"; the merge question "This email already has a
  Wambito account. Bring this phone's data into it?"; the currency stop "Your account uses {a} and
  this phone {b}."; "This passkey can sign you in but cannot open your data. Add a recovery key.";
  the home card "If you lose this phone, you lose your data. It takes one minute to protect it".
- **Phones:** persistent names need a migration to change (every new one is listed in
  `apps/mobile/AGENTS.md` Traps by the task that adds it); the signing key alias stays `lukitas`;
  no Google dependency (`scripts/check-no-google.sh`); a `wambito/*` channel or method Dart calls
  needs its Kotlin and Swift sides (`scripts/check-channels.sh`; never widen
  `.github/channel-allowlist.txt`); new Swift files are added to `ios/Runner.xcodeproj/project.pbxproj`
  by hand; pure Swift logic goes in `ios/WambitoNative` with a `swift test`.
- **Secrets:** a typed recovery key (held only as zeroable bytes, ruling 6), a token, a data key, a
  PRF or an ephemeral private key is never logged or kept beyond its use; byte arrays are zeroed as
  `keys.dart` does.
- **`lib/app.dart` lifecycle:** Tasks 2, 8, 10, 11 and 13 hook start and resume through one
  `AppLifecycleListener`, in this order: the provisional promotion (Task 11), the adoption and merge
  resumes (Tasks 10, 8; both read `listVaultHolds`), the seen ping (Task 2; needs a user id, so none
  while provisional), the sign-in notice (Task 13; needs the vault Ready). Each task adds its hook
  at its place in that order.
- **Generated files:** `lib/api/gen` is never edited (the API delivery generated every route used
  here); l10n is regenerated by `flutter pub get`.
- **No root `CHANGELOG.md` line:** nothing here changes the API or the MCP.
- **Repo rules:** failing test first; English in code and docs; invented fixtures; money in integer
  cents. Commits `feat(mobile): …` (a lowercase sentence), `feat(core): …` for Task 3's schema line,
  staged by path, never `git add -A`, never a `Co-Authored-By` line. Each task updates the
  `apps/mobile/AGENTS.md` bullet it changes.
- **Commands** (from `apps/mobile`, `export PATH="$HOME/development/flutter/bin:$PATH"`):
  `flutter test <file>`; `flutter analyze`; `flutter test --exclude-tags golden,stack`; Kotlin
  `cd android && JAVA_HOME=<JDK 17> ./gradlew :app:testDebugUnitTest --console=plain`;
  `swift test --package-path ios/WambitoNative`; `../../scripts/check-channels.sh`.

## Rulings (where the spec leaves the choice, or the code forces one)

Each with what it costs if it turns out wrong.

1. **"Recovery key done" is a synced settings field** `recoveryKeySavedAt` (timestamp or null) on
   the `settings` record (both schemas are `loose`; Task 3 adds it to `packages/core` and the Dart
   port, default null). The server has no route that says whether a verifier exists, and a local
   flag would re-nag on every new phone. The passkey step reads the server's wraps
   (`anyPasskeyWrap`). *Cost if wrong:* a nudge shown or hidden wrongly; the web delivery reads the
   same field.
2. **The home card's clock is per phone and account**, in secure storage `home.protect.<userId>`
   (`firstOpen`, `lastDismissed`, `dismissals`). "7 days of use" = 7 days since this account's first
   open on this phone; "20 movements" = 20 live transactions in the vault. *Cost:* a second phone
   starts its own schedule.
3. **The first recovery key needs no recovery-key check:** `confirmSensitive` asks the screen lock
   when there is one; with no lock and no saved key (`recoveryKeySavedAt` null) it goes straight on,
   since there is no key to type. *Cost:* someone holding the unlocked phone can make a key; they
   already see the data.
4. **The gate's guest branch is retired:** every `preview` account, with or without email, gets
   Unlock (recovery key, passkey, "Add this phone from another device"); `VaultGateDeps.guest`,
   `LockedKind.guest` and `PairingFrom.guest` go, and Settings → Security is the full section for a
   `preview` guest too. `prepareAccount(guest: profile.isAnonymous)` still makes the hidden recovery
   wrap. *Cost:* none known; a no-email person who never protected sees an Unlock whose only way that
   can work is pairing.
5. **Passkey sign-in on the phone stays two touches** (sign in, then Unlock's "Use a passkey");
   one-touch PRF at sign-in is a follow-up. *Cost:* one more touch.
6. **Recovery-key sign-in unlocks with the same typed key**, held once in memory as the parsed
   16-byte secret (`Uint8List`), never as a `String` in a provider and never written; the gate's
   attempt zeroes it whether the unlock succeeds or fails, and a sign-in that fails zeroes it at
   once. *Cost:* a slightly more careful hand-off from the screen to the gate.
7. **Carry instead of rename, through one routine.** The offline start and the deleted-user
   adoption share `adoptVaultIntoNewUser` (Task 10, reused by Task 11); they copy the old
   vault's live records into the new user's vault as new local writes (`baseVersion: null` by
   construction) and then forget the old vault, instead of renaming the file (spec 10 step 3 says
   "moves"). The old vault stays held until the copy is done, so a crash resumes. *Cost:* the vault
   twice on disk for a moment.
8. **The offline start only where new users are encrypted** (the founder's answer 1). Offline, the
   phone cannot ask the server, and the API has no public route for it, so it trusts what it knows:
   `newUsersEncryptedProvider` is true when the build says so (`--dart-define=WAMBITO_NEW_USERS_ENCRYPTED=true`,
   set for builds made from the switch day on; default false) or when this phone already saw this
   server create a `preview` anonymous user (kept as `wambito.server.<host>.newUsers` = `encrypted`,
   written by every "Start" that answered `preview`). Otherwise an offline "Start" says, in Wambi's
   voice, that it needs a connection the first time, with "Try again"; nothing is made. If a
   provisional vault's promotion still finds a `plain` user (the flag turned off meanwhile), that
   anonymous session is signed out on the server, the vault stays held and the screen says it needs
   a connection to a server that keeps data encrypted; nothing is sent to `/v1`. *Cost:* before the
   switch, and on a fresh install of a build older than the switch day, the first "Start" needs the
   network.
9. **Vault holds** live in the vault's `meta` table, key `hold`, JSON `{ kind, target?, since }`,
   kinds `provisional`, `orphaned`, `merging`; `deleteStaleVaults` reads it read-only from the file
   (as `pendingChangesInVault` does) and skips held vaults and their keys. The merge keeps the
   anonymous token in secure storage `wambito.vault.<anonId>.mergeToken` (swept with that vault).
   *Cost:* one more file read per vault per sweep.
10. **Merge cancel at the currency stop** (confirmed by the founder) restores the kept anonymous session and
    signs this phone out of the email account (server sign-out, its vault here forgotten); "Keep
    only the account's data" deletes the anonymous user and its vault after a confirm. This diverges
    from spec 7.2's "cancel, which changes nothing", as the founder confirmed on 2026-11-18. *Cost:* the
    person signs in again later if they change their mind.
11. **Category matching in a merge:** a phone category matches an account category that is not
    archived, has the same `name.trim().toLowerCase()` (the local backend's `_requireUniqueName`
    folding) and the same `kind`. Same name, other kind: the phone category is kept and renamed
    `"<name> 2"`. `account` records match by the same folded name. *Cost:* a rare odd name.
12. **Merchant records are re-keyed** on any carry: their id is
    `merchantRecordId(targetUserId, merchantKey)` (`lib/local/captures.dart`), since ids derive from
    the user id; when that id exists in the target, the target's wins. The `settings` record is
    re-keyed to the target's seed id `uuidv5(uuidv5(seedNamespace, userId), "settings")`. *Cost:*
    none.
13. **`POST /v2/me/seen` is sent for every signed-in account, `plain` too** (nothing on screen
    changes; the founder's counts need it), once per local day per account (`wambito.seen.<userId>`),
    on start and on resume of the app only. `x-wambito-version` goes on every app request.
    *Cost:* one small request a day.
14. **Scanner:** `wambito/scanner` `scan` takes an optional `prefixes` list (default
    `["wambito://pair?"]`), so existing callers are unchanged. A `wambito://signin?…` link opened by
    the system camera opens the approval when the vault is open, and is dropped otherwise.
    *Cost:* a person scans again after unlocking.
15. **The sealed data key for a web sign-in** uses `WrapContext(kind: device, userId, keyV)` and
    `sealToDevice(N.pub, …, ephemeral: A)`, exactly as pairing (the API plan's tests open it with
    `openFromPairing`). *Cost:* the web delivery must open it the same way.
16. **The sign-in notice** (confirmed by the founder) covers every device wrap that is not this phone's and was not in the
    last look (`wambito.vault.<userId>.seenDevices`, a JSON list of wrap ids); the first look records
    silently. One new device: "That wasn't me" opens its removal sheet; several: Settings → Security.
    *Cost:* a notice also after the person paired their own phone.
17. **401s:** `GET /v1/me` at start and in `freshVaultAccountProvider` carries `x-wambito-user` with
    the kept account id, so a deleted user answers `user_deleted`. Only the app acts on the codes;
    a headless run ends with the code and touches nothing.
18. **"The vault holds data"** (adoption) = any live `transaction`, `recurrence`, `budget` or
    `merchant` record. Seeded settings and categories alone are not data.
19. **The stack e2e needs encrypted new users:** `docker-compose.yml` passes
    `NEW_USERS_ENCRYPTED: ${NEW_USERS_ENCRYPTED:-false}` and CI's `mobile-e2e` job starts its stack
    with `NEW_USERS_ENCRYPTED=true`; the web e2e jobs are untouched (API plan decision 17).
20. **Adding an email for a `preview` guest:** `/progress` gets a preview variant (what the email
    adds; no passkey section, that is step 2); after the claim the recovery key page opens with no
    way out until saved (`canLeave: false`) when `recoveryKeySavedAt` is null, then the existing
    passkey offer (`/entry/passkey-offer`).
21. **Home's "Guarda tu progreso"** (`home.saveProgress`, `settings.saveProgress`) is hidden for a
    `preview` guest: the card and the Settings block replace it.
22. **Leaving without a way back:** a `preview` guest with neither step done gets the new warning;
    one with a step done signs out with no warning beyond today's unsynced-changes sheet.
23. **`GUEST_SIGNUP` closed** while a provisional vault waits: it stays provisional and Settings says
    the server takes no new accounts without email; "I already have an account" still works.

## Review Focus

1. **The app is killed in the middle of a merge** (after the email sign-in, before or during the
   upload): the anonymous vault must survive the sweep that the new account's `/v1/me` runs, the
   merge resumes on the next start, and `DELETE /v1/me` of the anonymous user happens only after the
   account's outbox is empty. Pinned in Task 8, and run against the real API in Task 14.
2. **A `user_deleted` 401 reaching the headless engine** (background sync on Android, `BGAppRefresh`
   on iOS): it must end the run with that outcome and touch nothing; only the app adopts. Pinned in
   Task 10.
3. **A recovery key typed the way people type it** (lower case, spaces, dashes, `O` for `0`): the
   sign-in parses it like the unlock (`keysParseRecoveryKey`) before deriving `lookup`, and the same
   text then unlocks. Pinned in Task 5.
4. **A web sign-in that expires between "Approve" and the seal** (the person reads slowly; 2
   minutes): the phone says it expired and never posts a seal. Pinned in Task 12.
5. **An offline start (on a server known to make encrypted users) opened and killed several times before the network returns:** one provisional
   id, one vault, and exactly one anonymous user once online (the token is kept before anything is
   carried). Pinned in Task 11.

---

### Task 1: The welcome and the online first run

**Files:**
- Modify: `lib/entry/entry_screen.dart` (Wambi, "Start", "I already have an account"),
  `lib/vault/vault_gate.dart` (drop `guest`, `LockedKind.guest`, `PairingFrom.guest`),
  `lib/vault/vault_providers.dart` (stop passing `guest:`), `lib/vault/locked_view.dart`,
  `lib/vault/pair_new_device_view.dart`, `lib/vault/vault_screen.dart`,
  `lib/settings/security/security_section.dart` (its `guest` parameter and the guest-only lead
  `settingsSecurityGuestLead` go), `lib/settings/settings_screen.dart` (stops passing `guest:` to
  `SecuritySection`),
  `lib/l10n/app_{es,en,it,pt}.arb` (`entryStart`, `entryStartBusy`, `entryHaveAccount` replace
  `entryGuest`, `entryGuestBusy`, `entryGuestHint`, `entryEmail` after a grep shows no other user;
  `settingsSecurityGuestLead` removed), `apps/mobile/AGENTS.md`
  (the `lib/vault/` paragraph).
- Test: `test/entry/entry_test.dart`, `test/entry/entry_screens_test.dart`,
  `test/vault/vault_gate_test.dart`, `test/vault/vault_screen_test.dart`, and every test a grep for
  `LockedKind.guest`, `PairingFrom.guest` or `guest:` on the gate finds (the locked and pairing view
  tests), `test/settings/security/security_section_test.dart`.

**Interfaces:**
- Consumes: `SessionController.startGuest()` (unchanged: `POST /auth/sign-in/anonymous`).
- Produces: keys `entry.start` (primary) and `entry.haveAccount` (a link to `/entry/email`);
  `VaultGateDeps` without `guest`; `LockedKind { error, offline, unsupported }`;
  `enum PairingFrom { unlock }`.

- [ ] **Step 1: Write the failing tests.**
  - `entry_test.dart`: `the welcome shows Wambi, Start and I already have an account, and nothing else to fill`;
    `Start signs in anonymously once and lands home` (FakeAuthApi `signInAsGuestCalls == 1`, router
    at `/`); `I already have an account opens the email screen`; `with GUEST_SIGNUP closed, Start shows the server's refusal and the buttons work again`.
  - `vault_gate_test.dart`: `an anonymous account with wraps elsewhere shows Unlock, not Locked`
    (state `Unlock()`); `a removed anonymous phone shows Unlock(removed)`; delete the old
    `Locked(guest)` cases.
  - `security_section_test.dart`: `a preview guest sees devices, Remove and New recovery key`.
  - Plain: `entry_test.dart` `Start on a server that makes plain users keeps today's guest: no vault, /progress reachable` (`plainAccount()`).
- [ ] **Step 2: Run** `flutter test test/entry test/vault test/settings/security`. Expected: FAIL
  (old keys, `Locked(guest)`).
- [ ] **Step 3: Implement.** The screen keeps `_run`/`AuthError` handling; Wambi from
  `lib/home/wambi_face.dart`. Remove the guest branch from the gate and its views (pairing from a
  guest's Locked goes through Unlock now). In `security_section.dart` drop the `guest` parameter and its branch (the guest saw only
  "Approve a new device"); `_final` and the comments of `vault_gate.dart` lose `guest` too.
- [ ] **Step 4: Run** `flutter test --exclude-tags golden,stack` and `flutter analyze`. Expected:
  PASS (entry goldens may need `--update-goldens test/entry/entry_golden_test.dart`; keep only the
  welcome's diff).
- [ ] **Step 5: Commit.**
  ```bash
  git add lib/entry/entry_screen.dart lib/vault lib/settings/settings_screen.dart lib/l10n/app_es.arb lib/l10n/app_en.arb lib/l10n/app_it.arb lib/l10n/app_pt.arb test/entry test/vault test/settings/security AGENTS.md
  git commit -m "feat(mobile): a welcome with start and no question"
  ```

### Task 2: Active days and the app version

**Files:**
- Create: `lib/api/seen.dart`.
- Modify: `lib/api/device.dart` (`appVersion`), `lib/main.dart` (read it in `bootstrap()`),
  `lib/app.dart` (start and resume), `apps/mobile/AGENTS.md` (the `lib/api/device.dart` bullet; Traps:
  `wambito.seen.<userId>`).
- Test: `test/api/seen_test.dart`, `test/api/device_test.dart`,
  `test/background/background_run_test.dart`.

**Interfaces:**
- Produces:
  - `DeviceHints({required timezone, required locale, String? appVersion})`; `headers` adds
    `x-wambito-version` when `appVersion` matches `^[A-Za-z0-9.+_-]{1,64}$`; `DeviceHints.read()`
    reads `wambito/device` `appVersion` (exists on both phones);
  - `abstract interface class SeenStore { Future<String?> lastDay(String userId); Future<void> keep(String userId, String day); }`,
    `SecureSeenStore` (key `wambito.seen.<userId>`);
  - `class SeenPing { SeenPing({required SeenStore store, required Future<void> Function() post, required DateTime Function() now}); Future<void> foreground(String userId); }`
    — posts when the kept day is not today (local `yyyy-MM-dd`), keeps the day only after a 2xx,
    swallows every error;
  - `seenPingProvider` (posts `markSeen` through `networkClientProvider`).

- [ ] **Step 1: Write the failing tests.** `seen_test.dart`: `first foreground of the day posts once`;
  `a second foreground the same day posts nothing`; `the next local day posts again`;
  `a failed post keeps nothing, so the next foreground tries again`; `another account the same day posts for it too`.
  `device_test.dart`: `x-wambito-version carries the app version; a version with a space is not sent`.
  `background_run_test.dart`: `a headless run never calls /v2/me/seen` (a regression guard: it
  passes before the code, and must keep passing).
  Plain (`plainAccount()`): `seen_test.dart` `a plain account posts once a day too` (ruling 13).
- [ ] **Step 2: Run** `flutter test test/api/seen_test.dart test/api/device_test.dart test/background/background_run_test.dart`.
  Expected: FAIL.
- [ ] **Step 3: Implement**; `app.dart` calls `foreground(userId)` once the session's user id is known
  and on each `AppLifecycleListener.onResume` (ruling 13; every account).
- [ ] **Step 4: Run** the same files and `flutter analyze`. Expected: PASS.
- [ ] **Step 5: Commit** `feat(mobile): tell the server once a day that the app is open` (staged by
  path).

### Task 3: "Protect your data" in Settings

**Files:**
- Modify: `packages/core/src/records.ts` and `packages/core/src/records.test.ts`
  (`recoveryKeySavedAt`); `lib/core/records.dart` (the Dart twin); `lib/settings/settings_screen.dart`
  (the block at the top; `settings.saveProgress` hidden for a `preview` guest);
  `lib/settings/security/recovery_setup_page.dart` (`canLeave`); `lib/security/screen_lock.dart`
  (ruling 3); ARBs; `apps/mobile/AGENTS.md` (a `lib/protect/` bullet).
- Create: `lib/protect/protect_status.dart`, `lib/protect/protect_actions.dart`,
  `lib/protect/protect_block.dart`.
- Test: `test/core/records_test.dart` (or the file that ports `records.test.ts`),
  `test/protect/protect_status_test.dart`, `test/protect/protect_actions_test.dart`,
  `test/protect/protect_block_test.dart`.

**Interfaces:**
- Consumes: `newRecoveryKey(KeysOptions) → NewRecoveryKey` (`rotate.dart`), `RecoverySetupPage.open`,
  `securitySnapshotProvider`, `anyPasskeyWrap`, `settingsPasskeysProvider` (`add(prf:)`),
  `addPasskeyWrap`, `passkeysSupportedProvider`, `vaultSessionProvider`, `currentVaultAccountProvider`.
- Produces:
  - settings field `recoveryKeySavedAt`: TS `timestamp.nullable().default(null)`, Dart
    `_nullableDefaultNull(_timestamp)`;
  - `class ProtectStatus { final bool recoveryKey; final bool passkey; final bool passkeyOffered; final bool passkeyWithoutPrf; int get done; bool get protected; }`
    (`done` counts the first two; `protected` = either);
  - `protectStatusProvider = FutureProvider.autoDispose<ProtectStatus?>` — null unless the account is
    `preview`, anonymous and its vault open;
  - `Future<void> markRecoveryKeySaved(VaultSession session, DateTime now)` — puts the settings record
    with `recoveryKeySavedAt` (ISO UTC) in one store transaction, then `session.sync()`;
  - `Future<bool> protectWithRecoveryKey(BuildContext context, WidgetRef ref, {bool canLeave = true})`
    — confirm (ruling 3), `newRecoveryKey`, `RecoverySetupPage.open(canLeave:)`; a `refused` outcome
    makes a new key again; true when saved;
  - `Future<PasskeyOutcome> protectWithPasskey(BuildContext context, WidgetRef ref)`;
  - `RecoverySetupPage.open(..., bool canLeave = true)` and the same constructor field (the page's
    `canPop` is also false while `!canLeave` and not yet saved);
  - `confirmSensitive(context, ref, {required reason, required checkRecoveryKey, bool noKeyYet = false})`
    — `noKeyYet` with no screen lock returns true without the sheet (ruling 3); existing callers
    are unchanged;
  - `ProtectBlock` widget; keys `protect.block`, `protect.count`, `protect.recovery`,
    `protect.passkey`, `protect.passkeyNoPrf`, `protect.email` (opens `/progress`, Task 9).

- [ ] **Step 1: Write the failing tests.**
  - `records.test.ts` and the Dart port: `settings without recoveryKeySavedAt parses to null`;
    `a timestamp is kept`.
  - `protect_actions_test.dart` (FakeKeys over a guest account set up by `prepareAccount(guest: true)`):
    `the hidden recovery wrap is replaced by a shown one on the same key version, with no rotation`
    (one recovery wrap, new id, same `keyV`; no call to `/v2/keys/rotate`; one
    `PUT /v2/recovery/verifier`; settings `recoveryKeySavedAt` set); `rotated_elsewhere makes the key again`;
    `with no screen lock and no saved key, no recovery key is asked`; `screen_lock_test.dart`
    (`test/security/`): `noKeyYet without a lock skips the sheet; with a lock it still asks the lock`.
  - `protect_status_test.dart`: `null for plain, for an email account and while the vault is closed`;
    `a passkey without a wrap counts as not done and sets passkeyWithoutPrf`;
    `passkeyOffered is false when the phone reports no passkey support`.
  - `protect_block_test.dart`: `shows 0 of 2 until a first step is done, then a quiet list without the count`;
    `the no-PRF line reads protectPasskeyNoPrf`; `the passkey step is absent without passkey support`.
  - Plain: `settings_screen_test.dart` `a plain guest still sees Guarda tu progreso and no Protect block`.
- [ ] **Step 2: Run** `pnpm vitest run --project @wambito/core` (from the repo root) and
  `flutter test test/core test/protect test/settings/settings_screen_test.dart`. Expected: FAIL.
- [ ] **Step 3: Implement.** If `test/local/backend_shapes_test.dart` moves, run
  `pnpm --filter @wambito/web record:local-backend` and keep only the new field's diff.
- [ ] **Step 4: Run** `flutter test --exclude-tags golden,stack`, `flutter analyze`, `pnpm vitest run --project @wambito/core`.
  Expected: PASS.
- [ ] **Step 5: Commit** in two commits: `feat(core): settings remember when a recovery key was saved`
  (the two records files and their tests), then `feat(mobile): protect your data in settings`.

### Task 4: The home card and the warning before leaving

**Files:**
- Create: `lib/protect/protect_card.dart`, `lib/protect/leaving_warning.dart`.
- Modify: `lib/home/home_screen.dart` (the card before `WidgetCard`; the widget card waits while it
  shows), `lib/settings/home_actions.dart` (ruling 21), `lib/settings/settings_screen.dart` (sign-out
  and server change), ARBs, `apps/mobile/AGENTS.md` (home card bullet; Traps:
  `home.protect.<userId>`).
- Test: `test/protect/protect_card_test.dart`, `test/home/protect_card_home_test.dart`,
  `test/settings/settings_screen_test.dart`.

**Interfaces:**
- Consumes: `protectStatusProvider`, `protectWithRecoveryKey` (Task 3); `warnGuestLeaving`,
  `GuestLeaving` (`lib/progress/guest_warning.dart`, kept for `plain`); `confirmUnsyncedSignOut`.
- Produces:
  - `class ProtectCardState { final DateTime firstOpen; final DateTime? lastDismissed; final int dismissals; }`;
  - `bool protectCardDue(ProtectCardState state, {required int movements, required DateTime now})`
    — 0 dismissals: `now − firstOpen ≥ 7 days || movements ≥ 20`; 1: `now − lastDismissed ≥ 14 days`;
    2 or more: `≥ 30 days`;
  - `ProtectCardStore` (secure storage `home.protect.<userId>`, JSON); `protectCardProvider`; widget
    `ProtectCard` key `home.protectCard`, buttons `protect.cardGo` (step 1) and `protect.cardLater`;
  - `enum UnprotectedChoice { protectFirst, leave }`,
    `Future<UnprotectedChoice?> warnUnprotectedLeaving(BuildContext context, GuestLeaving leaving)`.

- [ ] **Step 1: Write the failing tests.** `protect_card_test.dart` (a fixed `now`):
  `not due at 6 days and 19 movements`; `due at 7 days`; `due on day 1 at 20 movements`;
  `dismissed on day 10: not due on day 23, due on day 24`; `second dismissal: due 30 days later, not 29`;
  `third and later: every 30`. `protect_card_home_test.dart`: `the card shows while neither step is done and goes once one is`;
  `it never covers the add button` (home's add stays tappable); `Not now keeps the dismissal across a restart`.
  `settings_screen_test.dart`: `an unprotected preview guest signing out is warned and Protect first opens the key`;
  `a protected preview guest signs out without the warning`; `changing server warns the same`;
  plain: `a plain guest still gets warnGuestLeaving`.
- [ ] **Step 2: Run** the three files. Expected: FAIL.
- [ ] **Step 3: Implement**; movements from the vault store (`list(RecordType.transaction)` live
  count); `firstOpen` written at the first evaluation for the account.
- [ ] **Step 4: Run** `flutter test --exclude-tags golden,stack`, `flutter analyze`. Expected: PASS.
- [ ] **Step 5: Commit** `feat(mobile): nudge to protect the data, and warn before leaving without a way back`.

### Task 5: Recovery key sign-in

**Files:**
- Create: `lib/entry/recovery_sign_in_screen.dart`.
- Modify: `lib/api/auth_api.dart` (`recoverySignIn`), `lib/api/session.dart`
  (`signInWithRecoveryKey`, `SignInRecoveryKey`), `lib/vault/vault_gate.dart`
  (`takeSignInRecoverySecret`), `lib/local/keys.dart` (`unlockWithRecoverySecret`), `lib/vault/vault_providers.dart`, `lib/entry/email_screen.dart` (the
  link), `lib/entry/auth_errors.dart` (`recovery_key_invalid`, `bad_recovery_key`), `lib/router.dart`
  (`/entry/recovery` signed out only), ARBs, `apps/mobile/AGENTS.md`.
- Test: `test/api/auth_api_test.dart`, `test/api/session_test.dart`,
  `test/entry/recovery_sign_in_test.dart`, `test/vault/vault_gate_test.dart`.

**Interfaces:**
- Consumes: `keysParseRecoveryKey` (keys.dart seam), `recoveryVerifier` (`lib/crypto`),
  `markRecoveryKeySaved` (Task 3).
- Produces:
  - `AuthApi.recoverySignIn(Uint8List lookup, Uint8List auth) → Future<String>` (the
    `set-auth-token`; errors as `AuthFailure` with the server's code and `retryAfter`);
  - `class SignInRecoveryKey { void hold(String userId, Uint8List secret); Uint8List? take(String userId); void clear(); }`
    and `signInRecoveryKeyProvider` (memory only, one take; `clear()` zeroes a held secret);
  - `keys.unlockWithRecoverySecret(KeysOptions options, Uint8List secret) → Future<LocalKeys>` —
    the body of `unlockWithRecovery` after parsing (which now calls it); the caller owns and zeroes
    the secret;
  - `SessionController.signInWithRecoveryKey(String text) → Future<void>`: parse (else
    `AuthFailure(code: 'bad_recovery_key', status: 400)`, nothing sent), derive, sign in,
    `_signedIn` with `standing`, then `hold(userId, secret)`; `lookup`/`auth` zeroed at once, the
    secret zeroed on any failure;
  - `VaultGateDeps.takeSignInRecoverySecret: Uint8List? Function()?` — tried once (through
    `unlockWithRecoverySecret`, the secret zeroed after the attempt either way) in Checking on an
    account with wraps and no local keys, before Unlock; a failure shows Unlock with its code;
  - route `/entry/recovery`; keys `recovery.input`, `recovery.submit`, link `entry.useRecoveryKey`.

- [ ] **Step 1: Write the failing tests.**
  - `auth_api_test.dart`: `recoverySignIn posts base64url lookup and auth and returns set-auth-token`;
    `401 recovery_key_invalid and 429 retry-after come back as AuthFailure`.
  - `session_test.dart` **(Review Focus 3)**: `a key typed in lower case with spaces and dashes signs in, and the gate unlocks with it without asking`;
    `a key that does not parse sends nothing`; `the held secret is taken once and is all zeros after the unlock, and after a failed one`.
  - `vault_gate_test.dart`: `a held recovery key opens a known account's wrap on a new phone`;
    `a held key that opens nothing shows Unlock with wrong_recovery_key`.
  - `recovery_sign_in_test.dart`: `wrong key shows the invalid message`; `429 shows the wait`;
    `offline shows offline`; `success lands home with the vault open and recoveryKeySavedAt set when it was null`.
  - Plain: `recovery_sign_in_test.dart` `a plain account has no verifier: the same invalid message, no session`.
- [ ] **Step 2: Run** the four files. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `flutter test --exclude-tags golden,stack`, `flutter analyze`. Expected: PASS.
- [ ] **Step 5: Commit** `feat(mobile): sign in with the recovery key`.

### Task 6: Vault holds

**Files:**
- Modify: `lib/local/db.dart`, `lib/local/sqlite_store.dart`, `lib/local/stale_vaults.dart`,
  `lib/vault/vault_providers.dart` (`staleVaultsProvider` passes `holdOf`), `apps/mobile/AGENTS.md`
  (stale-vault sentence; Traps: meta key `hold`).
- Test: `test/local/stale_vaults_test.dart`, `test/local/sqlite_store_test.dart`.

**Interfaces:**
- Produces:
  - `enum VaultHoldKind { provisional, orphaned, merging }`;
  - `class VaultHold { const VaultHold(this.kind, {this.target, required this.since}); final VaultHoldKind kind; final String? target; final String since; Map<String, Object?> toJson(); static VaultHold? fromJson(Object? json); }`
    (`target`: the new user id for `orphaned`, the email for `merging`);
  - `SqliteStore.hold() → Future<VaultHold?>`, `SqliteStore.setHold(VaultHold? hold) → Future<void>`
    (meta key `hold`);
  - `Future<VaultHold?> vaultHoldOf(String userId, {String? directory, DatabaseFactory? factory})`
    — read-only, null without a file or a hold;
  - `Future<List<({String userId, VaultHold hold})>> listVaultHolds({String? directory, DatabaseFactory? factory})`
    — every vault file in the folder that carries a hold (the `userId` is the file's id: the
    anonymous id for a `merging` hold, which also names `wambito.vault.<userId>.mergeToken`; the old
    id for `orphaned`; the local id for `provisional`); Task 8's and Task 10's resumes and Task 11's
    start use it;
  - `deleteStaleVaults(..., Future<VaultHold?> Function(String userId)? holdOf)` — skips a held id
    (file and keys); an unreadable hold skips too.

- [ ] **Step 1: Write the failing tests.** `stale_vaults_test.dart`:
  `a held vault and its wambito.vault.<id>.* keys survive the sweep`; `an unheld one goes`;
  `a vault whose hold cannot be read is left for the next time` (a `holdOf` that throws, injected);
  `listVaultHolds finds each held vault with its id and kind and skips unheld ones`.
  No `plainAccount()` case: holds are vault mechanics, and a `plain` account has no vault.
  `sqlite_store_test.dart`: `a hold round-trips and clears`; `vaultHoldOf reads it while the store is open elsewhere`.
- [ ] **Step 2: Run** them. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `flutter test test/local`. Expected: PASS.
- [ ] **Step 5: Commit** `feat(mobile): hold a vault the sweep must keep`.

### Task 7: Carrying records, and the merge rules

**Files:**
- Create: `lib/local/merge.dart`.
- Modify: `lib/local/vault_session.dart` (`OpenVaultOptions.seed`, default true; `seedIfEmpty`
  made public for Task 11), `apps/mobile/AGENTS.md`.
- Test: `test/local/merge_test.dart` (fixtures invented, in the test file),
  `test/local/vault_session_test.dart`. No `plainAccount()` case: a carry works on vaults only.

**Interfaces:**
- Consumes: `FinanceStore` (`list`, `transaction`, `StoreOps.put`), `merchantRecordId`, `uuidv5`,
  `seedNamespace`.
- Produces:
  - `enum CarryMode { adopt, merge }`;
  - `class CarryReport { final int written; final int dropped; final Map<String, String> remapped; }`;
  - `Future<String?> currencyOf(FinanceStore store)` (the settings record's `currency`);
  - `String foldedName(String name) => name.trim().toLowerCase()`;
  - `Future<CarryReport> carryRecords(FinanceStore from, FinanceStore into, {required CarryMode mode, required String intoUserId})`
    — live records only, one `into.transaction`, idempotent (a second run writes the same bodies
    under the same ids):
    - `adopt`: every record as is; `settings` re-keyed to `intoUserId`'s seed id with
      `recoveryKeySavedAt: null` and `revokedDevices: []`; merchants re-keyed (ruling 12);
    - `merge`: rulings 11 and 12 and spec 7.2 step 5 — categories and `account` records matched and
      dropped, references (`categoryId` of transactions, recurrences, budgets, merchants;
      `accountId` of transactions) re-pointed; the phone's `settings` dropped; a phone budget kept
      only when the account has no live budget for the mapped category; transactions, recurrences
      and their occurrences keep their ids;
  - `OpenVaultOptions.seed` (false: no `seedIfEmpty`, used when a carry fills a new vault).

- [ ] **Step 1: Write the failing tests** (two `MemoryStore`s):
  `adopt copies every live record, re-keys settings and merchants, clears recoveryKeySavedAt, skips tombstones`;
  `merge: a phone category with the account's folded name and kind is dropped and its transactions, recurrences, budgets and merchants point to the account's`;
  `merge: same name, other kind is kept as "<name> 2"`; `merge: an archived account category does not match`;
  `merge: the account's settings win`; `merge: a phone budget is added only where the account has none for that category`;
  `merge: a merchant whose re-keyed id exists keeps the account's`;
  `merge: occurrence ids are kept and do not collide`; `running the carry twice gives the same target`
  (the target's live records and its outbox ids are equal after the first and the second run);
  `openVaultSession with seed: false leaves an empty vault empty; with seed true it seeds as before`
  (`test/local/vault_session_test.dart`); `seedIfEmpty seeds once and never over existing settings`;
  `every written record is an outbox entry with no base version` (`readOutbox`).
- [ ] **Step 2: Run** `flutter test test/local/merge_test.dart`. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `flutter test test/local`. Expected: PASS.
- [ ] **Step 5: Commit** `feat(mobile): carry one vault's records into another`.

### Task 8: The merge into an existing account

**Files:**
- Create: `lib/merge/merge_controller.dart`, `lib/merge/merge_offer.dart`,
  `lib/merge/merge_screen.dart`.
- Modify: `lib/api/auth_api.dart` (`deleteUser`), `lib/api/session.dart` (`returnToGuest`),
  `lib/router.dart` (`/merge`), `lib/vault/unlock_view.dart` (one line while a merge waits), `lib/app.dart`
  (resume at start), ARBs, `apps/mobile/AGENTS.md` (a `lib/merge/` bullet; Traps:
  `wambito.vault.<anonId>.mergeToken`).
- Test: `test/merge/merge_controller_test.dart`, `test/merge/merge_screen_test.dart`.

**Interfaces:**
- Consumes: `VaultHold`/`setHold`/`vaultHoldOf`/`listVaultHolds` (Task 6), `carryRecords`,
  `currencyOf` (Task 7), the account's store as `VaultSession.store` of the Ready gate,
  `SessionController.sendCode/verifyCode(replaceGuest: true)`, `forgetVaultProvider`,
  `vaultGateStateProvider`, `VaultSession.sync()/pendingChanges()`.
- Produces:
  - `AuthApi.deleteUser(String token) → Future<void>` (`DELETE /v1/me` with that bearer; a 401
    counts as done);
  - `SessionController.returnToGuest(String guestToken) → Future<void>` — signs the current session
    out on the server, forgets its vault, then `_signedIn(guestToken, guest: true)`;
  - `Future<bool> askMerge(BuildContext context, String email)` — the spec's question and "this
    phone's recovery key stops working" before step 2; key `merge.yes`;
  - `sealed class MergeState` with `MergeIdle`, `MergeSigningIn(email)`, `MergeWaitingUnlock`,
    `MergeCurrencyStop(phone, account)`, `MergeUploading(pending)`, `MergeDone`, `MergeFailed(code)`;
  - `class MergeController extends Notifier<MergeState>`:
    `Future<void> begin(String email)` (holds the anonymous vault `merging`, keeps its token, before
    any code is sent); `Future<void> run()` (called when the account's gate is Ready and a
    `merging` hold names its email: currency check, carry, sync until `pendingChanges() == 0`, then
    `deleteUser`, `forgetVault(anonId)`, token key gone); `Future<void> cancel()` (ruling 10,
    confirmed by the founder: after the sign-in `returnToGuest`, then the hold cleared; before the
    sign-in only the hold cleared); resume at start: `listVaultHolds()` gives the `merging` vault's
    anonymous id and target email; `Future<void> keepAccountOnly()`; `mergeControllerProvider`;
  - route `/merge` (`MergeScreen`: progress, the currency stop with `merge.cancel` and
    `merge.keepAccount`).

- [ ] **Step 1: Write the failing tests** (`merge_controller_test.dart`, fake auth, fake sync,
  two SQLite vaults in a temp dir):
  - `the phone's records reach the account's vault and the anonymous user is deleted only after the outbox is empty`;
  - **(Review Focus 1)** `killed after the email sign-in: the sweep keeps the anonymous vault and a new controller resumes`;
    `killed during the upload: no DELETE until a later run empties the outbox`;
  - `offline during the upload stays MergeUploading and deletes nothing`;
  - `different currencies stop before anything is written; cancel puts the guest session back`;
  - `keep only the account's data deletes the anonymous user and its vault and carries nothing`;
  - `a DELETE answered 401 counts as done`;
  - `cancel after the sign-in leaves the guest session with its data and no hold`;
  - `returnToGuest's sign-out of the email account never takes the device_removed wipe path`.
  `merge_screen_test.dart`: `the currency stop names both currencies`;
  `the offer says the phone's recovery key stops working`.
  Plain: none reach this (the claim of a plain guest never calls `begin`, Task 9).
- [ ] **Step 2: Run** `flutter test test/merge`. Expected: FAIL.
- [ ] **Step 3: Implement.** The anonymous vault is read with `SqliteStore.open(anonId)` (no session,
  no keys) and closed after the carry.
- [ ] **Step 4: Run** `flutter test --exclude-tags golden,stack`, `flutter analyze`. Expected: PASS.
- [ ] **Step 5: Commit** `feat(mobile): bring the phone's data into an existing account`.

### Task 9: Adding an email to a user without one

**Files:**
- Modify: `lib/progress/progress_screen.dart` (the preview variant), `lib/api/session.dart`
  (`offerPasskey()`; `confirmClaim` itself offers nothing), `lib/entry/email_screen.dart`
  (409 `email_taken` of a `preview` guest → `askMerge` → `MergeController.begin` → the code for that
  email with `replaceGuest: true`), `lib/protect/protect_actions.dart` (`afterClaim`), ARBs,
  `apps/mobile/AGENTS.md`.
- Test: `test/entry/claim_preview_test.dart`, `test/entry/entry_screens_test.dart`.

**Interfaces:**
- Consumes: `protectWithRecoveryKey(canLeave: false)` (Task 3), `askMerge`,
  `mergeControllerProvider` (Task 8).
- Produces: `Future<void> afterClaim(BuildContext context, WidgetRef ref)` — reads
  `recoveryKeySavedAt` from the open vault's settings record (`vaultSessionProvider` →
  `store.list(RecordType.settings)`), never `protectStatusProvider` (null once the account has an
  email); the key when null, then `SessionController.offerPasskey()`; the only place the passkey is
  offered after a claim;
  `SessionController.offerPasskey() → Future<void>` (sets `offerPasskeyFor` to the signed-in id).

- [ ] **Step 1: Write the failing tests.** `claim_preview_test.dart`:
  `after the claim the recovery key page shows with no way out, then the passkey offer`;
  `an account whose key was already saved goes straight to the passkey offer`;
  `the passkey is offered exactly once`;
  `the preview /progress says what an email adds and has no passkey section`;
  `email_taken offers the merge; yes starts it and sends the code for that email`;
  `no keeps the screen and changes nothing`.
  Plain (`entry_screens_test.dart`): `a plain guest's claim ends as today, no recovery page`;
  `a plain guest's email_taken still offers today's sign-in as another account`.
- [ ] **Step 2: Run** them. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `flutter test --exclude-tags golden,stack`, `flutter analyze`. Expected: PASS.
- [ ] **Step 5: Commit** `feat(mobile): add an email, then the recovery key`.

### Task 10: Telling 401s apart, and adopting a deleted user's vault

**Files:**
- Create: `lib/api/unauthorized.dart`, `lib/local/adopt.dart`.
- Modify: `lib/api/auth_api.dart` (`standing(token, {String? userId})` sends `x-wambito-user`),
  `lib/vault/encryption_mode.dart` (`freshVaultAccountProvider`: the header, 401 kind),
  `lib/local/keys.dart` (a 401's code into `KeysError`), `lib/local/sync.dart`
  (`SyncProblemCode.userDeleted`; 401 `device_removed` → `deviceRemoved`),
  `lib/local/vault_session.dart` (`onUnauthorized(Unauthorized kind)`), `lib/vault/vault_providers.dart`,
  `lib/api/session.dart` (`sessionEnded`), `lib/background/background_run.dart` (the outcome only),
  `test/entry/fakes.dart` and every other `AuthApi` fake (the new `standing` parameter),
  `apps/mobile/AGENTS.md` (the 401 paragraph of `lib/vault/`).
- Test: `test/api/unauthorized_test.dart`, `test/local/sync_test.dart`, `test/local/adopt_test.dart`,
  `test/api/session_vault_test.dart`, `test/background/background_run_test.dart`.

**Interfaces:**
- Consumes: holds (Task 6), `carryRecords(mode: adopt)`, `OpenVaultOptions.seed` (Task 7),
  `prepareAccount(guest: true)`, `AuthApi.signInAsGuest`.
- Produces:
  - `enum Unauthorized { deviceRemoved, userDeleted, expired }`,
    `Unauthorized unauthorizedOf(String? code)` (`device_removed`, `user_deleted`, anything else);
  - `SessionController.sessionEnded({String? token, required Unauthorized kind}) → Future<void>`:
    `expired` → today's `sessionExpired`; `deviceRemoved` → the vault, home cache and widget wiped,
    then signed out (3a 6.5); `userDeleted` → `adoptOrphan`;
  - `class AdoptDeps { … }` (auth, key storage, vault directory, open-store, clock, and
    `Future<void> Function(String token) keepToken`);
  - **the shared routine** `Future<AdoptStep> adoptVaultIntoNewUser(String oldVaultId, AdoptDeps deps)`
    with `enum AdoptStep { adopted, plainUser, waiting }`: a token already kept for this vault is
    reused, else a new anonymous user whose token is kept at once (`keepToken`); hold target = new
    id; `standing` → `plainUser` stops there (the caller decides); `prepareAccount(guest: true)`,
    the new vault opened with `seed: false`, `carryRecords(adopt)`, old vault forgotten; `waiting`
    when offline. Task 11 reuses it unchanged;
  - `Future<AdoptOutcome> adoptOrphan(String oldUserId, AdoptDeps deps)` with
    `enum AdoptOutcome { adopted, wiped, waiting }`: hold `orphaned` first; no data (ruling 18) →
    wipe and sign out; else `adoptVaultIntoNewUser`;
  - `Future<void> resumeAdoption(AdoptDeps deps)` (start: `listVaultHolds()` finds an `orphaned`
    hold and continues).

- [ ] **Step 1: Write the failing tests.**
  - `unauthorized_test.dart`: the three codes and a missing body.
  - `sync_test.dart`: `401 user_deleted stops with userDeleted` (failing first);
    `401 device_removed stops with deviceRemoved` and `401 unauthenticated stays unauthorized`
    (regression guards: today's code already does it).
  - `adopt_test.dart`: `user_deleted: a new anonymous user, every record re-sealed under its id on the next push`
    (the fake sync opens each pushed body with the new keys and AAD of the new id);
    `the orphaned vault survives the new user's sweep`; `a crash after the new user exists resumes without a second user`;
    `an empty vault is wiped and the phone signs out`; `the nudges start over` (`recoveryKeySavedAt` null);
    `adoptVaultIntoNewUser reuses a kept token instead of making a second user`;
    `device_removed wipes, unauthenticated keeps the vault` (regression guards, as 3a).
  - **(Review Focus 2)** `background_run_test.dart`: `a headless run that gets user_deleted ends with it and adopts nothing`.
  - Plain: `session_vault_test.dart` `a plain account's 401 unauthenticated signs out as today, nothing wiped or adopted`.
- [ ] **Step 2: Run** them. Expected: FAIL.
- [ ] **Step 3: Implement** (ruling 17 for the header).
- [ ] **Step 4: Run** `flutter test --exclude-tags golden,stack`, `flutter analyze`. Expected: PASS.
- [ ] **Step 5: Commit** `feat(mobile): keep a deleted user's data under a new user`.

### Task 11: The offline first run

**Files:**
- Create: `lib/local/provisional.dart`, `lib/entry/needs_connection.dart`.
- Modify: `lib/api/server_address.dart` (the build define `WAMBITO_NEW_USERS_ENCRYPTED`, beside
  `WAMBITO_SERVER`), `lib/api/server_url.dart` (`newUsersEncryptedProvider`, which follows
  `serverUrlProvider`), `lib/entry/entry_screen.dart` (the needs-a-connection state),
  `lib/api/session.dart` (`SessionStatus.provisional`, `SessionState.provisional(localId)`,
  `SessionStore` keys, `startGuest` falls back on no network only when `newUsersEncryptedProvider`
  is true, `apiClientProvider` adds the provisional interceptor), `lib/router.dart` (provisional =
  an open vault; the entry routes go home), `lib/settings/settings_screen.dart` (only local
  preferences and a waiting line; no sign-in while provisional), `lib/app.dart` (promotion on
  start, resume and every minute), ARBs (`entryNeedsConnection`, `entryTryAgain`,
  `provisionalWaiting`, `provisionalPlainServer`, `provisionalNoGuests`), `apps/mobile/AGENTS.md`
  (Traps: `session.provisional`, `session.provisionalToken`, `wambito.server.<host>.newUsers`).
- Test: `test/local/provisional_test.dart`, `test/api/session_provisional_test.dart`,
  `test/entry/entry_test.dart`.

**Interfaces:**
- Consumes: holds and `listVaultHolds` (Task 6), `seedIfEmpty` (Task 7), **`adoptVaultIntoNewUser`,
  `AdoptDeps`, `AdoptStep` (Task 10)**, `createLocalBackend`, the backend interceptor.
- Produces:
  - `const bool newUsersEncryptedByBuild = bool.fromEnvironment('WAMBITO_NEW_USERS_ENCRYPTED')`
    (`server_address.dart`); `final newUsersEncryptedProvider = FutureProvider<bool>` (build define,
    or `wambito.server.<host>.newUsers == "encrypted"` for the current server) and
    `Future<void> rememberNewUsersEncrypted(Uri server)` (`server_url.dart`; called when a "Start"
    answers `preview`);
  - `String newProvisionalId()` → `local-<uuidv7>` (matches the vault file pattern);
  - `class LocalOnlyVault { final String localId; final FinanceStore store; final Interceptor interceptor; Future<void> close(); }`,
    `Future<LocalOnlyVault> openProvisionalVault(String localId, DeviceHints hints)` (hold
    `provisional`, seeded from the hints) — `provisional.dart`; `provisionalVaultProvider`;
  - `SessionStatus.provisional` and its one constructor `SessionState.provisional(String localId)`
    (`SessionState.localId`); `SessionStore.provisionalKey = 'session.provisional'`; the promotion's
    token is kept through `AdoptDeps.keepToken` under `SessionStore.provisionalTokenKey =
    'session.provisionalToken'`;
  - `enum ProvisionalBlock { plainServer, noGuests }` and `SessionState.provisionalBlock`
    (`ProvisionalBlock?`): why a provisional phone cannot be promoted yet; Settings shows
    `provisionalPlainServer` or `provisionalNoGuests` (ruling 23), else `provisionalWaiting`;
  - `Future<bool> SessionController.promoteProvisional()` — `adoptVaultIntoNewUser(localId, …)`:
    `adopted` → `_signedIn`, true; `plainUser` → that session signed out on the server, the vault
    kept held, `provisionalBlock = plainServer`, false; `waiting` → false; a 403 or the server's
    guest-sign-up refusal → `provisionalBlock = noGuests`, false;
  - `NeedsConnection` widget (keys `entry.needsConnection`, `entry.tryAgain`), shown by the welcome.

- [ ] **Step 1: Write the failing tests.**
  - `provisional_test.dart`: `newProvisionalId matches the vault file pattern`;
    `openProvisionalVault holds the vault provisional and seeds it from the hints`;
    `reopening the same id opens the same vault and seeds nothing twice`;
    `the provisional vault survives deleteStaleVaults`.
  - `session_provisional_test.dart`: `Start without network, on a server known to make encrypted users, lands home on a provisional vault`;
    `nothing is pushed or sealed while the user id is unknown`;
    **(Review Focus 5)** `killed and reopened offline three times: one provisional id, one vault; online, one anonymous sign-in`;
    `online on a preview server: the records reach the user's vault and sync sealed under its id`;
    `GUEST_SIGNUP closed: stays provisional with provisionalBlock noGuests and Settings says why`.
  - `entry_test.dart`: `offline Start with nothing known about the server says it needs a connection, makes nothing, and Try again signs in once online`;
    `offline Start after this phone saw the server make an encrypted user opens the provisional vault`;
    `the build define alone also allows it`.
  - Plain: `session_provisional_test.dart` `a promotion that finds a plain user sends nothing to /v1, signs that session out, keeps the vault and sets provisionalBlock plainServer`
    (the fake API records no `/v1/transactions*` or `/v1/categories` call).
- [ ] **Step 2: Run** them. Expected: FAIL.
- [ ] **Step 3: Implement.** Background engines, the widget and capture see no account while
  provisional (`AccountMode` unset), as signed out. While provisional there is no sign-in: a person
  with an account waits for the promotion, then adds the email (the merge, Task 8).
- [ ] **Step 4: Run** `flutter test --exclude-tags golden,stack`, `flutter analyze`. Expected: PASS.
- [ ] **Step 5: Commit** `feat(mobile): start without network`.

### Task 12: Approving a web sign-in

**Files:**
- Create: `lib/local/relay_clock.dart` (`PairingClock` and its real clock, moved), `lib/local/relay.dart`
  (from `pairing.dart`), `lib/local/signin_approval.dart`,
  `lib/settings/security/approve_signin_screen.dart`,
  `android/app/src/main/kotlin/com/wambito/app/scanner/ScannerPrefix.kt`,
  `ios/WambitoNative/Sources/WambitoNative/QrPrefix.swift`.
- Modify: `lib/local/pairing.dart` (uses `relay.dart`; behaviour unchanged),
  `lib/scanner/qr_scanner.dart` (`scan({List<String> prefixes})`), `ScannerChannel.kt`,
  `ScannerActivity.kt`, `ios/Runner/Scanner/ScannerChannel.swift`,
  `ios/Runner/Scanner/ScannerViewController.swift`, `lib/launch/launch_links.dart`
  (`LaunchAction.signin`), `android/app/src/main/AndroidManifest.xml` (host `signin`),
  `ios/WambitoNative/Sources/WambitoNative/LaunchLinks.swift`,
  `lib/settings/security/security_section.dart` (row `security.signinWeb`), `lib/router.dart`
  (`/settings/signin`), ARBs, `apps/mobile/AGENTS.md` (`lib/local/`, scanner, launch links; Traps:
  launch host `signin`).
- Test: `test/local/pairing_test.dart` (unchanged, must pass), `test/local/signin_approval_test.dart`,
  `test/settings/security/approve_signin_screen_test.dart`, `test/launch/launch_links_test.dart`,
  `test/tooling/manifest_test.dart`, `android/app/src/test/kotlin/com/wambito/app/scanner/ScannerPrefixTest.kt`,
  `ios/WambitoNative/Tests/WambitoNativeTests/QrPrefixTests.swift`, `LaunchLinksTests.swift`.

**Interfaces:**
- Consumes: `withDataKey`, `KeysOptions`, `pairingCommitment`, `pairingNumber`, `sealToDevice`
  (seam `pairingSealToDevice`), `generateDeviceKeyPair`, `normalizePairingCode`, `serverUrlProvider`.
- Produces:
  - `relay_clock.dart`: `abstract interface class PairingClock` and `RealPairingClock` (moved from
    `pairing.dart`, which re-exports `PairingClock` so its callers and tests are unchanged);
    `relay.dart` imports `relay_clock.dart`, never `pairing.dart` (no import cycle);
  - `relay.dart`: `class RelayClient` — the old `_Relay` as it is today (checked by grep: `send`,
    `get(String path)`, `post(...)`, `poll<T>`, `setDeadline`, `check`, `cancelled`), except that
    `poll` takes the path and a step over the decoded body
    (`Future<T> poll<T>(String path, Future<T?> Function(Map<String, Object?> body) step)`) and
    `pairing.dart` maps that body to its `_State`; `bool sameBytes(Uint8List a, Uint8List b)`,
    `Uint8List key32(String text)`, `relayCodePattern` (the old private `_sameBytes`, `_key32`,
    `_code`);
  - `class SigninError implements Exception { final String code; }` — `bad_code`, `expired`,
    `tampered`, `offline`, `server`;
  - `Future<SigninApproval> findSigninRequest(KeysOptions options, {String? code, String? qr, PairingClock? clock})`
    (named apart from the generated `DefaultApi.findSignin`)
    — exactly one of them; QR must be `wambito://signin?id=<uuid>&key=<base64url 32 bytes>`; pins the
    commitment (a QR's key must hash to it);
  - `class SigninApproval { String get label; String get expiresAt; bool get typed; Future<String?> approve(); Future<void> seal(); void cancel(); }`
    — `approve()` posts `A.pub` (409 → `tampered`), polls `GET /v2/signin/{id}` until `publicKey`,
    checks it against the commitment and the QR key, returns the 6-digit number after a typed code,
    null after a QR; `seal()` refuses with `StateError` after a typed code until `approve()` returned,
    checks the deadline, seals per ruling 15, posts it, then waits for the 404 of the pickup;
    `cancel()` zeroes `A`;
  - `ApproveSigninScreen({String? qr})`: code field or Scan, then "Sign in on **{label}**?" and
    "Only scan a code you see on **{host}**" (host of `serverUrlProvider`), Approve/Cancel, the
    number with "They match" after a typed code, done, failed;
  - `QrScanner.scan({List<String> prefixes = const ['wambito://pair?']})` (channel argument
    `prefixes`); Kotlin `fun acceptsQr(text: String, prefixes: List<String>): Boolean`; Swift
    `QrPrefix.accepts(_ text: String, prefixes: [String]) -> Bool`;
  - `LaunchAction.signin`; `String? launchSigninQrOf(String? link)`.

- [ ] **Step 1: Write the failing tests.** `signin_approval_test.dart` (fake relay, real crypto):
  `a scanned QR: approve, the key checks, no number, seal is sent and the web side opens the data key with openFromPairing`;
  `a typed code: seal before approve resolves is a StateError and sends nothing`;
  `a revealed key that misses the commitment, or differs from the QR's, is tampered and nothing is sealed`;
  `a second approver (409 already_set) is tampered`;
  **(Review Focus 4)** `expiring between approve and seal throws expired and posts no seal`;
  `cancel zeroes the ephemeral key`. `approve_signin_screen_test.dart`:
  `shows the label and the server's host`; `Cancel posts nothing`.
  `launch_links_test.dart`: `wambito://signin?id=…&key=… opens the approval when the vault is open and is dropped otherwise`.
  `manifest_test.dart`: host `signin` once. Kotlin `ScannerPrefixTest` and Swift `QrPrefixTests`:
  default pair only; signin when asked; a foreign text never. `LaunchLinksTests`: host `signin`.
  Plain: `launch_links_test.dart` `a plain account ignores a signin link`.
- [ ] **Step 2: Run** `flutter test test/local test/settings/security test/launch test/tooling/manifest_test.dart`,
  the Gradle unit tests, `swift test --package-path ios/WambitoNative`. Expected: FAIL.
- [ ] **Step 3: Extract `relay.dart`**, then run `flutter test test/local/pairing_test.dart`. Expected:
  PASS, unchanged.
- [ ] **Step 4: Implement** the rest; add new Swift files to the pbxproj by hand if any lands in
  `ios/Runner`.
- [ ] **Step 5: Run** everything from Step 2, `flutter analyze`, `../../scripts/check-channels.sh`.
  Expected: PASS.
- [ ] **Step 6: Commit** `feat(mobile): approve a web sign-in from the phone`.

### Task 13: The sign-in notice

**Files:**
- Create: `lib/settings/security/signin_notice.dart`.
- Modify: `lib/app.dart` (on open and resume with the vault Ready), ARBs, `apps/mobile/AGENTS.md` (Traps: `wambito.vault.<userId>.seenDevices`).
- Test: `test/settings/security/signin_notice_test.dart`.

**Interfaces:**
- Consumes: `listWraps`/`securitySnapshotProvider` (wraps and own id), `KeyStorage`,
  `deviceRows` (`security_model.dart`), and `RemoveDeviceSheet.show(context, device:, security:, hasPasskeys:, onChanged:)`
  as it is: it is already public and needs nothing from Settings, so `remove_device_sheet.dart` is
  not edited.
- Produces:
  - `List<WrapDto> newDevices(List<WrapDto> wraps, {required Set<String>? seen, required String ownId})`
    — device wraps not own and not in `seen`; `seen == null` → empty;
  - `SeenDevicesStore` (`wambito.vault.<userId>.seenDevices`, JSON list of ids);
  - `Future<void> showSigninNotice(BuildContext context, WidgetRef ref)` — "A session was opened on
    {label}" (+ a count line for more), "That wasn't me" (ruling 16), "OK" records the look.

- [ ] **Step 1: Write the failing tests:** `the first look records every device and says nothing`;
  `a device wrap added since shows its label once`; `OK records it; it never shows again`;
  `That wasn't me with one new device opens RemoveDeviceSheet for that device's row`
  (finds the sheet's title with the device's label); `with two it opens Settings → Security`;
  `this phone's own wrap never counts`. Plain: `no vault, no notice, no /v2/keys call`.
- [ ] **Step 2: Run** `flutter test test/settings/security/signin_notice_test.dart`. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `flutter test --exclude-tags golden,stack`, `flutter analyze`. Expected: PASS.
- [ ] **Step 5: Commit** `feat(mobile): tell the phone when a new device signed in`.

### Task 14: The stack e2e and close-out

**Files:**
- Create: `test_stack/phone_first_e2e_test.dart`.
- Modify: `test_stack/support.dart` (`startGuest()`, `signUpWithEmail(email)`, a web stand-in for
  `/v2/signin`), `scripts/run-vault-e2e.sh` (a third run and its checks), `docker-compose.yml`
  (`NEW_USERS_ENCRYPTED: ${NEW_USERS_ENCRYPTED:-false}`), `.github/workflows/ci.yml` (`mobile-e2e`:
  `NEW_USERS_ENCRYPTED=true docker compose up -d --build`), `apps/mobile/AGENTS.md` (the e2e
  paragraph, the Traps list read once whole), root `AGENTS.md` (the `mobile-e2e` line).

**Interfaces:**
- Consumes: every task above, through the same functions the app calls (as `support.dart` does
  today: the gate, `keys.dart`, `signin_approval.dart`, `HttpAuthApi`); the merge through
  **`MergeController`** (Task 8) in a `ProviderContainer` whose overrides point the network at the
  stack, the key storage at the phone's `MemoryStorage` and the vaults at its temp folder
  (`sqflite_common_ffi`), so Review Focus 1's controller runs against the real API.
- Produces: tag `stack` test `phone_first_e2e_test.dart` with four `test`s; each address is fresh and
  invented, `phone-first-<run>@wambito.test` (no clash with the 5-codes-per-address limit of
  `preview@wambito.test`). Tests 3 and 4 reuse test 1's phone A (its guest, its recovery key, its
  `cafeteria`) instead of making a new guest and claim: one more email code per run would hit the
  limit on reruns. Each says so in a comment, and the shared state is nullable with a guard that
  fails with `run the whole file: this test needs phone A from "first run without email…"`, never a
  `LateInitializationError`.
- No `plainAccount()` case: the stack runs with `NEW_USERS_ENCRYPTED=true`, and plain behaviour is
  pinned by each task's unit tests.

- [ ] **Step 1: Write the four tests** (they fail until the stack runs with the flag):
  - `first run without email, protect, then add an email`: a guest (`/v1/me` `preview`,
    `isAnonymous`), guest setup through the gate, a movement `cafeteria`, sync; `newRecoveryKey` +
    commit (one recovery wrap, same `keyV`, a verifier: `POST /v2/recovery/sign-in` with that key
    answers 200); claim the address with the Mailpit code; `/v1/me` has the email, same id; keeps
    phone A, its key and its id in the file's shared state.
  - `merge into an existing account`: phone B signs up `…-b@`, sets up with its recovery key, adds
    `mercado`; phone D, a guest, adds `cafeteria` in another category with the same folded name as
    one of B's (phone D, a guest of its own, so test 1's phone A stays as it is); claim of `…-b@` →
    409 `email_taken`; `MergeController.begin`, D signs in with the code, unlocks with B's key, and
    `MergeController.run()` ends in `MergeDone`; B syncs and lists both movements, the folded
    category once; the guest's token → 401.
  - `recovery key sign-in on a new phone` (needs test 1's phone A): phone C signs in with A's key typed in lower case with
    dashes, unlocks with it, sees `cafeteria`.
  - `approving a web QR` (needs test 1's phone A): the stand-in opens `POST /v2/signin` with a commitment, A `findSigninRequest(qr:)`,
    approves and seals, the stand-in reveals, picks up `{ sealed, keyV, userId }`, opens the data key
    with `openFromPairing` and `userId` is A's.
- [ ] **Step 2: Wire the run.** `run-vault-e2e.sh`: after `docker compose` is up it checks that a
  fresh guest's `/v1/me` says `preview` (else it stops with "start the stack with
  NEW_USERS_ENCRYPTED=true"); runs the new file; then `psql` checks that no `records.body` holds
  `cafeteria` or `mercado` in the clear and that the merged guest's user row is gone.
- [ ] **Step 3: Run** from the repo root `NEW_USERS_ENCRYPTED=true docker compose up -d --build`, then
  `apps/mobile/scripts/run-vault-e2e.sh`. Expected: the three runs PASS, each check prints 0.
- [ ] **Step 4: Run everything** from `apps/mobile`: `flutter analyze`,
  `flutter test --exclude-tags golden,stack`, the Gradle unit tests,
  `swift test --package-path ios/WambitoNative`, `scripts/check-no-google.sh`,
  `../../scripts/check-channels.sh`, `../../scripts/check-old-name.sh`; and `pnpm lint`,
  `pnpm vitest run --project @wambito/core` from the root. Expected: all green.
- [ ] **Step 5: Read `apps/mobile/AGENTS.md` once** against the plan's new names (`lib/protect/`,
  `lib/merge/`, `lib/local/{merge,adopt,provisional,relay,signin_approval}.dart`, the
  holds, the Traps list: `hold`, `home.protect.<userId>`, `wambito.seen.<userId>`,
  `session.provisional`, `session.provisionalToken`, `wambito.server.<host>.newUsers`,
  `wambito.vault.<anonId>.mergeToken`,
  `wambito.vault.<userId>.seenDevices`, `recoveryKeySavedAt`, launch host `signin`, scanner
  `prefixes`).
- [ ] **Step 6: Commit** `test(mobile): phone-first flows against the real api` (a test-only
  commit, so `test`, not `feat`), then the whole-branch
  review (superpowers:requesting-code-review) against the spec sections in the header and the
  Review Focus list.

## Follow-ups for later deliveries (found while planning)

- One-touch passkey sign-in with PRF on the phone (ruling 5).
- The web delivery opens the sign-in seal with `openFromPairing` under
  `WrapContext(kind: device, userId, keyV)` (ruling 15) and reads `recoveryKeySavedAt` for its
  "Protect your data" block (ruling 1).
- The F-Droid build's choice on `POST /v2/me/seen` waits for the F-Droid review (spec 14).
