<p align="center"><img src="docs/brand/wambi-banner.png" alt="Wambi, the gold coin mascot, waving next to the Wambito wordmark: Tus lukas, por fin claras." width="100%"></p>

# Wambito

**Your budget, and you'll actually enjoy looking after it.** Log an expense in seconds and see where your money goes: a monthly budget on the web, an Android and iOS app with widgets (soon), and an MCP server so your AI assistant (Claude, ChatGPT…) can help you with your money (soon).

Wambito is **free forever and open source** ([AGPL-3.0](LICENSE)): anyone can read the code and check what it does with your data.

## Why "Wambito"?

**Wambito** comes from *guambito*, how people in Ibagué and Tolima call a kid. The W spelling is closer to the Quechua *wambra*.

**Wambi is the project's mascot**, a gold coin that keeps you company in the app. It reacts to how your month is going, with short messages when a category is close to or over its limit and when you close the month within budget. The goal is for looking after your money to feel good, not like homework.

The app still talks about money the Colombian way: in Colombia we call money **lukas** (spelled *lucas* in Chile, Argentina and Peru), and one *luka* is a thousand pesos. You will see "Tus lukas, por fin claras" on the Spanish landing page.

## What it does

- **What's left to spend this month**, big and always visible, in the app and on the widget.
- **Monthly budget per category**, with bars that fill up with what you've spent and change color as you approach the limit.
- **Daily transactions**, paid or pending, with automatic recurring ones (rent, subscriptions, salary…).
- **Analysis** by category and month-over-month trends.
- **Import your history from other apps:** Budge today (CSV); Buddy and others soon.
- **Connect your assistant:** an MCP server so you can ask your AI to log expenses, prepare reports, or adjust your budget.
- **No passwords:** sign in with a magic link or a code sent to your email, or with a passkey.

## Coming: end-to-end encryption

🚧 **In progress, not active yet.** Today your data travels encrypted (HTTPS) and the backups are encrypted, but the server can read your movements. We are changing that before the public release in Google Play and F-Droid:

How it will work:

| | | | | |
|:-:|:-:|:-:|:-:|:-:|
| <img src="docs/brand/e2e/wambi-e2e-step1.webp" alt="Wambi locks receipts and coins in a chest on the phone; the key hangs from the phone." width="160"> | <img src="docs/brand/e2e/wambi-e2e-step2.webp" alt="The locked chest travels between clouds; a snooper with a magnifying glass sees only scribbles." width="160"> | <img src="docs/brand/e2e/wambi-e2e-step3.webp" alt="A server shelf full of locked chests, with no key." width="160"> | <img src="docs/brand/e2e/wambi-e2e-step4.webp" alt="A fingerprint touch opens the chest on a laptop; a recovery card is the other way in." width="160"> | <img src="docs/brand/e2e/wambi-e2e-step5.webp" alt="After the person taps allow, Wambi lends a temporary key to an assistant robot; when it is disconnected, Wambi changes the lock." width="160"> |
| **Locked on your device.** Each phone or browser will encrypt your movements with a key only you hold. | **Unreadable on the way.** Anyone in the middle will see scribbles. | **The server will keep chests, not keys.** It will store and sync encrypted records; its database and backups will reveal no name, amount or note. | **Your key will open it anywhere.** A passkey touch, your recovery key, or approval from another of your devices. | **Assistants only if you say so.** Connecting Claude or ChatGPT will lend them a key while connected; disconnecting will change the lock. |

What the server will still see: your email, how many records you have and when they change. Losing every passkey **and** the recovery key means losing the data: nobody else can open it, not even us. The design is in [`docs/superpowers/specs/2026-11-08-end-to-end-encryption-design.md`](docs/superpowers/specs/2026-11-08-end-to-end-encryption-design.md).

## Status

🚧 In development. Stage 1 (backend: API, auth, Budge import) is built; web, mobile (Android and iOS), MCP and celebrations (streaks, achievements) come next. The design is in [`docs/superpowers/specs/2026-10-20-lukas-design.md`](docs/superpowers/specs/2026-10-20-lukas-design.md).

## Architecture

A monorepo with:

- `apps/api`: TypeScript backend (Hono), Postgres and Better Auth
- `apps/web`: React + Vite
- `apps/mcp`: remote MCP server
- `apps/mobile`: Flutter (Android; iOS later), with a native Kotlin + Glance widget
- `packages/core`, `packages/db`, `packages/importers`: business rules, schema and migrations, importers

## Local development

Requirements: Node 22, pnpm 12 and Docker.

```bash
pnpm install
cp .env.example .env
docker compose up -d          # Postgres, Mailpit and the API on http://localhost:3000/api
pnpm --filter @wambito/api seed # creates dev@wambito.test with sample data
```

Sign in without a password: request a code, then open Mailpit at http://localhost:8025 to read it.

```bash
curl -X POST localhost:3000/api/auth/email-otp/send-verification-otp \
  -H 'content-type: application/json' -d '{"email":"dev@wambito.test","type":"sign-in"}'
curl -i -X POST localhost:3000/api/auth/sign-in/email-otp \
  -H 'content-type: application/json' -d '{"email":"dev@wambito.test","otp":"<code>"}'
# use the set-auth-token response header as a bearer token:
curl localhost:3000/api/v1/summary -H 'authorization: Bearer <token>'
```

The API is documented at http://localhost:3000/api/openapi.json. Its routes live under the path of `API_URL` (`/api` in `.env.example`, so the web app can proxy `/api` from its own origin).

To run the API outside Docker, start only the services with `docker compose up -d postgres mailpit` and run `pnpm --filter @wambito/api dev`. On the host, Postgres listens on port 5433 and Mailpit SMTP on 1026, so they do not clash with a local Postgres or mail bridge.

**When you stop developing, stop the dev containers** to save the machine's resources:

```bash
docker compose stop
```

Run it from the repository root. It stops only this dev stack (`wambito-api`, `wambito-postgres`, `wambito-mailpit`, the compose project `wambito`) and keeps its data; `docker compose up -d` brings it back. The personal install (see [deploy/personal](deploy/personal/README.md)) is a separate stack and keeps running. The stack started under the old name used another volume, so `wambito` starts empty: find the old one with `docker volume ls` and remove it with `docker volume rm <name>` once you do not need it. If containers from the old project (`lukas-*`) are still running, they keep ports 5433, 3000 and 8025 and `docker compose up -d` fails: run `docker compose -p lukas stop` first. A root `.env` copied from the previous `.env.example` has `lukas_app` URLs that no longer work: copy `.env.example` to `.env` again. Never use `docker compose down -v` here: `-v` deletes the dev database volume.

### Web app

With the stack up (`docker compose up -d`), start the web app:

```bash
pnpm --filter @wambito/web dev   # http://localhost:5173
```

The landing is at `/`, the app at `/sign-in` and `/app`, and a demo without an account at `/demo`. Vite proxies `/api` to the API on port 3000, so the browser talks to one origin (`API_URL` and `WEB_URL` in `.env` point at it). Sign in with any email and read the code in Mailpit at http://localhost:8025. The components have stories: `pnpm --filter @wambito/web storybook` (http://localhost:6006).

### Tests

```bash
pnpm lint && pnpm typecheck && pnpm test
```

`pnpm test` runs the unit tests, the API's integration tests and every Storybook story (rendered in Chromium, with its interactions and an accessibility check). The first time, install the browser: `pnpm --filter @wambito/web exec playwright install chromium`.

Integration tests start a throwaway Postgres in Docker (testcontainers). Without Docker, use the Postgres binaries on your PATH instead:

```bash
WAMBITO_TEST_DB=local pnpm test
```

End-to-end tests drive the web app in Chromium at phone and desktop sizes, against the dev stack. They read the sample data's months (September and October 2026) against a fixed date, so start the API with its clock pinned to it, then run them (Playwright starts `pnpm dev` unless it is already running):

```bash
E2E_NOW=2026-10-21T15:00:00Z docker compose up -d --build
pnpm --filter @wambito/web e2e
```

A spec that reads a month pins its page the same way, with `pinClock(page)` from `apps/web/e2e/helpers.ts`. The landing is tested as it ships, built first: `pnpm --filter @wambito/web e2e:landing` (the full site), `e2e:landing-only` and `e2e:landing-only-app` (the landing-only release, without and with an app). CI runs all of these on every pull request.

## Deploying

- **The landing page** ships on its own as static files (Cloudflare), published by CI after every merge into `main`: [`docs/deploy/landing.md`](docs/deploy/landing.md), with its config in [`deploy/landing/`](deploy/landing/).
- **A personal install** runs the whole app for one person on one machine, behind a Cloudflare tunnel, with an email allowlist and daily backups: [`docs/deploy/personal.md`](docs/deploy/personal.md), with the stack and scripts in [`deploy/personal/`](deploy/personal/README.md).
- **The API** on its own: [`docs/deploy/api.md`](docs/deploy/api.md).

## Self-hosting

For now Wambito is offered as a hosted service, and there are no docs for running your own instance beyond the personal install above. If you're interested, open an issue and we'll take it into account.

## License

[AGPL-3.0](LICENSE). If you offer a modified Wambito as a service, you must publish your changes.
