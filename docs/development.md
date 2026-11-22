# Developing Wambito

How to run the stack, the web app and the tests on your machine. The map of the repo, its guards and what CI runs are in the root [`AGENTS.md`](../AGENTS.md); each app has its own `AGENTS.md`. The phone app: [`docs/mobile/`](mobile/).

## Running it locally

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

Run it from the repository root. It stops only this dev stack (`wambito-api`, `wambito-postgres`, `wambito-mailpit`, the compose project `wambito`) and keeps its data; `docker compose up -d` brings it back. The personal install (see [deploy/personal](../deploy/personal/README.md)) is a separate stack and keeps running. Never use `docker compose down -v` here: `-v` deletes the dev database volume.

## Web app

With the stack up (`docker compose up -d`), start the web app:

```bash
pnpm --filter @wambito/web dev   # http://localhost:5173
```

The landing is at `/`, the app at `/sign-in` and `/app`, and a demo without an account at `/demo`. Vite proxies `/api` to the API on port 3000, so the browser talks to one origin (`API_URL` and `WEB_URL` in `.env` point at it). Sign in with any email and read the code in Mailpit at http://localhost:8025. The components have stories: `pnpm --filter @wambito/web storybook` (http://localhost:6006).

## Tests

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
