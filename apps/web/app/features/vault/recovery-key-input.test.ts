import { describe, expect, it } from "vitest";
import { groupRecoveryKey, groupRecoveryKeyEdit, isFullRecoveryKey } from "./recovery-key-input.ts";

const FULL = "ABCD-EFGH-2345-6789-ABCD-EFGH-234";

describe("groupRecoveryKey", () => {
  it("groups while typing", () => {
    expect(groupRecoveryKey("abcd2")).toBe("ABCD-2");
  });

  it("regroups a paste in any shape", () => {
    expect(groupRecoveryKey("abcd efgh\n2345-6789 abcd efgh 234 ")).toBe(FULL);
  });

  it("keeps O, I and L, drops what the alphabet lacks", () => {
    expect(groupRecoveryKey("o0il!?")).toBe("O0IL");
    expect(groupRecoveryKey("uU")).toBe("");
  });

  it("never grows past a full key", () => {
    expect(groupRecoveryKey(`${FULL}-5678`)).toBe(FULL);
    expect(groupRecoveryKey("a".repeat(60))).toHaveLength(33);
  });
});

describe("groupRecoveryKeyEdit", () => {
  it("deleting just after a dash removes the character before it and keeps the caret", () => {
    // "ABCD-E" with the caret after the dash: Backspace removed the dash only. The character
    // before it goes instead, the rest regroups and the caret stays after "ABC".
    expect(groupRecoveryKeyEdit("ABCD-E", "ABCDE", 4)).toEqual({ text: "ABCE", caret: 3 });
  });

  it("typing in the middle keeps the caret after the typed character", () => {
    expect(groupRecoveryKeyEdit("ABCD-EFGH", "ABCXD-EFGH", 4)).toEqual({
      text: "ABCX-DEFG-H",
      caret: 4,
    });
    // the typed character lands right before a dash that regrouping moves: caret after the dash
    expect(groupRecoveryKeyEdit("ABCD-EFGH", "ABCDX-EFGH", 5)).toEqual({
      text: "ABCD-XEFG-H",
      caret: 6,
    });
  });

  it("appending at the end puts the caret at the end", () => {
    expect(groupRecoveryKeyEdit("ABCD", "ABCDE", 5)).toEqual({ text: "ABCD-E", caret: 6 });
  });

  it("a paste puts the caret at the end of what was kept", () => {
    expect(groupRecoveryKeyEdit("", "abcd efgh", 9)).toEqual({ text: "ABCD-EFGH", caret: 9 });
  });
});

describe("isFullRecoveryKey", () => {
  it("is true only at 27 characters", () => {
    expect(isFullRecoveryKey(FULL)).toBe(true);
    expect(isFullRecoveryKey(FULL.slice(0, -1))).toBe(false);
    expect(isFullRecoveryKey("")).toBe(false);
  });
});
