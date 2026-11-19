import type { MigrationCounts, MigrationRecord } from "@wambito/vault";
import { countsOf } from "@wambito/vault";
import type { UnlockError } from "../vault/Unlock.tsx";

/**
 * The switch day's flow (E2E stage 5, spec 2026-11-19 section 3): a plain account with an email
 * moves to end-to-end encryption from the web, before the app. No React and no IndexedDB here;
 * every effect comes in as a dependency (`local/migration.ts` holds the live ones), so the tests
 * drive it with fakes, as `vault-gate.ts` does.
 *
 *   checking ─ available ─▶ intro ─ begin ─▶ start ─▶ keys (key shown) ─ confirm ─▶ commit ─┐
 *      │                                          └─ keys held here ─────────────────────────┤
 *      │                                          └─ the account has keys (already_set_up) ─▶ unlock ─┤
 *      │                                                                                       ▼
 *      │                     copying (resetAll, source, write, sync until the outbox is empty)
 *      │                                                                                       ▼
 *      │                                        finishing (finish with the client's counts) ─▶ done
 *      └─ in_progress ─┬─ keys here: start (this tab takes it over), then the step it was in
 *                      ├─ no keys, but this browser was showing its key: start, a new key
 *                      └─ no keys: noLocalVault ─ restart: start, cancel, resetAll, from the start
 *
 * Resume: meta `migrationStep` (`keys` | `copying` | `finishing`, through `remember`) is what a
 * reload reads. `keys` is written before the key is made, `copying` once the keys are kept (with
 * the moment the person confirmed the key), `finishing` once the outbox is empty; `null` at done.
 * A reload mid-copy starts the copy over (cancel, resetAll); one at `finishing` asks `finish` again.
 * A data key is made only while this browser holds none: once committed, every later step and
 * reload uses the kept keys.
 *
 * Failures: the plaintext stays on the server until a `finish` succeeds, so every failure is
 * honest and offers a retry. A failed commit commits the same prepared keys again; any other retry
 * runs `cancel`, `resetAll`, then the flow from `start` with the same keys (`taken_over` takes the
 * move back for this tab first, with `start`). `resetAll` runs only after a `cancel` that went
 * through: a `cancel` answered `not_migrating` or a `start` answered `not_migratable` (a finish
 * whose answer was lost, another tab of this browser that finished) re-reads the account instead;
 * an encrypted one reloads into the vault (never wiped), anything else is the server failure,
 * whose retry reloads. The flow never opens the vault session nor the
 * local backend (its first open seeds starter categories, its reads make recurring payments):
 * only `continue()` after done reloads, and the vault gate opens the keys kept here.
 */

export type MigrationStep = "keys" | "copying" | "finishing";

/** Why the move stopped; the plaintext is still there in every case. */
export type MigrationProblem = "count_mismatch" | "offline" | "server" | "taken_over";

/** A prepared new data key: the recovery key to show, and the commit that sends it. */
export interface MigrationPrepared<K> {
  recoveryKey: string | null;
  commit(): Promise<K>;
}

export interface MigrationDeps<K> {
  /** `GET /v1/me` `migration` when the page loaded. */
  migration: "available" | "in_progress";
  /** The keys this browser kept, or null. */
  loadLocalKeys(): Promise<K | null>;
  /** A new data key and recovery key, nothing sent; `{ code: "already_set_up" }` when the account has keys. */
  prepareAccount(): Promise<MigrationPrepared<K>>;
  /** Opens the account's keys with the recovery key; throws `{ code }` with an `UnlockError` code. */
  unlockWithRecovery(text: string): Promise<K>;
  /** What a reload resumes from (this browser's vault meta). */
  resume(): Promise<{ step: MigrationStep | null; keySavedAt: string | null }>;
  /** Notes the step (and, when given, when the person confirmed the recovery key). */
  remember(step: MigrationStep | null, keySavedAt?: string | null): Promise<void>;
  /**
   * `POST /v2/migration/start`: binds the move to this session (takes it over when migrating).
   * `{ code: "not_migratable" }` when the account cannot move (already encrypted, say).
   */
  start(): Promise<void>;
  /** `GET /v2/migration/source`, as records (`recordsFromSource`). */
  source(): Promise<MigrationRecord[]>;
  /** Writes the records into this browser's vault: one transaction, a tombstone for a deleted one. */
  write(records: MigrationRecord[]): Promise<void>;
  /** Pushes until the outbox is empty; `onProgress` gets how many changes the server took so far. */
  sync(keys: K, onProgress: (done: number) => void): Promise<void>;
  /** `POST /v2/migration/finish`; `{ code: "count_mismatch" }` when the copy does not match. */
  finish(counts: MigrationCounts): Promise<void>;
  /**
   * `POST /v2/migration/cancel`: the server's records go, the plaintext and the wraps stay.
   * `{ code: "not_migrating" }` when no move runs (finished, or never started).
   */
  cancel(): Promise<void>;
  /** `GET /v1/me` now: `encrypted` once a `finish` went through (whatever this page saw). */
  accountState(): Promise<"encrypted" | "migrating" | "plain">;
  /** Empties this browser's vault (records, outbox, cursors); keys and meta stay. */
  resetAll(): Promise<void>;
  /** Loads the page again: the loaders see the account as it is now. */
  reload(): void;
  now(): Date;
}

export type MigrationState =
  | { status: "checking" }
  | { status: "intro" }
  | { status: "keys"; recoveryKey: string; busy: boolean }
  /** The account already has keys (made in another browser): the recovery key opens them here. */
  | { status: "unlock" }
  | { status: "copying"; done: number; total: number }
  | { status: "finishing" }
  | { status: "done" }
  | { status: "failed"; problem: MigrationProblem; retrying: boolean }
  /** Migrating, but this browser has no vault for it: cancel it and start again here. */
  | { status: "noLocalVault"; busy: boolean };

export interface MigrationFlow {
  getState(): MigrationState;
  subscribe(listener: () => void): () => void;
  /** Runs the first check. Once; later calls do nothing. */
  start(): void;
  /** The intro's "Start". */
  begin(): Promise<void>;
  /** The person typed four characters of the key back. */
  confirmKey(): Promise<void>;
  /** Unlock's submit: null when it worked, else why not (the screen shows it). */
  unlock(text: string): Promise<UnlockError | null>;
  /** The failure's retry. */
  retry(): void;
  /** noLocalVault's "Start again here". */
  restart(): Promise<void>;
  /** Done's "Continue": reloads into the encrypted app. */
  continue(): void;
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

const problemOf = (error: unknown): MigrationProblem => {
  const code = codeOf(error);
  if (code === "count_mismatch") return "count_mismatch";
  if (code === "migration_in_progress") return "taken_over";
  if (code === "offline") return "offline";
  return "server";
};

/** The settings record with the moment the person confirmed the recovery key. */
const withKeySaved = (records: MigrationRecord[], at: string | null): MigrationRecord[] =>
  at === null
    ? records
    : records.map((r) =>
        r.type === "settings"
          ? { ...r, body: { ...(r.body as Record<string, unknown>), recoveryKeySavedAt: at } }
          : r,
      );

/** Thrown once the flow stopped on purpose (a reload, a failure already shown). */
const SETTLED = Symbol("settled");

export function createMigrationFlow<K>(deps: MigrationDeps<K>): MigrationFlow {
  let state: MigrationState = { status: "checking" };
  const listeners = new Set<() => void>();
  let started = false;
  let keys: K | null = null;
  let keySavedAt: string | null = null;
  let prepared: MigrationPrepared<K> | null = null;
  /** What the failure's retry runs. */
  let again: () => Promise<void> = fromScratch;

  const set = (next: MigrationState) => {
    state = next;
    for (const listener of listeners) listener();
  };

  /** Shows the failure; its retry runs `step`. Another account signed in: reload for them. */
  const fail = (error: unknown, step: () => Promise<void>) => {
    // Already handled: reloading, or the failure is on screen with its own retry.
    if (error === SETTLED) return;
    if (codeOf(error) === "session_changed") {
      set({ status: "checking" });
      deps.reload();
      return;
    }
    const problem = problemOf(error);
    // Taken over by another tab: this one takes it back before starting the copy over.
    again = problem === "taken_over" ? takeBack : step;
    set({ status: "failed", problem, retrying: false });
  };

  async function check(): Promise<void> {
    set({ status: "checking" });
    let resumed: { step: MigrationStep | null; keySavedAt: string | null };
    try {
      keys = await deps.loadLocalKeys();
      resumed = await deps.resume();
    } catch (error) {
      fail(error, check);
      return;
    }
    keySavedAt = resumed.keySavedAt;
    if (deps.migration === "available") {
      set({ status: "intro" });
      return;
    }
    if (keys) {
      // This tab takes the move over (a reload is a new page of the same session, or another
      // sign-in of this browser), then resumes where it was.
      if (resumed.step === "finishing") return guarded(resumeFinish);
      return guarded(takeBack);
    }
    // This browser was showing its key: nothing was kept, so a new one is made.
    if (resumed.step === "keys") return guarded(fromStart);
    set({ status: "noLocalVault", busy: false });
  }

  /** Runs `step`, sending any failure to the failed screen (its retry starts the copy over). */
  async function guarded(step: () => Promise<void>): Promise<void> {
    try {
      await step();
    } catch (error) {
      fail(error, fromScratch);
    }
  }

  /**
   * The server says no move runs (`not_migrating`, `not_migratable`): this page's view is stale.
   * Never `resetAll` here: the vault may be the encrypted account's only local copy now.
   */
  async function settle(): Promise<never> {
    const now = await deps.accountState();
    if (now === "encrypted") {
      set({ status: "checking" });
      deps.reload();
    } else {
      again = async () => deps.reload();
      set({ status: "failed", problem: "server", retrying: false });
    }
    throw SETTLED;
  }

  /** `start`, unless the server says the account cannot move any more. */
  async function startMove(): Promise<void> {
    try {
      await deps.start();
    } catch (error) {
      if (codeOf(error) === "not_migratable") await settle();
      throw error;
    }
  }

  /** Takes the move over for this tab, then starts the copy over. */
  async function takeBack(): Promise<void> {
    await startMove();
    await fromScratch();
  }

  /** The retry: the server's and this browser's records go, then the flow runs from `start`. */
  async function fromScratch(): Promise<void> {
    try {
      await deps.cancel();
    } catch (error) {
      if (codeOf(error) === "not_migrating") await settle();
      throw error;
    }
    // Only after a cancel that went through: the server holds no records of this move now.
    await deps.resetAll();
    await fromStart();
  }

  /** Step 1 onwards: start, the keys (when this browser holds none), then the copy. */
  async function fromStart(): Promise<void> {
    set({ status: "checking" });
    await startMove();
    if (keys) return copy(keys);
    await deps.remember("keys");
    try {
      prepared = await deps.prepareAccount();
    } catch (error) {
      if (codeOf(error) === "already_set_up") {
        set({ status: "unlock" });
        return;
      }
      throw error;
    }
    if (prepared.recoveryKey === null) return commit();
    set({ status: "keys", recoveryKey: prepared.recoveryKey, busy: false });
  }

  async function commit(): Promise<void> {
    const current = prepared;
    if (!current) return guarded(fromStart);
    if (state.status === "keys") set({ ...state, busy: true });
    let made: K;
    try {
      made = await current.commit();
    } catch (error) {
      // Another setup won the race: its keys are the account's; the recovery key opens them.
      if (codeOf(error) === "already_set_up") {
        prepared = null;
        set({ status: "unlock" });
        return;
      }
      // Retry-safe: the same wraps, the same ids.
      fail(error, commit);
      return;
    }
    prepared = null;
    keys = made;
    await kept(made);
  }

  /** Keys are kept here now: note the step and copy. */
  async function kept(made: K): Promise<void> {
    keySavedAt ??= deps.now().toISOString();
    try {
      await deps.remember("copying", keySavedAt);
      await copy(made);
    } catch (error) {
      fail(error, fromScratch);
    }
  }

  /** Steps 3 to 6: the source as records, into this browser's vault, pushed, then finish. */
  async function copy(current: K): Promise<void> {
    await deps.remember("copying");
    await deps.resetAll();
    const records = withKeySaved(await deps.source(), keySavedAt);
    set({ status: "copying", done: 0, total: records.length });
    await deps.write(records);
    await deps.sync(current, (done) => {
      if (state.status === "copying") set({ ...state, done: Math.min(done, state.total) });
    });
    await finishWith(records);
  }

  async function finishWith(records: MigrationRecord[]): Promise<void> {
    await deps.remember("finishing");
    set({ status: "finishing" });
    await deps.finish(countsOf(records));
    await deps.remember(null).catch(() => {
      // The account is encrypted now; the loaders never show the flow again.
    });
    set({ status: "done" });
  }

  /** A reload at `finishing`: everything was written; push what may be left, then finish. */
  async function resumeFinish(): Promise<void> {
    if (!keys) return fromStart();
    const current = keys;
    await startMove();
    const records = withKeySaved(await deps.source(), keySavedAt);
    set({ status: "finishing" });
    await deps.sync(current, () => {});
    await finishWith(records);
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
    async begin() {
      if (state.status !== "intro") return;
      await guarded(fromStart);
    },
    async confirmKey() {
      if (state.status !== "keys" || state.busy) return;
      await commit();
    },
    async unlock(text) {
      if (state.status !== "unlock") return null;
      let opened: K;
      try {
        opened = await deps.unlockWithRecovery(text);
      } catch (error) {
        const code = codeOf(error);
        if (code === "session_changed") {
          fail(error, fromScratch);
          return null;
        }
        return code && UNLOCK_ERRORS.includes(code) ? (code as UnlockError) : "server";
      }
      keys = opened;
      // The person just typed the recovery key: it is saved somewhere.
      keySavedAt = deps.now().toISOString();
      await kept(opened);
      return null;
    },
    retry() {
      if (state.status !== "failed" || state.retrying) return;
      set({ ...state, retrying: true });
      const step = again;
      void (async () => {
        try {
          await step();
        } catch (error) {
          fail(error, fromScratch);
        }
      })();
    },
    async restart() {
      if (state.status !== "noLocalVault" || state.busy) return;
      set({ status: "noLocalVault", busy: true });
      await guarded(takeBack);
    },
    continue() {
      if (state.status !== "done") return;
      deps.reload();
    },
  };
}
