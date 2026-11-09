import { parseRecord, RECORD_TYPES, type RecordType } from "@wambito/core";
import {
  fromBase64Url,
  openRecord,
  type RecordKeys,
  sealRecord,
  toBase64Url,
} from "@wambito/crypto";
import type { OutboxEntry } from "./db.ts";
import {
  changedKeys,
  type EncryptedStore,
  type SetAsideOutcome,
  VaultClosedError,
} from "./encrypted-store.ts";

/**
 * The sync engine: pushes the outbox to `POST /v2/sync`, pulls `GET /v2/sync`, and keeps the
 * encrypted store equal to the server. Spec: 2026-11-08 end-to-end-encryption section 6, stage 1b
 * addendum section 3. It never logs or reports plaintext, only ids, types and counts.
 *
 * Decisions worth knowing:
 *
 * - A run pushes first, then pulls, so a pulled record rarely has a pending local change.
 * - A pulled record whose id has a pending outbox entry is NOT applied (the cursor still moves
 *   past it). The check is repeated inside the apply transaction (`skipIfPending`), so an edit
 *   made while the page was being opened is not overwritten either. The push's conflict path
 *   fetches the server's current copy and merges field by field, so nothing the person typed is
 *   overwritten and nothing the server sent is lost. Conflict writes use `ifSeq`: a newer local
 *   write wins over the merge, and is pushed (and merged) again.
 * - A conflict on a create (`baseVersion: null`) only happens for deterministic ids (recurrence
 *   occurrences, seeded records): the server's copy is taken whole and nothing is pushed.
 * - The base version of a push is always the row's `version` (0 means never pushed: a create).
 *   A conflict merge stores the merged body at the server's version without touching the outbox
 *   entry, so the entry stays pending and its next push is based on that version.
 * - A local delete beats a concurrent server edit (the delete is pushed again on the new
 *   version). A server delete beats a local edit; the id is reported in `serverDeleted`.
 * - `not_found` and `id_taken` drop the entry (reported in `dropped`).
 * - A change that keeps failing is parked (persisted on its outbox entry, with attempts and a
 *   short error code) and not pushed again until its back-off ends or the person edits it:
 *   an unreadable conflict copy, a fourth conflict in one run, no result for it, a whole batch
 *   refused with 413/422 (bisected down to the bad changes), or any other 4xx but 401 (the whole
 *   batch, e.g. 409 `key_version_mismatch`). Parks are reported (`parked`, ids only) and never
 *   stop the pull. Offline, 401, 429 and 5xx stop the run as before.
 * - A parked change still blocks pulls of its id (an edit is not overwritten while it retries).
 *   On its fifth failure the engine gives up (`abandoned`, reported in `dropped`): it is never
 *   pushed again, pulls write the id again, and the server's copy replaces it (at once when the
 *   failure was a conflict, whose copy is at hand; else with the next server edit or resync).
 * - Every call sends `x-wambito-user` (the vault's account). `409 session_changed` (the cookie is
 *   now someone else's) stops the run and `start()`'s triggers; the session reloads the app.
 * - A create that lost to the server's copy while the person kept writing keeps only the fields
 *   they changed after the create, as an edit of the server's copy.
 * - `410 resync_required`: in the wipe's own commit every pending change is set aside with its
 *   body (outbox kept), the records and cursors go, and the full download runs with `base=0`.
 *   After a complete download the set-aside changes are written again, only their `touched`
 *   fields onto the fresh copy. If the download fails the set-aside entries wait (they are not
 *   pushed) and the next run's full download restores them.
 * - Commits made by the engine never trigger a run; commits made by the person while a run is in
 *   flight are picked up by a follow-up pass (only for writes newer than the run's start, so a
 *   change left pending never loops).
 * - Runs take the Web Lock `wambito-sync-<userId>` when the browser has it, so two tabs never
 *   sync the same vault at once.
 */

/** The record format version this client reads and writes. */
const ENC_V = 1;
const PUSH_BATCH = 500;
/** Stay under the server's 4 MiB request limit. */
const PUSH_BYTES = 3 * 1024 * 1024;
const PULL_LIMIT = 1000;
/** How many times one id may conflict inside one run before it is parked. */
const MAX_CONFLICTS = 3;
/** The failure on which a parked change is given up on (`abandoned`). */
const MAX_ATTEMPTS = 5;
/** A parked change's back-off: 1 min, doubling, at most 6 hours. */
const parkDelay = (attempts: number) => Math.min(60_000 * 2 ** (attempts - 1), 6 * 3_600_000);

export type SyncProblemCode =
  | "offline"
  | "server"
  | "unauthorized"
  | "rejected"
  | "dropped"
  | "server_deleted"
  | "quarantined"
  | "conflict_unreadable"
  /** Changes the engine gave up on for now (see `SyncResult.parked`). */
  | "parked"
  /** The store was closed (another tab deleted the vault, or the session closed it). */
  | "closed"
  /** The signed-in account is not the vault's (409 `session_changed`): the engine stops. */
  | "session_changed";

/** Something the UI may want to tell the person. Ids and counts only. */
export interface SyncProblem {
  code: SyncProblemCode;
  ids?: string[];
  count?: number;
  status?: number;
}

export interface SyncResult {
  /** False when the run stopped early (offline, server error): retry later. */
  ok: boolean;
  pushed: number;
  pulled: number;
  merged: number;
  /** Ids of records the server had deleted while the person had unsent edits. */
  serverDeleted: string[];
  /** Ids of changes dropped (`not_found`, `id_taken`, or given up on after 5 failures). */
  dropped: string[];
  quarantined: number;
  /** Ids of changes parked in this run (they back off; a local edit retries them at once). */
  parked: string[];
  resynced: boolean;
  error?: SyncProblemCode;
}

export interface SyncEngineOptions {
  store: EncryptedStore;
  /** Defaults to the global `fetch`. */
  fetch?: typeof globalThis.fetch;
  /** Where `/v2/sync` lives. Default `/api`. */
  baseUrl?: string;
  /** The account's exact id (it is part of every record's associated data). */
  userId: string;
  keys: RecordKeys;
  keyV: number;
  now?: () => number;
  onError?: (problem: SyncProblem) => void;
  /** `start()` only. Defaults: 1000, 60000. */
  debounceMs?: number;
  intervalMs?: number;
}

export interface SyncEngine {
  /** One push-then-pull cycle. Calls made while one runs share it (and force one more pass). */
  run(): Promise<SyncResult>;
  /** Starts the triggers (now, focus, visibility, local writes, every minute). Returns stop. */
  start(): () => void;
}

interface WireRecord {
  id: string;
  type: string;
  version: number;
  deleted: boolean;
  keyV: number;
  encV: number;
  body: string | null;
}

type PushResult =
  | { id: string; version: number }
  | { id: string; conflict: WireRecord }
  | { id: string; error: "id_taken" | "not_found" };

/** Thrown to stop a run; `problem` says why. */
class Stop extends Error {
  constructor(
    readonly code: SyncProblemCode,
    readonly status?: number,
  ) {
    super(code);
  }
}

class ResyncRequired extends Error {}

const isRecordType = (type: string): type is RecordType =>
  (RECORD_TYPES as string[]).includes(type);

/** JSON with sorted keys, to compare two bodies whatever their key order. */
function canonical(value: unknown): string {
  if (Array.isArray(value)) return `[${value.map(canonical).join(",")}]`;
  if (value && typeof value === "object") {
    const o = value as Record<string, unknown>;
    return `{${Object.keys(o)
      .sort()
      .filter((k) => o[k] !== undefined)
      .map((k) => `${JSON.stringify(k)}:${canonical(o[k])}`)
      .join(",")}}`;
  }
  return JSON.stringify(value) ?? "null";
}

/** Fields in `touched` keep the local value; every other field takes the server's. */
function mergeBodies(local: unknown, server: unknown, touched: string[]): unknown {
  const l = (local ?? {}) as Record<string, unknown>;
  const s = (server ?? {}) as Record<string, unknown>;
  const out: Record<string, unknown> = {};
  for (const key of new Set([...Object.keys(l), ...Object.keys(s)])) {
    const value = touched.includes(key) ? l[key] : s[key];
    if (value !== undefined) out[key] = value;
  }
  return out;
}

export function createSyncEngine(options: SyncEngineOptions): SyncEngine {
  const { store, userId, keys, keyV, onError } = options;
  const baseUrl = options.baseUrl ?? "/api";
  const now = options.now ?? Date.now;
  const doFetch = (input: string, init?: RequestInit) => (options.fetch ?? fetch)(input, init);

  const report = (problem: SyncProblem) => {
    try {
      onError?.(problem);
    } catch {
      // a listener must not break the sync
    }
  };

  async function call(path: string, init?: RequestInit): Promise<unknown> {
    let response: Response;
    try {
      response = await doFetch(`${baseUrl}${path}`, {
        ...init,
        headers: {
          ...(init?.headers as Record<string, string> | undefined),
          "x-wambito-user": userId,
        },
      });
    } catch {
      throw new Stop("offline");
    }
    if (response.status === 409 && (await problemCode(response)) === "session_changed") {
      throw new Stop("session_changed", 409);
    }
    if (response.status === 410) throw new ResyncRequired();
    if (response.status === 401) throw new Stop("unauthorized", 401);
    if (response.status === 429 || response.status >= 500)
      throw new Stop("server", response.status);
    if (!response.ok) throw new Stop("rejected", response.status);
    return response.json();
  }

  const ctx = (type: RecordType, id: string, v: number) => ({ userId, type, id, keyV: v });

  /** Opens and validates a server record: the body, or why it cannot be used. */
  async function openWire(
    rec: WireRecord,
  ): Promise<{ ok: true; body: unknown } | { ok: false; reason: string }> {
    if (!isRecordType(rec.type)) return { ok: false, reason: "unknown_type" };
    if (rec.encV !== ENC_V) return { ok: false, reason: "unsupported_enc_v" };
    if (rec.body === null) return { ok: false, reason: "missing_body" };
    let json: unknown;
    try {
      json = await openRecord(keys, ctx(rec.type, rec.id, rec.keyV), fromBase64Url(rec.body));
    } catch {
      return { ok: false, reason: "cannot_open" };
    }
    const parsed = parseRecord(rec.type, json);
    if (!parsed.ok) return { ok: false, reason: "invalid" };
    return { ok: true, body: parsed.value };
  }

  async function quarantine(rec: WireRecord, reason: string) {
    await store.quarantine({
      id: rec.id,
      type: rec.type as RecordType,
      version: rec.version,
      reason,
    });
  }

  // ---- push ----------------------------------------------------------------------------------

  interface Prepared {
    entry: OutboxEntry;
    /** The plaintext sent (a create conflict keeps only what changed after it). */
    body: unknown;
    change: Record<string, unknown>;
    size: number;
  }

  async function prepare(entry: OutboxEntry): Promise<Prepared | undefined> {
    const row = await store.getRaw(entry.type, entry.id);
    if (!row) {
      // Nothing local to send (should not happen): clear the entry.
      await store.ackOutbox(entry.id, 0, entry.seq);
      return undefined;
    }
    const deleted = entry.deleted || row.deleted;
    const sealed = deleted
      ? null
      : toBase64Url(await sealRecord(keys, ctx(entry.type, entry.id, keyV), row.body));
    return {
      entry,
      body: row.body,
      size: (sealed?.length ?? 0) + 200,
      change: {
        id: entry.id,
        type: entry.type,
        baseVersion: row.version > 0 ? row.version : null,
        deleted,
        keyV,
        encV: ENC_V,
        body: sealed,
      },
    };
  }

  async function handleConflict(
    p: Prepared,
    server: WireRecord,
    result: SyncResult,
  ): Promise<void> {
    const { entry } = p;
    const created = p.change.baseVersion === null;
    const type = entry.type;
    const row = await store.getRaw(type, entry.id);
    const remote = {
      origin: "remote",
      version: server.version,
      keyV: server.keyV,
      ifSeq: entry.seq,
    } as const;
    if (server.deleted) {
      await store.delete(type, entry.id, remote);
      await store.ackOutbox(entry.id, server.version, entry.seq);
      if (!entry.deleted) {
        result.serverDeleted.push(entry.id);
        report({ code: "server_deleted", ids: [entry.id] });
      }
      return;
    }
    if (entry.deleted && !created) {
      // The person's delete wins: keep the server's copy as the base and push the delete again.
      await store.transaction(async (tx) => {
        await tx.put(type, entry.id, row?.body as never, remote);
        await tx.delete(type, entry.id, remote);
      });
      result.merged += 1;
      return;
    }
    const opened = await openWire(server);
    if (!opened.ok) {
      await quarantine(server, opened.reason);
      result.quarantined += 1;
      report({ code: "conflict_unreadable", ids: [entry.id] });
      throw new Skip("conflict_unreadable");
    }
    if (created) {
      // Two devices created the same deterministic id: the server's copy wins, plus whatever the
      // person changed after the create (a write made while it was in flight).
      await store.adoptServerCopy(
        type,
        entry.id,
        entry.seq,
        { version: server.version, keyV: server.keyV, body: opened.body },
        (local) => {
          const touched = changedKeys(p.body, local);
          const rebased = parseRecord(type, mergeBodies(local, opened.body, touched));
          return rebased.ok ? { body: rebased.value, touched } : { body: opened.body, touched: [] };
        },
      );
      result.merged += 1;
      return;
    }
    const merged = mergeBodies(row?.body, opened.body, entry.touched);
    const parsed = parseRecord(type, merged);
    // A merge of two valid bodies that is not valid itself: the server's copy is the safe side.
    const next = parsed.ok ? parsed.value : opened.body;
    await store.put(type, entry.id, next as never, remote);
    if (canonical(next) === canonical(opened.body)) {
      // Nothing of ours differs from the server's copy (two devices made the same record).
      await store.ackOutbox(entry.id, server.version, entry.seq);
    }
    result.merged += 1;
  }

  /**
   * Gives up on `entry` for now; it backs off and is reported. On its fifth failure, for good: it
   * is abandoned, and `server` (the conflict's copy, when there is one) replaces it at once.
   */
  async function park(
    entry: OutboxEntry,
    lastError: string,
    result: SyncResult,
    server?: WireRecord,
  ) {
    const attempts = (entry.park?.attempts ?? 0) + 1;
    const park = { attempts, lastError, until: now() + parkDelay(attempts) };
    if (attempts < MAX_ATTEMPTS) {
      await store.parkOutbox(entry.id, entry.seq, park);
      result.parked.push(entry.id);
      return;
    }
    await store.abandonOutbox(entry.id, entry.seq, park);
    result.dropped.push(entry.id);
    if (!server) return;
    const remote = {
      origin: "remote",
      version: server.version,
      keyV: server.keyV,
      ifSeq: entry.seq,
    } as const;
    if (server.deleted) {
      await store.delete(entry.type, entry.id, remote);
      return;
    }
    const opened = await openWire(server);
    if (opened.ok) await store.put(entry.type, entry.id, opened.body as never, remote);
  }

  async function push(result: SyncResult): Promise<void> {
    const conflicts = new Map<string, number>();
    /** The seq of each entry this run is done with: it is sent again only after a newer write. */
    const handled = new Map<string, number>();
    const due = (e: OutboxEntry) =>
      !e.setAside &&
      !e.abandoned &&
      (!e.park || e.park.until <= now()) &&
      handled.get(e.id) !== e.seq;

    async function settle(p: Prepared, r: PushResult | undefined) {
      const { entry } = p;
      handled.set(entry.id, entry.seq);
      if (!r) {
        await park(entry, "no_result", result);
      } else if ("version" in r) {
        await store.ackOutbox(entry.id, r.version, entry.seq);
        result.pushed += 1;
      } else if ("conflict" in r) {
        const count = (conflicts.get(entry.id) ?? 0) + 1;
        conflicts.set(entry.id, count);
        if (count > MAX_CONFLICTS) {
          await park(entry, "conflict_limit", result, r.conflict);
          return;
        }
        try {
          await handleConflict(p, r.conflict, result);
          // Still pending after the merge: push it again on the server's version.
          handled.delete(entry.id);
        } catch (error) {
          if (!(error instanceof Skip)) throw error;
          await park(entry, error.message, result);
        }
      } else {
        // id_taken / not_found: the server will never take this change.
        const row = await store.getRaw(entry.type, entry.id);
        await store.ackOutbox(entry.id, row?.version ?? 0, entry.seq);
        result.dropped.push(entry.id);
      }
    }

    /** Sends a batch; a refused one is bisected (413/422) or parked whole (other 4xx). */
    async function send(batch: Prepared[]): Promise<void> {
      let response: { results: PushResult[] };
      try {
        response = (await call("/v2/sync", {
          method: "POST",
          headers: { "content-type": "application/json" },
          body: JSON.stringify({ changes: batch.map((p) => p.change) }),
        })) as { results: PushResult[] };
      } catch (error) {
        if (!(error instanceof Stop) || error.code !== "rejected") throw error;
        const code = `rejected_${error.status}`;
        if ((error.status === 413 || error.status === 422) && batch.length > 1) {
          const half = Math.ceil(batch.length / 2);
          await send(batch.slice(0, half));
          await send(batch.slice(half));
          return;
        }
        for (const p of batch) {
          handled.set(p.entry.id, p.entry.seq);
          await park(p.entry, code, result);
        }
        return;
      }
      const byId = new Map((response.results ?? []).map((r) => [r.id, r]));
      for (const p of batch) await settle(p, byId.get(p.entry.id));
    }

    for (;;) {
      const pending = (await store.readOutbox(Number.MAX_SAFE_INTEGER)).filter(due);
      if (pending.length === 0) return;
      const batch: Prepared[] = [];
      let bytes = 0;
      for (const entry of pending) {
        if (batch.length >= PUSH_BATCH) break;
        const prepared = await prepare(entry);
        if (!prepared) continue;
        if (batch.length > 0 && bytes + prepared.size > PUSH_BYTES) break;
        bytes += prepared.size;
        batch.push(prepared);
      }
      if (batch.length === 0) continue;
      await send(batch);
    }
  }

  // ---- pull ----------------------------------------------------------------------------------

  async function pull(result: SyncResult): Promise<void> {
    const since0 = (await store.getMeta<number>("latest")) ?? 0;
    const base = (await store.getMeta<number>("base")) ?? since0;
    let since = since0;
    let latest = since0;
    for (;;) {
      const page = (await call(`/v2/sync?since=${since}&base=${base}&limit=${PULL_LIMIT}`)) as {
        records: WireRecord[];
        next: number | null;
        latest: number;
      };
      const pending = new Set(
        (await store.readOutbox(Number.MAX_SAFE_INTEGER))
          .filter((e) => !e.setAside && !e.abandoned)
          .map((e) => e.id),
      );
      type Apply = { rec: WireRecord; body: unknown } | { rec: WireRecord; body: null };
      const apply: Apply[] = [];
      let quarantined = 0;
      for (const rec of page.records) {
        if (pending.has(rec.id)) continue; // the push's conflict path merges it
        if (!isRecordType(rec.type)) {
          await quarantine(rec, "unknown_type");
          quarantined += 1;
        } else if (rec.deleted) {
          apply.push({ rec, body: null });
        } else {
          const opened = await openWire(rec);
          if (opened.ok) apply.push({ rec, body: opened.body });
          else {
            await quarantine(rec, opened.reason);
            quarantined += 1;
          }
        }
      }
      if (apply.length > 0) {
        await store.transaction(async (tx) => {
          for (const { rec, body } of apply) {
            // Checked again here: the person may have written it since `pending` was read.
            const remote = {
              origin: "remote",
              version: rec.version,
              keyV: rec.keyV,
              skipIfPending: true,
            } as const;
            const type = rec.type as RecordType;
            if (body === null) await tx.delete(type, rec.id, remote);
            else await tx.put(type, rec.id, body as never, remote);
          }
        });
      }
      result.pulled += apply.length;
      result.quarantined += quarantined;
      if (quarantined > 0) report({ code: "quarantined", count: quarantined });
      latest = page.latest;
      if (page.next === null) break;
      since = page.next;
    }
    await store.setMeta("latest", latest);
    await store.setMeta("base", latest);
    // A resync's set-aside changes, once a whole download has landed.
    const outbox = await store.readOutbox(Number.MAX_SAFE_INTEGER);
    if (outbox.some((e) => e.setAside)) await restoreSetAside(result);
  }

  /** The server purged tombstones we may have missed: download everything again. */
  async function resync(result: SyncResult): Promise<void> {
    // Sets the pending changes aside in the same commit, so a failed download loses nothing.
    await store.wipeRecords();
    result.resynced = true;
    await pull(result);
  }

  /** Writes the set-aside changes again onto the fresh copies: only their touched fields. */
  async function restoreSetAside(result: SyncResult): Promise<void> {
    const serverDeleted: string[] = [];
    await store.restoreSetAside((entry, fresh): SetAsideOutcome => {
      const live = fresh && !fresh.deleted ? fresh : undefined;
      if (entry.deleted) return live ? { delete: true } : { drop: true };
      const aside = entry.setAside?.body;
      if (aside === null || aside === undefined) return { drop: true };
      if (entry.baseVersion === null) {
        // Never pushed: a create, unless the server has the id (a deterministic id): theirs wins.
        return fresh ? { drop: true } : { put: aside };
      }
      if (!live) {
        // The server deleted it: the deletion wins, and the person is told.
        serverDeleted.push(entry.id);
        return { drop: true };
      }
      const merged = mergeBodies(aside, live.body, entry.touched);
      const parsed = parseRecord(entry.type, merged);
      return parsed.ok ? { put: parsed.value } : { drop: true };
    });
    if (serverDeleted.length > 0) {
      result.serverDeleted.push(...serverDeleted);
      report({ code: "server_deleted", ids: serverDeleted });
    }
  }

  // ---- run -----------------------------------------------------------------------------------

  async function once(): Promise<SyncResult> {
    const result: SyncResult = {
      ok: true,
      pushed: 0,
      pulled: 0,
      merged: 0,
      serverDeleted: [],
      dropped: [],
      quarantined: 0,
      parked: [],
      resynced: false,
    };
    try {
      await push(result);
      try {
        await pull(result);
      } catch (error) {
        if (!(error instanceof ResyncRequired)) throw error;
        await resync(result);
      }
      await store.setMeta("lastSync", now());
    } catch (error) {
      if (error instanceof ResyncRequired) {
        // A 410 on the push path cannot happen; treat it as a server problem.
        result.ok = false;
        result.error = "server";
      } else if (error instanceof Stop) {
        result.ok = false;
        result.error = error.code;
        report({ code: error.code, status: error.status });
      } else if (error instanceof VaultClosedError || store.isClosed()) {
        result.ok = false;
        result.error = "closed";
        report({ code: "closed" });
      } else {
        throw error;
      }
    }
    if (result.dropped.length > 0) report({ code: "dropped", ids: result.dropped });
    if (result.parked.length > 0) report({ code: "parked", ids: [...new Set(result.parked)] });
    return result;
  }

  let current: Promise<SyncResult> | null = null;
  let again = false;
  /** True while a run is in flight: its own commits must not schedule another. */
  let running = false;

  /** One run's passes as one result: counts added, ids joined, `ok`/`error` of the last. */
  function combine(a: SyncResult | undefined, b: SyncResult): SyncResult {
    if (!a) return b;
    return {
      ...b,
      pushed: a.pushed + b.pushed,
      pulled: a.pulled + b.pulled,
      merged: a.merged + b.merged,
      quarantined: a.quarantined + b.quarantined,
      serverDeleted: [...a.serverDeleted, ...b.serverDeleted],
      dropped: [...a.dropped, ...b.dropped],
      parked: [...a.parked, ...b.parked],
      resynced: a.resynced || b.resynced,
    };
  }

  /** The store's write counter: outbox entries above it were written after this point. */
  async function mark(): Promise<number> {
    try {
      return (await store.getMeta<number>("seq")) ?? 0;
    } catch {
      return Number.MAX_SAFE_INTEGER; // closed: `once` reports it
    }
  }

  /** Another tab's run of the same vault waits for ours (Web Locks), where the browser has them. */
  function locked<R>(fn: () => Promise<R>): Promise<R> {
    const locks = (globalThis.navigator as Navigator | undefined)?.locks;
    if (!locks?.request) return fn();
    return locks.request(`wambito-sync-${userId}`, fn) as Promise<R>;
  }

  function run(): Promise<SyncResult> {
    if (current) {
      again = true;
      return current;
    }
    current = (async () => {
      running = true;
      try {
        return await locked(async () => {
          let last: SyncResult | undefined;
          do {
            again = false;
            const start = await mark();
            last = combine(last, await once());
            // Only what the person wrote during the run gets one more pass: a change left
            // pending (parked, set aside, waiting) waits for the next trigger.
            if (last.ok && !again) {
              const outbox = await store.readOutbox(Number.MAX_SAFE_INTEGER);
              if (outbox.some((e) => e.seq > start)) again = true;
            }
          } while (again && last.ok);
          return last;
        });
      } finally {
        running = false;
        current = null;
      }
    })();
    return current;
  }

  // ---- triggers ------------------------------------------------------------------------------

  function start(): () => void {
    const debounceMs = options.debounceMs ?? 1000;
    const intervalMs = options.intervalMs ?? 60_000;
    let stopped = false;
    let failures = 0;
    let debounce: ReturnType<typeof setTimeout> | undefined;
    let retry: ReturnType<typeof setTimeout> | undefined;

    const trigger = () => {
      if (stopped) return;
      void run()
        .then((result) => {
          if (stopped) return;
          clearTimeout(retry);
          if (result.ok) {
            failures = 0;
          } else if (result.error === "session_changed") {
            // Someone else's cookie: never again in this page (the session reloads it).
            stop();
          } else if (result.error !== "closed") {
            failures += 1;
            const delay = Math.min(2000 * 2 ** (failures - 1), 5 * 60_000);
            retry = setTimeout(trigger, delay);
          }
        })
        .catch(() => {
          // a bug in the engine must not stop the timers; the next trigger tries again
        });
    };
    const visible = () => typeof document === "undefined" || document.visibilityState === "visible";
    const onVisibility = () => {
      if (visible()) trigger();
    };
    const unsubscribe = store.subscribe(() => {
      if (running || stopped) return;
      clearTimeout(debounce);
      debounce = setTimeout(trigger, debounceMs);
    });
    const interval = setInterval(() => {
      if (visible()) trigger();
    }, intervalMs);
    if (typeof document !== "undefined")
      document.addEventListener("visibilitychange", onVisibility);
    if (typeof window !== "undefined") window.addEventListener("focus", trigger);
    trigger();

    function stop() {
      stopped = true;
      clearTimeout(debounce);
      clearTimeout(retry);
      clearInterval(interval);
      unsubscribe();
      if (typeof document !== "undefined") {
        document.removeEventListener("visibilitychange", onVisibility);
      }
      if (typeof window !== "undefined") window.removeEventListener("focus", trigger);
    }
    return stop;
  }

  return { run, start };
}

/** The problem's `code`, if the body has one. */
async function problemCode(response: Response): Promise<string | undefined> {
  try {
    const body = (await response.clone().json()) as { code?: unknown };
    return typeof body.code === "string" ? body.code : undefined;
  } catch {
    return undefined;
  }
}

/** Internal: park this change; the message is the park's `lastError`. */
class Skip extends Error {}
