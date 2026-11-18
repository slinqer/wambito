import { describe, expect, it } from "vitest";
import { protectStatus } from "./protect-model.ts";

const nothing = {
  anonymous: true,
  recoveryKeySavedAt: null,
  passkeyWrap: false,
  passkeyWithoutWrap: false,
  passkeysSupported: true,
};

describe("protectStatus", () => {
  it("null for an account with an email", () => {
    expect(protectStatus({ ...nothing, anonymous: false })).toBeNull();
    expect(
      protectStatus({ ...nothing, anonymous: false, recoveryKeySavedAt: "2026-11-18T10:00:00Z" }),
    ).toBeNull();
  });

  it("0 of 2 with nothing", () => {
    expect(protectStatus(nothing)).toEqual({
      show: true,
      recoveryKey: false,
      passkey: false,
      passkeyOffered: true,
      passkeyWithoutPrf: false,
      done: 0,
      protected: false,
    });
  });

  it("a passkey without a wrap is not done and sets passkeyWithoutPrf", () => {
    const status = protectStatus({ ...nothing, passkeyWithoutWrap: true });
    expect(status).toMatchObject({ passkey: false, passkeyWithoutPrf: true, done: 0 });
    expect(status?.protected).toBe(false);
    // another passkey's wrap counts: nothing to warn about then
    expect(
      protectStatus({ ...nothing, passkeyWithoutWrap: true, passkeyWrap: true }),
    ).toMatchObject({ passkey: true, passkeyWithoutPrf: false, done: 1 });
  });

  it("the passkey step is absent without passkey support", () => {
    const status = protectStatus({
      ...nothing,
      passkeysSupported: false,
      passkeyWithoutWrap: true,
    });
    expect(status).toMatchObject({ passkeyOffered: false, passkeyWithoutPrf: false, done: 0 });
  });

  it("protected once either is done", () => {
    const key = protectStatus({ ...nothing, recoveryKeySavedAt: "2026-11-18T10:00:00Z" });
    expect(key).toMatchObject({ recoveryKey: true, done: 1, protected: true, show: false });
    const passkey = protectStatus({ ...nothing, passkeyWrap: true });
    expect(passkey).toMatchObject({ passkey: true, done: 1, protected: true, show: false });
    const both = protectStatus({
      ...nothing,
      recoveryKeySavedAt: "2026-11-18T10:00:00Z",
      passkeyWrap: true,
    });
    expect(both).toMatchObject({ done: 2, protected: true, show: false });
  });
});
