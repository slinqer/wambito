import { type Db, session, type Tx, user } from "@wambito/db";
import { sql } from "@wambito/db/orm";
import type { Encryption } from "./encryption.ts";
import { stampActivity } from "./guest-cleanup.ts";

/**
 * How long a session lives (`session.lifetime`): `standard` is Better Auth's 60 days, sliding;
 * `long` is the phone session of an encrypted user without an email, 25 months (760 days), slid by
 * `slideLongSession`; `short` is an unticked web sign-in, 12 hours, never refreshed.
 */
export type SessionLifetime = "standard" | "long" | "short";

/** A `standard` session: 60 days after its last use, slid by Better Auth at most once a day. */
export const SESSION_SECONDS = 60 * 24 * 60 * 60;
/** A `long` session: 25 months, longer than the 24-month cleanup of an idle encrypted user. */
export const LONG_SESSION_SECONDS = 760 * 24 * 60 * 60;
/** A `short` session (an unticked web sign-in): 12 hours, never refreshed. */
export const SHORT_SESSION_SECONDS = 12 * 60 * 60;

/**
 * The lifetime of a session a sign-in gives `user` from `client`: `long` for an encrypted user
 * without an email on the phone (its only way back in is its recovery key), else `standard`. A
 * `migrating` user is plain here.
 */
export function lifetimeFor(
  user: { encryption: Encryption; isAnonymous: boolean },
  client: "android" | "ios" | "web",
): SessionLifetime {
  return user.encryption === "encrypted" && user.isAnonymous && client !== "web"
    ? "long"
    : "standard";
}

/**
 * Slides a `long` session: Better Auth only refreshes a session in the last 59 days before its
 * expiry, which a 760-day session used daily never reaches, so neither its `updatedAt` nor the
 * user's activity would move and the cleanup would delete a person who uses the app every day.
 * At most once a day, it renews the 760 days and stamps the user: when `updated_at` is a day old,
 * or when `expires_at` is more than a day short of 760 days (Better Auth's own refresh, after a
 * long idle, cut it to 60 days and moved `updated_at` to now). Only while the user is still an
 * encrypted user without an email, as `lifetimeFor` gives it.
 */
export async function slideLongSession(
  db: Db,
  sessionId: string,
  userId: string,
  now: Date,
): Promise<void> {
  const at = now.toISOString();
  const moved = await db.execute<{ id: string }>(sql`update ${session}
    set updated_at = ${at}::timestamp,
      expires_at = ${at}::timestamp + make_interval(secs => ${LONG_SESSION_SECONDS})
    where ${session.id} = ${sessionId} and ${session.userId} = ${userId}
      and ${session.lifetime} = 'long'
      and (${session.updatedAt} < ${at}::timestamp - interval '1 day'
        or ${session.expiresAt} < ${at}::timestamp + make_interval(secs => ${LONG_SESSION_SECONDS})
          - interval '1 day')
      and exists (select 1 from ${user} where ${user.id} = ${userId}
        and ${user.isAnonymous} and ${user.encryption} = 'encrypted')
    returning ${session.id}`);
  if (moved.length > 0) await stampActivity(db, userId, now);
}

/**
 * Brings the user's `long` sessions back to `standard` (an email was added: the person can sign in
 * again with it), expiring at most 60 days from `now`; Better Auth slides them from then on. Run it
 * in the transaction that adds the email.
 */
export async function endLongSessions(db: Db | Tx, userId: string, now: Date): Promise<void> {
  // Raw SQL: an ORM update would also move `session.updatedAt`.
  await db.execute(sql`update ${session}
    set lifetime = 'standard',
      expires_at = least(expires_at, ${now.toISOString()}::timestamp + make_interval(secs => ${SESSION_SECONDS}))
    where ${session.userId} = ${userId} and ${session.lifetime} = 'long'`);
}
