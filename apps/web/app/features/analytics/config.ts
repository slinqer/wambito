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
