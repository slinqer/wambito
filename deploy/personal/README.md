# Personal install

Run your own Wambito on one machine, reach it from your phone at `https://app.wambito.com`, and keep
your real data safe with a daily backup. Two ways to be reached, chosen in `.env`:

- **Tunnel** (the default): a machine with no public address, such as a Mac at home, reached
  through a Cloudflare tunnel. The setup below starts this way.
- **Direct**: a server with its own public address serves the app itself, with its own
  certificate and no tunnel. The same files and the data move there (see
  [Moving to a server](#moving-to-a-server)).

It is a separate stack from the development one in the repository root: its own Docker project
(`wambito-personal`), database volume (`wambito-personal-db`) and private network. Nothing is shared
with `docker compose up` in the root (ports 5433, 3000, 5173, 8025, 1026), so both can run together.

```
 phone ──https──> Cloudflare ──tunnel──> cloudflared ──> web (Caddy) ──/api/*──> api ──> postgres
                  (TLS, DNS)             (outbound only)   │ static app                │ role wambito_app,
                                                           │                           │ row-level security
                                                           └ http://127.0.0.1:8088     └ the volume wambito-personal-db
                                                             (this Mac only)
```

The direct way (`COMPOSE_FILE` in `.env`, see [Moving to a server](#moving-to-a-server)):

```
 phone ──https──> web (Caddy, its own certificate) ──/api/*──> api ──> postgres
        :80 :443   │ static app
                   └ http://127.0.0.1:8088 (this server only)
```

- **One origin.** The app and the API share `app.wambito.com` (the API is under
  `/api`), so the session cookie is first-party and secure. No CORS.
- **Who can sign in.** Anyone, unless `SIGN_IN_ALLOWLIST` is set: then only those emails can ask
  for a sign-in code. Anyone else gets "Wambito todavía no está abierto al público" and no email
  is sent.
- **The landing lives elsewhere.** `/`, `/en`, `/it`, `/pt` and the roadmaps redirect (302, same path and query)
  to the public landing at `LANDING_URL` (default `https://wambito.com`), whose
  buttons come back here to `/sign-in` and `/demo`. Until the landing is deployed at `wambito.com`
  that redirect points at an empty site; the app's own paths are not affected. A home install can
  set `LANDING_URL` in `.env` to its own landing. The web build gets the same value
  (`VITE_LANDING_URL`), so the sign-in screen's logo and the end of "delete my account" leave
  for the landing too.
- **Assistants connect at `/mcp`.** Claude or ChatGPT add `https://<host>/mcp` as a connector,
  sign in with OAuth (`/api/auth/oauth2/*`, open for them) and act with the person's consent.
  The `mcp` service calls the API with each assistant's own token; it holds no secret.
  Caddy routes `/mcp`, `/.well-known/oauth-protected-resource*` and the OAuth server's
  metadata (`/.well-known/oauth-authorization-server/api/auth`). The person sees and revokes
  assistants in Ajustes → Conecta tu asistente.
- **Not everything is public.** Caddy answers 404 for `/api/openapi.json`, which is for
  developers.
- **No open ports through the tunnel.** Postgres and the API publish nothing. Caddy publishes
  `127.0.0.1:8088` for checking on this machine. The tunnel is outbound only. In the direct way
  Caddy also publishes 80 and 443 (TCP, and UDP for HTTP/3), and nothing else is added.
- **Mail** goes out from `MAIL_FROM` (default `hola@wambito.com`): through Resend on a server, or
  through Proton Bridge on a Mac, signed in to the Proton account that owns that address.
- **The API never holds the owner password.** A one-shot `migrate` service creates the `wambito_app`
  role and applies the migrations; the API connects as `wambito_app` only.

## First-time setup

On a Mac, through the tunnel. You need Docker Desktop, Node 22 with pnpm (`corepack enable`),
`cloudflared` (`brew install cloudflared`) and Proton Bridge, signed in to the Proton account you
send from (`MAIL_FROM` must be one of its addresses). On a server, see
[Moving to a server](#moving-to-a-server) instead: mail goes through Resend there.

### 1. Proton Bridge credentials

Bridge gives each account its own SMTP password; your Proton password does not work with it.

1. Open Proton Mail Bridge, click the account, then **Mailbox configuration**.
2. Under **SMTP** note the **Username** (the address) and the **Password** (a random string).
   Hostname `127.0.0.1`, port `1025`, security **STARTTLS**.
3. You will put them in `.env` as `SMTP_URL` (below). Containers reach Bridge on the Mac as
   `host.docker.internal:1025`. Bridge must be running whenever someone asks for a code.

Bridge's certificate is self-signed. `SMTP_TLS_INSECURE=true` tells the API to accept it, and only
for this mail connection: STARTTLS is still required, and the API refuses to start with the flag
unless `SMTP_URL` points at this machine (`localhost`, `127.0.0.1`, `[::1]` or
`host.docker.internal`).

### 2. `.env`

```sh
cd deploy/personal
cp .env.example .env
```

Fill it in (every variable is explained in the file; `.env` is ignored by git and never committed):

| Variable | Value |
|---|---|
| `POSTGRES_PASSWORD` | `openssl rand -hex 24` |
| `APP_DB_PASSWORD` | `openssl rand -hex 24` |
| `BETTER_AUTH_SECRET` | `openssl rand -hex 32` |
| `SIGN_IN_ALLOWLIST` | optional: your email(s), comma-separated, to keep sign-in closed; unset lets anyone in |
| `SMTP_URL` | `smtp://you%40example.com:BRIDGE_PASSWORD@host.docker.internal:1025`, with Bridge's username (the `@` is written `%40`) |
| `MAIL_FROM` | `Wambito <you@example.com>`, an address of that Proton account |
| `TUNNEL_ID` | from step 3 |

`up.sh` sets the file's mode to 600 each time it runs. Keep a copy of `.env` in your password manager: `BETTER_AUTH_SECRET` and the database passwords are
needed again when you move to a server.

### 3. The tunnel

Run these yourself, once. They talk to your Cloudflare account. (`login` writes an origin
certificate; if you already have a `~/.cloudflared/cert.pem` for another zone, keep the new one under
another name and give it to the commands with `--origincert "$CLOUDFLARED_ORIGINCERT"`, for example
`~/.cloudflared/<zone>-cert.pem`. Nothing in this folder uses that certificate: the running
tunnel needs only the credentials `.json`.)

```sh
cloudflared tunnel login                       # opens the browser: choose <your zone>
cloudflared tunnel create wambito-personal     # prints the tunnel id, writes ~/.cloudflared/<id>.json
cloudflared tunnel route dns wambito-personal <your PUBLIC_HOSTNAME>
```

The tunnel is for an install at home. `app.wambito.com` is served directly by the server (see
[Moving to a server](#moving-to-a-server)), so a home install uses a hostname of its own, in a zone
you own, and sets it as `PUBLIC_HOSTNAME`.

Put the id in `.env` as `TUNNEL_ID`. In the Cloudflare dashboard for your zone, switch on
**SSL/TLS > Edge Certificates > Always Use HTTPS** and **HSTS** (through the tunnel Caddy sets no HSTS
itself, because TLS ends at Cloudflare; in the direct way it does both). The stack mounts
`~/.cloudflared/<TUNNEL_ID>.json` read-only into the `cloudflared` container; it does not see `cert.pem` (the login certificate). Treat the
`.json` as a secret: anyone with it can run your tunnel. `cloudflared.yml` sends every hostname you
routed to the tunnel to the web container; it has no hostname of its own to edit.

### 4. First start

```sh
./up.sh --no-tunnel     # build, migrate, start; nothing is on the internet yet
./smoke.sh              # checks http://127.0.0.1:8088
```

`up.sh` builds the web app for your hostname into `apps/web/build-personal` (the landing release in
`apps/web/build` is not touched), builds the images, starts Postgres, runs the one-shot `migrate`
service (it creates the `wambito_app` role the first time), then starts the API and Caddy. If
`smoke.sh` passes, start the tunnel too:

```sh
./up.sh --skip-web      # adds cloudflared; reuses the web build
```

Open `https://app.wambito.com` on your phone and sign in with an allowlisted email:
the code arrives from `MAIL_FROM`.

### 5. The daily backup

```sh
./backup.sh             # try it once, by hand
./install-backup.sh     # then schedule it: every day at 03:00, as a launchd agent
```

See [Backup and restore](#backup-and-restore).

## Daily use

Run these from `deploy/personal` (compose reads `.env` there, `COMPOSE_FILE` included, so the
direct way's settings apply too):

```sh
docker compose ps                  # what is running
docker compose logs -f api         # follow the API (also: web, mcp, cloudflared, postgres)
docker compose logs web | tail     # access log: time, visitor address, path (no query string), status
docker compose restart api
docker compose stop                # stop everything, keep everything
./up.sh --skip-web                 # start it again
```

In the direct way `cloudflared` is switched off in the override, so a bare `docker compose up -d`
starts everything else and no tunnel. Everything has `restart: unless-stopped`, so it comes back
after a reboot once Docker (Desktop) is up.
In Docker Desktop settings, turn on **Start Docker Desktop when you sign in to your computer**.

**Never run `docker volume rm wambito-personal-db`**: that deletes the database. The volume is
external to the compose project (`up.sh` creates it), so `docker compose down -v` cannot delete it
either, and the scripts here refuse `down -v` anyway. `docker compose down` is safe.

### Who can sign in

Unset or empty, `SIGN_IN_ALLOWLIST` lets anyone create an account. To restrict it, list the emails
in `.env`, then `docker compose up -d api`; to open it again, delete the line and do the same. Case does not matter. Passkeys
of existing users keep working whatever the list says; the list only gates asking for a code. So
taking an address off the list does **not** sign that person out or remove their passkeys: delete
their sessions and passkeys in the database if you ever need to revoke access. A list that names no
valid email (for example `,`) stops the API from starting, instead of letting everyone in.

### The Android app

**`ANDROID_CERT_SHA256`** (in `.env`, empty by default) lets the Android app open magic links and
use passkeys for this hostname. Put in it the SHA-256 fingerprint of the certificate the app is
signed with, as `release.sh` prints it (`AB:CD:...`, 32 pairs); with more than one signing key
(yours now, F-Droid's later) list them all, comma-separated. The web container writes
`/.well-known/assetlinks.json` from it each time it starts, so after changing it run `./up.sh`
(compose recreates `web` when its settings change), then `./smoke.sh`. Left empty, the file is `[]`: it links no app, but it is still
there. A value that is not a fingerprint is skipped, with a warning in `docker compose logs web`.

### The iOS app

**`IOS_TEAM_ID`** (in `.env`, empty by default) lets the iOS app open magic links and use passkeys
for this hostname. Put in it the 10-character Apple team id the app is signed with (letters and
digits). The web container writes `/.well-known/apple-app-site-association` from it each time it
starts (the app id is `<team id>.com.wambito.app`; the link path is `/auth/verify`), so after
changing it run `./up.sh`, then `./smoke.sh`. Left empty, the file has empty lists: it links no app,
but it is still there, served as JSON. A value that is not a team id is skipped, with a warning in
`docker compose logs web`.
The API reads the same value to accept passkeys made in the app (Android sends the origin
`android:apk-key-hash:<the certificate's SHA-256>`); there a value that is not a fingerprint stops
the API from starting, so a typo shows up at once instead of as passkeys that never work.

**`GUEST_SIGNUP`** (default `true`) lets the app create an account without an email (a guest),
whatever `SIGN_IN_ALLOWLIST` says; the guest can save the account by claiming an email later (an
allowlisted one, if there is a list). Set `GUEST_SIGNUP=false` in `.env` and run `./up.sh` to stop new guests;
existing ones keep working. Once a day the API deletes guests that have not used the app for 60
days, with all their data. Accounts with an email are never deleted this way.

Sessions last 60 days from their last use (extended at most once a day), so a guest stays signed in as long as it is used within 60 days.

### Keeping the Mac awake

While the Mac sleeps, the tunnel is down and your phone shows a Cloudflare error (1033). To stay
reachable:

- Plugged in (the wording varies by macOS version): **System Settings > Battery > Options > Prevent automatic sleeping on power adapter
  when the display is off** (on desktop Macs: **Energy > Prevent automatic sleeping...**).
  Enable **Wake for network access** as well.
- Or hold it awake from a terminal: `caffeinate -s` (stays awake on AC power while it runs;
  `Ctrl-C` stops it). With the lid closed a laptop sleeps anyway unless it is plugged in with an
  external display, or you use a tool such as Amphetamine.

The backup does not need the Mac to be awake at 03:00: launchd runs a missed backup when the Mac wakes.

## Turning on the admin panel

The panel is off by default. To turn it on, put the admin's user id in `ADMIN_USER_IDS` in `.env`
(optionally `ADMIN_ALLOWED_IPS`), then, from this folder, `docker compose up -d api` (a plain
`docker compose restart api` does not re-read `.env`). Who may be an admin, the procedures and the
dry run: `docs/admin.md`.

## Update

```sh
./update.sh
```

It backs up first (a `-preupdate-` dump, see below), runs `git pull --ff-only`, rebuilds the web
app and the images, applies new migrations, and restarts. It never removes volumes. Options:
`--skip-backup`, `--no-pull`. If the pull cannot fast-forward (you have local commits) it stops
before changing anything.

**The install is built from the checkout you develop in**, so `up.sh` and `update.sh` refuse to run
(and say why) when:

- the repository is on a different branch than `PERSONAL_BRANCH` in `.env` (default `main`:
  the install follows what is merged), or
- tracked files have uncommitted changes (they would be built into the app, and their migrations
  applied to your real data; migrations only go forward).

Commit or stash and switch branch, or pass `--force` to go ahead anyway (the warning is printed).
Both print the branch and commit they are deploying. Untracked files are not checked.

Migrations should be backward compatible with the previous version, because the new API starts
after the migration but a failed deploy leaves the old API running against the new schema. To go
back to the code you had: `git checkout <old commit>`, `./update.sh --no-pull`; to go back to the
data you had, restore the backup `update.sh` made.

### The server's version

`/health` (and the server card in the app's Settings) reports the root `package.json`'s `"version"`
plus the commit it was built from, for example `1.0.0+1e5ccc2`, with `-dirty` after it when built with
`--force` from uncommitted changes. Raise the version by hand on `main` when a release of the
server deserves a new number (a commit `chore: version 1.1.0`); every deploy in between keeps it and
changes only the commit. What each version changed is in the root `CHANGELOG.md`. `up.sh` refuses a `package.json` without an `X.Y.Z` version. It does not
follow the app's `mobile-v*` tags: the two can share a number, but neither waits for the other.

### Automatic deploy (on a server)

On the server, `./install-auto-deploy.sh` (once, needs sudo and `sudo apt install jq`) installs a
systemd timer that runs `auto-deploy.sh` every 5 minutes. The server asks; GitHub holds no key to
it and nothing new is open in the firewall.

- When `PERSONAL_BRANCH` has a new commit, it waits until that commit's required CI checks have
  passed (`DEPLOY_REQUIRED_CHECKS` in `.env`, default `check e2e`; the mobile jobs and the landing
  do not count). It asks GitHub's public API, so it needs no token.
- Then it checks out **that** commit (not a newer one merged meanwhile) and runs
  `update.sh --no-pull` (backup, rebuild, restart) and `smoke.sh`.
- If either fails, it goes back to the commit before and rebuilds it. A commit whose CI, deploy or
  smoke test failed is never tried again; to retry one, delete its line from
  `~/.local/state/wambito/failed-commits`.
- A rewritten branch (force-pushed) is refused: it logs an error every run until a person looks.
- The same rule as above holds: a migration runs before the new API starts, so going back to the
  old code leaves the new schema. Keep migrations backward compatible; the pre-update backup is
  there if not.

There is no email yet, so a failed deploy only shows in `journalctl -u wambito-deploy.service`
(the app keeps running the version before). `./install-auto-deploy.sh --remove` turns it off.
`./test-auto-deploy.sh` checks all of this against a local repository and a fake GitHub API.

## Backup and restore

`backup.sh` writes `~/Backups/wambito/wambito-YYYY-MM-DD.dump` (`BACKUP_DIR` in `.env` changes the
folder; give it a folder of its own), keeps the newest 14 daily dumps, and checks every dump before
keeping it (below).

**No dump lives longer than 14 days**, daily or pre-update, and the same goes for the encrypted
copies. That is what the app tells someone who deletes their account: "Las copias de seguridad que
los incluyan se borran solas en 14 días". Every run applies it, even one that fails (a Mac that
was off for days removes them at its next run, on wake), with one exception: the newest dump
always stays, so weeks of failed backups never leave you with none (each failure notifies you;
fix the backup and the old one goes at the next good run). The count
limits below only cap what is younger. `./test-retention.sh` checks the rules on fake dumps (no
Docker needed). Copies made by anything else (Time Machine, iCloud's Recently Deleted) are not
covered: see [Keep a copy that is not on this Mac](#keep-a-copy-that-is-not-on-this-mac).

The checks:

1. `pg_dump -Fc` as the database owner, which bypasses row-level security. (Every table here is
   `FORCE ROW LEVEL SECURITY`; a dump as `wambito_app` fails, as it should. Do not change the role.)
2. `pg_restore -l` lists it and has a data section for every main table.
3. It restores into a scratch database (without the dump's owners and grants, as `restore.sh`
   does) and compares row counts with the live one for `user`,
   `passkey`, `accounts`, `categories`, `category_budgets`, `recurrences`, `imports` and
   `transactions`: a table with rows that restores empty fails the backup.

If a check fails, the new file is deleted, the older dumps stay (up to 14 days, and the newest always), the script exits non-zero and (from
the scheduled run) macOS shows a notification "Wambito backup failed". Log of the scheduled run:
`~/Library/Logs/wambito-backup.log`.

**Before an update** `update.sh` runs `backup.sh --pre-update`, which writes
`wambito-YYYY-MM-DD-preupdate-HHMM.dump`: its own file, so it never replaces that day's 03:00 dump,
and it does not count against the 14 daily dumps (the newest 10 pre-update dumps are kept, none
older than 14 days).

**Schedule.** `./install-backup.sh` installs `com.wambito.backup` for your user (check what it
installs first with `./install-backup.sh --render`; remove it with `./uninstall-backup.sh`). Runs at
03:00, or on wake if the Mac was asleep. If the Mac is switched off at 03:00 that day is skipped.
Docker Desktop must be running. `launchctl kickstart gui/$(id -u)/com.wambito.backup` runs it now.

### Keep a copy that is not on this Mac

The dumps are the whole database: your financial data **and** sign-in sessions and keys. They are
not encrypted, and they sit on the same disk as the database. Disk failure, theft, or Docker
Desktop's **Troubleshoot > Clean / Purge data** (which deletes every volume, whatever the compose
file says) would take both. So:

1. **Time Machine.** Keep **FileVault** on, and the Time Machine disk encrypted (Time Machine >
   Select Disk > Encrypt Backup). Time Machine keeps old versions of files for months, so a dump
   deleted at 14 days would live on there, holding accounts people deleted. Leave the backup folder
   out of it (`tmutil addexclusion ~/Backups/wambito`) and use the encrypted copy below as the copy
   off this Mac.
2. **An encrypted copy of every backup**, written by `backup.sh` itself, with
   [`age`](https://github.com/FiloSottile/age). It needs no password at backup time, only a public
   key; only the private key can open the copies. Once:

   ```sh
   brew install age
   age-keygen -o ~/wambito-backup.key
   # prints: Public key: age1....   <- this goes in .env
   ```

   Store the **whole key file** (`~/wambito-backup.key`) in your password manager, then delete it
   from disk. Without it the copies cannot be opened; anyone with it can open them. Then in `.env`:

   ```sh
   BACKUP_COPY_DIR=~/Library/Mobile Documents/com~apple~CloudDocs/Wambito   # iCloud Drive, or an external disk
   BACKUP_AGE_RECIPIENT=age1....
   ```

   After each good backup the dump is encrypted into `BACKUP_COPY_DIR/<name>.age` (same retention as
   the originals). If `age` is not installed the copy is skipped with a warning; a failed copy makes
   the run fail (the primary backup is kept either way). Only encrypted files ever reach iCloud.
   iCloud Drive keeps what is deleted from it in Recently Deleted for 30 days: to hold the 14-day
   promise there too, use an external disk, or empty Recently Deleted for that folder.

   **Restore from a copy:** put the key in a file, decrypt, then restore as usual.

   ```sh
   age -d -i wambito-backup.key -o wambito-2026-10-21.dump wambito-2026-10-21.dump.age
   ./restore.sh --drill wambito-2026-10-21.dump     # then ./restore.sh <dump> for real
   ```

### Backups in Cloudflare R2

On a server, the copy off the machine goes to a Cloudflare R2 bucket (its free tier is far more
than a few years of dumps). `backup.sh` uploads the **encrypted** copy above after each good backup,
never the plain dump, and the run fails if the upload does not show up in the bucket. The server
holds only the age **public** key: whoever gets into the server can write copies but cannot read
any of them.

Once, in the Cloudflare dashboard:

1. **R2 > Create bucket**, e.g. `wambito-backups`, no public access.
2. **The bucket > Settings > Object lifecycle rules > Add rule:** delete objects 14 days after they
   are uploaded, for the whole bucket. This is what keeps the 14-day promise in R2, even if the
   server is gone. `backup.sh` deletes nothing there.
3. **R2 > Manage API tokens > Create API token:** permission **Object Read & Write**, applied to
   **that bucket only**. It shows an access key id, a secret access key and the account's S3
   endpoint (`https://<account id>.r2.cloudflarestorage.com`). The secret is shown once.

On your Mac, make the age key (as in the section above) and keep the key file in your password
manager; only the `age1...` line goes to the server. On the server:

```sh
sudo apt install -y age rclone
```

and in `.env`:

```sh
BACKUP_COPY_DIR=~/Backups/wambito-encrypted
BACKUP_AGE_RECIPIENT=age1....
BACKUP_R2_BUCKET=wambito-backups
BACKUP_R2_ENDPOINT=https://<account id>.r2.cloudflarestorage.com
BACKUP_R2_ACCESS_KEY_ID=...
BACKUP_R2_SECRET_ACCESS_KEY=...
```

Then `./backup.sh` once by hand: it ends with `In R2: wambito-backups/wambito-YYYY-MM-DD.dump.age`.
The keys reach rclone through its environment, never its command line. `./test-r2.sh` checks that
logic against a fake rclone.

**Restore from R2.** It needs the age private key, which is not on the server. Either restore on
your Mac (with `age` and `rclone` installed and the same `BACKUP_R2_*` in its `.env`), or put the
key file on the server for the restore and delete it after:

```sh
./restore.sh --drill --from-r2 --identity=wambito-backup.key wambito-2026-10-21.dump.age
./restore.sh --from-r2 --identity=wambito-backup.key wambito-2026-10-21.dump.age    # for real
```

`restore.sh` also takes a local `.age` file with `--identity=KEY`. Either way it decrypts into a
private temporary folder that is removed when it ends.

**Restore drill** (do it after the first backup and every month or two): restores the dump into a
scratch database next to the real one, grants the app role on it, prints the row counts, drops it. Nothing live changes.

```sh
./restore.sh --drill ~/Backups/wambito/wambito-2026-10-21.dump
```

**Restore for real** (the data in the dump replaces the live data):

```sh
./restore.sh ~/Backups/wambito/wambito-2026-10-21.dump
```

It restores into a new database first (if that fails nothing has changed), asks you to type
`restore`, stops the API and the tunnel, renames the old database to `wambito_before_<time>` (kept:
drop it yourself when you are sure), puts the new one in its place, applies newer migrations,
grants the app role, and starts everything. `--yes` skips the question. A restore skips the dump's
own grants (`--no-acl`) and grants the app role afresh, so a dump restores whatever the role was
called when it was taken. Until the API connects as the new role, the restore grants the role
the API uses (from its `DATABASE_URL`) as well. If a step after the swap fails, it prints the
commands that put the previous database back.

**A restore brings back accounts deleted after the dump was taken**, with all their data, and they
can sign in again. Those people were told their data was gone, so delete each of them again right
after the restore. `restore.sh` warns about it and lists the accounts in the dump that the live
database does not have, each with the command that deletes it again. (When the live database is
lost or empty there is nothing to compare with: check who deleted their account since the dump.)

## Moving to a server

The same files run on any Linux server with Docker. A server with its own public address serves the
app itself: the **direct way**. Caddy answers on ports 80 and 443 with a Let's Encrypt certificate
for `PUBLIC_HOSTNAME`, redirects HTTP to HTTPS and sends HSTS; there is no tunnel, so no one between
the phone and the server reads the requests in clear. (A machine with no public address keeps the
tunnel.)

**Passkeys are bound to `PUBLIC_HOSTNAME`**: a passkey works only for the hostname it was made
for. Moving to a new hostname invalidates every passkey; email codes still work, and each person
registers a passkey again after signing in.

1. **`.env`.** On the server (Docker with Compose 2.24.4 or newer, see `docker compose version`;
   and Node 22 with pnpm for the web build), clone the repository and write
   `deploy/personal/.env` from `.env.example`, with:
   - `PUBLIC_HOSTNAME=app.wambito.com`;
   - the same `BETTER_AUTH_SECRET` as the old install, so sessions survive;
   - mail through Resend, since Bridge stays on the Mac: `RESEND_API_KEY`, with `SMTP_URL` empty and
     `SMTP_TLS_INSECURE=false`. The domain of `MAIL_FROM` must be verified in Resend (its SPF and
     DKIM records in the domain's DNS);
   - the same `ANDROID_CERT_SHA256` and `IOS_TEAM_ID`;
   - `COMPOSE_FILE=docker-compose.yml:docker-compose.direct.yml`, the direct way. No `TUNNEL_ID`.

   Keep a copy in your password manager.
2. **First start, on the server only.** DNS does not point at the server yet, so Caddy cannot get
   its certificate (it keeps trying, which is harmless). Check it on the local listener:

   ```sh
   ./up.sh       # build, migrate, start (waits for web's healthcheck on its plain-HTTP listener)
   ./smoke.sh    # checks http://127.0.0.1:8088 from the server
   ```
3. **Backups first.** Set up the copy in R2 ([above](#backups-in-cloudflare-r2)) and drill a full
   restore from it, before real data arrives.
4. **The data.** On the old machine, stop everything that writes and keep only the database up
   (`docker compose stop cloudflared web api mcp`), so nothing is saved after the dump. Then
   `./backup.sh`, copy the dump to the server, and there `./restore.sh --yes wambito-YYYY-MM-DD.dump`
   (the server's database is empty, so nothing is lost; the empty one is kept as
   `wambito_before_...`).
5. **Expose it.**
   - **Firewall, outside the machine:** in Hetzner, a Cloud Firewall attached to the server that lets
     in only 22/tcp from your own address (SSH with keys only: `PasswordAuthentication no`), plus
     80/tcp, 443/tcp and 443/udp (HTTP/3). Not `ufw`: Docker publishes ports around it.
   - **DNS:** only an `A` record for `PUBLIC_HOSTNAME` to the server, **DNS only** (grey cloud).
     Cloudflare's proxy (orange cloud) would end TLS at Cloudflare again. No `AAAA` record yet:
     the compose network has no IPv6, so every IPv6 visitor would reach the API as the network's
     gateway and share one sign-in limit. Phones on IPv6-only networks still reach an IPv4 address
     through their carrier's NAT64/464XLAT. Native IPv6 (`enable_ipv6` with a ULA subnet and a fixed
     IPv6 for `web` in the direct override, verified on the server with `curl -6`) is a later,
     separate change.
   - Once the `A` record resolves, `docker compose restart web` (in `deploy/personal`, where
     Compose reads `COMPOSE_FILE`). `./up.sh --skip-web` would not do it: it does not recreate
     `web`, and Caddy, started before DNS, is waiting out ACME's backoff. Watch
     `docker compose logs -f web` until it says the certificate was obtained.
   - `./smoke.sh` on the server, then from outside: `https://app.wambito.com/sign-in` answers with
     `Strict-Transport-Security`, and `http://` redirects to it. Check that the API sees real client
     addresses over IPv4 (`curl -4` from another network, then `docker compose logs web | tail`):
     `visitor_ip` must be the address you came from, not a Docker address (172.x). Fix that
     before the phones move: sign-in limits count by that address. (See
     [How the client address gets to the API](#how-the-client-address-gets-to-the-api).)
   - The rest of the outside checks: a request with a made-up `Cf-Connecting-Ip` or
     `X-Forwarded-For` is logged under your real address, not the made-up one; the certificate's
     issuer is Let's Encrypt (`openssl s_client -connect app.wambito.com:443 -servername app.wambito.com </dev/null 2>/dev/null | openssl x509 -noout -issuer`);
     and a port scan from outside shows only 22, 80 and 443.
   - Until the landing is deployed at `wambito.com`, `/` on the server redirects to an empty site.
     It is harmless: the app's paths are not affected.

Keep the old machine's last dump until the server has its own.

On the server, `./install-backup.sh` installs the daily backup as a systemd timer at 08:00 UTC (03:00
in Colombia; logs: `journalctl -u wambito-backup.service`), and `./uninstall-backup.sh` removes it.
Set up the copy in R2 (above) before real data lives there: a backup on the same disk is lost with
it. On the Mac, `./uninstall-backup.sh` removes the launchd agent once the server has taken over.

## Moving from the old names (part 2b)

Once, on the server that ran the install under the app's old name. The old install: a user of its
own with the checkout `~/lukitas`, the compose project `lukitas-personal`, the volumes
`lukitas-personal-db` and `lukitas-personal_web-caddy-data`, the images
`lukitas-{api,mcp,web}:personal`, the database and owner `lukitas` with the role `lukas_app`, dumps
`lukitas-*.dump` in `~/Backups/lukitas`, the bucket `lukitas-backups` and the units
`lukitas-backup.*` and `lukitas-deploy.*`. The new one is built next to it under a new user,
`wambito`, so the old install is never written to and stays the way back until the last step.

Below, `<old>` is the old user's name and `<host>` the server. A command marked **as `<old>`** runs
in an SSH session of the old user, **as `wambito`** in one of the new user. Do not start the
cutover (step 5) close to 08:00 UTC, when the old daily backup runs.

**1. Before merging PR B.**

- PR A is merged, deployed and working, and the repository is `slinqer/wambito`; the old checkout
  already points there (`git -C ~/lukitas remote -v`).
- As `<old>`: switch the old automatic deploy off, so merging PR B deploys nothing:

  ```sh
  sudo systemctl disable --now lukitas-deploy.timer
  systemctl is-enabled lukitas-deploy.timer    # disabled
  systemctl is-active lukitas-deploy.service   # inactive (if active, a deploy is running: wait)
  ```

**2. Merge PR B.** Nothing deploys: the timer is off. The old install keeps running PR A, and its
daily backup goes on.

**3. The user `wambito`.** As `<old>` (`adduser` asks for a password: `wambito` needs it for
`sudo`, which the install scripts use):

```sh
sudo adduser wambito
sudo usermod -aG docker,sudo wambito
sudo install -d -o wambito -g wambito -m 700 ~wambito/.ssh
sudo install -o wambito -g wambito -m 600 ~/.ssh/authorized_keys ~wambito/.ssh/authorized_keys
```

From a second terminal on your Mac, `ssh wambito@<host>` must log in, and `docker ps` must work
there, before you go on (keep the first session open until it does).

As `wambito`, GitHub read access of its own: the old user's deploy key stays with it. Make a key,
add `~/.ssh/id_ed25519.pub` to `slinqer/wambito` (**Settings > Deploy keys**, read-only), then
clone:

```sh
ssh-keygen -t ed25519 -N '' -C wambito-deploy -f ~/.ssh/id_ed25519
cat ~/.ssh/id_ed25519.pub        # paste it as the deploy key
git clone git@github.com:slinqer/wambito.git ~/wambito
node -v && pnpm -v               # Node 22 and pnpm, for up.sh's web build
```

If Node was installed in the old user's home (nvm, for example), install it for `wambito` the same
way. `jq`, `age` and `rclone` are system packages and are already there.

The settings: as `<old>`, copy the old `.env`:

```sh
sudo install -o wambito -g wambito -m 600 ~/lukitas/deploy/personal/.env ~wambito/wambito/deploy/personal/.env
```

Then as `wambito`, edit `~/wambito/deploy/personal/.env`:

- `DEPLOY_GITHUB_REPO=slinqer/wambito` (if the line is there);
- `BACKUP_R2_BUCKET=wambito-backups` and the new token's keys (step 4);
- `BACKUP_DIR` and `BACKUP_COPY_DIR`, if set: `~/Backups/wambito` and
  `~/Backups/wambito-encrypted`;
- `DB_VOLUME_NAME`, if set: delete the line (the default is `wambito-personal-db`). Never point it
  at `lukitas-personal-db`: the new stack would write the old volume, and there would be no way
  back;
- `NETWORK_PREFIX=172.28.78` (add it, or change the line). The old stack's network, which `stop`
  keeps, holds `172.28.77.0/24`, and two networks cannot share a subnet: with the same prefix
  `./up.sh` fails at the end ("Pool overlaps"). The old network is untouched, so the rollback's
  `start` still works. Caddy's fixed address and `TRUSTED_PROXIES` follow the prefix by
  themselves.

Everything else stays as it was: the passwords, `BETTER_AUTH_SECRET` (sessions survive),
`PUBLIC_HOSTNAME`, `COMPOSE_FILE`, mail, and `BACKUP_AGE_RECIPIENT`. **The age key is not
regenerated**: the same private key opens the old `lukitas-*.dump.age` copies and the new
`wambito-*.dump.age` ones. When you need it in a file, save it as `wambito-backup.key`; its entry
in the password manager can keep its old name.
`grep -n -i '^[A-Z0-9_]*=.*luk' ~/wambito/deploy/personal/.env | cut -d= -f1` should print no
variable left to change (it prints only the names, never the values).

**4. R2.** In the Cloudflare dashboard, as in [Backups in Cloudflare R2](#backups-in-cloudflare-r2):
a bucket `wambito-backups` with the same 14-day lifecycle rule, and an API token with **Object Read
& Write** on that bucket only. Its keys go in the new `.env` (`BACKUP_R2_ACCESS_KEY_ID`,
`BACKUP_R2_SECRET_ACCESS_KEY`; the endpoint is the account's, unchanged). The old bucket stays as an
archive; its own lifecycle rule empties it. The new stack's retention counts only `wambito-*`
names, so it never prunes a `lukitas-*` file, here or anywhere.

**5. The cutover** (the app is down from 5.1 to 5.5, a few minutes plus the web build).

1. As `<old>`, stop what writes, then take the final, verified dump (it goes to the old bucket
   too):

   ```sh
   cd ~/lukitas/deploy/personal
   docker compose -p lukitas-personal stop web api mcp
   ./backup.sh       # note the dump it writes: ~/Backups/lukitas/lukitas-YYYY-MM-DD.dump
   ```
2. Stop the rest. Never `down -v`; `stop` removes nothing, and `start` brings it all back:

   ```sh
   docker compose -p lukitas-personal stop
   ```
3. Copy Caddy's certificates into the new project's volume, so Let's Encrypt is not asked again.
   The volume is made first, with the labels compose gives its own volumes, so compose takes it
   as its own:

   ```sh
   docker volume create --label com.docker.compose.project=wambito-personal \
     --label com.docker.compose.volume=web-caddy-data wambito-personal_web-caddy-data
   docker run --rm -v lukitas-personal_web-caddy-data:/from -v wambito-personal_web-caddy-data:/to alpine cp -a /from/. /to/
   docker run --rm -v wambito-personal_web-caddy-data:/to alpine ls /to/caddy/certificates   # an acme folder
   ```
4. Still as `<old>`, give the final dump to `wambito` (the date from 5.1):

   ```sh
   sudo -u wambito mkdir -p -m 700 ~wambito/Backups/wambito
   sudo install -o wambito -g wambito -m 600 ~/Backups/lukitas/lukitas-YYYY-MM-DD.dump ~wambito/Backups/wambito/
   ```
5. As `wambito`, bring up the new stack (it builds the web app, makes the empty volume
   `wambito-personal-db`, migrates and creates the role `wambito_app`), close the app again at
   once, so no phone signs out against the empty database and nothing is saved into it, then
   restore the dump (type `restore` when asked):

   ```sh
   cd ~/wambito/deploy/personal
   ./up.sh
   docker compose stop web api mcp
   ./restore.sh ~/Backups/wambito/lukitas-YYYY-MM-DD.dump
   ```

   `./up.sh --skip-web` does not work here: the new checkout has no web build yet. `restore.sh`
   starts the database itself, and starts `api`, `mcp` and `web` again once the dump is live. It
   keeps the empty database it replaces as `wambito_before_<time>` (drop it later, step 8).
6. Check it: `./smoke.sh`; sign in at `https://app.wambito.com` (the phone should still be signed
   in, and your data is there); ask a connected assistant something through the MCP (for example,
   this month's spending).

**6. The new units**, as `wambito`, in `~/wambito/deploy/personal`, back to back:

```sh
./install-backup.sh
./install-auto-deploy.sh
./backup.sh
```

Either install removes **all** the old units (both timers and services), so between the two the
server has no automatic deploy; run the second right after the first. If an old backup or deploy is
running, the install waits for it to finish (up to 30 minutes) instead of stopping it. The backup by
hand must end with `In R2: wambito-backups/wambito-YYYY-MM-DD.dump.age`. Then
`systemctl list-timers 'wambito-*'` lists both timers, and `systemctl list-timers 'lukitas-*'`
none.

**7. Rollback**, if step 5 or 6 fails. Nothing is lost: the old volume was never written (only what
was saved in the new install after the restore stays behind, in `wambito-personal-db`). As
`wambito`, remove the new units and the new stack (`down` without `-v` keeps the volumes):

```sh
cd ~/wambito/deploy/personal
./uninstall-backup.sh
./install-auto-deploy.sh --remove
docker compose -p wambito-personal down
```

As `<old>`, start the old install again and reinstall its daily backup with its own script (the
new install deleted the old unit files):

```sh
cd ~/lukitas/deploy/personal
docker compose -p lukitas-personal start
./smoke.sh
./install-backup.sh
```

Leave the old automatic deploy off: `main` now holds PR B, and the old checkout's deploy (or
`./update.sh`, which pulls) would build it under the old user. Find what failed, then start again
from step 5.

**8. After a week without problems, and no later than 14 days after the cutover.** Since step 6
nothing prunes the old dumps in `~/Backups/lukitas`, the copy from 5.4 or the old volume, and they
still hold the accounts deleted since the cutover: past 14 days they break the promise that
deleted accounts are gone from every backup. As `<old>`, the old stack and its data:

```sh
cd ~/lukitas/deploy/personal
docker compose -p lukitas-personal down
docker volume rm lukitas-personal-db lukitas-personal_web-caddy-data
docker image rm lukitas-api:personal lukitas-mcp:personal lukitas-web:personal
```

The `lukitas` database and the `lukas_app` role lived in that volume, so they are gone with it.
Then log out, and as `wambito`:

```sh
sudo loginctl terminate-user <old>    # ends its sessions and processes, or deluser refuses
sudo deluser --remove-home <old>      # its checkout, .env, ~/Backups/lukitas
rm ~/Backups/wambito/lukitas-*.dump   # the dump from 5.4: retention never prunes it
cd ~/wambito/deploy/personal
docker compose exec postgres psql -U wambito -d postgres -c '\l'    # shows wambito_before_<time>
docker compose exec postgres psql -U wambito -d postgres -c 'drop database "wambito_before_<time>"'
```

The last line drops the empty database the restore kept in 5.5 (its name from the line before).
Remove the old user's deploy key from the repository's settings. Delete the bucket
`lukitas-backups` once its lifecycle rule has emptied it (14 days after the last old upload), and
the old tunnel, if one exists (`cloudflared tunnel delete lukitas-personal`).

## Files

| File | What |
|---|---|
| `docker-compose.yml` | The stack: postgres, migrate, api, mcp, web, cloudflared |
| `docker-compose.direct.yml` | The direct way (`COMPOSE_FILE` in `.env`): web on 80 and 443 with its certificates in a volume, the plain-HTTP listener on `127.0.0.1`, no cloudflared |
| `routes.caddy` | Every route, the same for both ways: static app, SPA fallback, cache rules, `/api` and `/mcp` proxies, blocked paths, landing redirects, access log |
| `Caddyfile` | The tunnel's Caddy: plain HTTP behind cloudflared, the client's address from `Cf-Connecting-Ip` |
| `Caddyfile.direct` | The direct way's Caddy: automatic HTTPS and HSTS for `PUBLIC_HOSTNAME`, the client's address from the TCP peer, no log of requests for other hosts |
| `cloudflared.yml` | Tunnel ingress: everything the tunnel receives goes to `web`; no hostname in it |
| `Dockerfile.web` | Caddy with the web build inside (the API image is `apps/api/Dockerfile.prod`) |
| `web-entrypoint.sh` `assetlinks.json.template` `apple-app-site-association.template` | At start, write `/.well-known/assetlinks.json` from `ANDROID_CERT_SHA256` and `/.well-known/apple-app-site-association` from `IOS_TEAM_ID` |
| `.env.example` | Every setting, documented |
| `up.sh` `update.sh` `smoke.sh` | Start, update, check |
| `backup.sh` `restore.sh` | Verified backups; restore and drill |
| `install-backup.sh` `uninstall-backup.sh` | The daily backup: launchd on the Mac, systemd on Linux |
| `com.wambito.backup.plist` | The 03:00 launchd agent (macOS) |
| `wambito-backup.service` `wambito-backup.timer` | The 08:00 UTC systemd timer (Linux) |
| `test-retention.sh` `test-r2.sh` | The 14-day retention, and the R2 upload against a fake rclone |
| `test-caddy.sh` | Both Caddy configs against real Caddy in Docker: client address, spoofed headers, HTTPS, routes |
| `test-compose-files.sh` | Which compose files, ports, Caddy config and services each way uses (`docker compose config`, no daemon) |
| `test-install-units.sh` | The install scripts against stubbed systemctl and launchctl: the wambito units, and the old ones removed (waiting for a running one) |
| `auto-deploy.sh` `install-auto-deploy.sh` `wambito-deploy.service` `wambito-deploy.timer` `test-auto-deploy.sh` | The server's automatic deploy of `main` once CI passed, and its test |

## How the client address gets to the API

Sign-in limits (5 codes per 10 minutes per address) count by client address. Caddy writes it as
the only `X-Forwarded-For` entry to the API and the MCP, replacing anything the client sent, and
logs it as `visitor_ip`. The API cannot see the TCP peer, so it relies on that: only Caddy can reach
it, and Caddy always overwrites the header. `TRUSTED_PROXIES=<NETWORK_PREFIX>.10` (Caddy's fixed address, `172.28.77.10` by default)
is the matching setting, but the guarantee is the network layout. Publishing the API's port or
adding another proxy would make the header spoofable. See `docs/deploy/api.md`.

Where Caddy takes the address from depends on the way:

- **Tunnel** (`Caddyfile`): Cloudflare puts the visitor's address in `CF-Connecting-IP` and
  overwrites any value the visitor sent; cloudflared hands it to Caddy, which trusts it, because
  nothing from outside reaches Caddy except through the tunnel. A request without that header (curl
  on this machine) is counted by the address Docker shows.
- **Direct** (`Caddyfile.direct`): anyone can reach Caddy, so it trusts no header. The address is the
  TCP peer's; sending `CF-Connecting-IP` or `X-Forwarded-For` changes nothing (`./test-caddy.sh
  direct` checks both). Docker keeps the real source address of IPv4 connections to published
  ports; when it does not, every visitor shows up as one Docker address. IPv6 is different: the
  compose network is IPv4-only, so connections to a published port over IPv6 go through
  docker-proxy and arrive as the network's gateway. Keeping the real IPv6 address needs IPv6 on the
  compose network itself, which this install does not enable yet. That is why the DNS has no `AAAA`
  record. Check the IPv4 address after the move
  ([Moving to a server](#moving-to-a-server), step 5).

## Troubleshooting

- **Error 1033 / 530 on the phone**: the tunnel is down. Is the Mac awake, Docker running, and
  `docker compose ps` showing `cloudflared` up? `docker compose logs cloudflared`.
- **No email arrives**: on a Mac, Bridge not running or not signed in, or a wrong password in
  `SMTP_URL`; on a server, a wrong `RESEND_API_KEY` or the domain not verified in Resend
  (`docker compose logs api | tail`, either way); the address is not in `SIGN_IN_ALLOWLIST` (the
  app says so).
- **The certificate does not come (direct way)**: `docker compose logs web`. The `A` record
  must point at this server, DNS only, and 80 and 443 must be open in the Cloud Firewall.
- **`up.sh` says port or subnet in use**: change `WEB_PORT` or `NETWORK_PREFIX` in `.env`.
- **API restarts at start**: `docker compose logs api` prints which variable is wrong.
- **Backup fails with "Docker is not running"**: start Docker Desktop; the next run is tomorrow, or
  run `./backup.sh` now.
