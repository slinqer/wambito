# Admin panel and data-subject requests

The admin panel is how the operator answers a person's rights under Colombia's Ley 1581 (access,
correction, deletion) and handles the rare account problem. Design: `docs/superpowers/specs/2026-11-04-admin-panel-design.md`.
It is off until an admin is configured.

## Who is an admin

An admin is a Wambito account whose user id is listed in `ADMIN_USER_IDS` (comma-separated) in the
server's `.env`. Empty or unset means no admins: every admin route answers 404 and the web panel
shows the not-found page.

To add one:

1. The account needs a passkey. The panel asks for a passkey check for each sign-in session, and
   again once 15 minutes have passed. Add it in the app's settings.
2. Find the account's id. For the first admin, ask the database, from `deploy/personal` on the
   server (put the account's own email in place of the example):

   ```sh
   docker compose exec postgres psql -U wambito -d wambito \
     -c "select id from \"user\" where email = 'you@example.com'"
   ```

   Once there is an admin, later admins' ids are in the panel's look-up (by email).
3. Put the id in `ADMIN_USER_IDS` in `deploy/personal/.env` on the server.
4. Apply it: from `deploy/personal`, `docker compose up -d api` (a plain `restart` keeps the old
   environment).

An assistant (an OAuth token) and the mobile app never reach the panel: it is a web session only.

### Limiting by address (optional)

`ADMIN_ALLOWED_IPS` is a comma-separated list of IPs or CIDR ranges, for example
`203.0.113.7,198.51.100.0/24`. When set, the panel answers 404 to any other address. Unset, any
address may try. It uses the client address the API already trusts (`docs/deploy/api.md`).

## Deadlines (Ley 1581)

- Consultation ("what data do you hold about me?"): answer within **10 business days**.
- Claim (correction, deletion): answer within **15 business days**.

Requests arrive at `privacy@wambito.com`. Write down when each one arrived.

## Procedures

Every action asks for a reason (1 to 300 characters, no personal data) and is written to the audit
log together with the action.

- **Consultation.** Answer with the categories of data Wambito stores (the list in
  `docs/privacy-policy.md`). An encrypted account's finances open only on the person's own
  devices (downloading them from Settings is not available yet for encrypted accounts). The admin
  exports nothing.
- **Deletion.** Check the request comes from the email address of the account. Delete the account in
  the panel and write the request as the reason. In the answer, say that backups age out within 14
  days.
- **Correction.** For a wrong or unreachable email, use the panel's email change: it sends a
  confirmation link to the new address, valid 24 hours. While `SIGN_IN_ALLOWLIST` is set, the new
  address must be on it (add it to the `.env` and apply it as above first), otherwise the panel
  refuses the change: the person could not sign in with it. Proving the requester is the account's
  owner is the admin's judgment; the reason records how it was checked. Other data the person
  corrects in the app.
- **Account problems.** Sign out everywhere, revoke an assistant or remove a passkey from the same
  screen. Suspend blocks sign-in and ends sessions and assistants until you reactivate it.

An admin cannot delete or suspend their own account from the panel.

## Numbers

The home screen shows aggregates only: no person's row, IP address or finance data is read.

- **Guests** (`guests`): people without an email. The name stays for compatibility.
- **Installs by platform:** users by the platform their app reported (`android`, `ios`, `web`);
  `unknown` are accounts made before the platform was recorded.
- **Daily actives** (90 days, UTC): the sum of the daily count the app adds the first time it is
  open each local day (`/v2/me/seen`). The count has no user id, so one person is counted once per
  day, never across days.
- **Cohorts:** people grouped by the ISO week they signed up (last 12 weeks). Week 1, 4 and 12 show
  the cohort's highest daily active count during that week after sign-up, so read it as "at least"
  that many came back; empty while that week has not ended.
- **Versions:** people seen in the last 30 days by platform and app version, most people first.

## Dry run

After turning the panel on, and before the first real request, try it on a test account made for
that purpose (never a real person's account). While `SIGN_IN_ALLOWLIST` is set, the test account's
address must be on it, or it cannot sign in to make the account or to check step 3:

1. Look the test account up by email.
2. Suspend it with a reason; confirm it can no longer sign in.
3. Reactivate it; confirm it signs in again.
4. Delete it; confirm the look-up no longer finds it, and that the audit log shows the three
   actions.
