/**
 * Builds the landing-only release (`pnpm build:landing`): the prerendered landing pages plus a 404
 * page, and nothing that leads to the app. VITE_SITE_URL (the site's public origin, used in the
 * canonical, hreflang, Open Graph, sitemap and robots) is required; there is no placeholder to fall
 * back on for something you are about to publish.
 *
 *   VITE_SITE_URL=https://wambito.com pnpm --filter @wambito/web build:landing
 *
 * VITE_APP_URL (the live app's origin) is optional. Without it the calls to action say "coming
 * soon" and lead to GitHub. With it the hero's and the closing's "Crear cuenta" open the app's
 * `/create-account`, and the header's "Entrar" its `/sign-in`:
 *
 *   VITE_SITE_URL=https://wambito.com VITE_APP_URL=https://app.wambito.com \
 *     pnpm --filter @wambito/web build:landing
 *
 * The output stays in build/client.
 */
import { spawnSync } from "node:child_process";
import { readBuildEnv } from "../app/site/build-env.ts";
import { resolveAppOrigin, resolveSiteOrigin } from "../app/site/origin.ts";

// The environment or a `.env` file of apps/web, as the build itself reads it.
const env = readBuildEnv();
const raw = env.siteUrl;
if (!raw?.trim()) {
  console.error(
    "VITE_SITE_URL is not set (environment or apps/web/.env). Pass the site's public origin, e.g.\n" +
      "  VITE_SITE_URL=https://wambito.com pnpm --filter @wambito/web build:landing",
  );
  process.exit(1);
}

let origin: string;
let appOrigin: string | undefined;
try {
  origin = resolveSiteOrigin(raw);
  appOrigin = resolveAppOrigin(env.appUrl);
} catch (error) {
  console.error(error instanceof Error ? error.message : error);
  process.exit(1);
}

console.log(
  `Building the landing-only release for ${origin}, ` +
    (appOrigin
      ? `with its calls to action opening ${appOrigin}`
      : "with coming-soon calls to action"),
);
const result = spawnSync("react-router", ["build"], {
  stdio: "inherit",
  // The build sees exactly what was validated (blank when there is no app yet).
  env: {
    ...process.env,
    VITE_SITE_URL: origin,
    VITE_LANDING_ONLY: "true",
    VITE_APP_URL: appOrigin ?? "",
  },
});
process.exit(result.status ?? 1);
