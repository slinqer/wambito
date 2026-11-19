import {
  createSyncEngine,
  type MigrationCounts,
  type MigrationRecord,
  type MigrationSource,
  recordsFromSource,
} from "@wambito/vault";
import type { MigrationDeps, MigrationStep } from "../features/migration/migration-flow.ts";
import { createEncryptedStore, type EncryptedStore } from "./encrypted-store.ts";
import {
  type Keyring,
  type LocalKeys,
  loadLocalKeys,
  prepareAccount,
  refreshKeys,
  unlockWithRecovery,
} from "./keys.ts";

/**
 * The migration flow's live dependencies (`features/migration/migration-flow.ts`): the
 * `/v2/migration/*` calls, the keys, this browser's vault and a sync engine of its own. Never the
 * vault session nor the local backend: the session's first open seeds starter categories and the
 * backend's reads make recurring payments, and either would add records `finish` does not expect.
 * The source answer and the sync bodies are never logged.
 */

/** Why a call failed, in the flow's words (`count_mismatch`, `migration_in_progress`, …). */
export class MigrationError extends Error {
  constructor(
    readonly code: string,
    readonly status?: number,
  ) {
    super(code);
    this.name = "MigrationError";
  }
}

/** The API's codes the flow tells apart; anything else is `server`. */
const KNOWN = new Set(["count_mismatch", "migration_in_progress", "session_changed"]);

const STEP = "migrationStep";
const KEY_SAVED_AT = "migrationKeySavedAt";

export interface LiveMigrationOptions {
  userId: string;
  migration: "available" | "in_progress";
  /** The network. Defaults to the global `fetch`. */
  fetch?: typeof globalThis.fetch;
  /** Loads the page again (the flow's done, or another account signed in). */
  reload?: () => void;
  /** A 401: the session is gone. */
  onUnauthorized?: () => void;
  /** The sync engine's key refresh; defaults to `keys.ts` `refreshKeys`. */
  refreshKeys?: () => Promise<Keyring>;
  now?: () => Date;
}

async function problemCode(response: Response): Promise<string | undefined> {
  try {
    const body = (await response.clone().json()) as { code?: unknown };
    return typeof body.code === "string" ? body.code : undefined;
  } catch {
    return undefined;
  }
}

export function liveMigrationDeps(
  options: LiveMigrationOptions,
): MigrationDeps<LocalKeys> & { close(): void } {
  const { userId } = options;
  const network = options.fetch ?? ((input, init) => globalThis.fetch(input, init));
  let opening: Promise<EncryptedStore> | null = null;

  /** This flow's own connection to the vault, opened once. */
  const store = () => {
    opening ??= createEncryptedStore(userId);
    return opening;
  };

  async function call(path: string, init?: RequestInit): Promise<Response> {
    let response: Response;
    try {
      response = await network(`/api${path}`, {
        ...init,
        headers: {
          ...(init?.headers as Record<string, string> | undefined),
          // Names the vault's account: a cookie that now belongs to someone else gets a 409.
          "x-wambito-user": userId,
        },
      });
    } catch {
      throw new MigrationError("offline");
    }
    if (response.ok) return response;
    if (response.status === 401) options.onUnauthorized?.();
    const code = await problemCode(response);
    if (code && KNOWN.has(code)) throw new MigrationError(code, response.status);
    if (code === "not_migrating") throw new MigrationError(code, response.status);
    throw new MigrationError("server", response.status);
  }

  const post = (path: string, body?: unknown) =>
    call(
      path,
      body === undefined
        ? { method: "POST" }
        : {
            method: "POST",
            headers: { "content-type": "application/json" },
            body: JSON.stringify(body),
          },
    );

  return {
    migration: options.migration,
    loadLocalKeys: () => loadLocalKeys(userId),
    prepareAccount: () => prepareAccount({ userId, guest: false, fetch: network }),
    unlockWithRecovery: (text) => unlockWithRecovery({ userId, text, fetch: network }),
    async resume() {
      const s = await store();
      return {
        step: (await s.getMeta<MigrationStep>(STEP)) ?? null,
        keySavedAt: (await s.getMeta<string>(KEY_SAVED_AT)) ?? null,
      };
    },
    async remember(step, keySavedAt) {
      const s = await store();
      if (step === null) await s.deleteMeta(STEP);
      else await s.setMeta(STEP, step);
      if (keySavedAt === null) await s.deleteMeta(KEY_SAVED_AT);
      else if (keySavedAt !== undefined) await s.setMeta(KEY_SAVED_AT, keySavedAt);
    },
    async start() {
      await post("/v2/migration/start");
    },
    async source(): Promise<MigrationRecord[]> {
      const response = await call("/v2/migration/source");
      let body: MigrationSource;
      try {
        body = (await response.json()) as MigrationSource;
      } catch {
        throw new MigrationError("server", response.status);
      }
      return recordsFromSource(body, userId);
    },
    async write(records) {
      const s = await store();
      // One transaction: put every record, then delete the deleted ones (a tombstone that keeps
      // its body, as a delete on any device does).
      await s.transaction(async (tx) => {
        for (const r of records) await tx.put(r.type, r.id, r.body as never);
        for (const r of records) if (r.deleted) await tx.delete(r.type, r.id);
      });
    },
    async sync(keys, onProgress) {
      const s = await store();
      let done = 0;
      let takenOver = false;
      // Counts what the server took, and notes a refusal because another tab took the move.
      const watched = (async (input: RequestInfo | URL, init?: RequestInit) => {
        const response = await network(input, init);
        const method = (
          init?.method ?? (input instanceof Request ? input.method : "GET")
        ).toUpperCase();
        if (method !== "POST") return response;
        if (response.status === 409 && (await problemCode(response)) === "migration_in_progress") {
          takenOver = true;
        } else if (response.ok) {
          try {
            const body = (await response.clone().json()) as { results?: unknown[] };
            done += body.results?.length ?? 0;
            onProgress(done);
          } catch {
            // the engine reads it again and decides
          }
        }
        return response;
      }) as typeof globalThis.fetch;
      const engine = createSyncEngine({
        store: s,
        fetch: watched,
        userId,
        keyring: keys.keyring,
        refreshKeys:
          options.refreshKeys ??
          (async () => (await refreshKeys({ userId, fetch: network })).keyring),
      });
      for (;;) {
        const before = (await s.readOutbox(Number.MAX_SAFE_INTEGER)).length;
        if (before === 0) return;
        const result = await engine.run();
        if (takenOver) throw new MigrationError("migration_in_progress", 409);
        if (result.error === "offline") throw new MigrationError("offline");
        if (result.error === "session_changed") throw new MigrationError("session_changed", 409);
        const after = (await s.readOutbox(Number.MAX_SAFE_INTEGER)).length;
        if (after === 0) return;
        // Something the server will not take: never loop on it.
        if (!result.ok || result.parked.length > 0 || after >= before) {
          throw new MigrationError("server");
        }
      }
    },
    async finish(counts: MigrationCounts) {
      await post("/v2/migration/finish", { counts });
    },
    async cancel() {
      try {
        await post("/v2/migration/cancel");
      } catch (error) {
        // Nothing to cancel: the move never started, or was cancelled elsewhere.
        if (error instanceof MigrationError && error.code === "not_migrating") return;
        throw error;
      }
    },
    async resetAll() {
      await (await store()).resetAll();
    },
    reload: options.reload ?? (() => window.location.reload()),
    now: options.now ?? (() => new Date()),
    close() {
      void opening?.then((s) => s.close());
      opening = null;
    },
  };
}
