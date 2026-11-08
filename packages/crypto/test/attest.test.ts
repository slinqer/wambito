import { describe, expect, it } from "vitest";
import { deviceAttestation, verifyDeviceAttestation } from "../src/index.ts";

const dataKey = new Uint8Array(32).fill(5);
const input = {
  userId: "userOne",
  wrapId: "0194f3a2-8c00-7000-8000-000000000001",
  publicKey: new Uint8Array(32).fill(3),
};

describe("device attestation", () => {
  it("is 32 bytes and verifies", async () => {
    const att = await deviceAttestation(dataKey, input);
    expect(att).toHaveLength(32);
    expect(await verifyDeviceAttestation(dataKey, input, att)).toBe(true);
  });

  it("matches HMAC with the HKDF attest key", async () => {
    const base = await crypto.subtle.importKey("raw", dataKey, "HKDF", false, ["deriveKey"]);
    const key = await crypto.subtle.deriveKey(
      {
        name: "HKDF",
        hash: "SHA-256",
        salt: new Uint8Array(0),
        info: new TextEncoder().encode("wambito/v1/device-attest"),
      },
      base,
      { name: "HMAC", hash: "SHA-256", length: 256 },
      false,
      ["sign"],
    );
    const enc = new TextEncoder();
    const msg = new Uint8Array([
      ...enc.encode(input.userId),
      0,
      ...enc.encode(input.wrapId),
      0,
      ...input.publicKey,
    ]);
    const expected = new Uint8Array(await crypto.subtle.sign("HMAC", key, msg));
    expect(await deviceAttestation(dataKey, input)).toEqual(expected);
  });

  it("fails for another key, user, wrap, public key or length", async () => {
    const att = await deviceAttestation(dataKey, input);
    expect(await verifyDeviceAttestation(new Uint8Array(32).fill(6), input, att)).toBe(false);
    expect(await verifyDeviceAttestation(dataKey, { ...input, userId: "userTwo" }, att)).toBe(
      false,
    );
    expect(
      await verifyDeviceAttestation(
        dataKey,
        { ...input, wrapId: "0194f3a2-8c00-7000-8000-000000000002" },
        att,
      ),
    ).toBe(false);
    expect(
      await verifyDeviceAttestation(
        dataKey,
        { ...input, publicKey: new Uint8Array(32).fill(4) },
        att,
      ),
    ).toBe(false);
    expect(await verifyDeviceAttestation(dataKey, input, att.slice(0, 31))).toBe(false);
    expect(await verifyDeviceAttestation(dataKey, input, new Uint8Array(33))).toBe(false);
  });

  it("validates its inputs", async () => {
    await expect(deviceAttestation(dataKey, { ...input, userId: "a/b" })).rejects.toMatchObject({
      code: "bad_input",
    });
    await expect(
      deviceAttestation(dataKey, { ...input, wrapId: input.wrapId.toUpperCase() }),
    ).rejects.toMatchObject({ code: "bad_input" });
    await expect(
      deviceAttestation(dataKey, { ...input, publicKey: new Uint8Array(31) }),
    ).rejects.toMatchObject({ code: "bad_input" });
    await expect(deviceAttestation(new Uint8Array(31), input)).rejects.toMatchObject({
      code: "bad_input",
    });
  });
});
