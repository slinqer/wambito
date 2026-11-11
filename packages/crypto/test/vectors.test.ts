import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import {
  CryptoError,
  dedupeTag,
  deriveRecordKeys,
  deviceAttestation,
  formatRecoveryKey,
  fromBase64Url,
  importDevicePrivateKey,
  type LinkContext,
  openFromDevice,
  openFromPairing,
  openKeyLink,
  openRecord,
  pairingCommitment,
  pairingNumber,
  parseRecoveryKey,
  type RecordContext,
  sealKeyLink,
  sealRecord,
  toBase64Url,
  unwrapDataKey,
  verifyDeviceAttestation,
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
  approvals: {
    newPrivateKey: string;
    newPublicKey: string;
    commitment: string;
    approverPrivateKey: string;
    approverPublicKey: string;
    number: string;
    ctx: WrapContext;
    sealed: string;
    dataKey: string;
  }[];
  attestations: {
    dataKey: string;
    userId: string;
    wrapId: string;
    publicKey: string;
    attestation: string;
  }[];
  links: { newKey: string; oldKey: string; ctx: LinkContext; nonce: string; link: string }[];
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

  it("approvals: commitment, number, and the sealed blob open under the approver key", async () => {
    expect(vectors.approvals.length).toBeGreaterThanOrEqual(2);
    for (const p of vectors.approvals) {
      expect(toBase64Url(await pairingCommitment(b(p.newPublicKey)))).toBe(p.commitment);
      expect(await pairingNumber(b(p.newPublicKey), b(p.approverPublicKey))).toBe(p.number);
      const key = await importDevicePrivateKey(b(p.newPrivateKey));
      expect(await openFromPairing(key, p.ctx, b(p.sealed), b(p.approverPublicKey))).toEqual(
        b(p.dataKey),
      );
    }
  });

  it("attestations: the HMAC is exact and verifies", async () => {
    expect(vectors.attestations.length).toBeGreaterThanOrEqual(2);
    for (const a of vectors.attestations) {
      const input = { userId: a.userId, wrapId: a.wrapId, publicKey: b(a.publicKey) };
      expect(toBase64Url(await deviceAttestation(b(a.dataKey), input))).toBe(a.attestation);
      expect(await verifyDeviceAttestation(b(a.dataKey), input, b(a.attestation))).toBe(true);
    }
  });

  it("links: sealKeyLink is exact and openKeyLink returns oldKey", async () => {
    expect(vectors.links.length).toBeGreaterThanOrEqual(2);
    for (const l of vectors.links) {
      const link = await sealKeyLink(b(l.newKey), b(l.oldKey), l.ctx, b(l.nonce));
      expect(toBase64Url(link)).toBe(l.link);
      expect(await openKeyLink(b(l.newKey), l.ctx, b(l.link))).toEqual(b(l.oldKey));
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
        } else if (r.op === "openFromPairing") {
          await openFromPairing(
            await importDevicePrivateKey(b(r.privateKey)),
            r.ctx,
            b(r.sealed),
            b(r.approverKey),
          );
        } else if (r.op === "openKeyLink") {
          await openKeyLink(b(r.newKey), r.ctx, b(r.link));
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
