# Running Wambito on your own server

Wambito is free to use at [app.wambito.com](https://app.wambito.com). You can also run your own
copy, for yourself, your family or a small group: the same Docker stack that serves
`app.wambito.com` runs on any Linux server. This page is the short way. The full runbook, with every
option, the reasons behind them and troubleshooting, is
[`deploy/personal/README.md`](../deploy/personal/README.md).

What you get on your own hostname: the web app, the API the phone app talks to, the MCP server for
assistants at `/mcp`, and a daily database backup. The public landing page is not part of it: `/`
redirects to `LANDING_URL` (`https://wambito.com` by default).

> **Encryption.** End-to-end encryption is not switched on yet (see
> [`encryption.md`](encryption.md)). Until it is, your server can read the movements stored on it.
> On your own server that means you, and whoever can reach the machine or its backups.

## Let an AI assistant install it

If you use a coding agent that can run commands on your server (Claude Code, Codex or similar,
over SSH), you can hand it this guide. Paste this prompt and answer its questions:

```text
Install Wambito on my server by following
https://github.com/slinqer/wambito/blob/main/docs/self-hosting.md (and, when it says so,
deploy/personal/README.md in the same repository).

Before you change anything, ask me in one message for:
- how to reach the server (SSH user and address) and whether you may use sudo;
- the hostname it will answer at (for example wambito.example.com);
- how sign-in emails go out (a Resend API key, or an SMTP URL) and the sender address;
- whether sign-in should be open to anyone or limited to a list of emails;
- whether it should update itself when the project releases changes.

Then:
1. Check the requirements in the guide, and tell me what is missing before installing anything.
2. Generate every secret on the server with the commands the guide gives. Never print a secret
   in the chat or in a log; tell me which file holds them so I can keep a copy in my password
   manager.
3. Stop and wait for me before any step that needs me: DNS records, the firewall in my provider's
   panel, paying for or signing up to anything.
4. Start it, run ./smoke.sh, and check that https://<hostname>/sign-in loads with a valid
   certificate.
5. Set up the daily backup, and run one backup by hand.
6. Finish with a short list: what you did, where things are, what I still have to do, and how
   to update it.
```

The agent reads the repository's `AGENTS.md` files too, which tell it what not to touch (for
example, never to delete the database volume).

## What you need

- **A Linux server with a public IPv4 address.** A small VPS is enough: `app.wambito.com` runs on 2
  ARM64 cores and 4 GB of RAM. x86-64 works too.
- **Docker** with Compose 2.24.4 or newer (`docker compose version`), **git**, and **Node 22 with
  pnpm** (`corepack enable`): the web app is built on the server.
- **A hostname you control**, such as `wambito.example.com`, and access to its DNS.
- **A way to send email**, for the sign-in codes: a [Resend](https://resend.com) API key with the
  sender's domain verified, or any SMTP server that speaks TLS.
- **A firewall in front of the server** that lets in only 80/tcp, 443/tcp, 443/udp, and SSH from your
  own address. Use your provider's firewall, not `ufw`: Docker publishes ports around it.

No server with a public address (a computer at home)? The same stack works through a Cloudflare
tunnel: see "First-time setup" in the [runbook](../deploy/personal/README.md#first-time-setup).

## 1. Get the code

```bash
git clone https://github.com/slinqer/wambito.git
cd wambito
pnpm install --frozen-lockfile
cd deploy/personal
cp .env.example .env
```

The install is built from this checkout and follows the `main` branch. `up.sh` and `update.sh`
refuse to run on another branch, or with changes to tracked files, so a stray edit never reaches
your data.

## 2. Fill in `.env`

Every variable is explained in the file itself. The ones a server needs:

| Variable | Value |
|---|---|
| `POSTGRES_PASSWORD` | `openssl rand -hex 24` |
| `APP_DB_PASSWORD` | `openssl rand -hex 24` |
| `BETTER_AUTH_SECRET` | `openssl rand -hex 32` |
| `PUBLIC_HOSTNAME` | your hostname, for example `wambito.example.com` |
| `COMPOSE_FILE` | `docker-compose.yml:docker-compose.direct.yml` (served directly, with its own certificate) |
| `TUNNEL_ID` | leave empty |
| `RESEND_API_KEY` | your Resend key, with `SMTP_URL` empty; or leave it unset and put your SMTP server in `SMTP_URL` |
| `SMTP_TLS_INSECURE` | `false` |
| `MAIL_FROM` | `Wambito <hola@example.com>`, an address of your verified domain |
| `SIGN_IN_ALLOWLIST` | optional: the emails allowed to sign in, comma-separated; unset lets anyone create an account |
| `MCP_WK_PUBLIC_KEY`, `MCP_WK_PRIVATE_KEY` | the two lines `./gen-mcp-keys.sh` prints (lets assistants work on encrypted accounts) |

Keep a copy of `.env` in your password manager: without `BETTER_AUTH_SECRET`, the database passwords
and the MCP's private key, a backup cannot be brought back as it was. Never commit it (git ignores
it).

**Passkeys are tied to `PUBLIC_HOSTNAME`.** Pick the hostname for good: a passkey made for one name
does not work on another (email codes always do).

## 3. Start it

```bash
./up.sh       # builds the web app and the images, applies the migrations, starts everything
./smoke.sh    # checks the install on http://127.0.0.1:8088, from the server
```

Then point the hostname at the server: an `A` record to its IPv4 address (if your DNS is on
Cloudflare, **DNS only**, the grey cloud). Leave out an `AAAA` record for now (the runbook says
why). Once the name resolves:

```bash
docker compose restart web          # Caddy asks Let's Encrypt for the certificate again
docker compose logs -f web          # wait until it says the certificate was obtained
```

Open `https://<your hostname>/sign-in`, ask for a code and sign in.

## 4. Connect the apps and assistants

- **Phone app:** in Wambito's settings, **Servidor**, write `https://<your hostname>`. Another server
  is another account: the app signs out of the one it had.
- **Assistants:** in Claude or ChatGPT, add `https://<your hostname>/mcp` as a connector (a custom
  MCP server) and sign in. You see and disconnect them in the app's settings.
- **Passkeys in the Android app** need `ANDROID_CERT_SHA256` in `.env`, the fingerprint of the
  certificate the app you install is signed with. Without it, the app signs in with email codes and
  passkeys work on the web. See the runbook's "The Android app".

## 5. Backups

```bash
./backup.sh            # one backup now, checked by restoring it into a throwaway database
./install-backup.sh    # every day at 08:00 UTC, as a systemd timer (needs sudo)
```

A backup on the same disk is lost with the disk. Set up the encrypted copy off the server (`age` and
a Cloudflare R2 bucket, or any folder you sync elsewhere) as the runbook's "Backup and restore"
explains, and try a restore once before you rely on it.

## 6. Updates

```bash
./update.sh            # backs up, pulls main, rebuilds, migrates, restarts
```

Or let the server update itself: `./install-auto-deploy.sh` (needs `sudo` and `jq`) checks every 5
minutes and deploys a new commit of `main` once the project's CI has passed, backing up first and
going back if the check after it fails. It is how `app.wambito.com` updates. What changed in each
server version is in [`CHANGELOG.md`](../CHANGELOG.md).

## Day to day

From `deploy/personal`:

```bash
docker compose ps                  # what is running
docker compose logs -f api         # the API's log (also: web, mcp, postgres)
docker compose stop                # stop it, keeping everything
./up.sh --skip-web                 # start it again
```

**Never run `docker volume rm wambito-personal-db`**: that is the database. `docker compose down`
is safe; the scripts refuse `down -v`.

Something wrong? See the runbook's [Troubleshooting](../deploy/personal/README.md#troubleshooting),
or open an issue.
