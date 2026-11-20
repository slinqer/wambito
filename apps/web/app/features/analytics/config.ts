import { isLandingOnly } from "../../site/origin.ts";

export type AnalyticsConfig = { key: string; host: string };

const DEFAULT_HOST = "https://eu.i.posthog.com";

/**
 * The build switch: no key, no analytics at all (no banner, no link, no PostHog code in the page).
 * The host defaults to PostHog's EU cloud; a trailing slash is dropped.
 */
export function analyticsConfig(
  env: { VITE_POSTHOG_KEY?: string; VITE_POSTHOG_HOST?: string } = import.meta.env as Record<
    string,
    string | undefined
  >,
): AnalyticsConfig | null {
  const key = env.VITE_POSTHOG_KEY?.trim();
  if (!key) return null;
  const host = env.VITE_POSTHOG_HOST?.trim().replace(/\/+$/, "") || DEFAULT_HOST;
  return { key, host };
}

/**
 * The site's switch: only a landing-only build (`VITE_LANDING_ONLY=true`, wambito.com) honours
 * the key, so `pnpm dev` and the VPS's full build never load PostHog, whatever their env holds.
 */
export function siteAnalyticsConfig(env: {
  VITE_LANDING_ONLY?: string;
  VITE_POSTHOG_KEY?: string;
  VITE_POSTHOG_HOST?: string;
}): AnalyticsConfig | null {
  return isLandingOnly(env.VITE_LANDING_ONLY) ? analyticsConfig(env) : null;
}

/** The build's PostHog switch (a build-time constant): `null` means no analytics in this build. */
export const SITE_ANALYTICS_CONFIG = siteAnalyticsConfig({
  VITE_LANDING_ONLY: import.meta.env.VITE_LANDING_ONLY,
  VITE_POSTHOG_KEY: import.meta.env.VITE_POSTHOG_KEY,
  VITE_POSTHOG_HOST: import.meta.env.VITE_POSTHOG_HOST,
});
