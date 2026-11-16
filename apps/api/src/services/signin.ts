import { createHash, randomBytes } from "node:crypto";
import { pairingCode, pairingCommitment } from "@wambito/crypto";
import { type Db, signinRequests, type Tx, withUser } from "@wambito/db";
import { and, eq, gt, isNotNull, isNull, lte, type SQL } from "@wambito/db/orm";
import { isUniqueViolation } from "../http/db-errors.ts";
import { ApiError } from "../http/problem.ts";
import { currentKeyV } from "./keys.ts";
import {
  assertCanReveal,
  assertCanSeal,
  assertCanSetApprover,
  normalizeRelayCode,
} from "./relay.ts";

/** A sign-in request lives this long (spec 2026-11-15 section 8.1). */
export const SIGNIN_TTL_MS = 2 * 60 * 1000;
/** Unexpired requests one client address may hold open (kept in memory, `IpOpenCount`). */
export const MAX_OPEN_SIGNINS_PER_IP = 5;
/** Requests one client address may open per window (plan decision 18; `IpWindowLimit`). */
export const SIGNIN_OPEN_LIMIT = { max: 30, windowMs: 10 * 60 * 1000 };
const CODE_TRIES = 5;
const POLL_SECRET_BYTES = 32;

const b64 = (bytes: Uint8Array) => Buffer.from(bytes).toString("base64url");
const bytes = (text: string) => new Uint8Array(Buffer.from(text, "base64url"));
const sha256 = (data: Uint8Array) => new Uint8Array(createHash("sha256").update(data).digest());

/** The stored form of a poll secret: SHA-256 of its decoded bytes. */
const pollHashOf = (pollSecret: string) => sha256(bytes(pollSecret));

const notFound = () => new ApiError(404, "not_found");

export interface SigninStartedDto {
  id: string;
  code: string;
  pollSecret: string;
  expiresAt: string;
}

/**
 * Opens a request for the browser's key commitment. The poll secret (32 random bytes, base64url)
 * goes back to the browser only; the row keeps its SHA-256. A code that collides with a live
 * request retries; an expired request holding the code is replaced.
 */
export async function startSignin(
  db: Db,
  { commitment, remember, label }: { commitment: string; remember: boolean; label: string },
  now: Date,
): Promise<SigninStartedDto> {
  const expiresAt = new Date(now.getTime() + SIGNIN_TTL_MS);
  const secret = randomBytes(POLL_SECRET_BYTES);
  const pollSecret = b64(secret);
  for (let attempt = 0; attempt < CODE_TRIES; attempt++) {
    const code = pairingCode();
    try {
      return await db.transaction(async (tx) => {
        await tx
          .delete(signinRequests)
          .where(and(eq(signinRequests.code, code), lte(signinRequests.expiresAt, now)));
        const [row] = await tx
          .insert(signinRequests)
          .values({
            code,
            commitment: bytes(commitment),
            pollHash: sha256(secret),
            label,
            remember,
            expiresAt,
          })
          .returning({ id: signinRequests.id });
        if (!row) throw new Error("sign-in insert returned nothing");
        return { id: row.id, code, pollSecret, expiresAt: expiresAt.toISOString() };
      });
    } catch (error) {
      if (!isUniqueViolation(error)) throw error;
    }
  }
  throw new Error("Could not make a free sign-in code");
}

const live = (now: Date, ...conditions: (SQL | undefined)[]) =>
  and(gt(signinRequests.expiresAt, now), ...conditions);

/** The unexpired request with this id (and these conditions), locked for the transaction. */
async function loadLocked(tx: Tx, id: string, now: Date, ...conditions: (SQL | undefined)[]) {
  const [row] = await tx
    .select()
    .from(signinRequests)
    .where(live(now, eq(signinRequests.id, id.toLowerCase()), ...conditions))
    .for("update");
  if (!row) throw notFound();
  return row;
}

/** The browser's proof: the request's poll hash. */
const byPoll = (pollSecret: string) => eq(signinRequests.pollHash, pollHashOf(pollSecret));

/** The request as an approving phone sees it. */
export interface SigninFoundDto {
  id: string;
  commitment: string;
  label: string;
  expiresAt: string;
}

const found = (row: typeof signinRequests.$inferSelect): SigninFoundDto => ({
  id: row.id,
  commitment: b64(row.commitment),
  label: row.label,
  expiresAt: row.expiresAt.toISOString(),
});

/** The request with this typed code that has no approver yet and has not expired; 404 otherwise. */
export async function findSignin(db: Db, code: string, now: Date): Promise<SigninFoundDto> {
  const [row] = await db
    .select()
    .from(signinRequests)
    .where(
      live(
        now,
        eq(signinRequests.code, normalizeRelayCode(code)),
        isNull(signinRequests.approverKey),
      ),
    );
  if (!row) throw notFound();
  return found(row);
}

/**
 * The request as the phone sees it by id (a scanned QR), with the browser's revealed key. Any
 * signed-in person until it is approved; after, only the approving user (404 for others).
 */
export async function viewSignin(
  db: Db,
  userId: string,
  id: string,
  now: Date,
): Promise<SigninFoundDto & { publicKey: string | null }> {
  const [row] = await db
    .select()
    .from(signinRequests)
    .where(live(now, eq(signinRequests.id, id.toLowerCase())));
  if (!row || (row.userId !== null && row.userId !== userId)) throw notFound();
  return { ...found(row), publicKey: row.publicKey ? b64(row.publicKey) : null };
}

/**
 * The phone approves: stores its ephemeral key and binds the request to its user, once; 409
 * `already_set` after, whoever asks.
 */
export async function setSigninApprover(
  db: Db,
  userId: string,
  id: string,
  publicKey: string,
  now: Date,
): Promise<void> {
  await db.transaction(async (tx) => {
    const row = await loadLocked(tx, id, now);
    assertCanSetApprover(row);
    await tx
      .update(signinRequests)
      .set({ approverKey: bytes(publicKey), userId })
      .where(eq(signinRequests.id, row.id));
  });
}

/** The browser polls with its secret: the approver key once set, and whether it is sealed. */
export async function pollSignin(
  db: Db,
  id: string,
  pollSecret: string,
  now: Date,
): Promise<{ approverKey: string | null; ready: boolean; expiresAt: string }> {
  const [row] = await db
    .select()
    .from(signinRequests)
    .where(live(now, eq(signinRequests.id, id.toLowerCase()), byPoll(pollSecret)));
  if (!row) throw notFound();
  return {
    approverKey: row.approverKey ? b64(row.approverKey) : null,
    ready: row.sealed !== null,
    expiresAt: row.expiresAt.toISOString(),
  };
}

/** The browser reveals its key; the relay checks (`assertCanReveal`). */
export async function revealSignin(
  db: Db,
  id: string,
  pollSecret: string,
  publicKey: string,
  now: Date,
): Promise<void> {
  const key = bytes(publicKey);
  const hash = await pairingCommitment(key);
  await db.transaction(async (tx) => {
    const row = await loadLocked(tx, id, now, byPoll(pollSecret));
    assertCanReveal(row, hash);
    await tx.update(signinRequests).set({ publicKey: key }).where(eq(signinRequests.id, row.id));
  });
}

/**
 * The approving phone stores the sealed data key (`assertCanSeal`); 404 for anyone else. In the
 * user's scope, for its key version.
 */
export async function sealSignin(
  db: Db,
  userId: string,
  id: string,
  sealed: string,
  keyV: number,
  now: Date,
): Promise<void> {
  const blob = bytes(sealed);
  await withUser(db, userId, async (tx) => {
    const row = await loadLocked(tx, id, now, eq(signinRequests.userId, userId));
    assertCanSeal(row, blob, keyV, await currentKeyV(tx, userId));
    await tx
      .update(signinRequests)
      .set({ sealed: blob, keyV })
      .where(eq(signinRequests.id, row.id));
  });
}

/**
 * The browser takes the sealed key: one `delete … returning` of a sealed row, so of two pickups at
 * once exactly one gets it and the other finds nothing (404). 409 `not_ready` while unsealed.
 */
export async function takeSignin(
  db: Db,
  id: string,
  pollSecret: string,
  now: Date,
): Promise<{ sealed: string; keyV: number; userId: string; remember: boolean }> {
  const where = live(now, eq(signinRequests.id, id.toLowerCase()), byPoll(pollSecret));
  const [row] = await db
    .delete(signinRequests)
    .where(and(where, isNotNull(signinRequests.sealed)))
    .returning();
  if (row?.sealed && row.keyV !== null && row.userId) {
    return { sealed: b64(row.sealed), keyV: row.keyV, userId: row.userId, remember: row.remember };
  }
  const [waiting] = await db.select({ id: signinRequests.id }).from(signinRequests).where(where);
  if (waiting) throw new ApiError(409, "not_ready", "The phone has not sealed the key yet");
  throw notFound();
}

/** Deletes every request that expired before `now`; returns how many. */
export async function purgeExpiredSignins(db: Db, now: Date): Promise<number> {
  const deleted = await db
    .delete(signinRequests)
    .where(lte(signinRequests.expiresAt, now))
    .returning({ id: signinRequests.id });
  return deleted.length;
}
