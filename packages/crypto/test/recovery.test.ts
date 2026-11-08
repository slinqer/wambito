import { describe, expect, it } from "vitest";
import {
  CryptoError,
  formatRecoveryKey,
  newRecoverySecret,
  parseRecoveryKey,
} from "../src/index.ts";

const ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ*~$=U";

function code(fn: () => unknown) {
  try {
    fn();
  } catch (e) {
    return e instanceof CryptoError ? e.code : "other";
  }
  return "none";
}

describe("recovery key", () => {
  it("makes 16 random bytes", () => {
    const s = newRecoverySecret();
    expect(s).toHaveLength(16);
    expect(s).not.toEqual(newRecoverySecret());
  });

  it("formats as 26 + 1 characters in groups of four (check may be * ~ $ = U)", () => {
    for (let i = 0; i < 20; i++) {
      expect(formatRecoveryKey(newRecoverySecret())).toMatch(/^([0-9A-Z]{4}-){6}[0-9A-Z*~$=]{3}$/);
    }
  });

  it("round trips; lower case, spaces and missing dashes are accepted", () => {
    const s = newRecoverySecret();
    const t = formatRecoveryKey(s);
    expect(parseRecoveryKey(t)).toEqual(s);
    expect(parseRecoveryKey(t.toLowerCase())).toEqual(s);
    expect(parseRecoveryKey(` ${t.replace(/-/g, " ")} `)).toEqual(s);
    expect(parseRecoveryKey(t.replace(/-/g, ""))).toEqual(s);
  });

  it("all-zero and all-ones secrets round trip", () => {
    for (const fill of [0, 255]) {
      const s = new Uint8Array(16).fill(fill);
      expect(parseRecoveryKey(formatRecoveryKey(s))).toEqual(s);
    }
  });

  it("O reads as 0, I and L read as 1", () => {
    const s = new Uint8Array(16); // zero secret: all data characters are 0
    const t = formatRecoveryKey(s);
    expect(parseRecoveryKey(t.replace(/0/g, "O"))).toEqual(s);
    const ones = new Uint8Array(16).fill(0x08).fill(0x42, 0, 1);
    const tt = formatRecoveryKey(ones);
    expect(parseRecoveryKey(tt.replace(/1/g, "I"))).toEqual(ones);
    expect(parseRecoveryKey(tt.replace(/1/g, "l"))).toEqual(ones);
    expect(parseRecoveryKey(tt.replace(/0/g, "o"))).toEqual(ones);
  });

  it("one wrong character is caught by the check character", () => {
    for (let n = 0; n < 50; n++) {
      const t = formatRecoveryKey(newRecoverySecret()).replace(/-/g, "");
      for (let i = 0; i < t.length; i++) {
        for (const c of ALPHABET) {
          if (c === t[i]) continue;
          const mutated = t.slice(0, i) + c + t.slice(i + 1);
          // I/L/O are not in the alphabet, so a mutation never aliases the original.
          expect(code(() => parseRecoveryKey(mutated))).toBe("bad_recovery_key");
        }
      }
    }
  });

  it("rejects wrong length and foreign characters", () => {
    const t = formatRecoveryKey(newRecoverySecret());
    expect(code(() => parseRecoveryKey(""))).toBe("bad_recovery_key");
    expect(code(() => parseRecoveryKey(t.slice(0, -1)))).toBe("bad_recovery_key");
    expect(code(() => parseRecoveryKey(`${t}0`))).toBe("bad_recovery_key");
    expect(code(() => parseRecoveryKey(`${t.slice(0, 5)}!${t.slice(6)}`))).toBe("bad_recovery_key");
  });

  it("rejects non-16-byte secrets when formatting", () => {
    expect(code(() => formatRecoveryKey(new Uint8Array(15)))).toBe("bad_input");
  });
});
