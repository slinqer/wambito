import { describe, expect, it } from "vitest";
import { IDEMPOTENCY_NAMESPACE, uuidv5, uuidv5Sync, uuidv7 } from "./ids.ts";

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

/** The previous implementation, over WebCrypto: the sync one must give the same bytes. */
async function webCryptoV5(namespace: string, name: string): Promise<string> {
  const ns = namespace.replaceAll("-", "");
  const nsBytes = Uint8Array.from(ns.match(/../g) ?? [], (h) => Number.parseInt(h, 16));
  const nameBytes = new TextEncoder().encode(name);
  const input = new Uint8Array(nsBytes.length + nameBytes.length);
  input.set(nsBytes);
  input.set(nameBytes, nsBytes.length);
  const d = new Uint8Array(await crypto.subtle.digest("SHA-1", input)).slice(0, 16);
  d[6] = 0x50 | ((d[6] ?? 0) & 0x0f);
  d[8] = 0x80 | ((d[8] ?? 0) & 0x3f);
  const h = Array.from(d, (b) => b.toString(16).padStart(2, "0")).join("");
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20)}`;
}

describe("uuidv5Sync", () => {
  it("matches the RFC 4122 v5 vectors (DNS and URL namespaces)", () => {
    expect(uuidv5Sync("6ba7b810-9dad-11d1-80b4-00c04fd430c8", "python.org")).toBe(
      "886313e1-3b8a-5372-9b90-0c9aee199e5d",
    );
    expect(uuidv5Sync("6ba7b810-9dad-11d1-80b4-00c04fd430c8", "www.example.com")).toBe(
      "2ed6657d-e927-568b-95e1-2665a8aea6a2",
    );
    expect(uuidv5Sync("6ba7b811-9dad-11d1-80b4-00c04fd430c8", "http://python.org/")).toBe(
      "4c565f0d-3f5a-5890-b41b-20cf47701c5e",
    );
  });

  it("gives the same ids as the WebCrypto version, for names of every block length", async () => {
    const rule = "01930000-0000-7000-8000-000000000001";
    const names = [
      "",
      "2026-10:0",
      "2026-11:3",
      "settings",
      "merchant:éxito café ☕",
      `01930000-0000-7000-8000-0000000000aa/key-1/0`,
      "a".repeat(39),
      "a".repeat(40),
      "a".repeat(41),
      "b".repeat(47),
      "b".repeat(48),
      "c".repeat(55),
      "c".repeat(56),
      "d".repeat(64),
      "e".repeat(1000),
    ];
    for (const namespace of [rule, IDEMPOTENCY_NAMESPACE, "6BA7B810-9DAD-11D1-80B4-00C04FD430C8"]) {
      for (const name of names) {
        expect(uuidv5Sync(namespace, name)).toBe(await webCryptoV5(namespace, name));
        expect(await uuidv5(namespace, name)).toBe(await webCryptoV5(namespace, name));
      }
    }
  });

  it("refuses a namespace that is not a UUID", () => {
    expect(() => uuidv5Sync("not-a-uuid", "x")).toThrow(/namespace/);
  });
});
