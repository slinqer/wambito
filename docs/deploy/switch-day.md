# Switch day: every account becomes end-to-end encrypted

The runbook for E2E stage 5 (design: `docs/superpowers/specs/2026-11-19-e2e-stage-5-switch-design.md`,
sections 6 and 7). On the day, the founder's account moves from plain to encrypted from the web,
every new user is born encrypted, and the test accounts are deleted. Each step names who does it:
the **builder** (the coding agent or whoever merges the code) or the **founder**.

Rules for every step:

- No real data goes into the repo, a PR, an issue or a log: no email, name, amount, merchant or
  category. Write down counts per type and "matched" / "did not match", nothing else.
- Never read a `.env` file or a key in chat or in a tool: the founder edits them and pastes only
  what a step asks for.
- The plaintext is deleted only by a `finish` whose counts match (the server checks). Until then a
  failure loses nothing: retry from the flow, never by hand in the database.

## 0. Before the day (builder)

1. The stage 5 code is merged and deployed (`/health` shows the commit). Production still has
   `NEW_USERS_ENCRYPTED` and `MIGRATION_OPEN` off, so nothing has changed for anyone.
2. `deploy/personal/docker-compose.yml` passes `NEW_USERS_ENCRYPTED`, `MIGRATION_OPEN` and
   `MIGRATION_OPEN_USER_IDS` to the `api` service, and `deploy/personal/.env.example` documents
   them. The `api` service lists its variables one by one, so a `.env` line it does not list has no
   effect. Done: all three are passed, off by default, and `test-compose-files.sh` checks each one.
   The direct-mode file adds no `api` variables of its own.
3. A phone release that opens encrypted accounts is published (a `mobile-v*` tag, `docs/mobile/release.md`):
   the founder installs it in step 4.
4. The rehearsal below passed.

## 1. The rehearsal (builder runs it, the founder decrypts)

A copy of production, migrated on the founder's Mac, so the real migration holds no surprise.

1. **Builder:** stop the dev stack (it keeps its data): `docker compose stop` from the repo root.
   Start a throwaway stack under its own compose project, so it gets its own empty database volume:

   ```sh
   docker compose -p wambito-rehearsal up -d postgres mailpit
   ```

2. **Founder:** download the newest encrypted dump from R2 (Cloudflare dashboard: R2, the backups
   bucket, the newest `wambito-YYYY-MM-DD.dump.age`, Download) into a private folder outside the
   repo, and decrypt it with the age key from the password manager (`deploy/personal/README.md`,
   "Backups in Cloudflare R2"):

   ```sh
   umask 077; dir="$(mktemp -d)"; echo "$dir"
   # move the downloaded .dump.age into "$dir", put the age key file there too, then:
   age -d -i "$dir/wambito-backup.key" -o "$dir/rehearsal.dump" "$dir/wambito-YYYY-MM-DD.dump.age"
   rm "$dir/wambito-backup.key"
   ```

3. **Builder:** restore it into the throwaway database, with the flags `backup.sh` and
   `restore.sh` use (no owners and no grants from the dump; the dev role's default privileges grant
   the restored tables to `wambito_app`):

   ```sh
   docker compose -p wambito-rehearsal exec -T postgres \
     pg_restore -U wambito -d wambito --no-owner --no-acl --exit-on-error --single-transaction \
     <"$dir/rehearsal.dump"
   ```

4. **Builder:** start the API on the real clock with the migration still closed, and the web:

   ```sh
   docker compose -p wambito-rehearsal up -d --build api   # applies newer migrations at start
   pnpm --filter @wambito/web dev                           # http://localhost:5173
   ```

   Every email goes to Mailpit (http://localhost:8025): the compose file sets `SMTP_URL` to it, and
   the API refuses to start with a Resend key next to it, so nothing reaches a real inbox.
5. **Founder:** sign in at http://localhost:5173 with the email link or code from Mailpit (passkeys
   only work on app.wambito.com). In the plain app, note privately one month's summary (spent,
   income, left) and each budget's figures. **Builder:** note the founder's counts per type with
   aggregates only (`docker compose -p wambito-rehearsal exec -T postgres psql -U wambito -d wambito`):
   transactions live and deleted, categories (archived included), budgets, recurring payments,
   merchant rules.
6. **Builder:** open the migration and reload the page:

   ```sh
   MIGRATION_OPEN=true docker compose -p wambito-rehearsal up -d api
   ```

   **Founder:** the "Protect your data" flow runs: the recovery key (a throwaway one: this copy
   only, never confused with the real one), then the copy, then "Done".
7. **Both:** compare. The records per type (`select type, deleted, count(*) from records where
   user_id = '…' group by 1, 2`) match the counts of step 5 (live transactions, deleted ones as
   tombstones with a body, one `settings` record). The same month's summary and budgets show the
   same figures. A deleted transaction can be restored. The plaintext tables hold nothing for that
   user, and `"user".encryption` is `encrypted`.
8. **Builder:** delete everything: sign out in the browser (it wipes the local vault), then

   ```sh
   docker compose -p wambito-rehearsal down -v   # -v only with -p wambito-rehearsal: never on the dev stack
   rm -rf "$dir"
   docker compose up -d                          # the dev stack back
   ```

   The founder deletes the throwaway recovery key. In the PR, record only the counts per type and
   "summary and budgets matched".

If anything did not match, stop: the day waits for a fix and a new rehearsal.

## 2. The switch, in production

### Step 3. Flags (founder)

On the VPS, in `deploy/personal/.env`:

```sh
NEW_USERS_ENCRYPTED=true
MIGRATION_OPEN=true
# and delete the E2E_PREVIEW_USER_IDS line if there is one
```

Apply it from `deploy/personal` with `docker compose up -d api` (a plain `restart` does not re-read
`.env`). Check what the API got (no secret in it):

```sh
docker compose exec -T api node -e 'const e = process.env; console.log(e.NEW_USERS_ENCRYPTED, e.MIGRATION_OPEN, e.E2E_PREVIEW_USER_IDS ?? "(unset)")'
# expected: true true (unset)
```

Then a backup by hand, so the newest dump is from just before the move: `./backup.sh`.

### Step 4. The founder's migration (founder)

1. Open app.wambito.com and sign in. "Protect your data" runs before the app:
   - save the recovery key in the password manager and type the check characters;
   - wait for the copy and "Checking that nothing is missing";
   - "Done": the app opens on the encrypted account.

   On "Something did not add up" or any failure: "Try again" (nothing was deleted). A closed tab
   resumes where it was. If it keeps failing, leave the account as it is and call the builder.
2. Check the figures: the same month's summary and budgets as before, the recurring payments, the
   merchant memory (a capture suggests the usual category), a deleted transaction restores.
3. On the VPS, aggregates only: `select encryption, count(*) from "user" group by 1;` shows the
   founder's account as `encrypted`.
4. Add a passkey on the web: Settings → Security (one with PRF opens the data without the recovery
   key).
5. The phone: install the new release, sign in with the email, then open the data with "Connect
   another device" (approve it from the web, Settings → Security) or with the recovery key.
6. The assistant: the old connection was revoked by the move. In the assistant (Claude, ChatGPT),
   remove the Wambito connector and add it again (`https://app.wambito.com/mcp`), then approve on
   Wambito's consent page; it makes the assistant's key.

### Step 5. The test accounts (founder)

1. List the accounts on the VPS, ids only:

   ```sh
   docker compose exec -T postgres psql -U wambito -d wambito \
     -c 'select id, is_anonymous, encryption, created_at from "user" order by created_at'
   ```

   Expected: 12 rows, the founder's (now `encrypted`) and 11 test accounts (4 with an email, 7
   guests). If there is any other row, someone else signed up: do not delete it.
2. In the admin panel (`docs/admin.md`), look each test account up (by email, or by id for a
   guest) and delete it with the reason `switch-day test data`. The panel cannot delete the
   founder's own account, which stays.
3. Check: `select encryption, count(*) from "user" group by 1;` shows no `plain` account.

### The copy, on the day (founder or builder)

- The policy's dates: replace every `TODO-DATE` in `apps/web/app/i18n/messages/{es,en,it,pt}.json`
  (`legal.privacy.version`, `legal.privacy.sections.storage.body`, `legal.delete_account.version`)
  and in `docs/privacy-policy.md`. `TODO-DATE` is the day of step 4; `TODO-DATE+14` is that day plus
  14 days (the last dump holding plaintext ages out then). The words around them already carry the
  article, so write the bare date: es `21 de noviembre de 2026`, en `21 November 2026`, it
  `21 novembre 2026`, pt `21 de novembro de 2026`. Then `git grep -n TODO-DATE` prints nothing.
  Commit `docs: date the privacy policy for the switch day`; merging deploys the web and the
  landing.
- Google Play: paste each language's `apps/mobile/fastlane/metadata/android/<locale>/full_description.txt`
  into the store listing (F-Droid reads them from the repo), and update the **Data safety** form
  with the answers in `docs/mobile/play.md` ("Data safety"):
  - data is encrypted in transit: yes;
  - financial info (purchase history, other financial info) stays declared, end-to-end encrypted,
    so the developer cannot read it; check Play's current help on end-to-end encrypted data first;
  - "Device or other IDs" goes (no IP address is stored); "App activity → App interactions" is
    declared (the active-day count).

## 3. Later: dropping the old tables (builder, a PR after a week without problems)

Only once `select count(*) from "user" where encryption <> 'encrypted'` is 0 in production. One PR,
a major server version (`CHANGELOG.md`, root `package.json`), clients regenerated:

- drop `transactions` (and `external_hash`), `categories`, `category_budgets`, `recurrences` (with
  their occurrence and dismissal rows), `merchant_categories`, `accounts`, `imports` and the
  `idempotency_keys` use;
- remove the old `/v1` finance routes and reports, the MCP's plain path, the web's plain mode and
  the migration flow, `/v2/migration/*`, `MIGRATION_OPEN` and `MIGRATION_OPEN_USER_IDS`, the
  `migrating` state and `user.migration_session_id`, `E2E_PREVIEW_USER_IDS`; `NEW_USERS_ENCRYPTED`
  becomes the only behaviour;
- update the `AGENTS.md` files and this runbook's status.

Backups holding plaintext age out by themselves with the 14-day retention, locally and in R2.
