import { afterEach, describe, expect, it, vi } from "vitest";
import { KeysError } from "../../local/keys.ts";

const live = vi.hoisted(() => ({
  hasPasskeyWrap: vi.fn<(options: { userId: string }) => Promise<boolean>>(),
  forgetVault: vi.fn(async () => {}),
  removedListeners: [] as (() => void)[],
}));

vi.mock("../../local/keys.ts", async (actual) => ({
  ...(await actual<typeof import("../../local/keys.ts")>()),
  loadLocalKeys: vi.fn(async () => ({ kept: true })),
  hasPasskeyWrap: live.hasPasskeyWrap,
}));

vi.mock("../../local/vault-session.ts", async (actual) => ({
  ...(await actual<typeof import("../../local/vault-session.ts")>()),
  forgetVault: live.forgetVault,
  openVaultSession: vi.fn(async () => ({
    onRemoved: (cb: () => void) => {
      live.removedListeners.push(cb);
      return () => {};
    },
  })),
}));

import { gateFor } from "./VaultGate.tsx";

const PROFILE = {
  id: "u-1",
  email: "ana@example.test",
  isAnonymous: false,
  timezone: "Europe/Madrid",
} as Parameters<typeof gateFor>[0];

const settle = () => new Promise((resolve) => setTimeout(resolve, 0));

describe("the live vault gate", () => {
  afterEach(() => {
    vi.unstubAllGlobals();
    live.hasPasskeyWrap.mockReset();
    live.forgetVault.mockClear();
  });

  it("a removal whose wraps read answers 401 shows Unlock with the removed notice, and never signs in again", async () => {
    const assign = vi.fn();
    vi.stubGlobal("window", { location: { assign, pathname: "/app", search: "", hash: "" } });
    // The removal ended this session: `GET /v2/keys` answers 401.
    live.hasPasskeyWrap.mockRejectedValue(new KeysError("server", 401));
    const gate = gateFor(PROFILE);
    gate.start();
    await settle();
    expect(gate.getState().status).toBe("ready");

    await gate.removed();
    await settle();
    expect(gate.getState()).toEqual({
      status: "unlock",
      notice: "removed",
      means: { noPrfHere: false, passkeyWrap: true },
    });
    expect(live.hasPasskeyWrap).toHaveBeenCalled();
    // No wipe and no trip to sign-in: the notice is what the person sees.
    expect(live.forgetVault).not.toHaveBeenCalled();
    expect(assign).not.toHaveBeenCalled();
  });
});
