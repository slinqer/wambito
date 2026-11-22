import { beforeEach, describe, expect, it, vi } from "vitest";
import { markSeenToday } from "./seen.ts";

function memoryStorage() {
  const data = new Map<string, string>();
  return {
    getItem: (k: string) => data.get(k) ?? null,
    setItem: (k: string, v: string) => void data.set(k, v),
    removeItem: (k: string) => void data.delete(k),
  };
}

describe("markSeenToday", () => {
  beforeEach(() => {
    vi.stubGlobal("localStorage", memoryStorage());
  });

  const ok = () => vi.fn(async () => new Response(null, { status: 204 }));

  it("the first load of a day posts once with x-wambito-version", async () => {
    const fetch = ok();
    await markSeenToday("u1", "UTC", { fetch, now: () => new Date("2026-11-18T10:00:00Z") });
    expect(fetch).toHaveBeenCalledTimes(1);
    const [url, init] = fetch.mock.calls[0] as unknown as [string, RequestInit];
    expect(url).toBe("/api/v2/me/seen");
    expect(init.method).toBe("POST");
    expect(init.credentials).toBe("same-origin");
    expect((init.headers as Record<string, string>)["x-wambito-version"]).toBe("dev");
    expect(localStorage.getItem("wambito.seen.u1")).toBe("2026-11-18");
  });

  it("a second load the same local day posts nothing", async () => {
    const fetch = ok();
    const now = () => new Date("2026-11-18T10:00:00Z");
    await markSeenToday("u1", "UTC", { fetch, now });
    await markSeenToday("u1", "UTC", { fetch, now });
    expect(fetch).toHaveBeenCalledTimes(1);
  });

  it("the next local day posts again (America/Bogota, across UTC midnight)", async () => {
    const fetch = ok();
    // 22:00 Bogota on the 18th is 03:00 UTC on the 19th: still the same Bogota day.
    await markSeenToday("u1", "America/Bogota", {
      fetch,
      now: () => new Date("2026-11-18T15:00:00Z"),
    });
    await markSeenToday("u1", "America/Bogota", {
      fetch,
      now: () => new Date("2026-11-19T03:00:00Z"),
    });
    expect(fetch).toHaveBeenCalledTimes(1);
    await markSeenToday("u1", "America/Bogota", {
      fetch,
      now: () => new Date("2026-11-19T05:00:00Z"),
    });
    expect(fetch).toHaveBeenCalledTimes(2);
    expect(localStorage.getItem("wambito.seen.u1")).toBe("2026-11-19");
  });

  it("a failed post is tried again on the next load", async () => {
    const now = () => new Date("2026-11-18T10:00:00Z");
    const down = vi.fn(async () => new Response(null, { status: 500 }));
    await markSeenToday("u1", "UTC", { fetch: down, now });
    expect(localStorage.getItem("wambito.seen.u1")).toBeNull();
    const broken = vi.fn(async () => {
      throw new TypeError("offline");
    });
    await expect(markSeenToday("u1", "UTC", { fetch: broken, now })).resolves.toBeUndefined();
    const fetch = ok();
    await markSeenToday("u1", "UTC", { fetch, now });
    expect(fetch).toHaveBeenCalledTimes(1);
  });
});
