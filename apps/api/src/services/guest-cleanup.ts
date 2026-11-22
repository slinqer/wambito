import { type Db, keyWraps, recoveryVerifiers, session, user, withUser } from "@wambito/db";
import { and, asc, eq, gt, inArray, type SQL, sql } from "@wambito/db/orm";
import { ENDED_SESSION_DAYS, purgeEndedSessions, recordDeletedUsers } from "./ended.ts";

/** A plain guest idle for longer than this is deleted (spec §4.4). */
export const GUEST_INACTIVE_DAYS = 60;
/**
 * An encrypted user without an email is deleted after this many idle days (12 months) when only
 * its phone can open the account: no recovery verifier and no passkey wrap (spec 2026-11-15 §10).
 */
export const UNPROTECTED_IDLE_DAYS = 365;
/** ...and after this many (24 months) when a recovery key or a passkey can still open it. */
export const PROTECTED_IDLE_DAYS = 730;
const DAY_MS = 24 * 60 * 60 * 1000;

/** Postgres advisory lock key of the cleanup ("luka"): one run at a time, across API instances. */
export const GUEST_CLEANUP_LOCK = 0x6c756b61;

/** Guests deleted per transaction: a spike of sign-ups never makes one huge delete or lock hold. */
export const GUEST_CLEANUP_BATCH = 500;

/**
 * Records that the user was active at `at` (`user.lastActiveAt`, which only moves forward), so the
 * activity outlives the session: a guest who signs out keeps 60 days to come back with a passkey.
 * Every user is stamped, with or without an email (spec 2026-11-15 §9). Better Auth's session
 * hooks call it when a session is created, refreshed or ended (auth.ts), and `slideLongSession`
 * when it slides a long one (services/sessions.ts); a background request refreshes nothing, so it
 * never gets here.
 */
export async function stampActivity(db: Db, userId: string, at: Date): Promise<void> {
  // Raw SQL: an ORM update would also move `user.updatedAt`.
  await db.execute(sql`update ${user}
    set last_active_at = greatest(last_active_at, ${at.toISOString()}::timestamp)
    where ${user.id} = ${userId}`);
}

/**
 * The user's latest activity: the later of `user.lastActiveAt` and its latest `session.updatedAt`;
 * `greatest` skips nulls, and a user with neither, which should not happen, counts as inactive
 * since it was created.
 */
const lastActive = (): SQL => sql`coalesce(
  greatest(
    (select max(${session.updatedAt}) from ${session} where ${session.userId} = ${user.id}),
    ${user.lastActiveAt}
  ),
  ${user.createdAt}
)`;
const before = (cutoff: Date): SQL => sql`${lastActive()} < ${cutoff.toISOString()}::timestamp`;
const daysBefore = (now: Date, days: number) => new Date(now.getTime() - days * DAY_MS);

/**
 * Deletes the plain guests (anonymous users, `encryption = 'plain'`) whose latest activity is more
 * than 60 days before `now`, and returns how many it deleted. Encrypted guests are left to
 * `cleanupInactiveEncrypted`. The latest activity is the later of `user.lastActiveAt` and the
 * latest `session.updatedAt`; a guest with neither, which should not happen, counts as inactive
 * since it was created. A user with an email is never touched: `isAnonymous` turns false the
 * moment a guest claims one.
 *
 * Deleting the user cascades to all of its data, as `DELETE /v1/me` does (sessions, accounts,
 * categories, transactions...). That needs no privilege beyond the API's own role: `user` and
 * `session` are not under row-level security, and foreign-key cascades bypass it.
 *
 * It deletes in batches of 500, one transaction each, until a batch deletes fewer than that. Every
 * batch first takes a transaction-level advisory lock; one that cannot get it, because another run
 * is going, deletes nothing and ends this run. (A session-level lock would belong to whichever
 * pooled connection took it; this one is released with the transaction.)
 */
export async function cleanupInactiveGuests(db: Db, now: Date): Promise<number> {
  let total = 0;
  for (;;) {
    const deleted = await deleteBatch(db, now);
    total += deleted;
    if (deleted < GUEST_CLEANUP_BATCH) return total;
  }
}

async function deleteBatch(db: Db, now: Date): Promise<number> {
  const cutoff = daysBefore(now, GUEST_INACTIVE_DAYS);
  return db.transaction(async (tx) => {
    if (!(await tryLock(tx))) return 0;

    const inactive = tx
      .select({ id: user.id })
      .from(user)
      // A `migrating` guest is in the plain tier (spec 2026-11-19 §1).
      .where(
        and(
          eq(user.isAnonymous, true),
          inArray(user.encryption, ["plain", "migrating"]),
          before(cutoff),
        ),
      )
      .limit(GUEST_CLEANUP_BATCH);
    const deleted = await tx
      .delete(user)
      .where(inArray(user.id, inactive))
      .returning({ id: user.id });
    return deleted.length;
  });
}

type Lockable = Pick<Db, "execute">;

/** Takes the cleanup's transaction-level advisory lock; false when another run holds it. */
async function tryLock(tx: Lockable): Promise<boolean> {
  const [lock] = await tx.execute<{ locked: boolean }>(
    sql`select pg_try_advisory_xact_lock(${GUEST_CLEANUP_LOCK}) as locked`,
  );
  return lock?.locked === true;
}

/**
 * Deletes the encrypted users without an email (anonymous, `encryption = 'encrypted'`) left idle
 * too long, and returns how many it deleted (spec 2026-11-15 §10). The latest activity is the
 * plain cleanup's. A candidate idle for more than 365 days is deleted unless something other than
 * its phone can still open the account: a `recovery_verifiers` row (the recovery key signs in) or a
 * `passkey` key wrap (a passkey without a wrap cannot open the data, so it does not count, and a
 * recovery wrap without a verifier is unreachable). Such a protected user is deleted once idle for
 * more than 730 days. A user with an email is never deleted for inactivity.
 *
 * It walks the candidates by id, `GUEST_CLEANUP_BATCH` at a time, one transaction each under the
 * cleanup's advisory lock (a batch that cannot get it ends the run), so protected users that stay
 * do not hold the walk back. `key_wraps` has forced row-level security, so a candidate's passkey
 * wrap is read through `withUser`. The delete re-checks the candidate conditions, so a user active
 * since the batch read them is kept, and it records each deleted id's hash in `deleted_users` in
 * the same transaction.
 */
export async function cleanupInactiveEncrypted(db: Db, now: Date): Promise<number> {
  const unprotectedCutoff = daysBefore(now, UNPROTECTED_IDLE_DAYS);
  const protectedCutoff = daysBefore(now, PROTECTED_IDLE_DAYS);
  const candidate = and(
    eq(user.isAnonymous, true),
    eq(user.encryption, "encrypted"),
    before(unprotectedCutoff),
  );

  let total = 0;
  let cursor = "";
  for (;;) {
    const batch = await db.transaction(async (tx) => {
      if (!(await tryLock(tx))) return null;

      const rows = await tx
        .select({
          id: user.id,
          longIdle: sql<boolean>`${before(protectedCutoff)}`,
          hasVerifier: sql<boolean>`exists (select 1 from ${recoveryVerifiers} where ${recoveryVerifiers.userId} = ${user.id})`,
        })
        .from(user)
        .where(and(candidate, gt(user.id, cursor)))
        .orderBy(asc(user.id))
        .limit(GUEST_CLEANUP_BATCH);

      const doomed: string[] = [];
      for (const row of rows) {
        if (row.longIdle || (!row.hasVerifier && !(await hasPasskeyWrap(db, row.id)))) {
          doomed.push(row.id);
        }
      }
      let deleted: string[] = [];
      if (doomed.length > 0) {
        deleted = (
          await tx
            .delete(user)
            .where(and(inArray(user.id, doomed), candidate))
            .returning({ id: user.id })
        ).map((r) => r.id);
        await recordDeletedUsers(tx, deleted);
      }
      return { deleted: deleted.length, read: rows.length, last: rows.at(-1)?.id };
    });
    if (!batch) return total;
    total += batch.deleted;
    if (batch.read < GUEST_CLEANUP_BATCH || batch.last === undefined) return total;
    cursor = batch.last;
  }
}

/** Whether a passkey can open the user's data: a `passkey` key wrap, read under the user's RLS. */
function hasPasskeyWrap(db: Db, userId: string): Promise<boolean> {
  return withUser(db, userId, async (tx) => {
    const rows = await tx
      .select({ id: keyWraps.id })
      .from(keyWraps)
      .where(and(eq(keyWraps.userId, userId), eq(keyWraps.kind, "passkey")))
      .limit(1);
    return rows.length > 0;
  });
}

export interface GuestCleanupDeps {
  db: Db;
  /** Replace `cleanupInactiveGuests`, `cleanupInactiveEncrypted` and `purgeEndedSessions`; for tests. */
  cleanup?: (db: Db, now: Date) => Promise<number>;
  cleanupEncrypted?: (db: Db, now: Date) => Promise<number>;
  purgeEnded?: (db: Db, now: Date) => Promise<number>;
  log?: (message: string) => void;
  logError?: (message: string, error: unknown) => void;
}

/**
 * Runs the cleanups now and then once a day, until the returned function is called: the plain
 * guests (60 days), then the encrypted users without an email (12 or 24 months), then the purge of
 * `ended_sessions` (90 days). Each step logs one line when it removed something; a failed step is
 * logged, the next steps still run, and so does the next day's run. The timer does not keep the
 * process alive.
 */
export function scheduleGuestCleanup(deps: GuestCleanupDeps): () => void {
  const log = deps.log ?? ((message) => console.log(message));
  const logError = deps.logError ?? ((message, error) => console.error(message, error));
  const steps: [string, (db: Db, now: Date) => Promise<number>, (count: number) => string][] = [
    [
      "Guest cleanup",
      deps.cleanup ?? cleanupInactiveGuests,
      (count) =>
        `Guest cleanup: deleted ${count} guest(s) inactive for over ${GUEST_INACTIVE_DAYS} days`,
    ],
    [
      "Encrypted cleanup",
      deps.cleanupEncrypted ?? cleanupInactiveEncrypted,
      (count) =>
        `Encrypted cleanup: deleted ${count} user(s) without an email idle for over ${UNPROTECTED_IDLE_DAYS} days (${PROTECTED_IDLE_DAYS} with a recovery key or a passkey)`,
    ],
    [
      "Ended sessions purge",
      deps.purgeEnded ?? purgeEndedSessions,
      (count) =>
        `Ended sessions purge: removed ${count} row(s) older than ${ENDED_SESSION_DAYS} days`,
    ],
  ];

  const run = async () => {
    const now = new Date();
    for (const [name, step, message] of steps) {
      try {
        const count = await step(deps.db, now);
        if (count > 0) log(message(count));
      } catch (error) {
        logError(`${name} failed`, error);
      }
    }
  };

  const timer = setInterval(run, DAY_MS);
  timer.unref();
  void run();
  return () => clearInterval(timer);
}
