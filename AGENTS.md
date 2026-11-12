# Wambito: agent map

Wambito is a free, open-source personal finance app; Wambi is its mascot (the same drawing as the
old Lukas). Monorepo: pnpm 12 workspaces + turbo, Node 22 (`.nvmrc`), TypeScript, Flutter for the
phone. Read the `AGENTS.md` of the area you work in; read code only to confirm.

## Map

| Folder | What | Map |
|---|---|---|
| `apps/api` | Hono + Better Auth HTTP API, OpenAPI | `apps/api/AGENTS.md` |
| `apps/web` | React Router app: landing, signed-in app, demo, OAuth consent | `apps/web/AGENTS.md` |
| `apps/mcp` | MCP server for AI assistants, calls the API | `apps/mcp/AGENTS.md` |
| `apps/mobile` | Flutter Android app + Kotlin side | `apps/mobile/AGENTS.md` |
| `packages/ai-assistant-tools` | MCP tools, prompts, instructions | `packages/ai-assistant-tools/AGENTS.md` |
| `packages/core` | shared domain: money, dates, budgets, quick-capture cases | `packages/core/AGENTS.md` |
| `packages/crypto` | end-to-end encryption: data key, record sealing, dedupe tags | `packages/crypto/AGENTS.md` |
| `packages/db` | Drizzle schema, migrations, RLS | `packages/db/AGENTS.md` |
| `packages/importers` | CSV importers | `packages/importers/AGENTS.md` |
| `deploy/personal` | the VPS / home install: compose, Caddy, backups, auto-deploy | `deploy/personal/AGENTS.md` |
| `deploy/landing` | Cloudflare Worker for the landing | `deploy/landing/AGENTS.md` |
| `docs` | design system, deploy, mobile, admin panel guide (`docs/admin.md`), history | `docs/AGENTS.md` |
| `scripts` | repo guards (`scripts/check-old-name.sh`) | here |
| `docker-compose.yml` | root dev stack: postgres, mailpit, api | here |

## Dev stack and commands (repo root)

- Install: `pnpm install --frozen-lockfile`.
- Dev stack: `cp .env.example .env` once, then `docker compose up -d` (API on :3000, Mailpit).
  Services only: `docker compose up -d postgres mailpit`. Stop with `docker compose stop`,
  never `down -v` (it deletes the dev database).
- Lint: `pnpm lint` (= `biome check .`); fix with `pnpm format` (`biome check --write .`).
- Typecheck: `pnpm typecheck` (turbo). Tests: `pnpm test` (Vitest; projects per package/app).
- Docker must run for API/DB/MCP tests (testcontainers); `WAMBITO_TEST_DB=local` uses a local
  `initdb`/`pg_ctl` instead.
- Web e2e needs the dev stack with the pinned clock (see `apps/web/AGENTS.md`).
- Flutter: `export PATH="$HOME/development/flutter/bin:$PATH"`.
- Gradle needs `JAVA_HOME` = JDK 17 (`docs/mobile/setup.md`).

## What CI runs (`.github/workflows/ci.yml`)

- `check`: install, Playwright chromium (`scripts/ci-install-chromium.sh`, browser only when
  apt cannot reach Ubuntu; tested by `scripts/test-ci-install-chromium.sh`), the two guards and the
  old-name guard's test, `pnpm lint`,
  generated-file checks (web `tokens`, web and mcp `api:types` + `git diff --exit-code`),
  `pnpm typecheck`, `pnpm test`, then `deploy/personal/test-*.sh` (retention, r2, auto-deploy,
  caddy, compose-files, version).
- `e2e`: root stack with `E2E_NOW=2026-10-21T15:00:00Z`, then web `e2e`, `e2e:landing`,
  `e2e:landing-only`, `e2e:landing-only-app`.
- `deploy-landing`: push to `main` after `check` + `e2e`; `wrangler deploy` from `deploy/landing`.
- `mobile` / `mobile-build` (only when mobile paths change): pub get, analyze, tests without
  goldens, tokens and `apps/mobile/lib/api/gen` staleness, release self-tests, `build-native-deps.sh`
  `--abi` and `build-sherpa-onnx.sh` argument tests, F-Droid recipe and lock checks (`check-fdroid-recipe.sh`,
  `check-fdroid-lock.sh`, tested by `test-fdroid-checks.sh`), no-Google check, debug build, Gradle
  lock check, Gradle unit tests, native-switch test (`test-native-switch.sh`), release build.
- `ios` (same filter; macOS runner): pub get, the signing guard and its test
  (`apps/mobile/scripts/check-ios-signing.sh`), `swift test` on `ios/WambitoNative`,
  `flutter build ios --release --no-codesign`.
- `iOS release` (`ios-release.yml`, on a `mobile-v*` tag, environment `app-store`): archive, export
  and upload to App Store Connect for TestFlight (`docs/mobile/ios.md`).

## Guards (all in CI `check`, before lint)

- Old name: `scripts/check-old-name.sh` fails on the old app or mascot name outside
  `.github/name-allowlist.txt` (`<pathspec>  # <reason>[, <reason>]`; reasons `money`, `history`,
  `docs-rule`, `key-alias`). It also fails on a line with no reason or another one (tested by
  `scripts/test-check-old-name.sh`). A new legit hit: add the file there with its reason, never a
  folder glob.
- Channel guard (`ci.yml` `check`): `scripts/check-channels.sh` fails when a `wambito/*` channel or a
  method Dart calls is missing from `apps/mobile` Kotlin or Swift, unless `.github/channel-allowlist.txt`
  has `<channel>  # <reason>` (`ios-impossible`, `ios-part-two`, `android-only`); tested by
  `scripts/test-check-channels.sh`. Fix the missing native side, never widen the allowlist.
- Personal-name guard (`ci.yml`): a `git grep` for the founder's name outside `docs/superpowers`.
  Never write personal names, emails or paths into the repo.

## Cross-cutting rules

- Names: app = Wambito, mascot = Wambi. Packages are `@wambito/*`, headers `x-wambito-*`,
  stored keys `wambito.*`, deep links `wambito://`, channels `wambito/*`.
- Money slang is never renamed: «lukas/luka/palo» in the capture parser, copy and tests,
  `lukasHint`, the money words of the landing. A global search-and-replace of the old name breaks
  them; check each hit.
- The signing key's alias stays `lukitas` (reason `key-alias`): it is inside the key, and
  re-keying breaks every update (`docs/mobile/release.md`).
- Persistent names on phones (prefs files, WorkManager unique names, widget receivers, snapshot
  key) need a migration to change.
- Never read `deploy/personal/.env`, the root `.env`, `~/.cloudflared/*.json`, the signing keystore
  or any other secret. Use the `.env.example` files.
- Money is an integer number of cents, never a float. Fixtures are invented, never real data.
- Generated files are regenerated, never hand-edited:
  - `apps/web/app/styles/tokens.css`: `pnpm --filter @wambito/web tokens`;
  - `apps/mobile/lib/theme/tokens.g.dart`: `dart run scripts/gen-tokens.dart` (in `apps/mobile`);
    both from `docs/design/system/project/tokens.json`;
  - `apps/web/app/api/schema.d.ts`: `pnpm --filter @wambito/web api:types --file`;
  - `apps/mcp/src/api/schema.d.ts`: `pnpm --filter @wambito/mcp api:types`;
  - `apps/mobile/lib/api/gen`: `apps/mobile/scripts/gen-api.sh`;
  - `apps/web/public/email/*` (email images, fonts): `node docs/brand/tools/gen-email-images.cjs`;
  - Flutter l10n (`app_localizations*.dart`, git-ignored): `flutter pub get`.
- Write the failing test first. Everything in English.
- A change to the API or the MCP (routes, fields, errors, auth, scopes, tools, prompts, limits) adds
  a line under "Unreleased" in the root `CHANGELOG.md`, the server's changelog; a server release
  raises the root `package.json` version and moves those lines under it (`chore: version X.Y.Z`).
- Commits: Conventional Commits, repo style `feat(area): …`, `fix(android): …`, `docs: …`, a
  lowercase sentence. Never a `Co-Authored-By` line. Stage by path, never `git add -A`.
- Whoever changes an area's structure, commands or conventions updates its `AGENTS.md`.

## Production

- The VPS serves `app.wambito.com` directly (no tunnel), `direct` mode via `COMPOSE_FILE` in its
  `.env`. It deploys `main` by itself once CI passes (`deploy/personal/auto-deploy.sh`).
  Merging to `main` is deploying.
- The landing `wambito.com` is the Cloudflare Worker (`deploy/landing`), deployed by CI.

## History: `docs/superpowers/**` (read only when needed, never edit)

- Part 1, URLs and direct mode: `docs/superpowers/specs/2026-11-02-wambito-urls-design.md`; part 2a
  rename: `docs/superpowers/specs/2026-11-02-wambito-part-2a-rename-design.md`; part 2b, the
  infrastructure names and the end of the transition:
  `docs/superpowers/specs/2026-11-03-wambito-part-2b-infrastructure-design.md`.
- Others (product, web, mobile, MCP, i18n): `ls docs/superpowers/specs`; plans in `plans/`.
