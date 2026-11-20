import { useCallback, useEffect, useRef, useState } from "react";
import type { AnalyticsConfig } from "./config.ts";
import {
  type BrowserSignals,
  browserSaysNo,
  type ConsentChoice,
  type ConsentState,
  consentState,
  encodeChoice,
  readStoredConsent,
  writeStoredConsent,
} from "./consent.ts";
import { startAnalytics, stopAnalytics, watchConsent } from "./posthog.ts";

/** What the hook reads and calls; stories pass fakes, the pages never do. */
export type ConsentDeps = {
  storage?: Storage;
  signals?: BrowserSignals;
  now?: () => Date;
  start?: (config: AnalyticsConfig) => Promise<void>;
  stop?: () => void;
};

export type AnalyticsConsent = {
  /** False until mounted: the prerendered HTML and the first client render show no banner. */
  ready: boolean;
  state: ConsentState;
  browserSaysNo: boolean;
  open: boolean;
  /** The footer link: opens the banner again, with the current choice. */
  reopen(): void;
  /** Closes it without a choice (the GPC note's "Close"). */
  close(): void;
  choose(choice: ConsentChoice): void;
};

/**
 * The landing's consent: reads the stored choice and the browser's signals once mounted, opens the
 * banner when it has to ask, starts PostHog on `granted` and stops it when the person withdraws
 * (here or in another tab). With no config (no key in the build) it does nothing.
 */
export function useAnalyticsConsent(
  config: AnalyticsConfig | null,
  deps: ConsentDeps = {},
): AnalyticsConsent {
  const [ready, setReady] = useState(false);
  const [state, setState] = useState<ConsentState>("ask");
  const [saysNo, setSaysNo] = useState(false);
  const [open, setOpen] = useState(false);
  // The latest config and deps, read by the callbacks; the effect runs again only for a new key.
  const latest = useRef({ config, deps });
  latest.current = { config, deps };
  const running = useRef(false);

  const begin = useCallback(() => {
    const { config, deps } = latest.current;
    if (!config || running.current) return;
    running.current = true;
    (deps.start ?? startAnalytics)(config).catch(() => {
      // Blocked or offline: nothing runs, and a later accept may try again.
      running.current = false;
    });
  }, []);

  // Always stops, even when this footer started nothing: PostHog is one per page, and an earlier
  // footer (before a client-side move) may have started it. With nothing started, `stopAnalytics`
  // loads nothing and only clears PostHog's storage.
  const end = useCallback(() => {
    running.current = false;
    (latest.current.deps.stop ?? stopAnalytics)();
  }, []);

  const key = config?.key;
  const host = config?.host;
  useEffect(() => {
    if (key === undefined || host === undefined) return;
    const { deps } = latest.current;
    const storage = deps.storage ?? pageStorage();
    const signals = deps.signals ?? navigatorSignals();
    const now = deps.now ?? (() => new Date());
    const current = consentState(readStoredConsent(storage), signals, now());
    setSaysNo(browserSaysNo(signals));
    setState(current);
    setOpen(current === "ask");
    setReady(true);
    // Not `granted` (asking, denied, an expired or old-version grant, GPC/DNT): stop, so what an
    // earlier visit left (`ph_*`) goes. A first visit has nothing to clear and sends nothing.
    if (current === "granted") begin();
    else end();
    // Another tab withdrew (or cleared the choice): stop here too.
    const unwatch = watchConsent(() => {
      setState(consentState(readStoredConsent(storage), signals, now()));
      end();
    });
    // Unmounting (a client-side move to another public page) keeps PostHog running: the next
    // page's footer finds it started.
    return unwatch;
  }, [key, host, begin, end]);

  const choose = useCallback(
    (choice: ConsentChoice) => {
      const { deps } = latest.current;
      const now = deps.now ?? (() => new Date());
      // A failed write (storage blocked) still applies the choice for this page.
      writeStoredConsent(deps.storage ?? pageStorage(), encodeChoice(choice, now()));
      setState(choice);
      setOpen(false);
      if (choice === "granted") begin();
      else end();
    },
    [begin, end],
  );

  const reopen = useCallback(() => setOpen(true), []);
  const close = useCallback(() => setOpen(false), []);

  return { ready, state, browserSaysNo: saysNo, open, reopen, close, choose };
}

function pageStorage(): Storage | undefined {
  try {
    return window.localStorage;
  } catch {
    return undefined;
  }
}

function navigatorSignals(): BrowserSignals {
  const nav = navigator as Navigator & BrowserSignals;
  return { globalPrivacyControl: nav.globalPrivacyControl, doNotTrack: nav.doNotTrack };
}
