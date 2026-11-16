import { describe, expect, test } from "vitest";
import { IpOpenCount, IpWindowLimit } from "../src/http/ip-limit.ts";

describe("IpWindowLimit", () => {
  const limit = () => new IpWindowLimit({ max: 3, windowMs: 1000 });

  test("counts requests and refuses the one over the limit", () => {
    const l = limit();
    expect([1, 2, 3, 4].map(() => l.hit("203.0.113.1", 0))).toEqual([false, false, false, true]);
  });

  test("counts per address", () => {
    const l = limit();
    for (let i = 0; i < 4; i++) l.hit("203.0.113.1", 0);
    expect(l.hit("203.0.113.2", 0)).toBe(false);
  });

  test("the window resets after windowMs from its first request", () => {
    const l = limit();
    for (let i = 0; i < 4; i++) l.hit("203.0.113.1", 0);
    expect(l.hit("203.0.113.1", 999)).toBe(true);
    expect(l.hit("203.0.113.1", 1000)).toBe(false);
    expect(l.hit("203.0.113.1", 1001)).toBe(false);
  });

  test("a null address shares one bucket", () => {
    const l = limit();
    for (let i = 0; i < 3; i++) l.hit(null, 0);
    expect(l.hit(null, 0)).toBe(true);
    expect(l.hit("203.0.113.1", 0)).toBe(false);
  });
});

describe("IpOpenCount", () => {
  test("refuses the 6th open id of an address", () => {
    const c = new IpOpenCount(5);
    for (let i = 0; i < 5; i++) expect(c.tryOpen("203.0.113.1", `id${i}`, 10_000, 0)).toBe(true);
    expect(c.tryOpen("203.0.113.1", "id5", 10_000, 0)).toBe(false);
    expect(c.tryOpen("203.0.113.2", "other", 10_000, 0)).toBe(true);
  });

  test("accepts again once one expires", () => {
    const c = new IpOpenCount(2);
    c.tryOpen("203.0.113.1", "a", 100, 0);
    c.tryOpen("203.0.113.1", "b", 200, 0);
    expect(c.tryOpen("203.0.113.1", "c", 300, 50)).toBe(false);
    expect(c.tryOpen("203.0.113.1", "c", 300, 100)).toBe(true);
  });

  test("accepts again once one is closed", () => {
    const c = new IpOpenCount(1);
    expect(c.tryOpen("203.0.113.1", "a", 1000, 0)).toBe(true);
    expect(c.tryOpen("203.0.113.1", "b", 1000, 0)).toBe(false);
    c.close("a");
    expect(c.tryOpen("203.0.113.1", "b", 1000, 0)).toBe(true);
  });

  test("closing an unknown id is a no-op", () => {
    const c = new IpOpenCount(1);
    c.close("nope");
    expect(c.tryOpen(null, "a", 10, 0)).toBe(true);
  });
});
