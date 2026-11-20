# Deploying the landing page (Cloudflare)

Wambito can ship as the landing page alone: the prerendered pages (`/` in Spanish, `/en` in
English, and the roadmap at `/roadmap` and `/en/roadmap`), a 404 page and the static files. The
app, when there is one, runs on its own origin, and the build says so with `VITE_APP_URL`:

- **Without `VITE_APP_URL`** (no app yet): every call to action reads "Coming soon · Follow on
  GitHub" and links to the repository; nothing leads to the app.
- **With `VITE_APP_URL`** (the release): the calls to action read "Empieza ahora" / "Get started"
  and "Entrar" / "Sign in" and open `${VITE_APP_URL}/sign-in?lang=<es|en>`. The "En la web" card
  links to the app too, and the closing text invites the visitor to create an account with their
  email ("Crea tu cuenta con tu correo en menos de un minuto"): sign-up is open to everyone.

## Build

```sh
VITE_SITE_URL=https://wambito.com pnpm --filter @wambito/web build:landing
```

The release, with the calls to action opening the live app:

```sh
VITE_SITE_URL=https://wambito.com VITE_APP_URL=https://app.wambito.com pnpm --filter @wambito/web build:landing
```

- `VITE_SITE_URL` is the site's public origin (no path). Set it in the environment or in `apps/web/.env`: both are read the same way, for the generated files and for the app code. It is required: the script stops with a
  message when it is missing or is not an `http(s)` origin. The same origin goes into the canonical
  and `hreflang` links, the Open Graph tags, `sitemap.xml` and `robots.txt`, which are generated at
  build time.
- `VITE_APP_URL` is optional: the live app's origin (no path), read like `VITE_SITE_URL`. The
  script stops with a message when it is set but is not an `http(s)` origin. It only has an effect
  in this landing-only build; a normal build serves the app from its own origin.
- The script builds with `VITE_LANDING_ONLY=true`. The output is `apps/web/build/client`:
  `index.html`, `en/index.html`, `roadmap/index.html`, `en/roadmap/index.html`, `404.html`, `assets/`, `wambi/`, `og-*.png`, `robots.txt`,
  `sitemap.xml` and `_headers`.
- There is no `__spa-fallback.html`, and `404.html` is at the top level, so Cloudflare serves
  it (with a 404 status) for any other path instead of treating the site as a single-page app.
- `public/_headers` sets long immutable caching for `/assets/*`, a short cache for the HTML and the
  basic security headers.

## Publishing on merge

Every merge into `main` publishes the landing: the CI job `deploy-landing`
(`.github/workflows/ci.yml`) runs after `check` and `e2e` pass, builds the landing-only release
(the `VITE_SITE_URL` and `VITE_APP_URL` above) and runs `wrangler deploy` from `deploy/landing`.
Pull requests never run it, so they never touch the live site. A newer merge waits for a publish in
flight.

It needs two repository secrets (GitHub → the repo → Settings → Secrets and variables → Actions):

1. **`CLOUDFLARE_API_TOKEN`.** In Cloudflare: My Profile → API Tokens → Create Token → template
   "Edit Cloudflare Workers". Under Account Resources choose only the account that holds
   `wambito.com`, and under Zone Resources only that zone. Copy the token once; Cloudflare
   does not show it again.
2. **`CLOUDFLARE_ACCOUNT_ID`.** On that account's home page in Cloudflare (Account details → Account
   ID).

Without them the job fails with a message naming them. To revoke the CI's access, delete the token
in Cloudflare.

## Analytics (PostHog)

The landing can measure visits with PostHog, only after the visitor accepts in the cookie banner
(`apps/web/app/features/analytics/`). Two build variables, read like `VITE_SITE_URL`:

- `VITE_POSTHOG_KEY`: the project's public key. **Unset or empty is a keyless build: analytics are
  off.** There is no banner, posthog-js is never loaded, no request goes to PostHog, and the privacy
  policy keeps its old wording (the analytics paragraphs appear only in builds with a key).
- `VITE_POSTHOG_HOST`: optional, the ingestion host (the EU region's by default).

CI passes the key from the repository variable `POSTHOG_KEY` (`deploy-landing` build step). Nothing
changes for visitors until it is set.

### Go-live checklist (the founder, in order)

1. Create a PostHog account and a project in the **EU** region.
2. Project settings: "Discard client IP data" on; authorized domains and recording domains limited
   to `https://wambito.com`; session recording on with input masking.
3. Accept PostHog's DPA (organization settings, as Slinqer S.A.S.).
4. Read the real retention of events and recordings for the plan and put them in
   `ANALYTICS_RETENTION` (`apps/web/app/features/legal/legal.ts`) in a PR; merge it. The values
   there (12 months of events, 30 days of recordings) are provisional and must be confirmed.
5. Do not configure a session-replay "linked flag" in the PostHog project: the client disables
   feature flags (`advanced_disable_feature_flags`), so the flag would never evaluate and recording
   would never start.
6. Set the repository variable `POSTHOG_KEY` (Settings → Secrets and variables → Actions →
   Variables) to the project's public key. The next merge to `main` turns analytics on.
7. To turn it off: delete the variable and merge anything (or rerun `deploy-landing`).

## Deploy by hand

The landing is served by Cloudflare Workers as static assets: no Worker code, only the files in
`apps/web/build/client`. (Cloudflare now builds new Pages projects on Workers; creating a classic
Pages project failed for this account.) The config lives in `deploy/landing/wrangler.jsonc`. Run
wrangler from that folder so it does not try to auto-configure the web app:

```sh
cd deploy/landing && npx wrangler@4 deploy
```

The first run asks you to sign in to Cloudflare (`npx wrangler@4 login`). Every run publishes a new
version of the `wambito-landing` Worker.

The Worker was named `lukitas-landing` before the rename. A new name is a new Worker: the first
deploy of `wambito-landing` (from CI, which has no TTY, so wrangler takes the custom domain over
from the old Worker) moves `wambito.com` to it. Afterwards delete `lukitas-landing` by hand in the
Cloudflare dashboard (Workers & Pages → `lukitas-landing` → Settings → Delete). If that first
deploy fails because the domain is still attached to the old Worker, the old one keeps serving:
detach `wambito.com` from `lukitas-landing` in the dashboard and re-run the `deploy-landing` job.

- `not_found_handling: "404-page"` serves `404.html` with a 404 status for unknown paths.
- `html_handling: "drop-trailing-slash"` serves `/en` directly (matching the canonical link) and
  redirects `/en/` to it.
- `_headers` from the build applies as on Pages.

## Custom domain

`routes` in the config attaches `wambito.com` as a custom domain on deploy. The
zone is on the same Cloudflare account, so Cloudflare creates the DNS record and certificate. To
serve the landing from another domain, change `routes` and rebuild with `VITE_SITE_URL` set to it,
so the canonical links and the sitemap point to the new origin.

## Switching back once the app exists

Stop using `build:landing`: a plain `pnpm --filter @wambito/web build` (without `VITE_LANDING_ONLY`)
keeps the sign-in calls to action, the "Empezar" card and the SPA fallback, and `robots.txt` hides
the app's routes again. Keep passing `VITE_SITE_URL` so the generated files carry the right origin.
Without it the placeholder `https://wambito.test` is used.

## Checking a build

`pnpm --filter @wambito/web e2e:landing-only` builds the landing-only release with a test origin and
runs its end-to-end suite (links, copy, origin, 404 page, accessibility).
`pnpm --filter @wambito/web e2e:landing-only-app` does the same with a test `VITE_APP_URL` and checks
that the calls to action open its sign-in and nothing says "coming soon". `pnpm --filter
@wambito/web e2e:landing` does it for the default build. Each overwrites `apps/web/build/client`, so
build the release again afterwards.
