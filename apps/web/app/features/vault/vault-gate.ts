import type { UnlockError } from "./Unlock.tsx";

/**
 * The vault gate's state machine (stage 2a): what a preview account sees before the app. No React
 * and no IndexedDB here; every effect comes in as a dependency, so the tests drive it with fakes.
 *
 *   checking ─ keys in this browser ──────────────────────────────▶ opening ─▶ ready
 *      │                                                               ▲
 *      ├─ account without wraps ─▶ setup (key shown) ─ confirm ─▶ committing
 *      │     (a guest commits at once, nothing to show)                │
 *      └─ account with wraps ─┬▶ unlock ─ recovery key or passkey ───┘
 *                              ├─ the sign-in's passkey PRF opens a wrap ─▶ opening
 *                              └─ "From another device" ─▶ pairing ─ finish() ─▶ opening
 *
 * Passkeys (stage 2b): a passkey sign-in (or a fresh registration) leaves its PRF in a one-shot
 * stash (`takeSignInPrf`). An account with keys elsewhere tries it first; when it opens nothing,
 * Unlock shows, and once the vault is unlocked by other means (the recovery key, a new account's
 * setup) the gate adds the wrap for that credential. Unlock's "Use a passkey" touches a passkey
 * for its PRF (`evaluatePrf`); one without a wrap is kept the same way. A known browser zeroes the
 * stash. Every PRF is zeroed once used.
 *
 * Pairing (stage 2b): Unlock's "From another device" (and a guest's Locked, which has nothing
 * else to open with) enters `pairing`. The screen starts a request through `startPairing()` (again
 * for "Start again", which cancels the previous one; only the latest call's request becomes
 * current, an older one answering later cancels itself); when its `finish()` resolves, the gate opens
 * the vault exactly as after a recovery unlock (pending passkey wrap, then a full sync). A failed
 * pairing stays on its screen, which shows why; `leavePairing()` cancels it and goes back.
 *
 * A browser removed from the account by another device (`removed()`, from the session's
 * `onRemoved`: its vault is already deleted) shows Unlock with the `removed` notice; a guest, which
 * has no recovery key to type, its Locked.
 *
 * Any failure outside Unlock's own errors lands on `locked`, whose retry repeats the step that
 * failed: a failed commit commits again (the same wraps, the same ids), anything else starts over.
 * A commit that lost the race to another setup (`already_set_up`) drops its keys and shows Unlock.
 * Two locked kinds have no retry: `unsupported` (the browser cannot keep a device key safely) and
 * `guest` (a guest's account has keys made elsewhere, and a guest has no recovery key to type).
 *
 * Another tab may sign in as someone else under this page (one cookie per browser). Before making
 * or unlocking keys, and when the open vault closes or its sync says `session_changed`, the gate
 * asks who is signed in; another account (or none) reloads the app for them, so nothing runs for
 * the old id. The server refuses a `/v2` call for another account (409) as the last guard.
 */

/** A touched passkey's credential id and PRF output; the gate zeroes `prf` once used. */
export interface GatePasskey {
  credentialId: string;
  prf: Uint8Array;
}

/** The keys a gate hands from setup or unlock to opening; opaque here. */
export type GateKeys = unknown;

/** A new device's pairing request (`local/pairing.ts` `NewDevicePairing`, keys opaque). */
export interface GatePairing<K = GateKeys> {
  id: string;
  code: string;
  qr: string;
  expiresAt: string;
  number(): Promise<string>;
  finish(): Promise<K>;
  cancel(): void;
}

/** A prepared new account: the key to show (null for a guest) and the commit that sends it. */
export interface GatePrepared<K = GateKeys> {
  recoveryKey: string | null;
  commit(): Promise<K>;
}

export interface VaultGateDeps<K = GateKeys, S = unknown> {
  /** The keys this browser kept, or null. */
  loadLocalKeys(): Promise<K | null>;
  /** Throws a `{ code: "already_set_up" }` error when the account has wraps. */
  prepareAccount(): Promise<GatePrepared<K>>;
  /** Throws `{ code }` with an `UnlockError` code when the key is refused. */
  unlockWithRecovery(text: string): Promise<K>;
  /**
   * Opens the store, runs the sync and returns the session. `fresh`: the keys were just made or
   * unlocked, so the first full sync must succeed (a known browser opens on its local data).
   */
  open(keys: K, fresh: boolean): Promise<S>;
  /** A guest: never shown a recovery key, so an account with keys elsewhere is `locked: guest`. */
  guest?: boolean;
  /** The account this gate is for. */
  userId?: string;
  /** Who is signed in now (null: no one); throws when it cannot tell (offline). */
  sessionUserId?(): Promise<string | null>;
  /** Loads the app again for whoever is signed in now. */
  reload?(): void;
  /** The sign-in's (or registration's) passkey PRF, once, when it is this account's; else null. */
  takeSignInPrf?(): GatePasskey | null;
  /** Opens the passkey wrap of that credential; throws `{ code: "no_passkey_wrap" }` when none. */
  unlockWithPasskey?(passkey: GatePasskey): Promise<K>;
  /** Adds the wrap for that passkey, from this browser's device wrap (once unlocked). */
  addPasskeyWrap?(passkey: GatePasskey): Promise<void>;
  /**
   * Touches a passkey (one of `credentialIds` when given) for its PRF: null when cancelled,
   * `{ code: "no_prf" }` without one.
   */
  evaluatePrf?(credentialIds?: string[]): Promise<GatePasskey | null>;
  /** The account's passkey credential ids, so Unlock offers only those; throws when unknown. */
  accountPasskeyIds?(): Promise<string[]>;
  /** Asks the relay for a pairing request; another unlocked device approves it. */
  startPairing?(): Promise<GatePairing<K>>;
}

/** Why the vault is locked; `unsupported` and `guest` have no retry. */
export type LockedKind = "error" | "offline" | "unsupported" | "guest";

export type VaultGateState<S = unknown> =
  | { status: "checking" }
  | { status: "setup"; recoveryKey: string }
  | { status: "committing" }
  /** `notice: "removed"`: this browser was removed from the account (its vault is gone). */
  | { status: "unlock"; notice?: "removed" }
  /** `from`: where back goes, Unlock or a guest's Locked. */
  | { status: "pairing"; from: "unlock" | "guest" }
  | { status: "opening" }
  | { status: "ready"; session: S }
  | { status: "locked"; kind: LockedKind; retrying: boolean };

export interface VaultGate<S = unknown, K = GateKeys> {
  getState(): VaultGateState<S>;
  subscribe(listener: () => void): () => void;
  /** Runs the first check. Once; later calls do nothing. */
  start(): void;
  /** The person typed four characters back on the setup screen. */
  confirmSetup(): Promise<void>;
  /** The Unlock screen's submit: null when it worked, else why not (the screen shows it). */
  unlock(text: string): Promise<UnlockError | null>;
  /** Unlock's "Use a passkey": null when it worked or was cancelled, else why not. */
  unlockWithPasskey(): Promise<UnlockError | null>;
  /** Unlock's "From another device", or a guest Locked's "Approve from another device". */
  pair(): Promise<void>;
  /**
   * The pairing screen asks for a request (again for "Start again": the previous one is
   * cancelled). Its `finish()` opens the vault; its errors are the screen's to show.
   */
  startPairing(): Promise<GatePairing<K>>;
  /** The pairing screen's back: cancels the request and returns to where it came from. */
  leavePairing(): void;
  /** Locked's retry. */
  retry(): void;
  /** The open vault closed under the app (another tab): check again (reopen, or Unlock). */
  closed(): void;
  /** The sync said another account is signed in (409 `session_changed`): reload or lock. */
  sessionChanged(): void;
  /**
   * This browser was removed from the account (`VaultSession.onRemoved`: its device wrap is gone
   * and the vault was deleted): Unlock with the `removed` notice; a guest's Locked.
   */
  removed(): void;
}

const UNLOCK_ERRORS: readonly string[] = [
  "bad_recovery_key",
  "wrong_recovery_key",
  "no_prf",
  "no_passkey_wrap",
  "offline",
  "server",
];

const codeOf = (error: unknown): string | undefined =>
  error && typeof error === "object" && "code" in error && typeof error.code === "string"
    ? error.code
    : undefined;

const lockedKind = (error: unknown): LockedKind => {
  const code = codeOf(error);
  if (code === "offline") return "offline";
  if (code === "unsupported_browser") return "unsupported";
  return "error";
};

/** Kinds a retry cannot fix. */
const FINAL: readonly LockedKind[] = ["unsupported", "guest"];

export function createVaultGate<K, S>(deps: VaultGateDeps<K, S>): VaultGate<S, K> {
  let state: VaultGateState<S> = { status: "checking" };
  const listeners = new Set<() => void>();
  let started = false;
  let prepared: GatePrepared<K> | null = null;
  let again: () => Promise<void> = check;
  /** A passkey without a wrap yet: its wrap is added once the vault is unlocked by other means. */
  let pendingPasskey: GatePasskey | null = null;
  /** The pairing request the screen shows now; only its `finish()` opens the vault. */
  let pairing: GatePairing<K> | null = null;
  /**
   * Bumped by every `startPairing()` and by `leavePairing()`: only the latest call's request
   * becomes current (StrictMode's double effect, a quick "Start again", answers out of order).
   */
  let pairingCall = 0;

  const dropPairing = () => {
    pairing?.cancel();
    pairing = null;
  };

  /** A finished pairing opens like a recovery unlock; a failed one stays for the screen. */
  async function watchPairing(current: GatePairing<K>): Promise<void> {
    let keys: K;
    try {
      keys = await current.finish();
    } catch (error) {
      if (pairing !== current || state.status !== "pairing") return;
      const code = codeOf(error);
      if (code === "session_changed") {
        pairing = null;
        await changed(error, check);
      } else if (code === "unsupported_browser") {
        pairing = null;
        lock(error, check);
      }
      return;
    }
    if (pairing !== current || state.status !== "pairing") return;
    pairing = null;
    await wrapPending();
    await open(keys, true);
  }

  const keepPending = (passkey: GatePasskey | null) => {
    if (pendingPasskey && pendingPasskey !== passkey) pendingPasskey.prf.fill(0);
    pendingPasskey = passkey;
  };

  /** Adds the pending passkey's wrap (a failure only leaves it without one), then zeroes it. */
  async function wrapPending(): Promise<void> {
    const passkey = pendingPasskey;
    pendingPasskey = null;
    if (!passkey) return;
    try {
      await deps.addPasskeyWrap?.(passkey);
    } catch {
      // The passkey simply does not unlock yet; Settings can turn it on later.
    } finally {
      passkey.prf.fill(0);
    }
  }

  /** Tries a passkey's PRF on its wrap; on failure keeps it for after another unlock. */
  async function tryPasskey(passkey: GatePasskey): Promise<{ keys: K } | { error: unknown }> {
    if (!deps.unlockWithPasskey) {
      keepPending(passkey);
      return { error: { code: "no_passkey_wrap" } };
    }
    try {
      const keys = await deps.unlockWithPasskey(passkey);
      passkey.prf.fill(0);
      return { keys };
    } catch (error) {
      if (codeOf(error) === "no_passkey_wrap") keepPending(passkey);
      else passkey.prf.fill(0);
      return { error };
    }
  }

  const set = (next: VaultGateState<S>) => {
    state = next;
    for (const listener of listeners) listener();
  };

  /** The account has keys made elsewhere: Unlock, or Locked for a guest (nothing to type). */
  const hasKeysElsewhere = () => {
    prepared = null;
    if (deps.guest) {
      // Nothing to unlock with first: a guest has no recovery key to type.
      keepPending(null);
      set({ status: "locked", kind: "guest", retrying: false });
    } else set({ status: "unlock" });
  };

  /** This browser was removed (its vault is gone): Unlock with the notice, a guest's Locked. */
  const showRemoved = () => {
    prepared = null;
    if (deps.guest) set({ status: "locked", kind: "guest", retrying: false });
    else set({ status: "unlock", notice: "removed" });
  };

  /** Shows Locked; its retry runs `step`. */
  const lock = (error: unknown, step: () => Promise<void>) => {
    again = step;
    set({ status: "locked", kind: lockedKind(error), retrying: false });
  };

  /**
   * Whether this gate's account is still the signed-in one. When not, reloads the app (the gate
   * stays on checking until the page goes). Unknown (offline, say): true, the server guards.
   */
  async function sameSession(): Promise<boolean> {
    if (!deps.sessionUserId || deps.userId === undefined) return true;
    let current: string | null;
    try {
      current = await deps.sessionUserId();
    } catch {
      return true;
    }
    if (current === deps.userId) return true;
    set({ status: "checking" });
    deps.reload?.();
    return false;
  }

  /** A call was refused with `session_changed`: reload for the new account, else lock (no loop). */
  async function changed(error: unknown, step: () => Promise<void>): Promise<void> {
    if (await sameSession()) lock(error, step);
  }

  async function open(keys: K, fresh: boolean): Promise<void> {
    set({ status: "opening" });
    try {
      const session = await deps.open(keys, fresh);
      keepPending(null);
      set({ status: "ready", session });
    } catch (error) {
      // The keys are kept now: a retry starts over and finds them.
      const code = codeOf(error);
      if (code === "session_changed") await changed(error, check);
      else if (code === "device_removed") {
        // Removed while this page was closed: the session deleted the vault, so say so.
        keepPending(null);
        showRemoved();
      } else lock(error, check);
    }
  }

  /** Checks again after the open vault went away: first, is it still the same account? */
  async function recheck(): Promise<void> {
    set({ status: "checking" });
    if (await sameSession()) await check();
  }

  async function check(): Promise<void> {
    set({ status: "checking" });
    let keys: K | null;
    try {
      keys = await deps.loadLocalKeys();
    } catch (error) {
      lock(error, check);
      return;
    }
    const stashed = deps.takeSignInPrf?.() ?? null;
    if (keys) {
      stashed?.prf.fill(0);
      return open(keys, false);
    }
    if (stashed) keepPending(stashed);
    // Never make keys for an account that is no longer the signed-in one (nor keep its PRF).
    if (!(await sameSession())) {
      keepPending(null);
      return;
    }
    try {
      prepared = await deps.prepareAccount();
    } catch (error) {
      if (codeOf(error) === "already_set_up") {
        const passkey = pendingPasskey;
        if (passkey) {
          pendingPasskey = null;
          const tried = await tryPasskey(passkey);
          if ("keys" in tried) return open(tried.keys, true);
          if (codeOf(tried.error) === "session_changed") return changed(tried.error, check);
        }
        hasKeysElsewhere();
      } else if (codeOf(error) === "session_changed") await changed(error, check);
      else lock(error, check);
      return;
    }
    if (prepared.recoveryKey === null) return commit();
    set({ status: "setup", recoveryKey: prepared.recoveryKey });
  }

  async function commit(): Promise<void> {
    const current = prepared;
    if (!current) return check();
    set({ status: "committing" });
    let keys: K;
    try {
      keys = await current.commit();
    } catch (error) {
      // Another tab or device set the account up first: its data key wins, this one is dropped.
      if (codeOf(error) === "already_set_up") hasKeysElsewhere();
      else if (codeOf(error) === "session_changed") await changed(error, commit);
      else lock(error, commit);
      return;
    }
    prepared = null;
    await wrapPending();
    return open(keys, true);
  }

  return {
    getState: () => state,
    subscribe(listener) {
      listeners.add(listener);
      return () => listeners.delete(listener);
    },
    start() {
      if (started) return;
      started = true;
      void check();
    },
    confirmSetup: () => (state.status === "setup" ? commit() : Promise.resolve()),
    async unlock(text) {
      if (state.status !== "unlock") return null;
      if (!(await sameSession())) return null;
      let keys: K;
      try {
        keys = await deps.unlockWithRecovery(text);
      } catch (error) {
        const code = codeOf(error);
        if (code === "session_changed") {
          await changed(error, check);
          return null;
        }
        if (code === "unsupported_browser") {
          lock(error, check);
          return null;
        }
        return code && UNLOCK_ERRORS.includes(code) ? (code as UnlockError) : "server";
      }
      await wrapPending();
      await open(keys, true);
      return null;
    },
    async unlockWithPasskey() {
      if (state.status !== "unlock" || !deps.evaluatePrf) return null;
      if (!(await sameSession())) return null;
      // Only this account's passkeys (another account's on a shared browser would open nothing,
      // and must never get a wrap of this data key); an unreadable list leaves the browser's
      // choice open, and the server refuses a wrap for a credential not this account's.
      let ids: string[] | undefined;
      try {
        ids = await deps.accountPasskeyIds?.();
      } catch {
        ids = undefined;
      }
      if (ids && ids.length === 0) return "no_passkey_wrap";
      let passkey: GatePasskey | null;
      try {
        passkey = await deps.evaluatePrf(ids);
      } catch (error) {
        const code = codeOf(error);
        return code && UNLOCK_ERRORS.includes(code) ? (code as UnlockError) : "server";
      }
      if (!passkey) return null;
      const tried = await tryPasskey(passkey);
      if ("keys" in tried) {
        keepPending(null);
        await open(tried.keys, true);
        return null;
      }
      const code = codeOf(tried.error);
      if (code === "session_changed") {
        await changed(tried.error, check);
        return null;
      }
      if (code === "unsupported_browser") {
        lock(tried.error, check);
        return null;
      }
      return code && UNLOCK_ERRORS.includes(code) ? (code as UnlockError) : "server";
    },
    closed() {
      if (state.status === "ready") void recheck();
    },
    sessionChanged() {
      if (state.status === "ready") void changed({ code: "session_changed" }, recheck);
    },
    removed() {
      if (state.status !== "ready") return;
      showRemoved();
    },
    async pair() {
      const from =
        state.status === "unlock"
          ? "unlock"
          : state.status === "locked" && state.kind === "guest"
            ? "guest"
            : null;
      if (!from || !deps.startPairing) return;
      if (!(await sameSession())) return;
      set({ status: "pairing", from });
    },
    async startPairing() {
      if (state.status !== "pairing" || !deps.startPairing) {
        throw Object.assign(new Error("not_pairing"), { code: "cancelled" });
      }
      dropPairing();
      const call = ++pairingCall;
      let next: GatePairing<K>;
      try {
        next = await deps.startPairing();
      } catch (error) {
        if (call === pairingCall && codeOf(error) === "session_changed") {
          await changed(error, check);
        }
        throw error;
      }
      if (call !== pairingCall || state.status !== "pairing") {
        // A newer call started (it wins), or the screen was left, while this one was made.
        next.cancel();
        throw Object.assign(new Error("cancelled"), { code: "cancelled" });
      }
      dropPairing();
      pairing = next;
      void watchPairing(next);
      return next;
    },
    leavePairing() {
      if (state.status !== "pairing") return;
      const { from } = state;
      pairingCall++;
      dropPairing();
      if (from === "guest") set({ status: "locked", kind: "guest", retrying: false });
      else set({ status: "unlock" });
    },
    retry() {
      if (state.status !== "locked" || state.retrying || FINAL.includes(state.kind)) return;
      set({ ...state, retrying: true });
      void again();
    },
  };
}
