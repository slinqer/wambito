import { describe, expect, it } from "vitest";
import { pairingCode, pairingNumber } from "../src/index.ts";

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
