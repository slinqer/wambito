import { describe, expect, it } from "vitest";
import {
  generateDeviceKeyPair,
  openFromDevice,
  openFromPairing,
  pairingCode,
  pairingCommitment,
  pairingNumber,
  sealToDevice,
} from "../src/index.ts";

describe("pairing", () => {
  it("codes are 8 Crockford characters", () => {
    const seen = new Set<string>();
    for (let i = 0; i < 200; i++) {
      const c = pairingCode();
      expect(c).toMatch(/^[0-9A-HJKMNP-TV-Z]{8}$/);
      seen.add(c);
    }
    expect(seen.size).toBeGreaterThan(190);
  });

  it("the number is the same from both sides, 6 digits", async () => {
    const a = crypto.getRandomValues(new Uint8Array(32));
    const b = crypto.getRandomValues(new Uint8Array(32));
    const n = await pairingNumber(a, b);
    expect(n).toBe(await pairingNumber(b, a));
    expect(n).toMatch(/^\d{6}$/);
  });

  it("keeps leading zeros and depends on both keys", async () => {
    const seen = new Set<string>();
    let zero = 0;
    for (let i = 0; i < 400; i++) {
      const n = await pairingNumber(
        crypto.getRandomValues(new Uint8Array(32)),
        crypto.getRandomValues(new Uint8Array(32)),
      );
      expect(n).toHaveLength(6);
      if (n.startsWith("0")) zero++;
      seen.add(n);
    }
    expect(zero).toBeGreaterThan(0);
    expect(seen.size).toBeGreaterThan(300);
    const a = new Uint8Array(32).fill(1);
    expect(await pairingNumber(a, new Uint8Array(32).fill(2))).not.toBe(
      await pairingNumber(a, new Uint8Array(32).fill(3)),
    );
  });
});

describe("pairingCommitment", () => {
  it("is SHA-256 of the label and the key", async () => {
    const key = new Uint8Array(32).fill(7);
    const input = new Uint8Array([
      ...new TextEncoder().encode("wambito/v1/pairing-commit"),
      ...key,
    ]);
    const expected = new Uint8Array(await crypto.subtle.digest("SHA-256", input));
    expect(await pairingCommitment(key)).toEqual(expected);
  });

  it("is 32 bytes, depends on the key and rejects other lengths", async () => {
    const a = await pairingCommitment(new Uint8Array(32).fill(1));
    expect(a).toHaveLength(32);
    expect(a).not.toEqual(await pairingCommitment(new Uint8Array(32).fill(2)));
    await expect(pairingCommitment(new Uint8Array(31))).rejects.toMatchObject({
      code: "bad_input",
    });
  });
});

describe("openFromPairing", () => {
  const ctx = { kind: "device", userId: "userOne", keyV: 2 } as const;
  const dataKey = new Uint8Array(32).fill(9);

  it("opens a seal made with the approver's ephemeral key", async () => {
    const n = await generateDeviceKeyPair();
    const a = await generateDeviceKeyPair();
    const sealed = await sealToDevice(n.publicKey, ctx, dataKey, a);
    expect(sealed.slice(0, 32)).toEqual(a.publicKey);
    expect(await openFromPairing(n.privateKey, ctx, sealed, a.publicKey)).toEqual(dataKey);
  });

  it("refuses a blob whose ephemeral key is not the approver key", async () => {
    const n = await generateDeviceKeyPair();
    const a = await generateDeviceKeyPair();
    const other = await generateDeviceKeyPair();
    const sealed = await sealToDevice(n.publicKey, ctx, dataKey, other);
    await expect(openFromPairing(n.privateKey, ctx, sealed, a.publicKey)).rejects.toMatchObject({
      code: "cannot_open",
    });
    // openFromDevice would have accepted it
    expect(await openFromDevice(n.privateKey, ctx, sealed)).toEqual(dataKey);
  });

  it("refuses a sealed blob that is not bytes", async () => {
    const n = await generateDeviceKeyPair();
    const a = await generateDeviceKeyPair();
    for (const bad of ["text", null, undefined, [1, 2, 3]]) {
      await expect(
        openFromPairing(n.privateKey, ctx, bad as unknown as Uint8Array, a.publicKey),
      ).rejects.toMatchObject({ code: "bad_input" });
    }
  });

  it("sealToDevice without an ephemeral still makes a fresh key each time", async () => {
    const n = await generateDeviceKeyPair();
    const s1 = await sealToDevice(n.publicKey, ctx, dataKey);
    const s2 = await sealToDevice(n.publicKey, ctx, dataKey);
    expect(s1.slice(0, 32)).not.toEqual(s2.slice(0, 32));
  });
});
