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

This branch is **not merged before the day**: merging deploys, and the policy and landing copy say
what is true only from the founder's migration on. The day starts by dating the copy in this
branch and merging it (section 2, "The day starts").

1. The encrypted import and export stage (importing a Budge CSV and downloading your data, made on
   the device, for encrypted accounts) is merged and deployed. The policy, the FAQ and the store
   listings in this branch say both work.
2. `deploy/personal/docker-compose.yml` passes `NEW_USERS_ENCRYPTED`, `MIGRATION_OPEN` and
   `MIGRATION_OPEN_USER_IDS` to the `api` service, and `deploy/personal/.env.example` documents
   them. The `api` service lists its variables one by one, so a `.env` line it does not list has no
   effect. Done: all three are passed, off by default, and `test-compose-files.sh` checks each one.
   The direct-mode file adds no `api` variables of its own.
3. **Founder:** the MCP's key pair is set on the VPS, or the founder's assistant cannot connect
   again after the move (step 4.6). Check by name only, never printing a value, from
   `deploy/personal`:

   ```sh
   docker compose exec -T api node -e 'console.log("MCP_WK_PUBLIC_KEY set:", Boolean(process.env.MCP_WK_PUBLIC_KEY))'
   docker compose exec -T mcp node -e 'console.log("MCP_WK_PRIVATE_KEY set:", Boolean(process.env.MCP_WK_PRIVATE_KEY))'
   # expected: true, true
   ```

   If either is false, make the pair once with `deploy/personal/gen-mcp-keys.sh`
   (`deploy/personal/AGENTS.md`, "The MCP's key pair"), put both lines in `.env`, and
   `docker compose up -d api mcp`.
4. A phone release that opens encrypted accounts is published (a `mobile-v*` tag, `docs/mobile/release.md`):
   the founder installs it in step 4.
5. The rehearsal below passed, on this branch.
6. The founder picks the day.

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

### The day starts: date the copy, then merge (builder, with the founder)

1. In this branch, list the date markers the policy still holds:

   ```sh
   scripts/check-switch-dates.sh   # prints each file:line left, exits 1 while any is left
   ```

   They are in `apps/web/app/i18n/messages/{es,en,it,pt}.json` (`legal.privacy.version`,
   `legal.privacy.sections.storage.body`, `legal.delete_account.version`) and in
   `docs/privacy-policy.md`.
2. Replace the marker ending in `_PLUS_14` **first**, with today plus 14 days (the last dump holding
   plaintext ages out then), then the other one with today (the day of step 4). Replacing the short
   one first would leave `_PLUS_14` glued to a date. The words around them carry the article, so
   write the bare date: es `21 de noviembre de 2026`, en `21 November 2026`, it `21 novembre 2026`,
   pt `21 de novembro de 2026`.
3. `scripts/check-switch-dates.sh` prints `none left` and exits 0. Run the i18n tests
   (`cd apps/web && pnpm exec vitest run --project unit app/i18n`), commit
   `docs: date the privacy policy for the switch day`, and merge. Merging deploys the API and the
   web (`deploy/personal/auto-deploy.sh`, once CI passes) and the landing (CI). Wait until
   `/health` on app.wambito.com shows the merge commit.
4. If step 4 slips past the dated day, date the copy again in a new PR: the policy's dates are the
   day of the founder's migration and that day plus 14.

### Step 3. Flags (founder)

On the VPS, in `deploy/personal/.env`:

```sh
NEW_USERS_ENCRYPTED=true
MIGRATION_OPEN=true
```

Delete the `E2E_PREVIEW_USER_IDS` line too if there is one (the production compose does not pass
it to the API, so it has no effect; it simply goes).

Apply it from `deploy/personal` with `docker compose up -d api` (a plain `restart` does not re-read
`.env`). Check what the API got (no secret in it):

```sh
docker compose exec -T api node -e 'const e = process.env; console.log(e.NEW_USERS_ENCRYPTED, e.MIGRATION_OPEN)'
# expected: true true
```

Then a backup by hand, so the newest dump is from just before the move: `./backup.sh`.

### Step 4. The founder's migration (founder)

Before you start, leave the phone app and the assistant idle until step 4.5: no edit in the phone
app, no question to the assistant. A `/v1` edit that lands at the moment the move starts can be
lost (its row is copied before the edit). Bank-notification captures may still arrive: the phone
keeps them queued while the account is migrating (the server answers its background requests with
a retryable 403, and the new release also keeps them on a 426), and they go to the vault once the
new release is opened in step 4.5.

1. Open app.wambito.com and sign in. "Protect your data" runs before the app:
   - save the recovery key in the password manager and type the check characters;
   - wait for the copy and "Checking that nothing is missing";
   - "Done": the app opens on the encrypted account.

   On "Something did not add up" or any failure: "Try again" (nothing was deleted). A closed tab
   resumes where it was. If it keeps failing, roll back (below) and call the builder.
2. Check the figures: the same month's summary and budgets as before, the recurring payments, the
   merchant memory (a capture suggests the usual category), a deleted transaction restores.
3. On the VPS, aggregates only: `select encryption, count(*) from "user" group by 1;` shows the
   founder's account as `encrypted`.
4. Add a passkey on the web: Settings → Security (one with PRF opens the data without the recovery
   key).
5. The phone: install the new release (over the old one, so its queue of captures stays) and open
   it. It learns the account is encrypted and moves every capture still queued into the vault once
   the vault opens. Sign in with the email if it asks. On its Unlock screen choose
   "Add this phone from another device" and approve it on the web (Settings → Security → "Connect
   another device"), or type the recovery key.
6. The assistant: the old connection was revoked by the move. In the assistant (Claude, ChatGPT),
   remove the Wambito connector and add it again (`https://app.wambito.com/mcp`), then approve on
   Wambito's consent page; it makes the assistant's key.

### Roll back: the account back to plain (founder, with the builder)

When `finish` keeps failing, the account stays `migrating`: the web shows only the flow, the old
phone app and the assistant get refusals, and turning `MIGRATION_OPEN` off does not change that.
The plaintext is intact the whole time. Only `POST /v2/migration/cancel`, from the session the move
is bound to, makes the account `plain` again. The flow's failure screens offer "Try again" (or
"Continue here", or "Start again") and "Sign out", never a way back to plain, and signing out does
not cancel. So
the way back is the browser console of the founder's signed-in tab on app.wambito.com.

1. **Founder**, on the VPS from `deploy/personal`: stop new migrations. Set `MIGRATION_OPEN=false`
   in `.env`, then `docker compose up -d api`. `NEW_USERS_ENCRYPTED` may stay on.
2. **Founder**, in the tab where you are signed in to app.wambito.com (the flow's screen), open the
   developer tools' console (Cmd+Option+J in Chrome, Cmd+Option+K in Firefox, or Safari's Develop
   menu) and paste:

   ```js
   const me = await (await fetch("/api/v1/me")).json();
   const h = { "x-wambito-user": me.id };
   const started = await fetch("/api/v2/migration/start", { method: "POST", headers: h });
   const cancelled = await fetch("/api/v2/migration/cancel", { method: "POST", headers: h });
   console.log(me.migration, started.status, cancelled.status);
   // expected: in_progress 200 204
   ```

   The requests are same-origin, so the browser sends the session cookie by itself; nothing secret
   is typed or printed. `start` binds the move to this tab's session (it works with the gate
   closed, since the account is already migrating), and `cancel` deletes the account's records and
   their purge mark, keeps its key wraps and the recovery verifier, and sets `plain`. Anything else:
   stop, and paste only the three printed values to the builder.
3. Reload the page: the plain app opens with every movement, category, budget and recurring
   payment as before. Check one month's summary.
4. What stays: the saved recovery key keeps working for the next attempt (the flow asks for it at
   "Unlock"), and this browser still holds the vault of the attempt; signing out wipes it. The
   phone's queued captures go to the plain account again as soon as the server takes them.
5. **Builder**, aggregates only: `select encryption, count(*) from "user" group by 1;` shows the
   founder's account as `plain`, and the plaintext counts per type match those noted before step 4.

Last resort, only if the account is not `plain` with its plaintext after this: restore the
backup taken in step 3 (`deploy/personal/restore.sh`, `deploy/personal/README.md`). It loses
whatever was written after it.

### Step 5. The test accounts (founder)

1. Tell the accounts that stay. In the admin panel (`docs/admin.md`), look up your own email (you
   know it; it never goes into the repo, a PR or a log): that row is your account, now `encrypted`,
   and its id is the one to keep. Then check whom the panel belongs to, ids only:

   ```sh
   docker compose exec -T api node -e 'console.log(process.env.ADMIN_USER_IDS)'
   ```

   - It is your account's id: one account stays, and **11** are deleted.
   - It is another id: that admin account is a separate one. It stays too, and migrates as in step 4
     (sign in with it, "Protect your data"). Then two accounts stay and **10** are deleted.
2. List every account on the VPS, ids only:

   ```sh
   docker compose exec -T postgres psql -U wambito -d wambito \
     -c 'select id, is_anonymous, encryption, created_at from "user" order by created_at'
   ```

   Expected: 12 rows (on 2026-11-19: 5 with an email, yours among them, and 7 guests). Every row
   that is not an id kept in 1 is a test account. If there are more rows than that, someone else
   signed up: do not delete those.
3. In the admin panel, look each test account up (by email for those with one, by id for a guest)
   and delete it with the reason `switch-day test data`. The panel cannot delete its own admin
   account in any case.
4. Check: `select encryption, count(*) from "user" group by 1;` shows no `plain` account.

### Stores, the same day (founder)

- Google Play: paste each language's `apps/mobile/fastlane/metadata/android/<locale>/full_description.txt`
  into the store listing (F-Droid reads them from the repo), and update the **Data safety** form
  with the answers in `docs/mobile/play.md` ("Data safety"):
  - data is encrypted in transit: yes;
  - financial info (purchase history, other financial info) stays declared, end-to-end encrypted,
    so the developer cannot read it; check Play's current help on end-to-end encrypted data first;
  - "Device or other IDs" goes (no IP address is stored); "App activity → App interactions" is
    declared (the active-day count).
- `README.md` and `docs/encryption.md` already say encryption is on for every account (they merge
  with this branch, on the day).

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
