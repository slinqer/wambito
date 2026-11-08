import { describe, expect, it } from "vitest";
import { uuidv5, uuidv7 } from "./ids.ts";

const V7 = /^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;

describe("uuidv7", () => {
  it("is a lower-case version 7 UUID carrying the time in its first 48 bits", () => {
    const id = uuidv7(Date.UTC(2026, 10, 8, 12, 0, 0));
    expect(id).toMatch(V7);
    expect(Number.parseInt(id.replaceAll("-", "").slice(0, 12), 16)).toBe(
      Date.UTC(2026, 10, 8, 12, 0, 0),
    );
  });

  it("sorts in creation order, also within one millisecond or when the clock goes back", () => {
    const at = Date.UTC(2026, 10, 8);
    const ids = [uuidv7(at), uuidv7(at), uuidv7(at), uuidv7(at - 5), uuidv7(at + 1)];
    expect([...ids].sort()).toEqual(ids);
    expect(new Set(ids).size).toBe(ids.length);
  });

  it("uses the current time by default", () => {
    const before = Date.now();
    const ms = Number.parseInt(uuidv7().replaceAll("-", "").slice(0, 12), 16);
    expect(ms).toBeGreaterThanOrEqual(before);
    expect(ms).toBeLessThanOrEqual(Date.now() + 1);
  });
});

describe("uuidv5", () => {
  it("matches the RFC 4122 example (DNS namespace, python.org)", async () => {
    expect(await uuidv5("6ba7b810-9dad-11d1-80b4-00c04fd430c8", "python.org")).toBe(
      "886313e1-3b8a-5372-9b90-0c9aee199e5d",
    );
  });

  it("is stable per rule and month and differs between them", async () => {
    const rule = "01930000-0000-7000-8000-000000000001";
    const a = await uuidv5(rule, "2026-10");
    expect(await uuidv5(rule, "2026-10")).toBe(a);
    expect(await uuidv5(rule, "2026-11")).not.toBe(a);
    expect(a).toMatch(/^[0-9a-f]{8}-[0-9a-f]{4}-5[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/);
  });
});
