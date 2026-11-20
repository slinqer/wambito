import { beforeEach, describe, expect, it, vi } from "vitest";
import { CONSENT_KEY, encodeChoice } from "./consent";
import {
  clearPosthogStorage,
  type PostHogLike,
  posthogOptions,
  resetAnalyticsForTests,
  startAnalytics,
  stopAnalytics,
  watchConsent,
} from "./posthog";

beforeEach(resetAnalyticsForTests);

function fakePosthog() {
  const calls: string[] = [];
  const fn = (name: string) =>
    vi.fn((..._args: unknown[]) => {
      calls.push(name);
    });
  return {
    calls,
    init: fn("init"),
    opt_in_capturing: fn("opt_in_capturing"),
    opt_out_capturing: fn("opt_out_capturing"),
    startSessionRecording: fn("startSessionRecording"),
    stopSessionRecording: fn("stopSessionRecording"),
    reset: fn("reset"),
  };
}
const noDoc = { document: { cookie: "" } as Document };
const config = { key: "k", host: "https://h.test" };

function memoryStorage(initial: Record<string, string>): Storage {
  const data = new Map(Object.entries(initial));
  return {
    get length() {
      return data.size;
    },
    key: (i: number) => [...data.keys()][i] ?? null,
    getItem: (k: string) => data.get(k) ?? null,
    setItem: (k: string, v: string) => void data.set(k, v),
    removeItem: (k: string) => void data.delete(k),
    clear: () => data.clear(),
  };
}

describe("posthogOptions", () => {
  it("carries the privacy-first init options", () => {
    expect(posthogOptions({ key: "k", host: "https://h.test" })).toMatchObject({
      api_host: "https://h.test",
      person_profiles: "identified_only",
      respect_dnt: true,
      capture_pageview: "history_change",
      persistence: "localStorage+cookie",
      cross_subdomain_cookie: false,
      opt_out_persistence_by_default: true,
      session_recording: { maskAllInputs: true, maskTextSelector: "[data-ph-mask]" },
    });
  });
});

describe("startAnalytics and stopAnalytics", () => {
  it("removes a stale opt-out marker before init", async () => {
    const ph = fakePosthog();
    const storage = memoryStorage({ __ph_opt_in_out_phc_x: "0", theme: "dark" });
    let markerAtInit: string | null = "unset";
    ph.init.mockImplementation(() => {
      markerAtInit = storage.getItem("__ph_opt_in_out_phc_x");
    });
    await startAnalytics(config, async () => ph, storage);
    expect(ph.init).toHaveBeenCalledTimes(1);
    expect(markerAtInit).toBeNull();
    expect(storage.getItem("theme")).toBe("dark");
  });

  it("inits once for concurrent starts", async () => {
    const ph = fakePosthog();
    const load = vi.fn(async () => ph);
    const first = startAnalytics(config, load);
    const second = startAnalytics(config, load);
    await Promise.all([first, second]);
    expect(load).toHaveBeenCalledTimes(1);
    expect(ph.init).toHaveBeenCalledTimes(1);
    expect(ph.init.mock.calls[0]?.[0]).toBe("k");
  });

  it("stops recording, resets, then opts out last", async () => {
    const ph = fakePosthog();
    await startAnalytics(config, async () => ph);
    ph.calls.length = 0;
    stopAnalytics(noDoc);
    expect(ph.calls).toEqual(["stopSessionRecording", "reset", "opt_out_capturing"]);
  });

  it("never inits when stopped while still loading", async () => {
    const ph = fakePosthog();
    let release: (value: typeof ph) => void = () => {};
    const load = vi.fn(() => new Promise<typeof ph>((resolve) => (release = resolve)));
    const pending = startAnalytics(config, load);
    stopAnalytics(noDoc);
    release(ph);
    await pending;
    expect(ph.init).not.toHaveBeenCalled();
  });

  it("opts back in on the same page after a withdrawal", async () => {
    const ph = fakePosthog();
    await startAnalytics(config, async () => ph);
    stopAnalytics(noDoc);
    await startAnalytics(config, async () => ph);
    expect(ph.init).toHaveBeenCalledTimes(1);
    expect(ph.opt_in_capturing).toHaveBeenCalledTimes(1);
    expect(ph.opt_in_capturing).toHaveBeenCalledWith({ captureEventName: null });
    expect(ph.startSessionRecording).toHaveBeenCalledTimes(1);
  });
});

describe("clearPosthogStorage", () => {
  it("expires ph_ cookies and removes PostHog keys, keeping the rest", () => {
    const writes: string[] = [];
    const doc = {
      get cookie() {
        return "ph_phc_x_posthog=1; theme=dark";
      },
      set cookie(v: string) {
        writes.push(v);
      },
    };
    const storage = memoryStorage({
      ph_phc_x_posthog: "{}",
      __ph_opt_in_out_phc_x: "0",
      __ph_other: "1",
      [CONSENT_KEY]: "x",
    });
    clearPosthogStorage(doc, storage);
    expect(writes).toEqual(["ph_phc_x_posthog=; Max-Age=0; path=/"]);
    expect(storage.getItem("ph_phc_x_posthog")).toBeNull();
    expect(storage.getItem("__ph_other")).toBeNull();
    // The opt-out marker is what keeps capture off: it stays.
    expect(storage.getItem("__ph_opt_in_out_phc_x")).toBe("0");
    expect(storage.getItem(CONSENT_KEY)).toBe("x");
  });

  it("never throws", () => {
    const doc = {
      get cookie(): string {
        throw new Error("no");
      },
      set cookie(_v: string) {
        throw new Error("no");
      },
    };
    const storage = {
      get length(): number {
        throw new Error("no");
      },
    } as unknown as Storage;
    expect(() => clearPosthogStorage(doc, storage)).not.toThrow();
    expect(() => clearPosthogStorage(doc, undefined)).not.toThrow();
  });
});

describe("watchConsent", () => {
  function fakeWindow() {
    const target = new EventTarget();
    return Object.assign(target, { navigator: {} }) as unknown as Window;
  }
  function storageEvent(key: string | null, newValue: string | null): Event {
    return Object.assign(new Event("storage"), { key, newValue });
  }

  it("calls onDenied when the stored choice is no longer granted", () => {
    const win = fakeWindow();
    const onDenied = vi.fn();
    const stop = watchConsent(onDenied, win);

    win.dispatchEvent(storageEvent("other", null));
    expect(onDenied).not.toHaveBeenCalled();

    win.dispatchEvent(storageEvent(CONSENT_KEY, encodeChoice("granted", new Date())));
    expect(onDenied).not.toHaveBeenCalled();

    win.dispatchEvent(storageEvent(CONSENT_KEY, encodeChoice("denied", new Date())));
    expect(onDenied).toHaveBeenCalledTimes(1);

    win.dispatchEvent(storageEvent(CONSENT_KEY, null));
    expect(onDenied).toHaveBeenCalledTimes(2);

    stop();
    win.dispatchEvent(storageEvent(CONSENT_KEY, encodeChoice("denied", new Date())));
    expect(onDenied).toHaveBeenCalledTimes(2);
  });

  it("treats another tab's localStorage.clear() (null key) as not granted", () => {
    const win = fakeWindow();
    const onDenied = vi.fn();
    watchConsent(onDenied, win);
    win.dispatchEvent(storageEvent(null, null));
    expect(onDenied).toHaveBeenCalledTimes(1);
  });

  it("treats GPC as not granted", () => {
    const win = fakeWindow();
    Object.assign(win.navigator, { globalPrivacyControl: true });
    const onDenied = vi.fn();
    watchConsent(onDenied, win);
    win.dispatchEvent(storageEvent(CONSENT_KEY, encodeChoice("granted", new Date())));
    expect(onDenied).toHaveBeenCalledTimes(1);
  });
});
