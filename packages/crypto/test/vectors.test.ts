import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import {
  CryptoError,
  dedupeTag,
  deriveRecordKeys,
  formatRecoveryKey,
  fromBase64Url,
  importDevicePrivateKey,
  openFromDevice,
  openRecord,
  pairingNumber,
  parseRecoveryKey,
  type RecordContext,
  sealRecord,
  toBase64Url,
  unwrapDataKey,
  type WrapContext,
  wrapDataKey,
} from "../src/index.ts";

const vectors = JSON.parse(
  readFileSync(new URL("../test-vectors.json", import.meta.url), "utf8"),
) as {
  _about: string;
  records: {
    dataKey: string;
    ctx: RecordContext;
    nonce: string;
    value: unknown;
    body: string;
    dedupe: { text: string; tag: string };
  }[];
  wraps: {
    secret: string;
    ctx: WrapContext;
    nonce: string;
    dataKey: string;
    wrapped: string;
  }[];
  recovery: { secret: string; text: string }[];
  devices: {
    privateKey: string;
    publicKey: string;
    ctx: WrapContext;
    sealed: string;
    dataKey: string;
  }[];
  pairing: { a: string; b: string; number: string }[];
  rejects: Record<string, unknown>[];
};

const b = fromBase64Url;

describe("shared test vectors", () => {
  it("has the documented shape and coverage", () => {
    expect(vectors._about).toMatch(/never edit/i);
    expect(vectors.records.length).toBeGreaterThanOrEqual(3);
    expect(vectors.records.some((r) => /[^\x00-\x7f]/.test(JSON.stringify(r.value)))).toBe(true);
    expect(
      vectors.records.some((r) => new TextEncoder().encode(JSON.stringify(r.value)).length === 64),
    ).toBe(true);
    expect(new Set(vectors.wraps.map((w) => w.ctx.kind))).toEqual(
      new Set(["passkey", "recovery", "assistant"]),
    );
    expect(vectors.devices.length).toBeGreaterThanOrEqual(2);
    expect(vectors.rejects.length).toBeGreaterThanOrEqual(4);
  });

  it("records: seal with the fixed nonce is exact, open gives the value", async () => {
    for (const r of vectors.records) {
      const keys = await deriveRecordKeys(b(r.dataKey));
      const body = await sealRecord(keys, r.ctx, r.value, b(r.nonce));
      expect(toBase64Url(body)).toBe(r.body);
      expect(await openRecord(keys, r.ctx, b(r.body))).toEqual(r.value);
      expect(await dedupeTag(keys, r.dedupe.text)).toBe(r.dedupe.tag);
    }
  });

  it("wraps: wrap with the fixed nonce is exact, unwrap gives the data key", async () => {
    for (const w of vectors.wraps) {
      const wrapped = await wrapDataKey(b(w.secret), w.ctx, b(w.dataKey), b(w.nonce));
      expect(toBase64Url(wrapped)).toBe(w.wrapped);
      expect(await unwrapDataKey(b(w.secret), w.ctx, b(w.wrapped))).toEqual(b(w.dataKey));
    }
  });

  it("recovery: text and secret match both ways", () => {
    for (const r of vectors.recovery) {
      expect(parseRecoveryKey(r.text)).toEqual(b(r.secret));
      expect(formatRecoveryKey(b(r.secret))).toBe(r.text);
    }
  });

  it("devices: the sealed blob opens to the data key", async () => {
    for (const d of vectors.devices) {
      const key = await importDevicePrivateKey(b(d.privateKey));
      expect(await openFromDevice(key, d.ctx, b(d.sealed))).toEqual(b(d.dataKey));
    }
  });

  it("pairing: numbers match from either side", async () => {
    for (const p of vectors.pairing) {
      expect(await pairingNumber(b(p.a), b(p.b))).toBe(p.number);
      expect(await pairingNumber(b(p.b), b(p.a))).toBe(p.number);
    }
  });

  it("rejects: every input is refused with the expected code", async () => {
    for (const r of vectors.rejects as { op: string; code: string; [k: string]: any }[]) {
      let got = "none";
      try {
        if (r.op === "sealRecord") {
          const keys = await deriveRecordKeys(b(r.dataKey));
          await sealRecord(keys, r.ctx, r.value, b(r.nonce));
        } else if (r.op === "wrapDataKey") {
          await wrapDataKey(b(r.secret), r.ctx, b(r.dataKey), b(r.nonce));
        } else if (r.op === "parseRecoveryKey") {
          parseRecoveryKey(r.text);
        } else {
          throw new Error(`unknown op ${r.op}`);
        }
      } catch (e) {
        got = e instanceof CryptoError ? e.code : `other: ${e}`;
      }
      expect(got, r.name).toBe(r.code);
    }
  });
});
