import { afterEach, describe, expect, it, vi } from "vitest";
import {
  forgetUnlockHint,
  notePasskeyOpened,
  notePasskeyWithoutPrf,
  passkeyGaveNoPrf,
} from "./unlock-hint.ts";

function stubStorage() {
  const data = new Map<string, string>();
  vi.stubGlobal("localStorage", {
    getItem: (key: string) => data.get(key) ?? null,
    setItem: (key: string, value: string) => void data.set(key, value),
    removeItem: (key: string) => void data.delete(key),
  });
  return data;
}

afterEach(() => vi.unstubAllGlobals());

describe("the unlock hint", () => {
  it("is false until a passkey touch gave no PRF, then true", () => {
    const data = stubStorage();
    expect(passkeyGaveNoPrf("u1")).toBe(false);
    notePasskeyWithoutPrf("u1");
    expect(passkeyGaveNoPrf("u1")).toBe(true);
    expect(data.get("wambito.unlock.no-prf.u1")).toBe("1");
  });

  it("is cleared when a passkey opens the data, and by forget", () => {
    stubStorage();
    notePasskeyWithoutPrf("u1");
    notePasskeyOpened("u1");
    expect(passkeyGaveNoPrf("u1")).toBe(false);
    notePasskeyWithoutPrf("u1");
    forgetUnlockHint("u1");
    expect(passkeyGaveNoPrf("u1")).toBe(false);
  });

  it("is per user", () => {
    stubStorage();
    notePasskeyWithoutPrf("u1");
    expect(passkeyGaveNoPrf("u2")).toBe(false);
    notePasskeyWithoutPrf("u2");
    notePasskeyOpened("u1");
    expect(passkeyGaveNoPrf("u1")).toBe(false);
    expect(passkeyGaveNoPrf("u2")).toBe(true);
  });

  it("a throwing localStorage reads false and never throws", () => {
    const boom = () => {
      throw new Error("blocked");
    };
    vi.stubGlobal("localStorage", { getItem: boom, setItem: boom, removeItem: boom });
    expect(passkeyGaveNoPrf("u1")).toBe(false);
    expect(() => notePasskeyWithoutPrf("u1")).not.toThrow();
    expect(() => notePasskeyOpened("u1")).not.toThrow();
    expect(() => forgetUnlockHint("u1")).not.toThrow();
  });
});
