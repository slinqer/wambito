import { parseRecord, RECORD_TYPES, type RecordType } from "@wambito/core";
import {
  fromBase64Url,
  openRecord,
  type RecordKeys,
  sealRecord,
  toBase64Url,
} from "@wambito/crypto";
import type { OutboxEntry } from "./db.ts";
import type { EncryptedStore } from "./encrypted-store.ts";

/**
 * The sync engine: pushes the outbox to `POST /v2/sync`, pulls `GET /v2/sync`, and keeps the
 * encrypted store equal to the server. Spec: 2026-11-08 end-to-end-encryption section 6, stage 1b
 * addendum section 3. It never logs or reports plaintext, only ids, types and counts.
 *
 * Decisions worth knowing:
 *
 * - A run pushes first, then pulls, so a pulled record rarely has a pending local change.
 * - A pulled record whose id has a pending outbox entry is NOT applied (the cursor still moves
 *   past it). The push's conflict path fetches the server's current copy and merges field by
 *   field, so nothing the person typed is overwritten and nothing the server sent is lost.
 * - The base version of a push is always the row's `version` (0 means never pushed: a create).
 *   A conflict merge stores the merged body at the server's version without touching the outbox
 *   entry, so the entry stays pending and its next push is based on that version.
 * - A local delete beats a concurrent server edit (the delete is pushed again on the new
 *   version). A server delete beats a local edit; the id is reported in `serverDeleted`.
 * - `not_found` and `id_taken` drop the entry (reported in `dropped`).
 * - `410 resync_required`: the pending local changes are set aside, the records are wiped, the
 *   full download runs with `base=0`, and the set-aside changes are written again as local
 *   writes (so they diff against the fresh server copy and push as ordinary edits).
 * - Commits made by the engine never trigger a run; commits made by the person while a run is in
 *   flight are picked up by a follow-up pass.
 */

/** The record format version this client reads and writes. */
const ENC_V = 1;
const PUSH_BATCH = 500;
/** Stay under the server's 4 MiB request limit. */
const PUSH_BYTES = 3 * 1024 * 1024;
const PULL_LIMIT = 1000;
/** How many times one id may conflict inside one run before it is left for the next. */
const MAX_CONFLICTS = 3;

export type SyncProblemCode =
  | "offline"
  | "server"
  | "unauthorized"
  | "rejected"
  | "dropped"
  | "server_deleted"
  | "quarantined"
  | "conflict_unreadable";

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
  /** Ids of changes dropped (`not_found`, `id_taken`). */
  dropped: string[];
  quarantined: number;
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
      response = await doFetch(`${baseUrl}${path}`, init);
    } catch {
      throw new Stop("offline");
    }
    if (response.status === 410) throw new ResyncRequired();
    if (response.status === 401) throw new Stop("unauthorized", 401);
    if (response.status === 409 || response.status >= 500)
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
    entry: OutboxEntry,
    server: WireRecord,
    result: SyncResult,
  ): Promise<void> {
    const type = entry.type;
    const row = await store.getRaw(type, entry.id);
    if (server.deleted) {
      await store.delete(type, entry.id, {
        origin: "remote",
        version: server.version,
        keyV: server.keyV,
      });
      await store.ackOutbox(entry.id, server.version, entry.seq);
      if (!entry.deleted) {
        result.serverDeleted.push(entry.id);
        report({ code: "server_deleted", ids: [entry.id] });
      }
      return;
    }
    if (entry.deleted) {
      // The person's delete wins: keep the server's copy as the base and push the delete again.
      await store.put(type, entry.id, row?.body as never, {
        origin: "remote",
        version: server.version,
        keyV: server.keyV,
      });
      await store.delete(type, entry.id, {
        origin: "remote",
        version: server.version,
        keyV: server.keyV,
      });
      result.merged += 1;
      return;
    }
    const opened = await openWire(server);
    if (!opened.ok) {
      await quarantine(server, opened.reason);
      result.quarantined += 1;
      report({ code: "conflict_unreadable", ids: [entry.id] });
      throw new Skip();
    }
    const merged = mergeBodies(row?.body, opened.body, entry.touched);
    const parsed = parseRecord(type, merged);
    // A merge of two valid bodies that is not valid itself: the server's copy is the safe side.
    const next = parsed.ok ? parsed.value : opened.body;
    const remote = { origin: "remote", version: server.version, keyV: server.keyV } as const;
    await store.put(type, entry.id, next as never, remote);
    if (canonical(next) === canonical(opened.body)) {
      // Nothing of ours differs from the server's copy (two devices made the same record).
      await store.ackOutbox(entry.id, server.version, entry.seq);
    }
    result.merged += 1;
  }

  async function push(result: SyncResult): Promise<void> {
    const conflicts = new Map<string, number>();
    for (;;) {
      const all = await store.readOutbox(Number.MAX_SAFE_INTEGER);
      const due = all.filter((e) => (conflicts.get(e.id) ?? 0) < MAX_CONFLICTS);
      if (due.length === 0) return;
      const batch: Prepared[] = [];
      let bytes = 0;
      for (const entry of due) {
        if (batch.length >= PUSH_BATCH) break;
        const prepared = await prepare(entry);
        if (!prepared) continue;
        if (batch.length > 0 && bytes + prepared.size > PUSH_BYTES) break;
        bytes += prepared.size;
        batch.push(prepared);
      }
      if (batch.length === 0) continue;
      const response = (await call("/v2/sync", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ changes: batch.map((p) => p.change) }),
      })) as { results: PushResult[] };
      const byId = new Map(response.results.map((r) => [r.id, r]));
      for (const { entry } of batch) {
        const r = byId.get(entry.id);
        if (!r) continue;
        if ("version" in r) {
          await store.ackOutbox(entry.id, r.version, entry.seq);
          result.pushed += 1;
        } else if ("conflict" in r) {
          conflicts.set(entry.id, (conflicts.get(entry.id) ?? 0) + 1);
          try {
            await handleConflict(entry, r.conflict, result);
          } catch (error) {
            if (!(error instanceof Skip)) throw error;
            conflicts.set(entry.id, MAX_CONFLICTS);
          }
        } else {
          // id_taken / not_found: the server will never take this change.
          const row = await store.getRaw(entry.type, entry.id);
          await store.ackOutbox(entry.id, row?.version ?? 0, entry.seq);
          result.dropped.push(entry.id);
        }
      }
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
      const pending = new Set((await store.readOutbox(Number.MAX_SAFE_INTEGER)).map((e) => e.id));
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
            const remote = { origin: "remote", version: rec.version, keyV: rec.keyV } as const;
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
  }

  /** The server purged tombstones we may have missed: download everything again. */
  async function resync(result: SyncResult): Promise<void> {
    const setAside: Array<{ entry: OutboxEntry; body: unknown }> = [];
    for (const entry of await store.readOutbox(Number.MAX_SAFE_INTEGER)) {
      const row = await store.getRaw(entry.type, entry.id);
      if (row) setAside.push({ entry, body: row.body });
    }
    await store.wipeRecords();
    await store.setMeta("latest", 0);
    await store.setMeta("base", 0);
    await pull(result);
    // Written again as ordinary local edits: they diff against the fresh server copy.
    for (const { entry, body } of setAside) {
      if (entry.deleted) await store.delete(entry.type, entry.id);
      else await store.put(entry.type, entry.id, body as never);
    }
    result.resynced = true;
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
      } else {
        throw error;
      }
    }
    if (result.dropped.length > 0) report({ code: "dropped", ids: result.dropped });
    return result;
  }

  let current: Promise<SyncResult> | null = null;
  let again = false;
  /** True while a run is in flight: its own commits must not schedule another. */
  let running = false;

  function run(): Promise<SyncResult> {
    if (current) {
      again = true;
      return current;
    }
    current = (async () => {
      running = true;
      try {
        let last: SyncResult;
        do {
          again = false;
          last = await once();
          // Anything the person wrote during the run is still pending: one more pass.
          if (last.ok && !again && (await store.readOutbox(1)).length > 0) again = true;
        } while (again && last.ok);
        return last;
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
          } else {
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

    return () => {
      stopped = true;
      clearTimeout(debounce);
      clearTimeout(retry);
      clearInterval(interval);
      unsubscribe();
      if (typeof document !== "undefined") {
        document.removeEventListener("visibilitychange", onVisibility);
      }
      if (typeof window !== "undefined") window.removeEventListener("focus", trigger);
    };
  }

  return { run, start };
}

/** Internal: leave this change for a later run. */
class Skip extends Error {}
