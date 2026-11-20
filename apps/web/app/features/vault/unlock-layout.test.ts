import { describe, expect, it } from "vitest";
import { unlockLayout } from "./unlock-layout.ts";

const base = { noPrfHere: false, passkeyWrap: false, passkeysSupported: false, canPair: false };

describe("unlockLayout", () => {
  it("no PRF here: the key is main, another passkey is under more only with a passkey wrap", () => {
    const input = { ...base, noPrfHere: true, passkeysSupported: true, canPair: true };
    expect(unlockLayout({ ...input, passkeyWrap: true })).toEqual({
      main: "key",
      below: ["pair"],
      more: ["passkey"],
    });
    expect(unlockLayout({ ...input, passkeyWrap: false })).toEqual({
      main: "key",
      below: ["pair"],
      more: [],
    });
    expect(unlockLayout({ ...input, passkeyWrap: true, canPair: false })).toEqual({
      main: "key",
      below: [],
      more: ["passkey"],
    });
  });

  it("a passkey wrap and passkey support: the passkey is main, the key under more", () => {
    expect(
      unlockLayout({ ...base, passkeyWrap: true, passkeysSupported: true, canPair: true }),
    ).toEqual({ main: "passkey", below: ["pair"], more: ["key"] });
    expect(unlockLayout({ ...base, passkeyWrap: true, passkeysSupported: true })).toEqual({
      main: "passkey",
      below: [],
      more: ["key"],
    });
  });

  it("no passkey wrap: pairing is main, the key under more", () => {
    expect(unlockLayout({ ...base, passkeysSupported: true, canPair: true })).toEqual({
      main: "pair",
      below: [],
      more: ["key"],
    });
  });

  it("no passkey support with a wrap: pairing main, key under more", () => {
    expect(unlockLayout({ ...base, passkeyWrap: true, canPair: true })).toEqual({
      main: "pair",
      below: [],
      more: ["key"],
    });
  });

  it("nothing above more (no pairing, no passkey): the key is main and more is empty", () => {
    expect(unlockLayout(base)).toEqual({ main: "key", below: [], more: [] });
    expect(unlockLayout({ ...base, passkeysSupported: true })).toEqual({
      main: "key",
      below: [],
      more: [],
    });
  });
});
