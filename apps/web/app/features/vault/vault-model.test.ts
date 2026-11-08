import { describe, expect, it } from "vitest";
import {
  charsAt,
  confirmationMatches,
  groupPosition,
  pickPositions,
  recoveryFileText,
} from "./vault-model.ts";

const KEY = "ABCD-EFGH-JKMN-PQRS-TVWX-YZ01-234";

describe("pickPositions", () => {
  it("returns four distinct ascending positions among the 26 data characters", () => {
    for (let i = 0; i < 50; i++) {
      const p = pickPositions();
      expect(p).toHaveLength(4);
      expect([...p].sort((a, b) => a - b)).toEqual(p);
      expect(new Set(p).size).toBe(4);
      for (const n of p) {
        expect(n).toBeGreaterThanOrEqual(1);
        expect(n).toBeLessThanOrEqual(26);
      }
    }
  });
});

describe("groupPosition", () => {
  it("names a position by its group of four and its place in it", () => {
    expect([1, 4, 5, 6, 14, 26].map(groupPosition)).toEqual([
      { group: 1, char: 1 },
      { group: 1, char: 4 },
      { group: 2, char: 1 },
      { group: 2, char: 2 },
      { group: 4, char: 2 },
      { group: 7, char: 2 },
    ]);
  });
});

describe("charsAt", () => {
  it("reads 1-based positions ignoring the dashes", () => {
    expect(charsAt(KEY, [1, 5, 9, 26])).toEqual(["A", "E", "J", "3"]);
  });
});

describe("confirmationMatches", () => {
  it("accepts any case, and O or I typed for 0 or 1", () => {
    expect(confirmationMatches(KEY, [1, 5, 9, 26], ["a", "e", "j", "3"])).toBe(true);
    expect(confirmationMatches(KEY, [23, 24], ["o", "i"])).toBe(true);
    expect(confirmationMatches(KEY, [23, 24], ["0", "L"])).toBe(true);
  });
  it("rejects blanks and wrong characters", () => {
    expect(confirmationMatches(KEY, [1, 5], ["A", ""])).toBe(false);
    expect(confirmationMatches(KEY, [1, 5], ["A", "X"])).toBe(false);
  });
});

describe("recoveryFileText", () => {
  it("holds the key, a short line and the date, and nothing else", () => {
    const text = recoveryFileText({ title: "T", key: KEY, line: "L", date: "D" });
    expect(text).toBe(`T\n\n${KEY}\n\nL\nD\n`);
  });
});
