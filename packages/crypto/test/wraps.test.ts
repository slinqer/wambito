import { describe, expect, it } from "vitest";
import {
  CryptoError,
  generateDataKey,
  PRF_SALT,
  unwrapDataKey,
  type WrapContext,
  type WrapKind,
  wrapDataKey,
} from "../src/index.ts";

const U1 = "0194f3a2-7b1c-7d2e-9a4f-3c5b6d7e8f90";
const U2 = "0194f3a2-7b1c-7d2e-9a4f-3c5b6d7e8f91";
const kinds: WrapKind[] = ["passkey", "recovery", "assistant"];
const secret = new Uint8Array(32).fill(3);
const secretFor = (kind: WrapKind) => new Uint8Array(kind === "recovery" ? 16 : 32).fill(3);

async function code(p: Promise<unknown>) {
  try {
    await p;
  } catch (e) {
    return e instanceof CryptoError ? e.code : "other";
  }
  return "none";
}

describe("wraps", () => {
  it("PRF_SALT is SHA-256 of the fixed string", async () => {
    const h = await crypto.subtle.digest("SHA-256", new TextEncoder().encode("wambito/v1/prf"));
    expect(PRF_SALT).toHaveLength(32);
    expect(PRF_SALT).toEqual(new Uint8Array(h));
  });

  it("round trips per kind with the layout nonce || ciphertext+tag", async () => {
    for (const kind of kinds) {
      const ctx: WrapContext = { kind, userId: U1, keyV: 1 };
      const dk = generateDataKey();
      const wrapped = await wrapDataKey(secretFor(kind), ctx, dk);
      expect(wrapped).toHaveLength(12 + 32 + 16);
      expect(await unwrapDataKey(secretFor(kind), ctx, wrapped)).toEqual(dk);
    }
  });

  it("uses the given nonce", async () => {
    const nonce = new Uint8Array(12).fill(5);
    const w = await wrapDataKey(
      secretFor("recovery"),
      { kind: "recovery", userId: U1, keyV: 1 },
      generateDataKey(),
      nonce,
    );
    expect(w.slice(0, 12)).toEqual(nonce);
  });

  it("wrong secret, user, key version or kind cannot open", async () => {
    const ctx: WrapContext = { kind: "passkey", userId: U1, keyV: 1 };
    const w = await wrapDataKey(secret, ctx, generateDataKey());
    expect(await code(unwrapDataKey(new Uint8Array(32).fill(4), ctx, w))).toBe("cannot_open");
    expect(await code(unwrapDataKey(secret, { ...ctx, userId: U2 }, w))).toBe("cannot_open");
    expect(await code(unwrapDataKey(secret, { ...ctx, keyV: 2 }, w))).toBe("cannot_open");
    expect(await code(unwrapDataKey(secret, { ...ctx, kind: "assistant" }, w))).toBe("cannot_open");
    const flipped = w.slice();
    flipped[20] = (flipped[20] ?? 0) ^ 1;
    expect(await code(unwrapDataKey(secret, ctx, flipped))).toBe("cannot_open");
    expect(await code(unwrapDataKey(secret, ctx, w.slice(0, 10)))).toBe("cannot_open");
  });

  it("validates its input", async () => {
    const ctx: WrapContext = { kind: "passkey", userId: U1, keyV: 1 };
    const dk = generateDataKey();
    const w = await wrapDataKey(secret, ctx, dk);
    const bad: WrapContext[] = [
      { ...ctx, userId: "nope" },
      { ...ctx, keyV: -1 },
      { ...ctx, keyV: 32768 },
      { ...ctx, keyV: 0.5 },
      { ...ctx, kind: "other" as WrapKind },
      { ...ctx, kind: "device" },
    ];
    for (const c of bad) {
      expect(await code(wrapDataKey(secret, c, dk))).toBe("bad_input");
      expect(await code(unwrapDataKey(secret, c, w))).toBe("bad_input");
    }
    expect(await code(wrapDataKey(secret, ctx, new Uint8Array(31)))).toBe("bad_input");
    expect(await code(wrapDataKey(new Uint8Array(0), ctx, dk))).toBe("bad_input");
    expect(await code(wrapDataKey(new Uint8Array(16), ctx, dk))).toBe("bad_input");
    const rec: WrapContext = { ...ctx, kind: "recovery" };
    expect(await code(wrapDataKey(new Uint8Array(32), rec, dk))).toBe("bad_input");
    expect(await code(unwrapDataKey(new Uint8Array(32), rec, w))).toBe("bad_input");
    expect(await code(wrapDataKey(new Uint8Array(16), rec, dk))).toBe("none");
    expect(await code(wrapDataKey(new Uint8Array(31), { ...ctx, kind: "assistant" }, dk))).toBe(
      "bad_input",
    );
    expect(await code(wrapDataKey(secret, ctx, dk, new Uint8Array(8)))).toBe("bad_input");
  });
});
