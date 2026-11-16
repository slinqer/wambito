# Phone-first accounts

Status: design, agreed in chat with the founder on 2026-11-13 to 2026-11-15. Builds on
`2026-11-08-end-to-end-encryption-design.md` (the "E2E design"), `2026-11-08-e2e-stage-1b-design.md`
("1b") and `2026-11-12-e2e-stage-3-mobile-design.md` ("stage 3", with its deliveries 3a and 3b).
3a is built (slinqer/wambito#64, plan `plans/2026-11-12-e2e-stage-3a-mobile.md`). This spec adds
to those documents. Where it replaces a decision, it names it: 3a plan decision 29 (section 7.1)
and the 401 handling of decisions 35 and 36 for users without an email (section 10).

## 1. Intent

Wambito is designed for phones. Today a person starts on the phone either with an email or as a
guest, an anonymous server account whose finances sit in clear on the server and are deleted after
60 idle days. With end-to-end encryption, the phone already holds the data key and a full local
copy, so the account can be lighter and the start can ask for nothing.

What the founder wants:

- **Install and use.** The phone app starts without an email, a password or a question. A person
  can use Wambito for years without ever giving an email.
- **Nobody loses data.** Losing the phone must not mean losing the finances, email or not.
- **Every install is visible.** The server knows how many installs exist and how many are active,
  including those that never give an email, so the founder can measure use.
- **The web is opened with the phone,** WhatsApp-Web style: the web shows a QR, the phone approves,
  and the web works on its own from then on. No email code in the usual path.
- **The web stays a door too:** a demo, and creating an account with an email, so people who find
  Wambito on a computer can start there and install the app later.

### Goals

- One account model: every install is a server user from the first tap; "creating an account" in
  the app means adding an email to that user.
- Encrypted sync and backup for every user, with or without an email.
- Getting back in on a new phone without an email: a passkey, or the recovery key.
- Web sign-in by QR from the phone, with an email or passkey path as backup.
- Install and active counts in the admin panel, with no finance data and no IP address stored.

### Non-goals

- Separate anonymous usage statistics (per-feature counters, events). Deferred, section 13.
- A web-only guest: the web has the demo and the email sign-up, nothing anonymous.
- Changing how 3a/3b work inside the phone (vault, sync, local backend, unlock, pairing).

### Anti-goals (a failure even if it works)

- Any question, form or screen of explanation before the first use of the phone app beyond the
  welcome's "Start".
- A person who never gave an email losing their data because they changed phones while holding a
  recovery key or a passkey.
- Any finance field, or an IP address, stored for counting purposes.

## 2. Decisions taken

| Question | Decision |
|---|---|
| States of a person | Two: **without an email** and **with an email**. Both are server users with encrypted sync. The old "guest" goes away as a concept |
| What "Create account" means | Adding an email to the existing user (the claim flow that exists today) |
| Where the data lives without an email | On the phone and, encrypted, on the server (E2E design section 10), synced by 3a's engine |
| First run | A welcome with "Start" and a secondary "I already have an account". "Start" creates the anonymous user in the background; nothing else is asked |
| Recovery key | Not asked at the start. Asked for by Proton-style nudges ("Protect your data") |
| Getting back without an email | A discoverable passkey (PRF opens the data key in the same touch), or the recovery key as a sign-in |
| Email that already has an account | The phone's data is merged into that account |
| Web | Demo, sign-up with email, sign-in. No guest. Sign-in is a QR approved by the phone; passkey, or email code plus unlock, are the backup |
| Web for a user without an email | Allowed through the QR |
| Assistants (MCP) | Still need an email (`guest_cannot_authorize` stays) |
| Shared computers | A "Keep me signed in on this browser" box under the QR, ticked by default |
| Counting | Server-side, from the users themselves: installs, daily and monthly actives, cohorts. No separate stats |
| When it ships | Built in pieces behind the switch, turned on the same day as the stage 5 migration of every account, before the public release |

## 3. Approaches

**How the account model was chosen** (in the conversation, in this order):

1. *Local-only start, no server user until an email* (the starting idea). Rejected: installs that
   never give an email would be invisible to the server, and their data would rest on the phone
   alone. An encrypted copy in the OS backup (Android Auto Backup, iCloud) was considered to cover
   the second point, and dropped once the server keeps the encrypted copy.
2. *A server user from the first tap, data only on the phone.* Fixes counting; still loses the data
   with the phone unless an OS backup works.
3. *A server user from the first tap, data synced encrypted* (chosen). Counting comes from the
   users table; backup is the sync that every account already has; the email is only a way to sign
   in, reach the web and connect assistants.

**How to count** (before the account model settled it): ID-less counters ("installed", "active
today", "active this month") or a random install id. Both became unnecessary once every install is
a user; the counters idea survives in section 13.

**When to ship:**

- *With stage 5, one switch day* (chosen). The founder wants every account migrated at once, before
  the public release; the pieces are built behind the switch and turned on together.
- *Piece by piece, new accounts born encrypted after 3b.* Rejected: two kinds of new account would
  coexist for months.
- *The web QR first, for existing `preview` accounts.* Rejected: gives a newcomer nothing.

**The web sign-in API:** a new table and route family (`signin_requests`, `/v2/signin`) that reuses
1b's state machine code and crypto, rather than a mode on `pairing_requests`. The existing relay
requires a session on both sides and is built and tested; a sign-in request has no session on the
new side, a different expiry and a different end (a session is created), so mixing them would
weaken the checks of both. (Builder's latitude: share the state-machine module; keep the tables
and routes apart.)

## 4. The phone's first run

1. The welcome shows Wambi, "Start" (primary) and "I already have an account" (a link).
2. **Start:**
   - the app calls `POST /auth/sign-in/anonymous` (Better Auth's `anonymous` plugin, as today's
     guest);
   - it then makes the data key, the device key and the device wrap, without a recovery key: this
     is stage 3a's guest path (3a section 6.4), unchanged;
   - it creates the `settings` record and the suggested categories as records (E2E design 7.1),
     and syncs.

   The person lands on home. Nothing else is asked.
3. **Offline first run:** the vault and the data key are made at once under a provisional local
   id. The records are sealed and the anonymous user is created when the network first answers.
   The associated data of every record and wrap includes the user id, so nothing is sealed under
   the provisional id; the local backend works on the opened records meanwhile. (Builder's
   latitude: the outbox can hold unsealed entries until the user id is known.)
4. **I already have an account:** the sign-in screen (section 7.4). No anonymous user is created,
   so no orphan is left.

## 5. Protecting the data

### 5.1 What protects what

| Lose the phone, and the person has… | Gets back in with |
|---|---|
| Neither a recovery key nor a passkey | Nothing. The encrypted copy is on the server but nobody can open it |
| A recovery key | Recovery key sign-in (section 6), on any phone or the web |
| A passkey (synced by the person's password manager) | Passkey sign-in; with PRF, the data key opens in the same touch; without PRF, the recovery key is still needed |
| An email | Email code to sign in, then the passkey or the recovery key to unlock (E2E design 7.2). An email alone never decrypts |

### 5.2 Nudges ("Protect your data")

Modeled on Proton's recovery checklist.

- **Settings, at the top**, a block "Protect your data" with three steps. It shows "N of 2" until
  one of the first two is done, then stays as a quiet list.
  1. **Recovery key.** Opens 3a section 6.3's screen: show, copy or share, type four characters
     back. It also writes the recovery verifier (section 6). Behind it, this replaces the hidden
     recovery wrap that 3a's guest path uploads at setup, whose secret is never shown and never
     kept (3a plan decision 14; `lib/local/keys.dart` discards it):
     - the phone makes a new recovery secret;
     - it `PUT`s a new `recovery` wrap of the current data key on the current key version. Today's
       `/v2/keys` rule ("a new recovery wrap replaces the old one") already allows it;
     - no rotation is needed: nobody ever held the old secret, so the old wrap gave nobody a way
       in.
  2. **Passkey.** Shown only where the phone reports passkey support. It counts as done only when
     a **passkey wrap** exists, that is, when the password manager returned PRF. A passkey without
     PRF can sign in but cannot open the data. In that case the passkey is kept for signing in,
     the step stays open, and the copy says "This passkey can sign you in but cannot open your
     data. Add a recovery key." This happens with some managers, for example Samsung Pass, even on
     phones where PRF works with others. The nudges, the "N of 2" count and the cleanup tier
     (section 10) all check for the wrap, never for the passkey row.
  3. **Create account (add an email).** Explains what the email adds: the web by email code,
     assistants, sign-in when the passkey is gone.
- **Home card** (Wambi, "If you lose this phone, you lose your data. It takes one minute to
  protect it"), shown while neither step 1 nor step 2 is done:
  - first after 7 days of use or 20 movements, whichever comes first;
  - dismissed, it comes back after 14 days, then 30, then every 30;
  - it never blocks anything.
- **Leaving without a way back:** signing out, or changing the server, while neither step 1 nor
  step 2 is done warns that the data cannot be opened again. The warning offers step 1 first. It
  replaces today's guest warning (`warnGuestLeaving`), with new copy.
- Copy in the four languages, with web parity where the web shows the same block (Settings →
  Security for a user without an email signed in by QR).

## 6. Recovery key as a sign-in (new API piece)

A user without an email has no other way to find their account from a new phone without a passkey.

**Derivation** (two new HKDF infos, with test vectors in `packages/crypto/test-vectors.json` and
the Dart port):

- `lookup = HKDF-SHA256(recovery secret, info "wambito/v1/recovery/lookup")`, 16 bytes;
- `auth = HKDF-SHA256(recovery secret, info "wambito/v1/recovery/auth")`, 32 bytes.

Neither reveals the secret or the recovery wrap key, since the HKDF infos differ.

**Storage:** a new table `recovery_verifiers`, one row per user:
- `user_id`, the primary key;
- `lookup_hash`, SHA-256 of `lookup`, unique;
- `auth_hash`, SHA-256 of `auth`;
- `created_at`.

The inputs are high-entropy (128-bit secret), so a fast hash is enough.

**Routes:**

- `PUT /v2/recovery/verifier` (session; not assistant tokens) with `{ lookupHash, authHash }`.
  The client sends it whenever it creates the recovery wrap, replaces the recovery key, or unlocks
  with the recovery key and finds no verifier: accounts made before this spec get one at the next
  typed key.
- `POST /v2/recovery/sign-in` (no session) with `{ lookup, auth }`:
  - the server hashes both and finds the user;
  - on a match it creates a Better Auth session, the same as any sign-in;
  - on no match it answers 401 `recovery_key_invalid`, the same answer for an unknown lookup and a
    wrong auth;
  - rate-limited per IP.

  The client then reads `GET /v2/keys`, opens the recovery wrap, and continues as 3a's unlock does
  (registers its device wrap).
- The recovery wrap cannot be deleted (today's `/v2/keys` rule). Replacing it replaces the
  verifier, and a rotation keeps the verifier, since the secret is the same. The hidden wrap of
  3a's guest path has no verifier, so a user who never saw a key counts as "no recovery key" for
  the nudges and the cleanup (section 10).

**Where it shows:**
- **Phone:** "I already have an account" → "Use your recovery key".
- **Web:** under the QR, "Other ways to sign in" → "Recovery key".

## 7. Adding an email, and merging

### 7.1 Adding an email to this user

The existing claim flow (`POST /v1/me/claim-email/send` and `/verify`) sets the email on the
anonymous user. Nothing is re-sealed and the data key stays: the user id does not change. If no
recovery key was shown yet, the recovery key screen comes right after the email, as 3a section 6.4
asks of "Save your progress", through the new-wrap path of section 5.2 step 1, not a rotation. An
optional passkey follows.

This replaces 3a plan decision 29, which deferred the guest's recovery key on conversion to 3b
because the web does it through a rotation.

### 7.2 The email already has an account: merge

The claim answers that the email is taken. The phone then offers "This email already has a
Wambito account. Bring this phone's data into it?":

1. **Check the currency first.** The phone reads nothing of the other account yet, so it asks for
   the email code and the unlock (passkey, that account's recovery key, or a QR approval from a web
   tab already signed in to it) before the check.
2. **Sign in** to the existing account with the email code; keep the anonymous user's session aside.
3. **Unlock** the existing account's data key and download its records into a new vault.
4. **If the currencies differ, stop.** "Your account uses COP and this phone USD." The person
   chooses between cancel, which changes nothing, and keeping only the account's data, which
   discards the phone's records after an explicit confirm.
5. **Merge rules:**
   - **categories:** matched by name with the existing uniqueness folding. Each phone category that
     matches is dropped, and its references (transactions, recurrences, budgets, merchants) point
     to the account's category;
   - **settings:** the account's win;
   - **budgets:** a phone budget whose category has none in the account is added;
   - **transactions, recurrences and their occurrences:** keep their ids (UUIDs; occurrence ids
     are v5 of the rule id, and rule ids differ, so they do not collide);
   - **merchant records with the same id:** the account's win.
6. **Re-seal and push** every kept phone record under the account's user id and data key, with
   `baseVersion: null`, through the normal outbox.
7. **Delete the anonymous user** (`DELETE /v1/me` with the kept session) only after the outbox is
   empty.

Until step 7 the old vault is kept, so an interrupted merge resumes from step 6. The phone's own
recovery key stops working, and the confirm screen says so before step 2.

Builder's note: Better Auth's `anonymous` plugin may delete the anonymous user by itself when it
signs in to another account. That must be turned off (`disableDeleteAnonymousUser`), so step 7
stays the only delete.

## 8. Web sign-in through the phone (new API piece)

### 8.1 Flow

The same keys and checks as 1b section 1: `N` is the web's X25519 key pair, `A` the phone's
ephemeral one, and the commitment is `SHA-256("wambito/v1/pairing-commit" || N.pub)`.

1. **The web opens a request.** `POST /v2/signin` with `{ commitment, remember, label }`, no
   session:
   - `label` is "Firefox on Mac", made from the user agent;
   - the answer is `{ id, code, pollSecret, expiresAt }`;
   - the web shows a QR `wambito://signin?id=<id>&key=<base64url N.pub>` and the 8-character code
     under it;
   - the request lives **2 minutes**. While the page is visible, the web opens a new one when the
     old one expires.
2. **The phone finds it.** It scans the QR (or the person types the code) and calls
   `GET /v2/signin?code=` or `GET /v2/signin/{id}` with its session. The answer is
   `{ id, commitment, label, expiresAt }`. The phone pins the commitment.
3. **The phone shows the approval:**
   - "Sign in on **Firefox on Mac**?";
   - the warning "Only scan a code you see on **app.wambito.com**";
   - Approve and Cancel.

   The phone must have its vault open.
4. **Approve.** `POST /v2/signin/{id}/approver` with `{ publicKey: A.pub }` binds the request to
   the phone's user. It is accepted once; a second call answers 409 `already_set`.
5. **The web reveals.** It polls `GET /v2/signin/{id}` with `x-wambito-poll: <pollSecret>`, pins
   `approverKey`, and posts `POST /v2/signin/{id}/reveal` with `{ publicKey: N.pub }`. The server
   checks the commitment.
6. **The phone checks and seals.**
   - It checks the revealed key against the pinned commitment and, after a QR scan, against the
     QR key.
   - Only after a typed code (no QR key) do both show 1b's 6-digit number for the person to
     compare.
   - It posts `POST /v2/signin/{id}/seal` with `{ sealed, keyV }`, the same checks as 1b step 6.
7. **The web picks up.** `POST /v2/signin/{id}/pickup` with the poll secret returns
   `{ sealed, keyV, userId }`, creates the Better Auth session for the bound user and sets its
   cookie in the same response, then deletes the row.
8. **The web registers itself.** It opens the data key, registers its device wrap with its
   attestation (1b section 2), and syncs. From then on it works without the phone.

**Rules:**

- **Who may call:** assistant tokens get 403 on every `/v2/signin` route.
- **The poll secret:** only the web holds it. It is required for the poll, reveal and pickup calls,
  and the server stores only its hash.
- **Rate limits:** per IP, on opening requests, and at most 5 open requests per IP.
- **Sessions:** created only through Better Auth's internal adapter, so session hooks (activity,
  section 9) run as for any sign-in.

### 8.2 "Keep me signed in on this browser"

A box under the QR, ticked by default.

- **Ticked:** the normal session lifetime (today 60 days, renewed on use; `auth.ts`), and the vault
  and keys kept in IndexedDB, as stage 2 does today. This holds for users without an email too:
  the 25-month lifetime of section 10 is for the phone's own session only, since a browser is
  easier to leave behind.
- **Unticked:**
  - a session cookie without `Max-Age` and with a 12-hour server expiry;
  - the vault is marked ephemeral and wiped on the next load that finds no session;
  - the copy says "Nothing stays on this computer when you close the browser".

  (Builder's latitude on the mechanics: a reload of the same tab may ask for a new scan.)

### 8.3 After the sign-in

- **Settings → Devices** lists the browser, on the phone and on the web, with "Sign out", which
  removes the device and rotates, as 3b section 7.6.
- **The phone's notice:** the next time the phone opens, it shows "A session was opened on Firefox
  on Mac" with "That wasn't me" (which goes to the device's removal). It learns this from device
  wraps newer than its last look, kept locally.

### 8.4 The web's doors

- **Landing:** "Try the demo", "Create account", "Sign in".
- **Create account (web):**
  - E2E design 7.1, unchanged: email code, data key, the recovery key screen, an optional passkey;
  - it also writes the recovery verifier;
  - it ends with an "Install the app" card linking to the stores and F-Droid.
- **Sign in (web):**
  - the QR, with the box;
  - "Other ways to sign in": a passkey (with PRF, unlocked in the same touch), the recovery key
    (section 6), or the email code followed by the unlock screen of stage 2.
- **The phone joining an account made on the web:** "I already have an account" → passkey,
  recovery key, or email code. When the sign-in did not unlock, 3a's unlock follows, including 3b's
  "Add this phone from another device", where the web approves the phone's QR or its typed code.
- **The web has no guest.** It never called `sign-in/anonymous`; nothing to remove beyond copy that
  mentions guests.

## 9. Counting installs and actives

Every install is a user, so the counts come from the users table and one aggregate table. No other
statistics are collected.

- **On the user** (new columns):
  - `platform` (`android`, `ios`, `web`), set at creation from `x-wambito-client`;
  - `app_version`, updated on each daily "seen" call, from a new `x-wambito-version` header that the
    app sends (the web sends its build id).
- **"Seen today."** The app calls `POST /v2/me/seen` at most once per local day, when it comes to
  the foreground. The web calls it once per day on load.
  - It sets a new column `user.last_seen_day` (a date in the user's time zone). When the previous
    value is an earlier day, the call adds one to `activity_daily`. Only this call moves
    `last_seen_day`, so the daily count is exact.
  - **Two clocks.** `user.lastActiveAt` stays the clock of the inactivity cleanup (section 10). It
    is moved, as today, by the session hooks (`stampGuestActivity` on create, refresh and
    sign-out), now for every user, and also by `/v2/me/seen`. The cleanup never depends on
    `/v2/me/seen`, so a build that skips it (section 14's F-Droid option) is never deleted while
    in use.
  - Background work (workers, the widget, headless sync) never calls it.
- **`activity_daily(day, platform, app_version, cohort_week, has_email, count)`.** This aggregate
  keeps no per-user history:
  - `cohort_week` is the ISO week the user was created;
  - it gives daily actives and retention by cohort;
  - installs per day come from `user.created_at`;
  - monthly actives come from `lastActiveAt`, as the panel's `active30d` does today.
- **Admin panel** (`docs/admin.md`, `services/admin/metrics.ts`): today's guests and with-email
  series become "without email" and "with email", plus:
  - daily actives over 90 days;
  - a cohort retention table (week 1, 4 and 12);
  - installs by platform;
  - versions in use.
- **No IP stored.** Better Auth's IP tracking on sessions is turned off for every user, if nothing
  in the API reads it (the plan checks; the admin panel's IP allowlist reads the request, not the
  session). Rate limits keep IPs in memory only. Caddy's access log for the API host does not
  record client IPs, or is off; the plan checks `deploy/personal`.

## 10. Lifecycle

- **Deletion for inactivity** replaces today's 60-day guest cleanup for encrypted users (it keeps
  running for `plain` guests until stage 5 ends them). It applies only to users without an email:
  - **no recovery verifier and no passkey wrap, idle 12 months:** deleted. Nobody but that phone
    could ever open the data;
  - **a recovery verifier or a passkey wrap, idle 24 months:** deleted;
  - users with an email are never deleted for inactivity.

  The privacy policy states both periods.
- **Session lifetime without an email.** Today every session lives 60 days and renews once a day
  on use (`auth.ts`: `expiresIn` 60 days, `updateAge` 1 day). A user without an email has no way
  back after a session expires unless this phone has a passkey or a typed recovery key. So their
  sessions live **25 months**, longer than the 24-month cleanup, and renew silently on use as
  today. A session of a user without an email then only ends by sign-out, device removal, or the
  deletion of the user. The lifetime is set per session at creation (a session hook) and goes
  back to 60 days when an email is added. Users with an email are unchanged.
- **A phone whose user was deleted: adopting the orphan vault.** 3a keeps the vault on a 401 and
  reuses it when the same account signs in again (3a plan decisions 35 and 36). When another
  account signs in, `deleteStaleVaults` deletes every other account's vault. So the re-upload
  must claim the vault before that sweep:
  1. **Telling the 401s apart (new on the server).** Today a removed device and a deleted user
     both get a bare 401 `unauthenticated`, and 3a finds `device_removed` through `GET /v2/keys`,
     which a phone without a session cannot call. So the server says which one it is:
     - **removing a device** (or leaving it out of a rotation) records the ended session's id
       hash in `ended_sessions(session_hash, reason, ended_at)`, with reason `device_removed`.
       Rows are purged after 90 days;
     - **the inactivity cleanup** records the SHA-256 of each deleted user id in
       `deleted_users(user_hash, deleted_at)`;
     - **a 401 on an unknown session** answers `device_removed` when its hash is in
       `ended_sessions`, `user_deleted` when the `x-wambito-user` header's hash is in
       `deleted_users`, and `unauthenticated` otherwise.

     The phone acts only on the explicit codes:
     - `device_removed` wipes (3a section 6.5);
     - `user_deleted` adopts (below);
     - `unauthenticated` keeps the vault and shows sign-in, as 3a does.

     Nothing wipes or adopts on a guess. On `user_deleted`, the phone marks its vault `orphaned`
     in the vault's `meta`.
  2. If the vault holds data, the phone makes a new anonymous user (section 4). Otherwise it
     wipes as 3a does.
  3. **Adopt**, before the new user's `/v1/me` triggers the sweep:
     - the phone makes a new data key and device key, through 3a's first-setup path, with a
       hidden recovery wrap;
     - it re-seals every opened record under the new user id and key (the user id is in the
       record AAD, `packages/crypto` records), as `baseVersion: null` outbox entries;
     - it moves the vault file to the new user's name and clears `orphaned`.

     `deleteStaleVaults` skips a vault marked `orphaned`, so a crash mid-adoption resumes.
  4. The outbox uploads as usual. The nudges start over, since the old recovery key and passkey
     wrap belonged to the deleted user.

  The device-removed 401 still wipes (3a section 6.5). This path is rare by design: a user is
  deleted only after 12 or 24 idle months.
- **Abuse:** anonymous sign-up stays rate-limited per IP (today's limits); the 100,000-record cap
  per account holds. The plan measures whether a per-IP daily cap on new anonymous users is
  needed.
- **`GUEST_SIGNUP`** keeps its name and now opens or closes the "Start" path of the phone.
  Builder's call: rename it only if it is cheap.

## 11. The switch day and existing guests

Everything above is built behind the stage 5 switch and turned on the same day as the migration of
every account (E2E design section 11), before the public release.

**The switch, before stage 5 exists.** A new anonymous user has a random id, so the per-id
allowlist `E2E_PREVIEW_USER_IDS` cannot reach it. The API delivery therefore adds:

- **a column `user.encryption`** (`plain` | `encrypted`), set at creation. It is the start of the
  E2E design's `encryption_state`; stage 5 adds `migrating` to it;
- **a config flag `NEW_USERS_ENCRYPTED`** (default off). When it is on, every user created from
  then on is `encrypted`;
- **`isPreviewAccount`** becomes the allowlist or `encrypted`, so `GET /v1/me` answers
  `encryption: "preview"` for those users.

The flag is on in the dev stack, in the CI e2e jobs and on the founder's test server; production
turns it on on the switch day. The new cleanup tiers, the 25-month phone sessions, the nudges and
the 401 codes apply only to `encrypted` users. A store build released before the switch shows the
same "Start", but a `plain` user created by it behaves as today's guest: no nudges, today's
warnings, today's 60-day cleanup. The phone decides from `encryption`, which it already reads.

- **Existing guests** (all made by the phone; the web never made any) are `plain` anonymous users.
  The updated app migrates them like any `plain` account:
  - keys without the recovery key screen;
  - their data downloaded through `/v1/me/export`;
  - written as records;
  - `POST /v2/migration/finish`.

  They keep their user id and become "without an email". Their nudges start from their first
  open after the update.
- A guest whose app never updates is deleted by the old 60-day cleanup, as today, before stage 5
  drops the old tables.
- From the switch day, every new user (phone "Start", phone or web email sign-up) is born
  encrypted. The allowlist `E2E_PREVIEW_USER_IDS` becomes irrelevant; stage 5 removes it. The
  phone needs no change for this: it reads the mode from `GET /v1/me` `encryption` as 3a built
  it.

**Preconditions of the switch day.** With every account encrypted, nothing may still say "Coming
soon with encryption":

- **3b in full.** This covers:
  - Android automatic capture;
  - the widget;
  - due notices;
  - background sync;
  - QR pairing;
  - Settings → Security.

  The merchant memory is part of this: for encrypted accounts it is the sealed `merchant` record
  type (already in `packages/core` records), applied on the phone with the same prefix rule
  (`merchantKeyPrefixes`, slinqer/wambito#66), not the server's `merchant_categories` table.
- **Stage 4,** for export, import and the assistants.
- **The PRF spike** (3a plan task 1) on a real Android phone and a real iPhone. Passkey sign-in
  with PRF is one of the two ways back without an email. If PRF fails on a platform, that
  platform's "Passkey" step in section 5.2 is hidden, and the recovery key is the only way back.
- **The shared crypto vectors** passing on a real iPhone, as they already do on Android after
  slinqer/wambito#65.

## 12. Threat model additions (E2E design section 3)

- **QR sign-in phishing ("QRLjacking").** A fake page shows a real Wambito sign-in QR that its
  owner requested, and the victim approves it believing it is their own browser. The attacker gets
  a session and the data key. No technical fix exists: the phone cannot know where the QR was
  shown. The same risk is accepted by WhatsApp and Signal. Mitigations:
  - the approval screen names the domain and the requester's browser;
  - the 2-minute expiry;
  - the after-the-fact notice and device removal (section 8.3).
- **The recovery key is now also a sign-in.** Whoever holds it can sign in, not only decrypt: same
  power as before, since decrypting was the valuable part. Rate limits and 128-bit entropy stop
  guessing.
- **Metadata for users without an email:**
  - a random id;
  - creation and last-active dates;
  - platform, app version, time zone and locale;
  - record counts and sizes (as E2E design section 3).

  No IP address and no email.

## 13. Later: anonymous usage statistics

Not built now. When a question comes up that the users table and the store consoles cannot answer
(which features are used, voice versus typing), the agreed constraints are:

- **opt-in**, offered once after the first week;
- ID-less daily counters, each event sent at most once per day;
- version, platform and locale only;
- no IP stored;
- a Settings switch;
- a privacy policy line;
- off on the F-Droid build.

## 14. Policy, stores, F-Droid

- **Privacy policy** (`docs/privacy-policy.md`, Ley 1581):
  - what the server keeps for a user without an email (section 12);
  - the activity day count;
  - the deletion periods;
  - that no IP is stored.
- **Play data safety:**
  - "App activity: app interactions" (the active-day count), collected, not shared;
  - the email as optional;
  - the finance data per E2E design section 12.

  The plan checks Play's current wording on end-to-end encrypted data before filling the form.
- **App Store privacy label:** "Usage data, not linked to you" does not fit, since the count is
  tied to the user row. The answer is "Usage data, linked, app functionality and analytics". The
  plan confirms it.
- **F-Droid:**
  - "Start" registers a user with Wambito's own server (free software) and reports active days.
  - Risk: the "Tracking" anti-feature, which F-Droid sets when an app reports activity by default.
    `NonFreeNet` does not apply, since the server is free software.
  - Decision deferred to the F-Droid review (resubmission from 2027-01-20). If it is flagged, the
    founder chooses between accepting the label and skipping `POST /v2/me/seen` in the F-Droid
    build, which then counts as installs only.

## 15. Testing

- **`packages/crypto` and Dart:** vectors for `lookup` and `auth`.
- **API (testcontainers):**
  - **recovery verifier and sign-in:** match, wrong auth, unknown lookup (the same 401), rate
    limit, verifier deleted with the wrap;
  - **every `/v2/signin` transition and its out-of-order errors:**
    - poll secret required;
    - expiry at 2 minutes;
    - approver bound once;
    - pickup sets a session for the bound user only;
    - assistant tokens refused;
    - a ticked request versus an unticked one (cookie and expiry);
  - **`/v2/me/seen`:** once per day per user, `activity_daily` rows, background calls absent;
  - **cleanup:** 12 and 24 months, email users untouched, `plain` guests still on 60 days;
  - **claim:** for an encrypted anonymous user, and the "email taken" answer used by the merge;
  - **sessions:** no IP stored.
- **Dart:**
  - first run, online and offline (records sealed only after the user id is known);
  - nudge timing (7 days or 20 movements, then 14, 30, 30), with a fake clock;
  - the merge rules on fixtures: categories by folded name, references re-pointed, currency stop,
    resume after interruption;
  - the deleted-user 401 adoption (new user, re-seal, vault renamed, `deleteStaleVaults` skips an
    `orphaned` vault, resume after a crash) versus the removed-device 401 wipe;
  - "Protect your data" replacing the hidden recovery wrap with a shown one, on the same key
    version, with no rotation.
- **API, sessions:** a user without an email gets a 25-month session on the phone and 60 days on
  the web; adding an email brings the phone back to 60 days.
- **API, 401 codes:** `device_removed` after a device removal or a rotation that leaves it out;
  `user_deleted` after the cleanup (`x-wambito-user` hash); `unauthenticated` otherwise; rows
  purged after 90 days.
- **API, switch:** with `NEW_USERS_ENCRYPTED` off, a new user is `plain` and nothing in this spec
  applies to it; with it on, `encrypted` and `GET /v1/me` says `preview`.
- **Web:**
  - Vitest on the QR sign-in model (states, renewal every 2 minutes, the box);
  - e2e: a second browser context plays the phone through the API and approves; sign-in by
    recovery key; the unticked box leaves nothing after a new context.
- **Admin:** the new metrics on seeded users.

## 16. Deliveries

Each is its own plan and PR, all behind the switch:

1. **API:**
   - recovery verifier and sign-in;
   - `/v2/signin`;
   - `/v2/me/seen`, the user columns and `activity_daily`;
   - cleanup;
   - no IP on sessions;
   - admin metrics;
   - crypto vectors;
   - `CHANGELOG.md` lines;
   - `apps/api/AGENTS.md`.
2. **Phone** (after 3a and 3b):
   - the welcome and first run;
   - "Protect your data" and the nudges;
   - adding an email and the merge;
   - recovery key sign-in;
   - the approval screen for web QRs and the sign-in notice;
   - the deleted-user re-upload;
   - `apps/mobile/AGENTS.md`.
3. **Web:**
   - the landing's doors;
   - the QR sign-in with the box;
   - recovery key sign-in;
   - "Install the app" after sign-up;
   - the "Protect your data" block for users without an email;
   - `apps/web/AGENTS.md`.
4. **Switch day** (with stage 5):
   - policy and store forms;
   - the guest migration as part of stage 5;
   - removing the guest copy and the 60-day cleanup once no `plain` guest remains.

## 17. Left to the builder

- Exact copy in the four languages (Wambi's voice), and screen layouts within the design system.
- Whether the offline first run holds unsealed outbox entries or a separate pending list.
- Sharing the pairing state-machine module between `/v2/pairing` and `/v2/signin`.
- The ephemeral-vault mechanics of an unticked web sign-in.
- Rate-limit numbers, within today's style.
- The admin panel's charts.
