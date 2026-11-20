import { describe, expect, it, vi } from "vitest";
import { KeysError } from "../../local/keys.ts";
import { type ConsentKeysDeps, consentKeysOf } from "./consent-keys.ts";

const MEANS = { noPrfHere: false, passkeyWrap: true };
const passkey = () => ({ credentialId: "cred-1", prf: new Uint8Array(32).fill(7) });

function keysWith(overrides: Partial<ConsentKeysDeps> = {}) {
  const deps: ConsentKeysDeps = {
    withDataKeyFrom: vi.fn(async (_options, _source, fn) => fn(new Uint8Array(32), 1)),
    evaluatePrf: vi.fn(async () => passkey()),
    accountPasskeyIds: vi.fn(async () => ["cred-1"]),
    notePasskeyWithoutPrf: vi.fn(),
    notePasskeyOpened: vi.fn(),
    ...overrides,
  };
  return { deps, keys: consentKeysOf({ userId: "u-1", device: false, means: MEANS }, deps) };
}

describe("the consent page's keys", () => {
  it("a touch offers only the account's passkeys", async () => {
    const { deps, keys } = keysWith();
    expect(await keys.touchPasskey()).toEqual(passkey());
    expect(deps.evaluatePrf).toHaveBeenCalledWith(["cred-1"]);
  });

  it("an account without passkeys is no_passkey_wrap, with no touch", async () => {
    const { deps, keys } = keysWith({ accountPasskeyIds: async () => [] });
    await expect(keys.touchPasskey()).rejects.toMatchObject({ code: "no_passkey_wrap" });
    expect(deps.evaluatePrf).not.toHaveBeenCalled();
  });

  it("a touch without PRF notes the hint for the signed-in account, so a reload leads with the key", async () => {
    const { deps, keys } = keysWith({
      evaluatePrf: async () => {
        throw new KeysError("no_prf");
      },
    });
    await expect(keys.touchPasskey()).rejects.toMatchObject({ code: "no_prf" });
    expect(deps.notePasskeyWithoutPrf).toHaveBeenCalledWith("u-1");
  });

  it("an unreadable passkey list still asks, and a touch without PRF then notes nothing", async () => {
    const { deps, keys } = keysWith({
      accountPasskeyIds: async () => {
        throw new Error("passkeys_unavailable");
      },
      evaluatePrf: vi.fn(async () => {
        throw new KeysError("no_prf");
      }),
    });
    await expect(keys.touchPasskey()).rejects.toMatchObject({ code: "no_prf" });
    expect(deps.evaluatePrf).toHaveBeenCalledWith(undefined);
    expect(deps.notePasskeyWithoutPrf).not.toHaveBeenCalled();
  });

  it("a cancelled touch notes nothing", async () => {
    const { deps, keys } = keysWith({ evaluatePrf: async () => null });
    expect(await keys.touchPasskey()).toBeNull();
    expect(deps.notePasskeyWithoutPrf).not.toHaveBeenCalled();
  });

  it("a passkey's PRF that opens the data clears the hint; the recovery key or the device does not", async () => {
    const { deps, keys } = keysWith();
    const fn = vi.fn(async () => "done");
    expect(await keys.open(passkey(), fn)).toBe("done");
    expect(deps.notePasskeyOpened).toHaveBeenCalledWith("u-1");
    expect(deps.withDataKeyFrom).toHaveBeenCalledWith(
      { userId: "u-1" },
      passkey(),
      expect.any(Function),
    );

    vi.mocked(deps.notePasskeyOpened).mockClear();
    await keys.open({ recovery: "ABCD" }, fn);
    await keys.open({ device: true }, fn);
    expect(deps.notePasskeyOpened).not.toHaveBeenCalled();
  });

  it("a passkey whose PRF opens nothing keeps the hint", async () => {
    const { deps, keys } = keysWith({
      withDataKeyFrom: async () => {
        throw new KeysError("no_passkey_wrap");
      },
    });
    await expect(keys.open(passkey(), async () => "done")).rejects.toMatchObject({
      code: "no_passkey_wrap",
    });
    expect(deps.notePasskeyOpened).not.toHaveBeenCalled();
  });

  it("carries the account, the device and the means", () => {
    const { keys } = keysWith();
    expect(keys).toMatchObject({ userId: "u-1", device: false, means: MEANS });
  });
});
