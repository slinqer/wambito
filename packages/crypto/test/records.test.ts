import { describe, expect, it } from "vitest";
import {
  CryptoError,
  dedupeTag,
  deriveRecordKeys,
  generateDataKey,
  openRecord,
  type RecordContext,
  type RecordType,
  sealRecord,
} from "../src/index.ts";

const U1 = "0194f3a2-7b1c-7d2e-9a4f-3c5b6d7e8f90";
const U2 = "0194f3a2-7b1c-7d2e-9a4f-3c5b6d7e8f91";
const R1 = "11111111-2222-4333-8444-555555555555";
const R2 = "11111111-2222-4333-8444-555555555556";
const ctx: RecordContext = { userId: U1, type: "transaction", id: R1, keyV: 1 };
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
      { ...ctx, userId: U2 },
      { ...ctx, type: "budget" },
      { ...ctx, id: R2 },
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

  it("round-trips trailing spaces and multibyte text", async () => {
    const k = await keys();
    const v = { note: "ñ   " };
    expect(await openRecord(k, ctx, await sealRecord(k, ctx, v))).toEqual(v);
  });

  it("accepts upper-case UUIDs of any version", async () => {
    const k = await keys();
    const c: RecordContext = {
      ...ctx,
      userId: U1.toUpperCase(),
      id: "AAAAAAAA-BBBB-1CCC-8DDD-EEEEEEEEEEEE",
    };
    expect(await openRecord(k, c, await sealRecord(k, c, value))).toEqual(value);
  });

  it("rejects bad input with bad_input", async () => {
    const k = await keys();
    const body = await sealRecord(k, ctx, value);
    const badCtx: RecordContext[] = [
      { ...ctx, userId: "u1" },
      { ...ctx, id: "r1" },
      { ...ctx, id: `${R1}/x` },
      { ...ctx, keyV: -1 },
      { ...ctx, keyV: 32768 },
      { ...ctx, keyV: 1.5 },
      { ...ctx, keyV: Number.NaN },
      { ...ctx, type: "other" as RecordType },
    ];
    for (const c of badCtx) {
      expect(((await failure(sealRecord(k, c, value))) as CryptoError).code).toBe("bad_input");
      expect(((await failure(openRecord(k, c, body))) as CryptoError).code).toBe("bad_input");
    }
    for (const keyV of [0, 32767]) {
      const c = { ...ctx, keyV };
      expect(await openRecord(k, c, await sealRecord(k, c, value))).toEqual(value);
    }
    const nonce = (n: number) => sealRecord(k, ctx, value, new Uint8Array(n));
    expect(((await failure(nonce(11))) as CryptoError).code).toBe("bad_input");
    expect(((await failure(nonce(13))) as CryptoError).code).toBe("bad_input");
    expect(((await failure(sealRecord(k, ctx, undefined))) as CryptoError).code).toBe("bad_input");
    expect(((await failure(sealRecord(k, ctx, () => 1))) as CryptoError).code).toBe("bad_input");
  });
});
