import { x25519 } from "@noble/curves/ed25519.js";
import { afterEach, describe, expect, it } from "vitest";
import { __forceX25519Backend } from "../src/devices.ts";
import {
  CryptoError,
  generateDataKey,
  generateDeviceKeyPair,
  importDevicePrivateKey,
  openFromDevice,
  sealToDevice,
  type WrapContext,
} from "../src/index.ts";

const U1 = "0194f3a2-7b1c-7d2e-9a4f-3c5b6d7e8f90";
const ctx: WrapContext = { kind: "device", userId: U1, keyV: 1 };

async function code(p: Promise<unknown>) {
  try {
    await p;
  } catch (e) {
    return e instanceof CryptoError ? e.code : "other";
  }
  return "none";
}

afterEach(() => __forceX25519Backend(null));

describe("device sealing", () => {
  it("seals to a public key and opens with the private key", async () => {
    const pair = await generateDeviceKeyPair();
    expect(pair.publicKey).toHaveLength(32);
    const dk = generateDataKey();
    const sealed = await sealToDevice(pair.publicKey, ctx, dk);
    expect(sealed).toHaveLength(32 + 12 + 32 + 16);
    expect(await openFromDevice(pair.privateKey, ctx, sealed)).toEqual(dk);
  });

  it("the private key is not extractable", async () => {
    const pair = await generateDeviceKeyPair();
    await expect(crypto.subtle.exportKey("pkcs8", pair.privateKey)).rejects.toThrow();
  });

  it("another key pair, user, key version or kind cannot open", async () => {
    const a = await generateDeviceKeyPair();
    const b = await generateDeviceKeyPair();
    const sealed = await sealToDevice(a.publicKey, ctx, generateDataKey());
    expect(await code(openFromDevice(b.privateKey, ctx, sealed))).toBe("cannot_open");
    const other = "0194f3a2-7b1c-7d2e-9a4f-3c5b6d7e8f91";
    expect(await code(openFromDevice(a.privateKey, { ...ctx, userId: other }, sealed))).toBe(
      "cannot_open",
    );
    expect(await code(openFromDevice(a.privateKey, { ...ctx, keyV: 2 }, sealed))).toBe(
      "cannot_open",
    );
  });

  it("a tampered ephemeral key, ciphertext or truncation fails", async () => {
    const a = await generateDeviceKeyPair();
    const sealed = await sealToDevice(a.publicKey, ctx, generateDataKey());
    for (const i of [0, 31, 40, 60]) {
      const t = sealed.slice();
      t[i] = (t[i] ?? 0) ^ 1;
      expect(await code(openFromDevice(a.privateKey, ctx, t))).toBe("cannot_open");
    }
    expect(await code(openFromDevice(a.privateKey, ctx, sealed.slice(0, 40)))).toBe("cannot_open");
    expect(await code(openFromDevice(a.privateKey, ctx, new Uint8Array(32)))).toBe("cannot_open");
  });

  it("validates its input", async () => {
    const a = await generateDeviceKeyPair();
    const dk = generateDataKey();
    expect(await code(sealToDevice(new Uint8Array(31), ctx, dk))).toBe("bad_input");
    expect(await code(sealToDevice(a.publicKey, { ...ctx, userId: "x" }, dk))).toBe("bad_input");
    expect(await code(sealToDevice(a.publicKey, { ...ctx, keyV: 99999 }, dk))).toBe("bad_input");
    expect(await code(sealToDevice(a.publicKey, { ...ctx, kind: "passkey" }, dk))).toBe(
      "bad_input",
    );
    expect(await code(sealToDevice(a.publicKey, ctx, new Uint8Array(16)))).toBe("bad_input");
    expect(await code(importDevicePrivateKey(new Uint8Array(31)))).toBe("bad_input");
  });

  it("imports a raw private key (native)", async () => {
    const raw = new Uint8Array(32).fill(11);
    const pub = x25519.getPublicKey(raw);
    const dk = generateDataKey();
    const key = await importDevicePrivateKey(raw);
    await expect(crypto.subtle.exportKey("pkcs8", key)).rejects.toThrow();
    expect(await openFromDevice(key, ctx, await sealToDevice(pub, ctx, dk))).toEqual(dk);
  });

  it("the noble fallback is interoperable with the native path", async () => {
    const dk = generateDataKey();
    // Native pair, sealed by noble, opened by native.
    __forceX25519Backend("native");
    const native = await generateDeviceKeyPair();
    __forceX25519Backend("noble");
    const sealedByNoble = await sealToDevice(native.publicKey, ctx, dk);
    __forceX25519Backend("native");
    expect(await openFromDevice(native.privateKey, ctx, sealedByNoble)).toEqual(dk);

    // Noble pair, sealed by native, opened by noble.
    __forceX25519Backend("noble");
    const fallback = await generateDeviceKeyPair();
    expect(fallback.publicKey).toHaveLength(32);
    __forceX25519Backend("native");
    const sealedByNative = await sealToDevice(fallback.publicKey, ctx, dk);
    __forceX25519Backend("noble");
    expect(await openFromDevice(fallback.privateKey, ctx, sealedByNative)).toEqual(dk);

    // A raw key imported on the noble path opens what native sealed to its public key.
    const raw = new Uint8Array(32).fill(21);
    const imported = await importDevicePrivateKey(raw);
    __forceX25519Backend("native");
    const toRaw = await sealToDevice(x25519.getPublicKey(raw), ctx, dk);
    __forceX25519Backend("noble");
    expect(await openFromDevice(imported, ctx, toRaw)).toEqual(dk);
  });
});
