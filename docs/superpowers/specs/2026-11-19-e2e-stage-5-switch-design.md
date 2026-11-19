# E2E stage 5: the switch day (web-only migration)

Agreed with the founder on 2026-11-19. Parent designs:
- `docs/superpowers/specs/2026-11-08-end-to-end-encryption-design.md`, sections 11–14;
- `docs/superpowers/specs/2026-11-15-phone-first-accounts-design.md`, section 11 and delivery 4 of section 16.

This design replaces their migration plan where the two differ. The founder chose approach B below.

## Why

Stages 1–4 and the phone-first deliveries are on `main` behind the switch. Production still makes
`plain` users and keeps every finance row in clear. The switch day makes every account
end-to-end encrypted before the public store release.

Production on 2026-11-19 (admin panel, aggregates only):
- 12 accounts: 5 with an email, 7 guests. All were made since 2026-10-19.
- No app version reported, and no daily actives.

The founder says there are no outside users; only test accounts and the founder's own. **The
founder's account holds real data in daily use and must not lose any of it.** All of that data is
in one account with an email; no guest holds real data. Everything else is test data and is
deleted on the day. Production does not set `E2E_PREVIEW_USER_IDS`, so no account is in preview
through the allowlist.

## Goals

- The founder's account becomes `encrypted` with all of its data:
  - transactions (and the deleted ones still in the restore window);
  - categories (archived ones included);
  - budgets;
  - recurring payments;
  - the merchant memory;
  - the profile settings (currency, time zone, language, onboarding).

  It keeps its user id, email and passkeys.
- No plaintext row of a migrated account is deleted unless the server has checked that the
  encrypted copy holds the same number of each type.
- An old web tab is told to update, never shown an empty account. The installed Android release
  needs no new screen: only the founder's phone exists, and it is reinstalled on the day.
- From that day every new user is born encrypted (`NEW_USERS_ENCRYPTED=true` in production), and
  the preview allowlist is gone.
- The policy, landing and store copy say what is true from that day.
- After the day, no `plain` account remains, so the old finance tables can be dropped.

## Non-goals

- No migration on the phone, and none for guests. The 7 guests are test data and are deleted.
- No general "import a Wambito export" feature.
- No change to the crypto, the sync protocol or the vault.
- No keeping `plain` accounts alive after the day.

## Anti-goals (a failure even if it technically works)

- The founder's data partly lost, silently: a type, the deleted-but-restorable rows, a budget or a
  merchant rule missing after the switch.
- A migration that can half-finish: plaintext deleted while the encrypted copy is incomplete, or an
  account stuck between the two with no way to retry.
- The server reading or logging the plaintext it sends during the migration anywhere other than the
  answer itself.

## Approaches considered

- **A. Full migration on web and phone (the parent spec).** Both clients migrate any `plain`
  account on open; guests migrate on the phone without a recovery key. It is robust for strangers,
  but costs two clients and the guest path, for code that runs once.
- **B. Web-only migration (chosen).** Only the web migrates, once, for the founder. The phone
  needs no change: it is reinstalled and linked through its existing encrypted-account flows. Test accounts are
  deleted. It is as safe as A for the data that matters, at about half the work.
- **C. Export and import into a new account.** It needs a full importer, changes the account id
  (passkeys and assistants redone), and has no safety net if the import misses something.
  Rejected.

## Design

### 1. Account state

- `user.encryption` gains `migrating`. The full set is `plain` | `migrating` | `encrypted`.
- **Only the session that called `start` may write during the migration** (builder-check ruling).
  It is kept in a new column `user.migration_session_id`. A `start` from another session of the
  same account while `migrating` takes the migration over (planning ruling): a lost tab or a new
  sign-in can always resume or cancel.
  - For a `migrating` account, `/v2/sync` pushes and `/v2/keys` writes from any other session get
    409 `migration_in_progress`.
  - Its old `/v1` finance routes answer 426 for every session.

  So a phone or another tab that opens meanwhile cannot add records and break the count check.
  (`/v2/keys` and `/v2/sync` are open to any account today; this rule is new.)
- `GET /v1/me` gains an optional `migration` field: `"available"` for a `plain` account with an
  email while the new config flag `MIGRATION_OPEN` is on (or its id is in `MIGRATION_OPEN_USER_IDS`,
  for the dev stack's seeded test user); `"in_progress"` while `migrating`; absent otherwise.
  - It is a flag of its own, not `NEW_USERS_ENCRYPTED`, because CI runs every web e2e with
    `NEW_USERS_ENCRYPTED=true` on plain seeded users (planning ruling).
  - The web runs the flow only on `available`, so the deploy is inert until the founder turns
    `MIGRATION_OPEN` on.
  - The web resumes on `in_progress`.
  - `encryption` answers `"preview"` for `migrating` and `encrypted` (an additive field; old
    clients ignore it).
- Elsewhere, `migrating` behaves as `plain`: cleanup tiers, session length, the 401 codes and
  recovery sign-in. It behaves as `encrypted` only for the 426 and the write rule above (my call).
- The plaintext tables stay readable to the migration routes while the account is `migrating`.

### 2. Server routes (new, `/v2/migration/*`)

- **`POST /v2/migration/start`** (session only, the account must be `plain` with an email).
  - It sets `migrating` and answers the counts the server holds per type. Calling it again while
    `migrating` answers the same counts, so a retry is safe.
  - A guest or an `encrypted` account gets 409.
- **`GET /v2/migration/source`** (session only, `migrating` only). Everything the vault needs, in
  one JSON answer, with the server's ids:
  - transactions (the soft-deleted ones still in the restore window are marked deleted);
  - categories with archived ones;
  - budgets;
  - recurrences;
  - the merchant memory (`merchant_categories`);
  - the default account;
  - the profile settings.

  `/v1/me/export` is not reused: it leaves out deleted rows, the merchant memory and the
  settings. The body is never logged.
- **`POST /v2/migration/finish`** with the client's counts per type. In one transaction, the server:
  1. counts the account's `records` per record type: live ones, and deleted ones with a body;
  2. compares them with its plaintext rows and with the client's counts;
  3. on a match:
     - deletes the account's plaintext rows in `transactions` (`external_hash` with them),
       `categories`, `category_budgets`, `recurrences` (with their occurrence and dismissal rows),
       `merchant_categories`, `accounts`, `imports` (their payload) and `idempotency_keys` (their
       stored response bodies);
     - revokes the account's assistants (their tokens carry no assistant secret and could not read
       the vault anyway);
     - sets `encrypted` and answers 200;
  4. on a mismatch, deletes nothing, stays `migrating`, and answers 409 `count_mismatch` with both
     sets of counts.

  The profile columns of `user` (time zone, language, onboarding) stay: they are the
  profile, not finance rows, and the policy says so. The vault's `settings` record copies them.
  The vault writes no `account` records, so the default account is not counted.
- **`POST /v2/migration/cancel`** (`migrating` only, the starting session).
  - It deletes the account's `records` and their purge rows, keeps its key wraps, and sets `plain`
    again.
  - The web wipes its local records, outbox and sync position, keeps its keys, and starts again
    from `source` with the same data key. So the recovery key the person saved keeps working
    (builder-check ruling).
  - An `encrypted` account cannot call it.
- **426 `update_required`** from every old `/v1` finance route for a `migrating` or `encrypted`
  account (today a preview account gets 403 `encrypted_account`; the code changes to 426).
  - `GET /v1/me` and `DELETE /v1/me` stay.
  - The web maps 426 to "update Wambito" (a reload).
  - The MCP maps it to its existing "reconnect" answer: a token without the assistant secret is
    fixed by connecting again.
  - The phone needs nothing new (see section 4).
- `CHANGELOG.md` gets a line under "Unreleased" for each.

### 3. Web migration flow

When the web opens a `plain` account that has an email, on the switch-day build, it runs a
"Protect your account" flow before the app:

1. It says once, in Wambi's voice, what changes and that it takes a minute.
2. Keys and the recovery key, as for a new encrypted account (the existing setup screen and its
   check characters). A passkey with PRF is offered after, as today.
3. `start`, then `source`. Each row becomes a sealed record with the **same id**, through the
   existing store and sync:
   - a deleted transaction becomes a tombstone with its body (restore after delete);
   - the merchant memory becomes `merchant` records;
   - the profile becomes the `settings` record;
   - a recurring payment's occurrences keep their ids. A dismissed month is written as the vault
     writes a dismissal: with the id the vault derives from the rule and the month. Otherwise a
     dismissed payment would come back (builder-check ruling).

   The web's own vault opening must not add records before `finish`: no starter categories, and
   no recurring payments generated. The flow holds those until the account is `encrypted`.
4. The sync pushes until the outbox is empty. Then `finish` with the client's counts.
5. **On 200,** the account is encrypted: the web's vault is open, and the app shows the same data.
6. **On a mismatch or any failure,** the person sees an honest message and a retry. The retry runs
   `cancel`, then starts again from step 3 with the same keys.

   Nothing is lost: the plaintext stays until a `finish` succeeds.
7. The flow survives a reload. While the account is `migrating` and the vault exists here, it
   resumes at the step it was in. With no vault here, it offers to cancel and start again.

The web's plain mode and the migration flow are deleted with the old tables (section 6).

### 4. Phone

- No phone change. The founder confirmed this: only the founder's phone exists, and the founder
  uses the web on the day.
- An installed release may show an error or the Unlock screen once the account is
  `migrating` or `encrypted`.
- After the switch, the founder installs the new release and links the phone through the existing
  flows: "Connect another device" from the web, or the recovery key.

### 5. MCP

The founder's assistant tokens carry no assistant secret `S`. After the switch, the API refuses
them for an encrypted account (stage 4: `invalid_grant`, the client revoked). The founder connects
the assistant again from Settings, and the consent page makes the wrap. The switch-day checklist
says so; there is no code change.

### 6. Switch day, in order

Each step names who does it.

1. **Builder:** the code above merges and deploys. Production still has `NEW_USERS_ENCRYPTED` off;
   nothing changes for anyone until step 3.
2. **Builder, rehearsal first** (the founder chose that the builder runs it, 2026-11-19):
   1. A copy of production is restored from the R2 backup into a throwaway local Postgres on the
      founder's Mac. The founder decrypts the dump, since the age key is theirs.
   2. On that copy, the local stack migrates the founder's account through the web flow, signing
      in with the email link through Mailpit (passkeys only work on app.wambito.com).
   3. Every type's counts match. A month's summary and the budgets show the same figures before
      and after.
   4. The throwaway database and the dump are deleted afterwards.

   No real data goes into the repo, the PR or a log: the PR records only counts and totals.
3. **Founder, in production:** sets `NEW_USERS_ENCRYPTED=true` and `MIGRATION_OPEN=true`, and removes `E2E_PREVIEW_USER_IDS`
   in the VPS `.env`, then restarts the API.
4. **Founder:**
   - opens app.wambito.com and runs the migration of their own account;
   - checks the figures;
   - pairs the phone, adds a passkey, reconnects the assistant.
5. **Founder:** deletes the 11 test accounts in the admin panel, with the reason "switch-day test
   data". The admin panel account is the founder's own and stays. If it turns out to be a
   separate account, it stays too, migrated in the same way.
6. **Builder, a later PR, after a week with no problem:** drops the old finance tables, routes,
   reports, `idempotency_keys` use, the web's plain mode and the migration routes (a major server
   version, `CHANGELOG.md`). Backups holding plaintext age out with the 14-day retention.

### 7. Copy, policy and stores

These ship with step 1 but say what is true from step 4. The founder publishes the stores and the
policy on the day.

- `docs/privacy-policy.md`, the landing FAQ and the store listings describe what the server can
  and cannot see, including the metadata and the web caveat. The policy gives the date after which
  no plaintext copy exists: the switch day plus 14 days.
- The landing tests that forbid end-to-end claims (`overclaims`) change to allow them.
- Play's data safety form: encrypted in transit, and the developer cannot read financial info
  (the founder fills it in).

## Constraints

- Money is integer cents; record ids are the server's ids.
- Nothing on the server stores or logs the source answer or a sync body outside `records`.
- Every API change gets a `CHANGELOG.md` line. Generated clients are regenerated.
- Failing tests first. Commit and naming rules as in `AGENTS.md`.

## Testing

- **API (testcontainers):**
  - start, source, finish and cancel, including the retry paths;
  - finish with good counts deletes the plaintext and sets `encrypted`;
  - finish with a bad count changes nothing;
  - a guest or an encrypted account is refused;
  - 426 on every old finance route for `migrating` and `encrypted`;
  - a test that no source body is logged.
- **Web:**
  - the flow's model, unit-tested: every step's failure leaves the plaintext, and a reload resumes;
  - a play story per screen;
  - an e2e on the dev stack: a seeded `plain` account with every data type, including deleted and
    archived rows, merchant rules and a recurring payment, migrates. After migration the summary,
    budgets, the merchant memory and a restore of a deleted row are the same as before, and `psql`
    finds no plaintext rows for it.
- **API:** while `migrating`, another session's push or key write gets 409 `migration_in_progress`;
  `GET /v1/me` `migration` is `available`, `in_progress` or absent as section 1 says.
- **The rehearsal (section 6, step 2)**, with its result written in the PR.

## Left to the builder

- Exact copy in the four languages, and the screens' layout within the design system.
- The JSON shape of `/v2/migration/source`.
- Where the flow's resume state lives in the web vault.
- How the counts are grouped per type: one count per record type, deleted-with-body counted apart.
