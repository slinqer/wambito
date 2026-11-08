import { type Db, records, type Tx, user, withUser } from "@wambito/db";
import { and, asc, eq, gt, lte, sql } from "@wambito/db/orm";
import type { SyncHooks } from "../deps.ts";
import { ApiError } from "../http/problem.ts";
import type { RECORD_TYPES } from "../http/schemas.ts";
import { purgeExpiredPairings } from "./pairing.ts";

type RecordType = (typeof RECORD_TYPES)[number];

/** Live (not deleted) records one account may hold (spec 2026-11-08 section 5.1). */
export const MAX_LIVE_RECORDS = 100_000;
/** Tombstones older than this are purged; a device away for longer does a full resync. */
export const TOMBSTONE_DAYS = 180;
const DAY_MS = 24 * 60 * 60 * 1000;
/** Users whose tombstones are purged per page of the purge. */
const PURGE_PAGE = 500;

type RecordRow = typeof records.$inferSelect;

/** A record as it travels: `body` is base64url, null once deleted. */
export interface SyncRecordDto {
  id: string;
  type: RecordType;
  version: number;
  deleted: boolean;
  keyV: number;
  encV: number;
  body: string | null;
}

export interface SyncChangeInput {
  id: string;
  type: RecordType;
  baseVersion: number | null;
  deleted: boolean;
  keyV: number;
  encV: number;
  /** base64url, already checked by the route's schema. */
  body: string | null;
}

export type PushResult =
  | { id: string; version: number }
  | { id: string; conflict: SyncRecordDto }
  | { id: string; error: "id_taken" | "not_found" };

/** Thrown inside a probe savepoint to undo the probe's insert. */
const PROBE_ROLLBACK = Symbol("probe rollback");

export function toSyncRecord(row: RecordRow): SyncRecordDto {
  return {
    id: row.id,
    // Only ever written from a validated change.
    type: row.type as RecordType,
    version: row.version,
    deleted: row.deleted,
    keyV: row.keyV,
    encV: row.encV,
    body: row.body === null ? null : Buffer.from(row.body).toString("base64url"),
  };
}

/**
 * Takes the transaction-level lock on one person's records. Every write to `records` takes it
 * first, so writes for one person run one at a time: a version (from the global sequence) is then
 * never committed after a higher one of the same person, and a device that pulled up to `latest`
 * cannot miss a record committed later with a lower version.
 */
async function lockRecords(tx: Tx, userId: string): Promise<void> {
  await tx.execute(sql`select pg_advisory_xact_lock(hashtextextended(${`records:${userId}`}, 0))`);
}

/**
 * The person's records with a version above `since`, oldest first, at most `limit`. `latest` is
 * read first and caps the page, so a record committed while this runs never makes `latest` skip
 * past one this page did not return.
 */
export async function pullRecords(
  db: Db,
  userId: string,
  since: number,
  limit: number,
): Promise<{ records: SyncRecordDto[]; next: number | null; latest: number }> {
  return withUser(db, userId, async (tx) => {
    const [top] = await tx
      .select({ latest: sql<string>`coalesce(max(${records.version}), 0)` })
      .from(records)
      .where(eq(records.userId, userId));
    const latest = Number(top?.latest ?? 0);
    const rows = await tx
      .select()
      .from(records)
      .where(
        and(eq(records.userId, userId), gt(records.version, since), lte(records.version, latest)),
      )
      .orderBy(asc(records.version))
      .limit(limit + 1);
    const page = rows.slice(0, limit);
    const last = page.at(-1);
    return {
      records: page.map(toSyncRecord),
      next: rows.length > limit && last ? last.version : null,
      latest,
    };
  });
}

const sameBytes = (a: Uint8Array | null, b: Uint8Array | null) =>
  a === null || b === null ? a === b : Buffer.from(a).equals(Buffer.from(b));

/**
 * Applies `changes` in order, each on its own (a conflict never rejects the others), in one
 * transaction that holds the person's records lock. Per change:
 *
 * - `baseVersion: null` creates. If the id is already the person's, a retry of the same create
 *   (same type, deleted, keyV, encV and body bytes) answers the stored version; anything else is
 *   a conflict carrying the stored record. An id that exists but is not visible (another
 *   person's) is `id_taken`, and nothing about that record is returned.
 * - Otherwise the write applies only when `baseVersion` is the stored version and `type` is the
 *   stored type (a record's type never changes); else a conflict. An update for an id the person
 *   does not have (never uploaded, or a tombstone purged after 180 days) creates nothing and is
 *   `not_found`, which tells the device to resync in full; another person's id stays `id_taken`.
 *
 * Every write takes a fresh version from `records_version_seq` and sets `updated_at`. Each change
 * runs in its own savepoint. More than MAX_LIVE_RECORDS live records after a change fails the
 * whole push with 409 `record_limit`.
 */
export async function pushRecords(
  db: Db,
  userId: string,
  changes: SyncChangeInput[],
  hooks: SyncHooks = {},
): Promise<PushResult[]> {
  return withUser(db, userId, async (tx) => {
    await lockRecords(tx, userId);

    // Live records, counted only when a push may add one, and before any of its writes (so the
    // count never includes a row this push wrote), then kept up to date.
    let live: number | null = null;
    const live$ = {
      async count() {
        if (live !== null) return;
        const [row] = await tx
          .select({ count: sql<string>`count(*)` })
          .from(records)
          .where(and(eq(records.userId, userId), eq(records.deleted, false)));
        live = Number(row?.count ?? 0);
      },
      add(count: number) {
        // A push of deletions only never counts: nothing it does can pass the limit.
        if (live === null && count <= 0) return;
        if (live === null) throw new Error("live records were not counted before the write");
        live += count;
        if (live > MAX_LIVE_RECORDS) {
          throw new ApiError(
            409,
            "record_limit",
            `An account holds at most ${MAX_LIVE_RECORDS} records`,
          );
        }
      },
    };
    if (changes.some((change) => !change.deleted)) await live$.count();

    const results: PushResult[] = [];
    for (const change of changes) {
      // A savepoint per change keeps its writes together; only conflicts, `id_taken` and
      // `not_found` are per-change results. An unexpected database error (and `record_limit`)
      // still aborts the whole push.
      results.push(await tx.transaction((sp) => applyChange(sp, userId, change, live$.add)));
    }
    await hooks.beforeCommit?.();
    return results;
  });
}

async function applyChange(
  tx: Tx,
  userId: string,
  change: SyncChangeInput,
  addLive: (count: number) => void,
): Promise<PushResult> {
  // A lower-case UUID already (the route's schema): it is never changed, as it is in the AAD.
  const { id } = change;
  const body = change.body === null ? null : new Uint8Array(Buffer.from(change.body, "base64url"));
  const fields = {
    type: change.type,
    deleted: change.deleted,
    keyV: change.keyV,
    encV: change.encV,
    body,
    version: sql`nextval('records_version_seq')`,
    updatedAt: sql`now()`,
  };

  const [current] = await tx
    .select()
    .from(records)
    .where(and(eq(records.userId, userId), eq(records.id, id)))
    .for("update");

  if (!current && change.baseVersion !== null) {
    return { id, error: (await existsHidden(tx, id, userId)) ? "id_taken" : "not_found" };
  }

  if (!current) {
    const [inserted] = await tx
      .insert(records)
      .values({ id, userId, ...fields })
      .onConflictDoNothing({ target: records.id })
      .returning({ version: records.version });
    // The id exists, but row-level security hides it: it is someone else's.
    if (!inserted) return { id, error: "id_taken" };
    if (!change.deleted) addLive(1);
    return { id, version: inserted.version };
  }

  if (change.baseVersion === null) {
    const retry =
      current.type === change.type &&
      current.deleted === change.deleted &&
      current.keyV === change.keyV &&
      current.encV === change.encV &&
      sameBytes(current.body, body);
    return retry ? { id, version: current.version } : { id, conflict: toSyncRecord(current) };
  }

  if (current.version !== change.baseVersion || current.type !== change.type) {
    return { id, conflict: toSyncRecord(current) };
  }

  const [updated] = await tx
    .update(records)
    .set(fields)
    .where(and(eq(records.userId, userId), eq(records.id, id)))
    .returning({ version: records.version });
  if (current.deleted !== change.deleted) addLive(change.deleted ? -1 : 1);
  return { id, version: (updated as { version: number }).version };
}

/**
 * Whether `id` exists for someone else, which row-level security hides. The API's role cannot read
 * the row, so it probes: a minimal tombstone insert with `on conflict do nothing`, in a savepoint
 * that is always rolled back. No row back means the id is taken. The probe spends one sequence
 * value and leaves nothing behind.
 */
async function existsHidden(tx: Tx, id: string, userId: string): Promise<boolean> {
  try {
    await tx.transaction(async (probe) => {
      const [inserted] = await probe
        .insert(records)
        .values({ id, userId, type: "settings", deleted: true, keyV: 0, encV: 0, body: null })
        .onConflictDoNothing({ target: records.id })
        .returning({ id: records.id });
      if (inserted) throw PROBE_ROLLBACK;
    });
    return true;
  } catch (error) {
    if (error === PROBE_ROLLBACK) return false;
    throw error;
  }
}

/**
 * Deletes every tombstone (deleted record) last written more than 180 days before `now`, and
 * returns how many it deleted. Live records are never touched.
 *
 * `records` is under forced row-level security and the API's role has no way around it, so the
 * purge goes person by person: it pages through `user` (not under row-level security, as the
 * guest cleanup reads it) and deletes each person's old tombstones in a `withUser` transaction
 * that takes that person's records lock, like a push.
 */
export async function purgeTombstones(db: Db, now: Date): Promise<number> {
  const cutoff = new Date(now.getTime() - TOMBSTONE_DAYS * DAY_MS);
  let total = 0;
  let after = "";
  for (;;) {
    const people = await db
      .select({ id: user.id })
      .from(user)
      .where(gt(user.id, after))
      .orderBy(asc(user.id))
      .limit(PURGE_PAGE);
    for (const { id } of people) {
      total += await withUser(db, id, async (tx) => {
        await lockRecords(tx, id);
        const deleted = await tx
          .delete(records)
          .where(
            and(
              eq(records.userId, id),
              eq(records.deleted, true),
              sql`${records.updatedAt} < ${cutoff.toISOString()}`,
            ),
          )
          .returning({ id: records.id });
        return deleted.length;
      });
    }
    const last = people.at(-1);
    if (!last || people.length < PURGE_PAGE) return total;
    after = last.id;
  }
}

export interface TombstonePurgeDeps {
  db: Db;
  /** Replaces `purgeTombstones`; for tests. */
  purge?: (db: Db, now: Date) => Promise<number>;
  /** Replaces `purgeExpiredPairings`; for tests. */
  purgePairings?: (db: Db, now: Date) => Promise<number>;
  log?: (message: string) => void;
  logError?: (message: string, error: unknown) => void;
}

/**
 * Runs the purge now and then once a day, until the returned function is called. A failure is
 * logged and the next day's run goes on. The timer does not keep the process alive.
 */
export function scheduleTombstonePurge(deps: TombstonePurgeDeps): () => void {
  const purge = deps.purge ?? purgeTombstones;
  const purgePairings = deps.purgePairings ?? purgeExpiredPairings;
  const log = deps.log ?? ((message) => console.log(message));
  const logError = deps.logError ?? ((message, error) => console.error(message, error));

  const run = async () => {
    // Expired pairing requests go with the daily purge (spec 2026-11-08 section 7.3); each purge
    // has its own try so a failure of one does not skip the other.
    try {
      await purgePairings(deps.db, new Date());
    } catch (error) {
      logError("Pairing purge failed", error);
    }
    try {
      const count = await purge(deps.db, new Date());
      if (count > 0)
        log(`Tombstone purge: deleted ${count} record(s) older than ${TOMBSTONE_DAYS} days`);
    } catch (error) {
      logError("Tombstone purge failed", error);
    }
  };

  const timer = setInterval(run, DAY_MS);
  timer.unref();
  void run();
  return () => clearInterval(timer);
}
