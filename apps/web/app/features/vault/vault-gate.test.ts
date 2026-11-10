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

  describe("another account signed in (another tab)", () => {
    /** The gate of `me`, whose cookie now says `signedIn` (null: signed out). */
    function changedGate(signedIn: () => string | null, overrides = {}) {
      const reload = vi.fn();
      const sessionUserId = vi.fn(async () => signedIn());
      const built = gateWith({ userId: "me", sessionUserId, reload, ...overrides });
      return { ...built, reload, sessionUserId };
    }

    it("a vault closed under the app reloads it when the signed-in account changed", async () => {
      let who: string | null = "me";
      const { gate, deps, reload } = changedGate(() => who, {
        loadLocalKeys: vi.fn(async () => ({ k: "kept" })),
      });
      gate.start();
      await settle();
      expect(gate.getState().status).toBe("ready");
      who = "someone-else";
      gate.closed();
      await settle();
      expect(reload).toHaveBeenCalledTimes(1);
      expect(deps.loadLocalKeys).toHaveBeenCalledTimes(1);
      expect(deps.open).toHaveBeenCalledTimes(1);
      expect(gate.getState().status).toBe("checking");
    });

    it("signed out in another tab: reloads too (the layout sends to sign-in)", async () => {
      let who: string | null = "me";
      const { gate, reload } = changedGate(() => who, {
        loadLocalKeys: async () => ({ k: "kept" }),
      });
      gate.start();
      await settle();
      who = null;
      gate.closed();
      await settle();
      expect(reload).toHaveBeenCalledTimes(1);
    });

    it("never prepares an account for the old id", async () => {
      const { gate, deps, reload } = changedGate(() => "someone-else");
      gate.start();
      await settle();
      expect(reload).toHaveBeenCalledTimes(1);
      expect(deps.prepareAccount).not.toHaveBeenCalled();
    });

    it("never unlocks for the old id", async () => {
      let who = "me";
      const { gate, deps, reload } = changedGate(() => who, {
        prepareAccount: async () => {
          throw fail("already_set_up");
        },
      });
      gate.start();
      await settle();
      expect(gate.getState()).toEqual({ status: "unlock" });
      who = "someone-else";
      expect(await gate.unlock("KEY")).toBeNull();
      expect(reload).toHaveBeenCalledTimes(1);
      expect(deps.unlockWithRecovery).not.toHaveBeenCalled();
    });

    it("a sync that says session_changed reloads when the id differs", async () => {
      let who = "me";
      const { gate, reload } = changedGate(() => who, {
        loadLocalKeys: async () => ({ k: "kept" }),
      });
      gate.start();
      await settle();
      who = "someone-else";
      gate.sessionChanged();
      await settle();
      expect(reload).toHaveBeenCalledTimes(1);
    });

    it("an open or a keys call refused with session_changed reloads too", async () => {
      let who = "me";
      const { gate, reload } = changedGate(() => who, {
        loadLocalKeys: async () => ({ k: "kept" }),
        open: async () => {
          who = "someone-else";
          throw fail("session_changed");
        },
      });
      gate.start();
      await settle();
      expect(reload).toHaveBeenCalledTimes(1);
    });

    it("session_changed while the same account is signed in locks, without looping", async () => {
      const { gate, deps, reload } = changedGate(() => "me", {
        loadLocalKeys: async () => ({ k: "kept" }),
        open: vi.fn(async () => {
          throw fail("session_changed");
        }),
      });
      gate.start();
      await settle();
      expect(reload).not.toHaveBeenCalled();
      expect(deps.open).toHaveBeenCalledTimes(1);
      expect(gate.getState()).toEqual({ status: "locked", kind: "error", retrying: false });
    });

    it("cannot tell who is signed in (offline): goes on as before", async () => {
      const { gate, deps, reload } = changedGate(() => "me", {
        sessionUserId: async () => {
          throw fail("offline");
        },
        loadLocalKeys: async () => ({ k: "kept" }),
      });
      gate.start();
      await settle();
      gate.closed();
      await settle();
      expect(reload).not.toHaveBeenCalled();
      expect(deps.open).toHaveBeenCalledTimes(2);
    });
  });

  describe("passkeys", () => {
    const stash = () => ({ credentialId: "cred-1", prf: new Uint8Array(32).fill(7) });
    const elsewhere = {
      prepareAccount: vi.fn(async () => {
        throw fail("already_set_up");
      }),
    };

    it("a stashed sign-in PRF that opens a wrap unlocks without showing Unlock", async () => {
      const kept = stash();
      const unlockWithPasskey = vi.fn(async () => ({ k: "passkey" }));
      const { gate, deps, seen } = gateWith({
        ...elsewhere,
        takeSignInPrf: () => kept,
        unlockWithPasskey,
      });
      gate.start();
      await settle();
      expect(unlockWithPasskey).toHaveBeenCalledWith(
        expect.objectContaining({ credentialId: "cred-1" }),
      );
      expect(deps.open).toHaveBeenCalledWith({ k: "passkey" }, true);
      expect(gate.getState()).toEqual({ status: "ready", session: { id: "passkey" } });
      expect(seen).not.toContain("unlock");
      // Used, then zeroed.
      expect(kept.prf.every((b) => b === 0)).toBe(true);
    });

    it("one that opens nothing shows Unlock, and after a recovery unlock the wrap for that credential is added", async () => {
      const kept = stash();
      const addPasskeyWrap = vi.fn(async (passkey: { credentialId: string; prf: Uint8Array }) => {
        expect(passkey.credentialId).toBe("cred-1");
        expect(passkey.prf).toEqual(new Uint8Array(32).fill(7));
      });
      const { gate, deps } = gateWith({
        ...elsewhere,
        takeSignInPrf: () => kept,
        unlockWithPasskey: vi.fn(async () => {
          throw fail("no_passkey_wrap");
        }),
        addPasskeyWrap,
      });
      gate.start();
      await settle();
      expect(gate.getState()).toEqual({ status: "unlock" });
      expect(addPasskeyWrap).not.toHaveBeenCalled();

      expect(await gate.unlock("ABCD")).toBeNull();
      expect(deps.unlockWithRecovery).toHaveBeenCalledWith("ABCD");
      expect(addPasskeyWrap).toHaveBeenCalledTimes(1);
      expect(gate.getState()).toEqual({ status: "ready", session: { id: "unlocked" } });
      expect(kept.prf.every((b) => b === 0)).toBe(true);
    });

    it("a wrap that fails to save still opens the vault", async () => {
      const { gate } = gateWith({
        ...elsewhere,
        takeSignInPrf: stash,
        unlockWithPasskey: vi.fn(async () => {
          throw fail("no_passkey_wrap");
        }),
        addPasskeyWrap: vi.fn(async () => {
          throw fail("offline");
        }),
      });
      gate.start();
      await settle();
      await gate.unlock("ABCD");
      expect(gate.getState()).toEqual({ status: "ready", session: { id: "unlocked" } });
    });

    it("no stash shows Unlock", async () => {
      const unlockWithPasskey = vi.fn(async () => ({ k: "passkey" }));
      const { gate } = gateWith({
        ...elsewhere,
        takeSignInPrf: () => null,
        unlockWithPasskey,
      });
      gate.start();
      await settle();
      expect(gate.getState()).toEqual({ status: "unlock" });
      expect(unlockWithPasskey).not.toHaveBeenCalled();
    });

    it("a new account adds the stashed passkey's wrap after setup", async () => {
      const addPasskeyWrap = vi.fn(async () => {});
      const { gate } = gateWith({ takeSignInPrf: stash, addPasskeyWrap });
      gate.start();
      await settle();
      await gate.confirmSetup();
      expect(addPasskeyWrap).toHaveBeenCalledWith(
        expect.objectContaining({ credentialId: "cred-1" }),
      );
      expect(gate.getState()).toEqual({ status: "ready", session: { id: "new" } });
    });

    it("a known browser zeroes the stash and opens", async () => {
      const kept = stash();
      const { gate } = gateWith({
        loadLocalKeys: async () => ({ k: "kept" }),
        takeSignInPrf: () => kept,
      });
      gate.start();
      await settle();
      expect(gate.getState()).toEqual({ status: "ready", session: { id: "kept" } });
      expect(kept.prf.every((b) => b === 0)).toBe(true);
    });

    it("Use a passkey: the touch's PRF opens the vault", async () => {
      const touched = stash();
      const unlockWithPasskey = vi.fn(async () => ({ k: "touched" }));
      const { gate } = gateWith({
        ...elsewhere,
        evaluatePrf: async () => touched,
        unlockWithPasskey,
      });
      gate.start();
      await settle();
      expect(await gate.unlockWithPasskey()).toBeNull();
      expect(gate.getState()).toEqual({ status: "ready", session: { id: "touched" } });
      expect(touched.prf.every((b) => b === 0)).toBe(true);
    });

    it("Use a passkey: cancelled stays on Unlock; no_prf and no_passkey_wrap are shown", async () => {
      const evaluatePrf = vi
        .fn<() => Promise<{ credentialId: string; prf: Uint8Array } | null>>()
        .mockResolvedValueOnce(null)
        .mockRejectedValueOnce(fail("no_prf"))
        .mockResolvedValueOnce(stash());
      const { gate } = gateWith({
        ...elsewhere,
        evaluatePrf,
        unlockWithPasskey: vi.fn(async () => {
          throw fail("no_passkey_wrap");
        }),
      });
      gate.start();
      await settle();
      expect(await gate.unlockWithPasskey()).toBeNull();
      expect(gate.getState()).toEqual({ status: "unlock" });
      expect(await gate.unlockWithPasskey()).toBe("no_prf");
      expect(await gate.unlockWithPasskey()).toBe("no_passkey_wrap");
      expect(gate.getState()).toEqual({ status: "unlock" });
    });

    it("a pending credential that is not the account's gets no wrap, is zeroed, and the vault opens", async () => {
      const kept = stash();
      const addPasskeyWrap = vi.fn(async () => {
        throw fail("unknown_passkey");
      });
      const { gate } = gateWith({
        ...elsewhere,
        takeSignInPrf: () => kept,
        unlockWithPasskey: vi.fn(async () => {
          throw fail("no_passkey_wrap");
        }),
        addPasskeyWrap,
      });
      gate.start();
      await settle();
      await gate.unlock("ABCD");
      expect(addPasskeyWrap).toHaveBeenCalledTimes(1);
      expect(kept.prf.every((b) => b === 0)).toBe(true);
      expect(gate.getState()).toEqual({ status: "ready", session: { id: "unlocked" } });
    });

    it("the stash is zeroed when another account is signed in now", async () => {
      const kept = stash();
      const reload = vi.fn();
      const unlockWithPasskey = vi.fn(async () => ({ k: "passkey" }));
      const { gate } = gateWith({
        ...elsewhere,
        userId: "me",
        sessionUserId: async () => "someone-else",
        reload,
        takeSignInPrf: () => kept,
        unlockWithPasskey,
      });
      gate.start();
      await settle();
      expect(reload).toHaveBeenCalled();
      expect(unlockWithPasskey).not.toHaveBeenCalled();
      expect(kept.prf.every((b) => b === 0)).toBe(true);
    });

    it("Use a passkey offers only the account's passkeys", async () => {
      const evaluatePrf = vi.fn(async () => null);
      const { gate } = gateWith({
        ...elsewhere,
        accountPasskeyIds: async () => ["cred-1", "cred-2"],
        evaluatePrf,
      });
      gate.start();
      await settle();
      await gate.unlockWithPasskey();
      expect(evaluatePrf).toHaveBeenCalledWith(["cred-1", "cred-2"]);
    });

    it("Use a passkey on an account without passkeys is no_passkey_wrap, with no touch", async () => {
      const evaluatePrf = vi.fn(async () => null);
      const { gate } = gateWith({ ...elsewhere, accountPasskeyIds: async () => [], evaluatePrf });
      gate.start();
      await settle();
      expect(await gate.unlockWithPasskey()).toBe("no_passkey_wrap");
      expect(evaluatePrf).not.toHaveBeenCalled();
    });

    it("Use a passkey with an unreadable list still asks (the server checks the wrap's ref)", async () => {
      const evaluatePrf = vi.fn(async () => null);
      const { gate } = gateWith({
        ...elsewhere,
        accountPasskeyIds: async () => {
          throw fail("offline");
        },
        evaluatePrf,
      });
      gate.start();
      await settle();
      await gate.unlockWithPasskey();
      expect(evaluatePrf).toHaveBeenCalledWith(undefined);
    });
  });

  describe("pairing", () => {
    const elsewhere = {
      prepareAccount: vi.fn(async () => {
        throw fail("already_set_up");
      }),
    };
    /** A new-device pairing whose `finish()` the test settles. */
    function fakePairing(finish: () => Promise<Keys>) {
      return {
        id: "p-1",
        code: "ABCDEFGH",
        qr: "wambito://pair?id=p-1&key=k",
        expiresAt: "2026-11-10T12:10:00Z",
        number: vi.fn(async () => "123456"),
        finish: vi.fn(finish),
        cancel: vi.fn(),
      };
    }

    it("pairing → open after finish(), as a fresh unlock (the pending passkey gets its wrap)", async () => {
      let done!: (keys: Keys) => void;
      const pairing = fakePairing(() => new Promise((resolve) => (done = resolve)));
      const addPasskeyWrap = vi.fn(async () => {});
      const { gate, deps } = gateWith({
        ...elsewhere,
        takeSignInPrf: () => ({ credentialId: "cred-1", prf: new Uint8Array(32).fill(7) }),
        unlockWithPasskey: vi.fn(async () => {
          throw fail("no_passkey_wrap");
        }),
        addPasskeyWrap,
        startPairing: vi.fn(async () => pairing),
      });
      gate.start();
      await settle();
      expect(gate.getState()).toEqual({ status: "unlock" });

      await gate.pair();
      expect(gate.getState()).toEqual({ status: "pairing", from: "unlock" });
      expect(await gate.startPairing()).toBe(pairing);
      await settle();
      expect(deps.open).not.toHaveBeenCalled();

      done({ k: "paired" });
      await settle();
      expect(addPasskeyWrap).toHaveBeenCalledTimes(1);
      expect(deps.open).toHaveBeenCalledWith({ k: "paired" }, true);
      expect(gate.getState()).toEqual({ status: "ready", session: { id: "paired" } });
    });

    it("back cancels the pairing and shows Unlock; starting again cancels the previous one", async () => {
      const first = fakePairing(() => new Promise(() => {}));
      const second = fakePairing(() => new Promise(() => {}));
      const startPairing = vi
        .fn<() => Promise<ReturnType<typeof fakePairing>>>()
        .mockResolvedValueOnce(first)
        .mockResolvedValueOnce(second);
      const { gate } = gateWith({ ...elsewhere, startPairing });
      gate.start();
      await settle();
      await gate.pair();
      await gate.startPairing();
      await gate.startPairing();
      expect(first.cancel).toHaveBeenCalledTimes(1);
      expect(second.cancel).not.toHaveBeenCalled();

      gate.leavePairing();
      expect(second.cancel).toHaveBeenCalledTimes(1);
      expect(gate.getState()).toEqual({ status: "unlock" });
    });

    it("the latest startPairing wins: an older call resolving last cancels its own request", async () => {
      let doneSecond!: (keys: Keys) => void;
      const first = fakePairing(() => new Promise(() => {}));
      const second = fakePairing(() => new Promise((resolve) => (doneSecond = resolve)));
      let resolveFirst!: (p: typeof first) => void;
      let resolveSecond!: (p: typeof second) => void;
      const startPairing = vi
        .fn<() => Promise<ReturnType<typeof fakePairing>>>()
        .mockImplementationOnce(() => new Promise((resolve) => (resolveFirst = resolve)))
        .mockImplementationOnce(() => new Promise((resolve) => (resolveSecond = resolve)));
      const { gate, deps } = gateWith({ ...elsewhere, startPairing });
      gate.start();
      await settle();
      await gate.pair();
      // StrictMode's double effect, or a quick "Start again": two calls in flight.
      const a = gate.startPairing();
      const b = gate.startPairing();
      a.catch(() => {});
      resolveSecond(second);
      expect(await b).toBe(second);
      resolveFirst(first);
      await expect(a).rejects.toMatchObject({ code: "cancelled" });
      expect(first.cancel).toHaveBeenCalled();
      expect(second.cancel).not.toHaveBeenCalled();

      doneSecond({ k: "second" });
      await settle();
      expect(deps.open).toHaveBeenCalledWith({ k: "second" }, true);
      expect(gate.getState()).toEqual({ status: "ready", session: { id: "second" } });
    });

    it("a guest locked out pairs from Locked, and back returns to Locked", async () => {
      const pairing = fakePairing(() => new Promise(() => {}));
      const { gate } = gateWith({
        ...elsewhere,
        guest: true,
        startPairing: vi.fn(async () => pairing),
      });
      gate.start();
      await settle();
      expect(gate.getState()).toEqual({ status: "locked", kind: "guest", retrying: false });
      await gate.pair();
      expect(gate.getState()).toEqual({ status: "pairing", from: "guest" });
      gate.leavePairing();
      expect(gate.getState()).toEqual({ status: "locked", kind: "guest", retrying: false });
    });

    it("a pairing that fails stays on the pairing screen, which shows why", async () => {
      const pairing = fakePairing(() => Promise.reject(fail("tampered")));
      const { gate, deps } = gateWith({ ...elsewhere, startPairing: vi.fn(async () => pairing) });
      gate.start();
      await settle();
      await gate.pair();
      await gate.startPairing();
      await settle();
      expect(deps.open).not.toHaveBeenCalled();
      expect(gate.getState()).toEqual({ status: "pairing", from: "unlock" });
    });

    it("a finish refused with session_changed reloads for the account signed in now", async () => {
      const reload = vi.fn();
      let who = "me";
      const pairing = fakePairing(
        () => new Promise((_, reject) => setTimeout(() => reject(fail("session_changed")), 1)),
      );
      const { gate } = gateWith({
        ...elsewhere,
        userId: "me",
        sessionUserId: async () => who,
        reload,
        startPairing: vi.fn(async () => pairing),
      });
      gate.start();
      await settle();
      await gate.pair();
      await gate.startPairing();
      who = "someone-else";
      await new Promise((resolve) => setTimeout(resolve, 5));
      await settle();
      expect(reload).toHaveBeenCalled();
    });

    it("pair() does nothing outside Unlock and a guest's Locked", async () => {
      const startPairing = vi.fn();
      const { gate } = gateWith({ loadLocalKeys: async () => ({ k: "kept" }), startPairing });
      gate.start();
      await settle();
      await gate.pair();
      expect(gate.getState()).toMatchObject({ status: "ready" });
    });
  });

  describe("a removed browser", () => {
    it("removed() from the open app shows Unlock with the removed notice", async () => {
      const { gate, deps } = gateWith({ loadLocalKeys: async () => ({ k: "kept" }) });
      gate.start();
      await settle();
      gate.removed();
      expect(gate.getState()).toEqual({ status: "unlock", notice: "removed" });
      // the vault is gone already: nothing is opened or made again
      expect(deps.prepareAccount).not.toHaveBeenCalled();
      expect(deps.open).toHaveBeenCalledTimes(1);
    });

    it("the notice stays through a failed unlock and goes with a new screen", async () => {
      const unlockWithRecovery = vi
        .fn<(text: string) => Promise<Keys>>()
        .mockRejectedValueOnce(fail("wrong_recovery_key"));
      const { gate } = gateWith({
        loadLocalKeys: async () => ({ k: "kept" }),
        unlockWithRecovery,
        startPairing: vi.fn(async () => ({
          id: "p-1",
          code: "ABCDEFGH",
          qr: "wambito://pair?id=p-1&key=k",
          expiresAt: "2026-11-10T12:10:00Z",
          number: async () => "123456",
          finish: () => new Promise<Keys>(() => {}),
          cancel: () => {},
        })),
      });
      gate.start();
      await settle();
      gate.removed();
      expect(await gate.unlock("nope")).toBe("wrong_recovery_key");
      expect(gate.getState()).toEqual({ status: "unlock", notice: "removed" });
      await gate.pair();
      gate.leavePairing();
      expect(gate.getState()).toEqual({ status: "unlock" });
    });

    it("a removed guest is locked out: it has no recovery key to type", async () => {
      const { gate } = gateWith({ loadLocalKeys: async () => ({ k: "kept" }), guest: true });
      gate.start();
      await settle();
      gate.removed();
      expect(gate.getState()).toEqual({ status: "locked", kind: "guest", retrying: false });
    });

    it("a browser removed while closed opens to Unlock with the removed notice", async () => {
      const open = vi.fn(async () => {
        throw fail("device_removed");
      });
      const { gate, deps } = gateWith({ loadLocalKeys: async () => ({ k: "kept" }), open });
      gate.start();
      await settle();
      expect(gate.getState()).toEqual({ status: "unlock", notice: "removed" });
      expect(deps.prepareAccount).not.toHaveBeenCalled();
    });

    it("a guest removed while closed is Locked guest", async () => {
      const open = vi.fn(async () => {
        throw fail("device_removed");
      });
      const { gate } = gateWith({ loadLocalKeys: async () => ({ k: "kept" }), open, guest: true });
      gate.start();
      await settle();
      expect(gate.getState()).toEqual({ status: "locked", kind: "guest", retrying: false });
    });

    it("removed() outside the open app does nothing", async () => {
      const { gate } = gateWith({
        prepareAccount: async () => {
          throw fail("already_set_up");
        },
      });
      gate.start();
      await settle();
      gate.removed();
      expect(gate.getState()).toEqual({ status: "unlock" });
    });
  });
  describe("a new key version this browser cannot verify", () => {
    it("unverified() from the open app shows Unlock with the unverified notice", async () => {
      const { gate, deps } = gateWith({ loadLocalKeys: async () => ({ k: "kept" }) });
      gate.start();
      await settle();
      gate.unverified();
      expect(gate.getState()).toEqual({ status: "unlock", notice: "unverified" });
      expect(deps.prepareAccount).not.toHaveBeenCalled();
      expect(deps.open).toHaveBeenCalledTimes(1);
    });

    it("an unverified guest goes to its Locked", async () => {
      const { gate } = gateWith({ loadLocalKeys: async () => ({ k: "kept" }), guest: true });
      gate.start();
      await settle();
      gate.unverified();
      expect(gate.getState()).toEqual({ status: "locked", kind: "guest", retrying: false });
    });

    it("an opening that fails with key_unverified shows Unlock with the notice; a guest its Locked", async () => {
      const open = vi.fn(async () => {
        throw fail("key_unverified");
      });
      const { gate, deps } = gateWith({ loadLocalKeys: async () => ({ k: "kept" }), open });
      gate.start();
      await settle();
      expect(gate.getState()).toEqual({ status: "unlock", notice: "unverified" });
      expect(deps.prepareAccount).not.toHaveBeenCalled();
      const guest = gateWith({ loadLocalKeys: async () => ({ k: "kept" }), open, guest: true });
      guest.gate.start();
      await settle();
      expect(guest.gate.getState()).toEqual({ status: "locked", kind: "guest", retrying: false });
    });

    it("the recovery key from unverified unlocks the kept vault and opens it fresh", async () => {
      const open = vi
        .fn<(keys: Keys, fresh: boolean) => Promise<Session>>()
        .mockImplementation(async (keys) => ({ id: keys.k }));
      const { gate, deps } = gateWith({ loadLocalKeys: async () => ({ k: "kept" }), open });
      gate.start();
      await settle();
      gate.unverified();
      expect(await gate.unlock("ABCD-EFGH")).toBeNull();
      expect(deps.unlockWithRecovery).toHaveBeenCalledWith("ABCD-EFGH");
      expect(deps.prepareAccount).not.toHaveBeenCalled();
      expect(open).toHaveBeenLastCalledWith({ k: "unlocked" }, true);
      expect(gate.getState()).toEqual({ status: "ready", session: { id: "unlocked" } });
    });

    it("unverified() outside the open app does nothing", async () => {
      const { gate } = gateWith({
        prepareAccount: async () => {
          throw fail("already_set_up");
        },
      });
      gate.start();
      await settle();
      gate.unverified();
      expect(gate.getState()).toEqual({ status: "unlock" });
    });
  });
});
