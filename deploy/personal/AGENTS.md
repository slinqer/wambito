# deploy/personal: the personal install (production VPS, or a Mac at home)

Docker compose stack: postgres, a one-shot `migrate`, api, mcp, web (Caddy serving the built web
app and proxying), optional cloudflared. Full runbook: `README.md` here; short version
`docs/deploy/personal.md`; settings `.env.example`.

## Two ways of serving (`COMPOSE_FILE` in `.env` picks)

- Tunnel (default, home Mac): `docker-compose.yml` + `Caddyfile` (plain HTTP, TLS at Cloudflare,
  client IP from `Cf-Connecting-Ip`) + `cloudflared.yml`.
- Direct (the VPS, `app.wambito.com`): `COMPOSE_FILE=docker-compose.yml:docker-compose.direct.yml`,
  `Caddyfile.direct` (Let's Encrypt, HSTS, client IP = TCP peer), no cloudflared.
- Both import `routes.caddy`: `/mcp` → mcp, `/api/*` → api, `/.well-known/…` (`assetlinks.json` from
  `ANDROID_CERT_SHA256`, `apple-app-site-association` from `IOS_TEAM_ID`, both written by
  `web-entrypoint.sh` at start, never a 404, tested by `test-web-entrypoint.sh`), assets, `/email/*`
  (CORS, for the emails' fonts), pages, the landing paths redirect (302) to `LANDING_URL`.

## Scripts

- `up.sh` (build, migrate, start; `--no-tunnel`, `--skip-web`), `update.sh`, `smoke.sh`.
- The server's version (`/health`, the app's Settings): the root `package.json` `"version"`, raised
  by hand (`chore: version X.Y.Z`), plus `+<commit>` and `-dirty` (`server_version` in `lib.sh`).
  Independent of the app's `mobile-v*` tags.
- `auto-deploy.sh` (timer every 5 min): deploys `main` once CI's `check` and `e2e` passed, backup
  first, rolls back on a failed smoke test. Installed by `install-auto-deploy.sh`.
- `backup.sh` / `restore.sh` / `install-backup.sh` / `uninstall-backup.sh`: age-encrypted dumps to
  Cloudflare R2, 14-day retention. `lib.sh`: shared helpers.
- Units `wambito-*.service|timer` (Linux, in `UNIT_DIR`, default `/etc/systemd/system`),
  `com.wambito.backup.plist` (macOS). Both install scripts first disable and delete the units from
  before the rename, waiting (up to 30 min) for a running old backup or deploy instead of stopping
  it (`remove_old_units` in `lib.sh`, the only script that names them, split as `"luk""itas"`).

## Test (CI runs all seven)

- `./test-retention.sh`, `./test-r2.sh`, `./test-auto-deploy.sh`, `./test-install-units.sh`,
  `./test-caddy.sh`, `./test-compose-files.sh`, `./test-version.sh` (from this folder).

## Traps

- Caddy `vars` ordering: set `client_ip` with plain `vars` lines (with matchers that exclude each
  other) before `import routes.caddy`; a `route { }` block would run after the handle blocks, so
  the routes would see no `client_ip`.
- `COMPOSE_FILE` lives in `.env`: run compose from this folder so it applies. `./up.sh --skip-web`
  does not recreate containers after a compose-file change.
- The API trusts exactly one X-Forwarded-For hop, set by Caddy (`docs/deploy/api.md`).
- Migrations run in `migrate` as the owner; the api runs as the runtime role (RLS).
- Nothing here names the old app, except the README's "Moving from the old names (part 2b)" (the
  one-time cutover runbook, allowlisted as `history`); scripts and tests split the old name
  (`"luk""itas"`) so the old-name guard does not match. Secrets: see root `AGENTS.md`.
- Merging to `main` deploys production by itself.
