# Deploying a personal install

Wambito runs as one Docker stack on one machine, at one hostname: served directly with its own
certificate on a server (how `app.wambito.com` runs), or through a Cloudflare named tunnel from a
machine at home. It has an optional email allowlist and a daily verified backup. The step-by-step
guide for running your own is [`docs/self-hosting.md`](../self-hosting.md).

Everything is in [`deploy/personal/`](../../deploy/personal/README.md): the compose stack (Postgres,
a one-shot migration step, the API, Caddy, cloudflared), the scripts (`up.sh`, `update.sh`,
`backup.sh`, `restore.sh`, `smoke.sh`) and the README with the setup, daily use, backup and restore,
the move to a server, and the one-time move of the server from the old names ("Moving from the old
names").

What the API gained for it (also useful for any deployment):

- **`SIGN_IN_ALLOWLIST`**: comma-separated emails (case-insensitive). When set, a sign-in code is
  only sent to those addresses; anyone else gets `403 sign_in_not_allowed` and no email goes out.
  Unset or empty means no restriction: anyone may create an account (production runs this way). Existing users' passkeys are not affected.
- **`SMTP_TLS_INSECURE=true`**: accept the SMTP server's self-signed certificate (Proton Bridge),
  still over STARTTLS. Refused unless `SMTP_URL` is on this machine (`localhost`, `127.0.0.1`,
  `[::1]`, `host.docker.internal`).
- **`DATABASE_ADMIN_URL` is optional outside development**, so a running production API never holds
  the owner credential. Migrations are a separate step: `apps/api/Dockerfile.prod` also builds
  `dist/bootstrap.js`, which creates the `wambito_app` runtime role (password from `APP_DB_PASSWORD`; the role
  exists only in the development `docker/postgres/init.sql` otherwise) and applies the migrations.
  It is idempotent. Locally: `DATABASE_ADMIN_URL=... APP_DB_PASSWORD=... pnpm --filter @wambito/db bootstrap`.
- **A production image**: `apps/api/Dockerfile.prod` (multi-stage, `node:22-alpine`, one esbuild
  bundle per entry point, runs with `node`, non-root, health check on `/api/health`).

Client addresses and rate limits behind this setup are described in [`api.md`](api.md).
