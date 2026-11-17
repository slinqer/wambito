import {
  type Db,
  keyWraps,
  oauthAccessToken,
  oauthConsent,
  oauthRefreshToken,
  session,
  type Tx,
  user,
} from "@wambito/db";
import { and, eq, sql } from "@wambito/db/orm";

/** Row-level security on `key_wraps` needs the user in the transaction (as `withUser` sets it). */
async function scopeToUser(tx: Db | Tx, userId: string): Promise<void> {
  await tx.execute(sql`select set_config('app.user_id', ${userId}, true)`);
}

/**
 * Deletes the account. Every user-owned row (domain data, sessions, passkeys, OAuth grants)
 * cascades from `user`. False when there was no such user.
 */
export async function deleteAccount(tx: Db | Tx, userId: string): Promise<boolean> {
  const removed = await tx.delete(user).where(eq(user.id, userId)).returning({ id: user.id });
  return removed.length > 0;
}

/**
 * Revokes one assistant: deletes the consent, the access and refresh tokens and its `assistant` key
 * wrap (it must not keep a copy of the data key once disconnected). Without a refresh token the
 * assistant cannot get a new access token, so it loses access within 15 minutes at most.
 * Atomic on a `Db` too (a transaction; a savepoint on a `Tx`). False when the user had no consent
 * for that client.
 */
export async function revokeAssistant(
  tx: Db | Tx,
  userId: string,
  clientId: string,
): Promise<boolean> {
  return tx.transaction(async (t) => {
    await scopeToUser(t, userId);
    await t
      .delete(keyWraps)
      .where(
        and(
          eq(keyWraps.userId, userId),
          eq(keyWraps.kind, "assistant"),
          eq(keyWraps.ref, clientId),
        ),
      );
    const consents = await t
      .delete(oauthConsent)
      .where(and(eq(oauthConsent.userId, userId), eq(oauthConsent.clientId, clientId)))
      .returning({ id: oauthConsent.id });
    await t
      .delete(oauthAccessToken)
      .where(and(eq(oauthAccessToken.userId, userId), eq(oauthAccessToken.clientId, clientId)));
    await t
      .delete(oauthRefreshToken)
      .where(and(eq(oauthRefreshToken.userId, userId), eq(oauthRefreshToken.clientId, clientId)));
    return consents.length > 0;
  });
}

/** The same (wraps included) for every assistant of the user; returns how many consents it removed. */
export async function revokeAllAssistants(tx: Tx, userId: string): Promise<number> {
  await scopeToUser(tx, userId);
  await tx.delete(keyWraps).where(and(eq(keyWraps.userId, userId), eq(keyWraps.kind, "assistant")));
  const consents = await tx
    .delete(oauthConsent)
    .where(eq(oauthConsent.userId, userId))
    .returning({ id: oauthConsent.id });
  await tx.delete(oauthAccessToken).where(eq(oauthAccessToken.userId, userId));
  await tx.delete(oauthRefreshToken).where(eq(oauthRefreshToken.userId, userId));
  return consents.length;
}

/** Signs the user out everywhere: deletes all their sessions and returns how many. */
export async function revokeSessions(tx: Db | Tx, userId: string): Promise<number> {
  const removed = await tx
    .delete(session)
    .where(eq(session.userId, userId))
    .returning({ id: session.id });
  return removed.length;
}
