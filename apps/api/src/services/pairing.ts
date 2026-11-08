import { pairingCode } from "@wambito/crypto";
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

/** Opens a request for the new device's public key; 429 past five open ones. */
export async function startPairing(
  db: Db,
  userId: string,
  publicKey: string,
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
          .where(sql`${pairingRequests.expiresAt} > ${nowIso}::timestamptz`);
        if ((open[0]?.n ?? 0) >= MAX_OPEN_PAIRINGS) {
          throw new ApiError(429, "too_many_pairings", "Too many open pairing requests");
        }
        // An expired request holding the same code is replaced rather than colliding with it.
        await tx
          .delete(pairingRequests)
          .where(
            and(
              eq(pairingRequests.code, code),
              sql`${pairingRequests.expiresAt} <= ${nowIso}::timestamptz`,
            ),
          );
        // The savepoint keeps a unique violation from aborting the outer transaction.
        const [row] = await tx.transaction((sp) =>
          sp
            .insert(pairingRequests)
            .values({ userId, code, publicKey: Buffer.from(bytes(publicKey)), expiresAt })
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

/** The unsealed, unexpired request with this code; 404 otherwise (also another person's). */
export async function findPairing(db: Db, userId: string, code: string, now: Date) {
  return withUser(db, userId, async (tx) => {
    const [row] = await tx
      .select()
      .from(pairingRequests)
      .where(
        and(
          eq(pairingRequests.code, normalizePairingCode(code)),
          isNull(pairingRequests.sealed),
          gt(pairingRequests.expiresAt, now),
        ),
      );
    if (!row) throw new ApiError(404, "not_found");
    return { id: row.id, publicKey: b64(row.publicKey), expiresAt: row.expiresAt.toISOString() };
  });
}

/** Stores the sealed key; 404 for a missing, expired or foreign request, 409 when already sealed. */
export async function sealPairing(
  db: Db,
  userId: string,
  id: string,
  sealed: string,
  now: Date,
): Promise<void> {
  await withUser(db, userId, async (tx) => {
    await lockPairings(tx, userId);
    const [row] = await tx
      .select({ sealed: pairingRequests.sealed })
      .from(pairingRequests)
      .where(and(eq(pairingRequests.id, id.toLowerCase()), gt(pairingRequests.expiresAt, now)));
    if (!row) throw new ApiError(404, "not_found");
    if (row.sealed) throw new ApiError(409, "already_sealed", "Already sealed");
    await tx
      .update(pairingRequests)
      .set({ sealed: Buffer.from(bytes(sealed)) })
      .where(eq(pairingRequests.id, id.toLowerCase()));
  });
}

/** The sealed key, deleting the request in the same transaction; `null` while unsealed. */
export async function takePairing(
  db: Db,
  userId: string,
  id: string,
  now: Date,
): Promise<string | null> {
  return withUser(db, userId, async (tx) => {
    await lockPairings(tx, userId);
    const [row] = await tx
      .select()
      .from(pairingRequests)
      .where(and(eq(pairingRequests.id, id.toLowerCase()), gt(pairingRequests.expiresAt, now)));
    if (!row) throw new ApiError(404, "not_found");
    if (!row.sealed) return null;
    await tx.delete(pairingRequests).where(eq(pairingRequests.id, row.id));
    return b64(row.sealed);
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
          .where(lte(pairingRequests.expiresAt, now))
          .returning({ id: pairingRequests.id });
        return deleted.length;
      });
    }
    const last = people.at(-1);
    if (!last || people.length < PURGE_PAGE) return total;
    after = last.id;
  }
}
