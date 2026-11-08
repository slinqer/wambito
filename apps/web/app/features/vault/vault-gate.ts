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
}

export type VaultGateState<S = unknown> =
  | { status: "checking" }
  | { status: "setup"; recoveryKey: string }
  | { status: "committing" }
  | { status: "unlock" }
  | { status: "opening" }
  | { status: "ready"; session: S }
  | { status: "locked"; kind: "error" | "offline"; retrying: boolean };

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

const lockedKind = (error: unknown): "error" | "offline" =>
  codeOf(error) === "offline" ? "offline" : "error";

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

  /** Shows Locked; its retry runs `step`. */
  const lock = (error: unknown, step: () => Promise<void>) => {
    again = step;
    set({ status: "locked", kind: lockedKind(error), retrying: false });
  };

  async function open(keys: K, fresh: boolean): Promise<void> {
    set({ status: "opening" });
    try {
      set({ status: "ready", session: await deps.open(keys, fresh) });
    } catch (error) {
      // The keys are kept now: a retry starts over and finds them.
      lock(error, check);
    }
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
    try {
      prepared = await deps.prepareAccount();
    } catch (error) {
      if (codeOf(error) === "already_set_up") set({ status: "unlock" });
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
      lock(error, commit);
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
      let keys: K;
      try {
        keys = await deps.unlockWithRecovery(text);
      } catch (error) {
        const code = codeOf(error);
        return code && UNLOCK_ERRORS.includes(code) ? (code as UnlockError) : "server";
      }
      await open(keys, true);
      return null;
    },
    retry() {
      if (state.status !== "locked" || state.retrying) return;
      set({ ...state, retrying: true });
      void again();
    },
  };
}
