import {
  isComingSoon,
  isLandingOnly,
  landingTarget,
  resolveAppOrigin,
  resolveLandingOrigin,
  resolveSiteOrigin,
} from "./origin.ts";

/** The public origin used in absolute URLs. `VITE_SITE_URL` at build time, else the placeholder. */
export const SITE_ORIGIN = resolveSiteOrigin(import.meta.env.VITE_SITE_URL);

/**
 * Landing-only release (`VITE_LANDING_ONLY=true`): only the landing ships. Off by default.
 * What its calls to action do depends on `APP_ORIGIN`.
 */
export const LANDING_ONLY = isLandingOnly(import.meta.env.VITE_LANDING_ONLY);

/**
 * The live app's origin (`VITE_APP_URL`), read in the landing-only release only: its calls to
 * action open the app's sign-in there. `undefined` when unset, and always outside landing-only
 * (the app is then served from the same origin).
 */
export const APP_ORIGIN = LANDING_ONLY ? resolveAppOrigin(import.meta.env.VITE_APP_URL) : undefined;

/**
 * Landing-only without an app to open: everything that would lead to the app leads to the GitHub
 * repo instead, marked as coming soon.
 */
export const COMING_SOON = isComingSoon(LANDING_ONLY, APP_ORIGIN);

/**
 * The public landing's origin when the app runs on its own (`VITE_LANDING_URL`, the personal
 * install, whose `/` redirects there): links to the landing leave the app for it.
 */
export const LANDING_ORIGIN = resolveLandingOrigin(import.meta.env.VITE_LANDING_URL);

/** Where a link to the landing page `path` goes in this build; see `landingTarget`. */
export const landingLink = (path = "/") => landingTarget(LANDING_ORIGIN, path);

/**
 * The build's id (`VITE_BUILD_ID`, the short git commit, set by `deploy/personal/up.sh`), else
 * `dev`. Sent as `x-wambito-version` on the daily seen call.
 */
export const BUILD_ID: string = import.meta.env.VITE_BUILD_ID || "dev";
