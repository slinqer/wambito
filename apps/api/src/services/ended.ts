import { createHash } from "node:crypto";
import { type Db, deletedUsers, endedSessions, type Tx } from "@wambito/db";
import { lt } from "@wambito/db/orm";

/** `ended_sessions` rows older than this are purged (spec 2026-11-15 §10). */
export const ENDED_SESSION_DAYS = 90;
const DAY_MS = 24 * 60 * 60 * 1000;

/** The SHA-256 of `text`'s UTF-8 bytes: how a session token or a user id is kept once it is gone. */
export function sha256(text: string): Buffer {
  return createHash("sha256").update(text, "utf8").digest();
}

/**
 * Records that the sessions with these tokens were ended because their device was removed, so a
 * 401 for one of them can say `device_removed`. Call it in the transaction that ends them; a token
 * already recorded is left as it is.
 */
export async function recordEndedSessions(tx: Tx, tokens: string[]): Promise<void> {
  if (tokens.length === 0) return;
  await tx
    .insert(endedSessions)
    .values(tokens.map((token) => ({ sessionHash: sha256(token), reason: "device_removed" })))
    .onConflictDoNothing();
}

/**
 * Records that these users were deleted (the hash of each id, nothing else), so a phone that comes
 * back with one of their sessions hears `user_deleted`. Call it in the transaction that deletes them.
 */
export async function recordDeletedUsers(tx: Tx, userIds: string[]): Promise<void> {
  if (userIds.length === 0) return;
  await tx
    .insert(deletedUsers)
    .values(userIds.map((id) => ({ userHash: sha256(id) })))
    .onConflictDoNothing();
}

/** Deletes the `ended_sessions` rows older than 90 days before `now`; returns how many. */
export async function purgeEndedSessions(db: Db, now: Date): Promise<number> {
  const cutoff = new Date(now.getTime() - ENDED_SESSION_DAYS * DAY_MS);
  const purged = await db
    .delete(endedSessions)
    .where(lt(endedSessions.endedAt, cutoff))
    .returning({ hash: endedSessions.sessionHash });
  return purged.length;
}
