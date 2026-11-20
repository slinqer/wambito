import type { PostHogConfig } from "posthog-js";
import type { AnalyticsConfig } from "./config";
import { type BrowserSignals, CONSENT_KEY, consentState } from "./consent";

/** The subset of the PostHog instance used here. */
export type PostHogLike = {
  init(key: string, options: Partial<PostHogConfig>): unknown;
  opt_out_capturing(): void;
  stopSessionRecording(): void;
  reset(): void;
};

export function posthogOptions(config: AnalyticsConfig): Partial<PostHogConfig> {
  return {
    api_host: config.host,
    person_profiles: "identified_only",
    respect_dnt: true,
    capture_pageview: "history_change",
    persistence: "localStorage+cookie",
    cross_subdomain_cookie: false,
    session_recording: { maskAllInputs: true, maskTextSelector: "[data-ph-mask]" },
  };
}

// The library is imported dynamically, so it never enters the static graph.
const loadPosthog = async (): Promise<PostHogLike> => (await import("posthog-js")).default;

let started: PostHogLike | null = null;
let starting: Promise<void> | null = null;

/** Loads and starts PostHog, at most once per page. Call it only after consent. */
export function startAnalytics(
  config: AnalyticsConfig,
  load: () => Promise<PostHogLike> = loadPosthog,
): Promise<void> {
  if (starting) return starting;
  starting = (async () => {
    try {
      const ph = await load();
      ph.init(config.key, posthogOptions(config));
      started = ph;
    } catch (error) {
      starting = null;
      throw error;
    }
  })();
  return starting;
}

/** Withdraws: stops capture and recording, forgets the visitor, clears PostHog's own storage. */
export function stopAnalytics(
  env: { document: Pick<Document, "cookie">; localStorage?: Storage } = {
    document,
    localStorage: safeLocalStorage(),
  },
): void {
  const ph = started;
  if (ph) {
    try {
      ph.opt_out_capturing();
      ph.stopSessionRecording();
      ph.reset();
    } catch {
      // Clearing the storage below still runs.
    }
  }
  clearPosthogStorage(env.document, env.localStorage);
}

function safeLocalStorage(): Storage | undefined {
  try {
    return window.localStorage;
  } catch {
    return undefined;
  }
}

/** Expires every `ph_*` cookie (this host, path `/`) and removes every `ph_*` / `__ph*` key. */
export function clearPosthogStorage(
  doc: Pick<Document, "cookie">,
  storage: Storage | undefined,
): void {
  try {
    for (const part of doc.cookie.split(";")) {
      const name = part.split("=")[0]?.trim();
      if (name?.startsWith("ph_")) doc.cookie = `${name}=; Max-Age=0; path=/`;
    }
  } catch {
    // Cookies unavailable: nothing to clear.
  }
  try {
    if (!storage) return;
    const keys: string[] = [];
    for (let i = 0; i < storage.length; i++) {
      const key = storage.key(i);
      if (key?.startsWith("ph_") || key?.startsWith("__ph")) keys.push(key);
    }
    for (const key of keys) storage.removeItem(key);
  } catch {
    // Storage blocked: nothing to clear.
  }
}

/** Calls `onDenied` when another tab leaves the consent anything but granted. */
export function watchConsent(onDenied: () => void, win: Window = window): () => void {
  const listener = (event: Event) => {
    const { key, newValue } = event as StorageEvent;
    if (key !== CONSENT_KEY) return;
    const nav = win.navigator as BrowserSignals | undefined;
    const signals: BrowserSignals = {
      globalPrivacyControl: nav?.globalPrivacyControl,
      doNotTrack: nav?.doNotTrack,
    };
    if (consentState(newValue, signals, new Date()) !== "granted") onDenied();
  };
  win.addEventListener("storage", listener);
  return () => win.removeEventListener("storage", listener);
}
