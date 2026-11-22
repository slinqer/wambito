import { type Db, user } from "@wambito/db";
import { sql } from "@wambito/db/orm";
import { stampActivity } from "./guest-cleanup.ts";

/** The longest app version `x-wambito-version` may carry; a longer one is ignored. */
export const MAX_APP_VERSION = 64;

/** What a version may hold: letters, digits and `.+_-`, 1 to 64 characters (`1.2.0+12`). */
const APP_VERSION = new RegExp(`^[0-9A-Za-z.+_-]{1,${MAX_APP_VERSION}}$`);

/** The app version a request's header says: trimmed, if it matches `APP_VERSION`, else null. */
export function appVersionOf(header: string | undefined): string | null {
  const version = header?.trim();
  return version && APP_VERSION.test(version) ? version : null;
}

export interface SeenInput {
  userId: string;
  /** The person's local day, `YYYY-MM-DD` (`userToday`). */
  today: string;
  platform: "android" | "ios" | "web";
  appVersion: string | null;
  now: Date;
}

/**
 * Counts the user's first call of a local day in `activity_daily` (spec 2026-11-15 §9) and returns
 * whether it counted. It is ONE statement: the `update` moves `last_seen_day` only when it is null
 * or earlier than `today`, so of two concurrent first calls only one finds the row to move (the
 * other waits on the row lock, re-reads it, and updates nothing), and only that one upserts
 * `count = count + 1` on the row of (`today`, platform, version or `''`, the user's cohort Monday,
 * has an email). Moving to a zone where `today` is earlier changes nothing, and never moves the
 * day back. The version is set whenever it is given. Activity (`last_active_at`) is stamped on
 * every call, counted or not.
 *
 * `activity_daily` has no user id: it keeps no per-person history.
 */
export async function markSeen(db: Db, input: SeenInput): Promise<boolean> {
  const { userId, today, platform, appVersion, now } = input;
  const counted = await db.execute<{ counted: boolean }>(sql`
    with moved as (
      update ${user}
      set last_seen_day = ${today}, app_version = coalesce(${appVersion}::text, app_version)
      where ${user.id} = ${userId}
        and (${user.lastSeenDay} is null or ${user.lastSeenDay} < ${today})
      returning (date_trunc('week', ${user.createdAt})::date) as cohort_week,
        not ${user.isAnonymous} as has_email
    ),
    counted as (
      insert into activity_daily (day, platform, app_version, cohort_week, has_email, count)
      select ${today}::date, ${platform}, ${appVersion ?? ""}, cohort_week, has_email, 1
      from moved
      on conflict (day, platform, app_version, cohort_week, has_email)
      do update set count = activity_daily.count + 1
      returning 1
    )
    select exists (select 1 from counted) as counted`);
  if (!counted[0]?.counted && appVersion) {
    // Not the first call of the day: the version may still have changed (an update mid-day).
    await db.execute(
      sql`update ${user} set app_version = ${appVersion} where ${user.id} = ${userId}
        and app_version is distinct from ${appVersion}`,
    );
  }
  await stampActivity(db, userId, now);
  return counted[0]?.counted === true;
}
