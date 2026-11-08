import { pairingCode, pairingCommitment } from "@wambito/crypto";
import { type Db, pairingRequests, user, withUser } from "@wambito/db";
import { and, asc, eq, gt, isNull, lte, sql } from "@wambito/db/orm";
import { ApiError } from "../http/problem.ts";

/** A pairing request lives this long (spec 2026-11-08 section 7.3). */
export const PAIRING_TTL_MS = 10 * 60 * 1000;
/** Unexpired requests one person may have open. */
export const MAX_OPEN_PAIRINGS = 5;
const PURGE_PAGE = 500;
const CODE_TRIES = 5;

const b64 = (bytes: Uint8Array) => Buffer.from(bytes).toString("base64url");
const bytes = (text: string) => new Uint8Array(Buffer.from(text, "base64url"));

/**
 * What the person typed, as the stored code: upper case, `I`/`L` read as 1, `O` as 0, dashes and
 * spaces dropped (the same reading as the recovery key's parser).
 */
export function normalizePairingCode(input: string): string {
  return input.toUpperCase().replace(/[-\s]/g, "").replace(/[IL]/g, "1").replace(/O/g, "0");
}

export interface PairingStartedDto {
  id: string;
  code: string;
  expiresAt: string;
}

const isUniqueViolation = (error: unknown): boolean => {
  for (let e: unknown = error; e && typeof e === "object"; e = (e as { cause?: unknown }).cause) {
    if ((e as { code?: unknown }).code === "23505") return true;
  }
  return false;
};

/** Takes the person's pairing lock, so the open-request count cannot race. */
async function lockPairings(tx: Parameters<Parameters<typeof withUser>[2]>[0], userId: string) {
  await tx.execute(
    sql`select pg_advisory_xact_lock(hashtextextended(${`pairing_requests:${userId}`}, 0))`,
  );
}

/** Opens a request for the new device's key commitment; 429 past five open ones. */
export async function startPairing(
  db: Db,
  userId: string,
  commitment: string,
  now: Date,
): Promise<PairingStartedDto> {
  const expiresAt = new Date(now.getTime() + PAIRING_TTL_MS);
  const nowIso = now.toISOString();
  for (let attempt = 0; attempt < CODE_TRIES; attempt++) {
    const code = pairingCode();
    try {
      return await withUser(db, userId, async (tx) => {
        await lockPairings(tx, userId);
        const open = await tx
          .select({ n: sql<number>`count(*)::int` })
          .from(pairingRequests)
          .where(
            and(
              eq(pairingRequests.userId, userId),
              sql`${pairingRequests.expiresAt} > ${nowIso}::timestamptz`,
            ),
          );
        if ((open[0]?.n ?? 0) >= MAX_OPEN_PAIRINGS) {
          throw new ApiError(429, "too_many_pairings", "Too many open pairing requests");
        }
        // An expired request holding the same code is replaced rather than colliding with it.
        await tx
          .delete(pairingRequests)
          .where(
            and(
              eq(pairingRequests.userId, userId),
              eq(pairingRequests.code, code),
              sql`${pairingRequests.expiresAt} <= ${nowIso}::timestamptz`,
            ),
          );
        // The savepoint keeps a unique violation from aborting the outer transaction.
        const [row] = await tx.transaction((sp) =>
          sp
            .insert(pairingRequests)
            .values({ userId, code, commitment: Buffer.from(bytes(commitment)), expiresAt })
            .returning({ id: pairingRequests.id }),
        );
        if (!row) throw new Error("pairing insert returned nothing");
        return { id: row.id, code, expiresAt: expiresAt.toISOString() };
      });
    } catch (error) {
      if (!isUniqueViolation(error)) throw error;
    }
  }
  throw new Error("Could not make a free pairing code");
}

/**
 * The request with this code that has no approver key yet and has not expired; 404 otherwise
 * (also another person's).
 */
export async function findPairing(db: Db, userId: string, code: string, now: Date) {
  return withUser(db, userId, async (tx) => {
    const [row] = await tx
      .select()
      .from(pairingRequests)
      .where(
        and(
          eq(pairingRequests.userId, userId),
          eq(pairingRequests.code, normalizePairingCode(code)),
          isNull(pairingRequests.approverKey),
          gt(pairingRequests.expiresAt, now),
        ),
      );
    if (!row) throw new ApiError(404, "not_found");
    return { id: row.id, commitment: b64(row.commitment), expiresAt: row.expiresAt.toISOString() };
  });
}

type Tx = Parameters<Parameters<typeof withUser>[2]>[0];

/** Locks the person's pairings and loads one unexpired request of theirs; 404 otherwise. */
async function loadLocked(tx: Tx, userId: string, id: string, now: Date) {
  await lockPairings(tx, userId);
  const [row] = await tx
    .select()
    .from(pairingRequests)
    .where(
      and(
        eq(pairingRequests.userId, userId),
        eq(pairingRequests.id, id.toLowerCase()),
        gt(pairingRequests.expiresAt, now),
      ),
    );
  if (!row) throw new ApiError(404, "not_found");
  return row;
}

const updateRow = (
  tx: Tx,
  userId: string,
  id: string,
  set: Partial<typeof pairingRequests.$inferInsert>,
) =>
  tx
    .update(pairingRequests)
    .set(set)
    .where(and(eq(pairingRequests.userId, userId), eq(pairingRequests.id, id)));

/** Stores the approving device's ephemeral key, once; 409 `already_set` after. */
export async function setApprover(
  db: Db,
  userId: string,
  id: string,
  publicKey: string,
  now: Date,
): Promise<void> {
  await withUser(db, userId, async (tx) => {
    const row = await loadLocked(tx, userId, id, now);
    if (row.approverKey) throw new ApiError(409, "already_set", "The approver key is already set");
    await updateRow(tx, userId, row.id, { approverKey: Buffer.from(bytes(publicKey)) });
  });
}

/**
 * Stores the new device's key once it matches the commitment. 409 `not_ready` before the approver
 * key, 409 `already_set` when revealed, 422 `commitment_mismatch` for a key that does not hash to
 * the commitment.
 */
export async function revealPairing(
  db: Db,
  userId: string,
  id: string,
  publicKey: string,
  now: Date,
): Promise<void> {
  const key = bytes(publicKey);
  const hash = Buffer.from(await pairingCommitment(key));
  await withUser(db, userId, async (tx) => {
    const row = await loadLocked(tx, userId, id, now);
    if (!row.approverKey) throw new ApiError(409, "not_ready", "The approver key is not set yet");
    if (row.publicKey) throw new ApiError(409, "already_set", "The key was already revealed");
    if (!hash.equals(row.commitment)) {
      throw new ApiError(422, "commitment_mismatch", "The key does not match the commitment");
    }
    await updateRow(tx, userId, row.id, { publicKey: Buffer.from(key) });
  });
}

/**
 * Stores the sealed key. 409 `not_ready` without a revealed key, 409 `already_sealed`, 422
 * `approver_mismatch` when the blob does not start with the approver key.
 */
export async function sealPairing(
  db: Db,
  userId: string,
  id: string,
  sealed: string,
  keyV: number,
  now: Date,
): Promise<void> {
  const blob = Buffer.from(bytes(sealed));
  await withUser(db, userId, async (tx) => {
    const row = await loadLocked(tx, userId, id, now);
    if (row.sealed) throw new ApiError(409, "already_sealed", "Already sealed");
    if (!row.approverKey || !row.publicKey) {
      throw new ApiError(409, "not_ready", "The new device has not revealed its key yet");
    }
    if (!blob.subarray(0, row.approverKey.length).equals(row.approverKey)) {
      throw new ApiError(422, "approver_mismatch", "The sealed key is not from the approver key");
    }
    await updateRow(tx, userId, row.id, { sealed: blob, keyV });
  });
}

export interface PairingStateDto {
  commitment: string;
  approverKey: string | null;
  publicKey: string | null;
  sealed: string | null;
  keyV: number | null;
  expiresAt: string;
}

/** The request's state; a sealed one is deleted in the same transaction (read once). */
export async function takePairing(
  db: Db,
  userId: string,
  id: string,
  now: Date,
): Promise<PairingStateDto> {
  return withUser(db, userId, async (tx) => {
    const row = await loadLocked(tx, userId, id, now);
    if (row.sealed) {
      await tx
        .delete(pairingRequests)
        .where(and(eq(pairingRequests.userId, userId), eq(pairingRequests.id, row.id)));
    }
    return {
      commitment: b64(row.commitment),
      approverKey: row.approverKey ? b64(row.approverKey) : null,
      publicKey: row.publicKey ? b64(row.publicKey) : null,
      sealed: row.sealed ? b64(row.sealed) : null,
      keyV: row.keyV,
      expiresAt: row.expiresAt.toISOString(),
    };
  });
}

/**
 * Deletes every request that expired before `now`, person by person (the table has forced
 * row-level security), and returns how many.
 */
export async function purgeExpiredPairings(db: Db, now: Date): Promise<number> {
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
        await lockPairings(tx, id);
        const deleted = await tx
          .delete(pairingRequests)
          .where(and(eq(pairingRequests.userId, id), lte(pairingRequests.expiresAt, now)))
          .returning({ id: pairingRequests.id });
        return deleted.length;
      });
    }
    const last = people.at(-1);
    if (!last || people.length < PURGE_PAGE) return total;
    after = last.id;
  }
}
