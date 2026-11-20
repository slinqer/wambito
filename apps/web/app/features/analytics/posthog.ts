import type { PostHogConfig } from "posthog-js";
import type { AnalyticsConfig } from "./config";
import { type BrowserSignals, CONSENT_KEY, consentState } from "./consent";

/** The subset of the PostHog instance used here. */
export type PostHogLike = {
  init(key: string, options: Partial<PostHogConfig>): unknown;
  opt_in_capturing(options?: { captureEventName?: string | null | false }): void;
  opt_out_capturing(): void;
  startSessionRecording(): void;
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
    opt_out_persistence_by_default: true,
    session_recording: { maskAllInputs: true, maskTextSelector: "[data-ph-mask]" },
    // The landing uses no feature flags; with them on, the withdrawal's `reset()` reloads them and
    // sends a request to PostHog after the person said no (the built-landing e2e proves it). Not
    // `advanced_disable_flags`: that also drops the remote config session recording needs.
    // Because flags are off, never configure a session-replay "linked flag" in the PostHog project:
    // it would never evaluate and recording would never start.
    advanced_disable_feature_flags: true,
  };
}

// The library is imported dynamically, so it never enters the static graph.
const loadPosthog = async (): Promise<PostHogLike> => (await import("posthog-js")).default;

let started: PostHogLike | null = null;
let starting: Promise<void> | null = null;
// Bumped by every stop: a start that was still loading when it changed must not init.
let generation = 0;

/** Test hook: forgets everything this module remembers about the page. */
export function resetAnalyticsForTests(): void {
  started = null;
  starting = null;
  generation = 0;
}

/**
 * Starts PostHog, at most once per page. Call it only after consent. After a withdrawal on the
 * same page, a new start opts back in instead of initialising again.
 */
export function startAnalytics(
  config: AnalyticsConfig,
  load: () => Promise<PostHogLike> = loadPosthog,
  storage: Storage | undefined = safeLocalStorage(),
): Promise<void> {
  if (started) {
    started.opt_in_capturing({ captureEventName: null });
    started.startSessionRecording();
    return Promise.resolve();
  }
  if (starting) return starting;
  const mine = generation;
  const attempt = (async () => {
    try {
      const ph = await load();
      if (mine !== generation) return; // withdrawn while loading: never init
      // A withdrawal on an earlier visit left its opt-out marker behind; PostHog would read it as
      // a denial. This runs only after consent, so a stale marker is never right here.
      removeOptOutMarkers(storage);
      ph.init(config.key, posthogOptions(config));
      started = ph;
    } catch (error) {
      if (mine === generation) starting = null; // a failed load can be retried
      throw error;
    }
  })();
  starting = attempt;
  return attempt;
}

/**
 * Withdraws: stops recording, forgets the visitor, clears PostHog's own storage and leaves capture
 * opted out. The order matters (posthog-js 1.447): `reset()` removes the opt-out marker, so the
 * opt-out comes last, and the marker key `__ph_opt_in_out_*` survives the clearing.
 */
export function stopAnalytics(
  env: { document: Pick<Document, "cookie">; localStorage?: Storage } = {
    document,
    localStorage: safeLocalStorage(),
  },
): void {
  generation += 1;
  starting = null;
  const ph = started;
  if (ph) {
    try {
      ph.stopSessionRecording();
      ph.reset();
      ph.opt_out_capturing();
    } catch {
      // Clearing the storage below still runs.
    }
  }
  clearPosthogStorage(env.document, env.localStorage);
}

function removeOptOutMarkers(storage: Storage | undefined): void {
  try {
    if (!storage) return;
    const keys: string[] = [];
    for (let i = 0; i < storage.length; i++) {
      const key = storage.key(i);
      if (key?.startsWith("__ph_opt_in_out_")) keys.push(key);
    }
    for (const key of keys) storage.removeItem(key);
  } catch {
    // Storage blocked: nothing to remove.
  }
}

function safeLocalStorage(): Storage | undefined {
  try {
    return window.localStorage;
  } catch {
    return undefined;
  }
}

/**
 * Expires every `ph_*` cookie (this host, path `/`) and removes every `ph_*` / `__ph*` key, except
 * the `__ph_opt_in_out_*` opt-out marker, which is what keeps capture off.
 */
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
      if (key?.startsWith("__ph_opt_in_out_")) continue;
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
    // A null key is another tab's `localStorage.clear()`: the consent is gone too.
    if (key !== null && key !== CONSENT_KEY) return;
    const nav = win.navigator as BrowserSignals | undefined;
    const signals: BrowserSignals = {
      globalPrivacyControl: nav?.globalPrivacyControl,
      doNotTrack: nav?.doNotTrack,
    };
    if (consentState(key === null ? null : newValue, signals, new Date()) !== "granted") {
      onDenied();
    }
  };
  win.addEventListener("storage", listener);
  return () => win.removeEventListener("storage", listener);
}
