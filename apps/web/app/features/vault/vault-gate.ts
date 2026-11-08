import type { UnlockError } from "./Unlock.tsx";

/**
 * The vault gate's state machine (stage 2a): what a preview account sees before the app. No React
 * and no IndexedDB here; every effect comes in as a dependency, so the tests drive it with fakes.
 *
 *   checking ─ keys in this browser ──────────────────────────────▶ opening ─▶ ready
 *      │                                                               ▲
 *      ├─ account without wraps ─▶ setup (key shown) ─ confirm ─▶ committing
 *      │     (a guest commits at once, nothing to show)                │
 *      └─ account with wraps ──▶ unlock ─ recovery key ────────────────┘
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

/** The keys a gate hands from setup or unlock to opening; opaque here. */
export type GateKeys = unknown;

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
}

/** Why the vault is locked; `unsupported` and `guest` have no retry. */
export type LockedKind = "error" | "offline" | "unsupported" | "guest";

export type VaultGateState<S = unknown> =
  | { status: "checking" }
  | { status: "setup"; recoveryKey: string }
  | { status: "committing" }
  | { status: "unlock" }
  | { status: "opening" }
  | { status: "ready"; session: S }
  | { status: "locked"; kind: LockedKind; retrying: boolean };

export interface VaultGate<S = unknown> {
  getState(): VaultGateState<S>;
  subscribe(listener: () => void): () => void;
  /** Runs the first check. Once; later calls do nothing. */
  start(): void;
  /** The person typed four characters back on the setup screen. */
  confirmSetup(): Promise<void>;
  /** The Unlock screen's submit: null when it worked, else why not (the screen shows it). */
  unlock(text: string): Promise<UnlockError | null>;
  /** Locked's retry. */
  retry(): void;
  /** The open vault closed under the app (another tab): check again (reopen, or Unlock). */
  closed(): void;
  /** The sync said another account is signed in (409 `session_changed`): reload or lock. */
  sessionChanged(): void;
}

const UNLOCK_ERRORS: readonly string[] = [
  "bad_recovery_key",
  "wrong_recovery_key",
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

export function createVaultGate<K, S>(deps: VaultGateDeps<K, S>): VaultGate<S> {
  let state: VaultGateState<S> = { status: "checking" };
  const listeners = new Set<() => void>();
  let started = false;
  let prepared: GatePrepared<K> | null = null;
  let again: () => Promise<void> = check;

  const set = (next: VaultGateState<S>) => {
    state = next;
    for (const listener of listeners) listener();
  };

  /** The account has keys made elsewhere: Unlock, or Locked for a guest (nothing to type). */
  const hasKeysElsewhere = () => {
    prepared = null;
    if (deps.guest) set({ status: "locked", kind: "guest", retrying: false });
    else set({ status: "unlock" });
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
      set({ status: "ready", session: await deps.open(keys, fresh) });
    } catch (error) {
      // The keys are kept now: a retry starts over and finds them.
      if (codeOf(error) === "session_changed") await changed(error, check);
      else lock(error, check);
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
    if (keys) return open(keys, false);
    // Never make keys for an account that is no longer the signed-in one.
    if (!(await sameSession())) return;
    try {
      prepared = await deps.prepareAccount();
    } catch (error) {
      if (codeOf(error) === "already_set_up") hasKeysElsewhere();
      else if (codeOf(error) === "session_changed") await changed(error, check);
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
      await open(keys, true);
      return null;
    },
    closed() {
      if (state.status === "ready") void recheck();
    },
    sessionChanged() {
      if (state.status === "ready") void changed({ code: "session_changed" }, recheck);
    },
    retry() {
      if (state.status !== "locked" || state.retrying || FINAL.includes(state.kind)) return;
      set({ ...state, retrying: true });
      void again();
    },
  };
}
