import { describe, expect, it, vi } from "vitest";
import { CONSENT_KEY, encodeChoice } from "./consent";
import {
  clearPosthogStorage,
  type PostHogLike,
  posthogOptions,
  startAnalytics,
  stopAnalytics,
  watchConsent,
} from "./posthog";

function fakePosthog() {
  return {
    init: vi.fn(),
    opt_out_capturing: vi.fn(),
    stopSessionRecording: vi.fn(),
    reset: vi.fn(),
  } satisfies PostHogLike;
}

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
      session_recording: { maskAllInputs: true, maskTextSelector: "[data-ph-mask]" },
    });
  });
});

describe("startAnalytics and stopAnalytics", () => {
  it("starts once per page and tears down on stop", async () => {
    const ph = fakePosthog();
    const load = vi.fn(async () => ph);
    const config = { key: "k", host: "https://h.test" };
    await startAnalytics(config, load);
    await startAnalytics(config, load);
    expect(load).toHaveBeenCalledTimes(1);
    expect(ph.init).toHaveBeenCalledTimes(1);
    expect(ph.init.mock.calls[0]?.[0]).toBe("k");

    stopAnalytics({ document: { cookie: "" } as Document });
    expect(ph.opt_out_capturing).toHaveBeenCalledTimes(1);
    expect(ph.stopSessionRecording).toHaveBeenCalledTimes(1);
    expect(ph.reset).toHaveBeenCalledTimes(1);
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
      __ph_opt_in_out_phc_x: "1",
      [CONSENT_KEY]: "x",
    });
    clearPosthogStorage(doc, storage);
    expect(writes).toEqual(["ph_phc_x_posthog=; Max-Age=0; path=/"]);
    expect(storage.getItem("ph_phc_x_posthog")).toBeNull();
    expect(storage.getItem("__ph_opt_in_out_phc_x")).toBeNull();
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

  it("treats GPC as not granted", () => {
    const win = fakeWindow();
    Object.assign(win.navigator, { globalPrivacyControl: true });
    const onDenied = vi.fn();
    watchConsent(onDenied, win);
    win.dispatchEvent(storageEvent(CONSENT_KEY, encodeChoice("granted", new Date())));
    expect(onDenied).toHaveBeenCalledTimes(1);
  });
});
