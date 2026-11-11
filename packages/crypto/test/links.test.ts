import { describe, expect, it } from "vitest";
import {
  CryptoError,
  generateDataKey,
  LINK_BYTES,
  type LinkContext,
  openKeyLink,
  sealKeyLink,
} from "../src/index.ts";

const USER = "kX3mQ9vTz2LpR8wYb5NcHd7JfA1sUe4B";
const ctx: LinkContext = { userId: USER, keyV: 2 };

async function code(p: Promise<unknown>): Promise<string> {
  try {
    await p;
    return "none";
  } catch (e) {
    return e instanceof CryptoError ? e.code : `other: ${e}`;
  }
}

describe("key links", () => {
  it("a link opens to the older key", async () => {
    const newKey = generateDataKey();
    const oldKey = generateDataKey();
    const link = await sealKeyLink(newKey, oldKey, ctx);
    expect(link.length).toBe(LINK_BYTES);
    expect(LINK_BYTES).toBe(60);
    expect(await openKeyLink(newKey, ctx, link)).toEqual(oldKey);
  });

  it("a link does not open under another key, version or account, or with a flipped byte", async () => {
    const newKey = generateDataKey();
    const link = await sealKeyLink(newKey, generateDataKey(), ctx);
    expect(await code(openKeyLink(generateDataKey(), ctx, link))).toBe("cannot_open");
    expect(await code(openKeyLink(newKey, { ...ctx, keyV: 3 }, link))).toBe("cannot_open");
    expect(
      await code(openKeyLink(newKey, { ...ctx, userId: "Zq8Rt2WnY5vLc1MbXe9HjD4sAf7GuK0p" }, link)),
    ).toBe("cannot_open");
    for (const i of [0, 12, 59]) {
      const bad = link.slice();
      bad[i] = (bad[i] ?? 0) ^ 1;
      expect(await code(openKeyLink(newKey, ctx, bad))).toBe("cannot_open");
    }
  });

  it("keyV below 2, a bad user id, keys that are not 32 bytes or a link that is not 60 bytes is bad_input", async () => {
    const k = generateDataKey();
    const link = await sealKeyLink(k, generateDataKey(), ctx);
    for (const keyV of [0, 1, -1, 1.5, 32768]) {
      expect(await code(sealKeyLink(k, k, { ...ctx, keyV }))).toBe("bad_input");
      expect(await code(openKeyLink(k, { ...ctx, keyV }, link))).toBe("bad_input");
    }
    expect(await code(sealKeyLink(k, k, { ...ctx, userId: "a/b" }))).toBe("bad_input");
    expect(await code(openKeyLink(k, { ...ctx, userId: "" }, link))).toBe("bad_input");
    expect(await code(sealKeyLink(k.slice(0, 31), k, ctx))).toBe("bad_input");
    expect(await code(sealKeyLink(k, k.slice(0, 31), ctx))).toBe("bad_input");
    expect(await code(openKeyLink(k.slice(0, 31), ctx, link))).toBe("bad_input");
    expect(await code(openKeyLink(k, ctx, link.slice(0, 59)))).toBe("bad_input");
    expect(await code(openKeyLink(k, ctx, new Uint8Array(61)))).toBe("bad_input");
    expect(await code(sealKeyLink(k, k, ctx, new Uint8Array(11)))).toBe("bad_input");
  });
});
