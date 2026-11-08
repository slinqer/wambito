import { describe, expect, it } from "vitest";
import {
  CryptoError,
  dedupeTag,
  deriveRecordKeys,
  generateDataKey,
  openRecord,
  type RecordContext,
  sealRecord,
} from "../src/index.ts";

const ctx: RecordContext = { userId: "u1", type: "transaction", id: "r1", keyV: 1 };
const value = { s: 1, name: "Almuerzo", amount: 1800000, note: "piña colada ñandú" };

async function keys(fill = 7, extractable = false) {
  return deriveRecordKeys(new Uint8Array(32).fill(fill), extractable);
}

async function failure(p: Promise<unknown>) {
  try {
    await p;
  } catch (e) {
    return e;
  }
  return undefined;
}

describe("records", () => {
  it("generates 32 random bytes", () => {
    const a = generateDataKey();
    expect(a).toHaveLength(32);
    expect(a).not.toEqual(generateDataKey());
  });

  it("seal then open returns the same value", async () => {
    const k = await keys();
    expect(await openRecord(k, ctx, await sealRecord(k, ctx, value))).toEqual(value);
  });

  it("body length is 12 + 16 + a multiple of 64", async () => {
    const k = await keys();
    for (const n of [1, 63, 64, 65]) {
      // The number 5 is 1 byte of JSON; a string of n-2 chars is n bytes.
      const body = await sealRecord(k, ctx, n === 1 ? 5 : "a".repeat(n - 2));
      const padded = Math.ceil(n / 64) * 64;
      expect(body.length).toBe(12 + padded + 16);
    }
  });

  it("two seals of the same value differ", async () => {
    const k = await keys();
    expect(await sealRecord(k, ctx, value)).not.toEqual(await sealRecord(k, ctx, value));
  });

  it("uses the given nonce as the first 12 bytes", async () => {
    const k = await keys();
    const nonce = new Uint8Array(12).fill(9);
    expect((await sealRecord(k, ctx, value, nonce)).slice(0, 12)).toEqual(nonce);
  });

  it("swapped associated data fails", async () => {
    const k = await keys();
    const body = await sealRecord(k, ctx, value);
    const others: RecordContext[] = [
      { ...ctx, userId: "u2" },
      { ...ctx, type: "budget" },
      { ...ctx, id: "r2" },
      { ...ctx, keyV: 2 },
    ];
    for (const other of others) {
      const e = await failure(openRecord(k, other, body));
      expect(e).toBeInstanceOf(CryptoError);
      expect((e as CryptoError).code).toBe("cannot_open");
    }
  });

  it("a flipped byte, a truncated body or another key fails", async () => {
    const k = await keys();
    const body = await sealRecord(k, ctx, value);
    const flipped = body.slice();
    flipped[20] = (flipped[20] ?? 0) ^ 1;
    const bad = [flipped, body.slice(0, body.length - 1), body.slice(0, 5)];
    for (const b of bad) {
      expect(((await failure(openRecord(k, ctx, b))) as CryptoError).code).toBe("cannot_open");
    }
    const e = await failure(openRecord(await keys(8), ctx, body));
    expect((e as CryptoError).code).toBe("cannot_open");
  });

  it("record keys are not extractable by default", async () => {
    const k = await keys();
    await expect(crypto.subtle.exportKey("raw", k.record)).rejects.toThrow();
    await expect(crypto.subtle.exportKey("raw", k.dedupe)).rejects.toThrow();
    const ex = await keys(7, true);
    expect((await crypto.subtle.exportKey("raw", ex.record)).byteLength).toBe(32);
  });

  it("dedupe tags are stable and key-dependent", async () => {
    const a = await keys(1);
    const b = await keys(2);
    const t = await dedupeTag(a, "revolut|1800|2026-11-08");
    expect(t).toBe(await dedupeTag(a, "revolut|1800|2026-11-08"));
    expect(t).not.toBe(await dedupeTag(b, "revolut|1800|2026-11-08"));
    expect(t).not.toBe(await dedupeTag(a, "other"));
    expect(t).toMatch(/^[A-Za-z0-9_-]{43}$/);
  });
});
