import { describe, expect, it, vi } from "vitest";
import { createVaultGate, type VaultGateDeps, type VaultGateState } from "./vault-gate.ts";

type Keys = { k: string };
type Session = { id: string };

const fail = (code: string) => Object.assign(new Error(code), { code });

/** Lets every pending promise settle. */
const settle = () => new Promise((resolve) => setTimeout(resolve, 0));

function gateWith(overrides: Partial<VaultGateDeps<Keys, Session>> = {}) {
  const deps: VaultGateDeps<Keys, Session> = {
    loadLocalKeys: vi.fn(async () => null),
    prepareAccount: vi.fn(async () => ({
      recoveryKey: "ABCD-EFGH",
      commit: vi.fn(async () => ({ k: "new" })),
    })),
    unlockWithRecovery: vi.fn(async () => ({ k: "unlocked" })),
    open: vi.fn(async (keys: Keys) => ({ id: keys.k })),
    ...overrides,
  };
  const gate = createVaultGate(deps);
  const seen: VaultGateState<Session>["status"][] = [];
  gate.subscribe(() => seen.push(gate.getState().status));
  return { gate, deps, seen };
}

describe("vault gate", () => {
  it("opens a known browser with its kept keys, without waiting for the network", async () => {
    const { gate, deps, seen } = gateWith({ loadLocalKeys: async () => ({ k: "kept" }) });
    gate.start();
    await settle();
    expect(gate.getState()).toEqual({ status: "ready", session: { id: "kept" } });
    expect(deps.open).toHaveBeenCalledWith({ k: "kept" }, false);
    expect(deps.prepareAccount).not.toHaveBeenCalled();
    expect(seen).toEqual(["checking", "opening", "ready"]);
  });

  it("a new account shows the key and sends nothing until the person confirms", async () => {
    const commit = vi.fn(async () => ({ k: "new" }));
    const { gate, deps } = gateWith({
      prepareAccount: async () => ({ recoveryKey: "ABCD-EFGH", commit }),
    });
    gate.start();
    await settle();
    expect(gate.getState()).toEqual({ status: "setup", recoveryKey: "ABCD-EFGH" });
    expect(commit).not.toHaveBeenCalled();

    await gate.confirmSetup();
    expect(commit).toHaveBeenCalledTimes(1);
    expect(deps.open).toHaveBeenCalledWith({ k: "new" }, true);
    expect(gate.getState()).toEqual({ status: "ready", session: { id: "new" } });
  });

  it("a guest commits at once: there is no key to show", async () => {
    const commit = vi.fn(async () => ({ k: "guest" }));
    const { gate, seen } = gateWith({
      prepareAccount: async () => ({ recoveryKey: null, commit }),
    });
    gate.start();
    await settle();
    expect(commit).toHaveBeenCalledTimes(1);
    expect(seen).not.toContain("setup");
    expect(gate.getState()).toEqual({ status: "ready", session: { id: "guest" } });
  });

  it("a failed commit locks, and the retry commits the same prepared keys again", async () => {
    const commit = vi
      .fn<() => Promise<Keys>>()
      .mockRejectedValueOnce(fail("offline"))
      .mockResolvedValueOnce({ k: "new" });
    const prepareAccount = vi.fn(async () => ({ recoveryKey: "ABCD-EFGH", commit }));
    const { gate } = gateWith({ prepareAccount });
    gate.start();
    await settle();
    await gate.confirmSetup();
    expect(gate.getState()).toEqual({ status: "locked", kind: "offline", retrying: false });

    gate.retry();
    expect(gate.getState()).toMatchObject({ status: "committing" });
    await settle();
    expect(commit).toHaveBeenCalledTimes(2);
    expect(prepareAccount).toHaveBeenCalledTimes(1);
    expect(gate.getState()).toEqual({ status: "ready", session: { id: "new" } });
  });

  it("an account with wraps asks for the recovery key; refusals stay on Unlock", async () => {
    const unlockWithRecovery = vi
      .fn<(text: string) => Promise<Keys>>()
      .mockRejectedValueOnce(fail("wrong_recovery_key"))
      .mockRejectedValueOnce(new Error("boom"))
      .mockResolvedValueOnce({ k: "unlocked" });
    const { gate, deps } = gateWith({
      prepareAccount: async () => {
        throw fail("already_set_up");
      },
      unlockWithRecovery,
    });
    gate.start();
    await settle();
    expect(gate.getState()).toEqual({ status: "unlock" });

    expect(await gate.unlock("nope")).toBe("wrong_recovery_key");
    expect(gate.getState()).toEqual({ status: "unlock" });
    expect(await gate.unlock("nope")).toBe("server");
    expect(await gate.unlock("right")).toBeNull();
    expect(deps.open).toHaveBeenCalledWith({ k: "unlocked" }, true);
    expect(gate.getState()).toEqual({ status: "ready", session: { id: "unlocked" } });
  });

  it("a failed first sync locks, and the retry starts over with the kept keys", async () => {
    let keys: Keys | null = null;
    const open = vi
      .fn<(k: Keys, fresh: boolean) => Promise<Session>>()
      .mockRejectedValueOnce(fail("server"))
      .mockResolvedValueOnce({ id: "again" });
    const { gate, deps } = gateWith({
      loadLocalKeys: async () => keys,
      prepareAccount: async () => ({
        recoveryKey: null,
        commit: async () => {
          keys = { k: "new" };
          return keys;
        },
      }),
      open,
    });
    gate.start();
    await settle();
    expect(gate.getState()).toEqual({ status: "locked", kind: "error", retrying: false });

    gate.retry();
    // starting over shows the check's loading state
    expect(gate.getState()).toEqual({ status: "checking" });
    await settle();
    expect(open).toHaveBeenLastCalledWith({ k: "new" }, false);
    expect(deps.open).toHaveBeenCalledTimes(2);
    expect(gate.getState()).toEqual({ status: "ready", session: { id: "again" } });
  });

  it("an error reading the account (offline) locks with the offline copy", async () => {
    const { gate } = gateWith({
      prepareAccount: async () => {
        throw fail("offline");
      },
    });
    gate.start();
    await settle();
    expect(gate.getState()).toEqual({ status: "locked", kind: "offline", retrying: false });
  });

  it("a setup that lost the race to another (409 already_set_up on commit) asks for the key", async () => {
    const commit = vi.fn(async (): Promise<Keys> => {
      throw fail("already_set_up");
    });
    const { gate, deps } = gateWith({
      prepareAccount: async () => ({ recoveryKey: "ABCD-EFGH", commit }),
    });
    gate.start();
    await settle();
    await gate.confirmSetup();
    expect(gate.getState()).toEqual({ status: "unlock" });
    expect(deps.open).not.toHaveBeenCalled();
    // the prepared data key is gone: nothing commits it again
    await gate.confirmSetup();
    expect(commit).toHaveBeenCalledTimes(1);
  });

  it("a guest whose account has keys elsewhere is locked out here: no recovery key to type", async () => {
    const { gate, deps } = gateWith({
      guest: true,
      prepareAccount: async () => {
        throw fail("already_set_up");
      },
    });
    gate.start();
    await settle();
    expect(gate.getState()).toEqual({ status: "locked", kind: "guest", retrying: false });
    gate.retry();
    await settle();
    expect(gate.getState()).toMatchObject({ status: "locked", kind: "guest" });
    expect(deps.unlockWithRecovery).not.toHaveBeenCalled();
  });

  it("a guest that loses the setup race is locked out too", async () => {
    const { gate } = gateWith({
      guest: true,
      prepareAccount: async () => ({
        recoveryKey: null,
        commit: async () => {
          throw fail("already_set_up");
        },
      }),
    });
    gate.start();
    await settle();
    expect(gate.getState()).toEqual({ status: "locked", kind: "guest", retrying: false });
  });

  it("a browser that cannot keep the key safely is locked, with no retry", async () => {
    const prepareAccount = vi.fn(async () => {
      throw fail("unsupported_browser");
    });
    const { gate } = gateWith({ prepareAccount });
    gate.start();
    await settle();
    expect(gate.getState()).toEqual({ status: "locked", kind: "unsupported", retrying: false });
    gate.retry();
    await settle();
    expect(prepareAccount).toHaveBeenCalledTimes(1);
  });

  it("unlocking in a browser that cannot keep the key safely locks too", async () => {
    const { gate } = gateWith({
      prepareAccount: async () => {
        throw fail("already_set_up");
      },
      unlockWithRecovery: async () => {
        throw fail("unsupported_browser");
      },
    });
    gate.start();
    await settle();
    expect(await gate.unlock("KEY")).toBeNull();
    expect(gate.getState()).toEqual({ status: "locked", kind: "unsupported", retrying: false });
  });

  it("a vault closed under the open app checks again: reopens with kept keys, else Unlock", async () => {
    let kept: Keys | null = { k: "kept" };
    const { gate, deps } = gateWith({
      loadLocalKeys: async () => kept,
      prepareAccount: async () => {
        throw fail("already_set_up");
      },
    });
    gate.start();
    await settle();
    expect(gate.getState().status).toBe("ready");

    gate.closed();
    await settle();
    expect(gate.getState()).toEqual({ status: "ready", session: { id: "kept" } });
    expect(deps.open).toHaveBeenCalledTimes(2);

    kept = null; // another tab signed out and deleted the vault
    gate.closed();
    await settle();
    expect(gate.getState()).toEqual({ status: "unlock" });
  });

  it("starts once", async () => {
    const { gate, deps } = gateWith();
    gate.start();
    gate.start();
    await settle();
    expect(deps.loadLocalKeys).toHaveBeenCalledTimes(1);
  });
});
