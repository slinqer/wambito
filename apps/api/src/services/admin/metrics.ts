import { activityDaily, type Db, session, user } from "@wambito/db";
import { sql } from "@wambito/db/orm";

const DAY_MS = 24 * 60 * 60 * 1000;
const WEEKS = 12;
const ACTIVE_DAYS = 90;
const VERSION_DAYS = 30;
const PLATFORMS = ["android", "ios", "web", "unknown"] as const;

export interface AdminMetrics {
  total: number;
  withEmail: number;
  guests: number;
  /** Accounts whose latest activity (as in the look-up) is within 30 days. */
  active30d: number;
  suspended: number;
  signups7d: number;
  signupsPrev7d: number;
  /** The last 12 ISO weeks (Monday, UTC), oldest first. */
  weekly: { weekStart: string; withEmail: number; guests: number }[];
  /** The last 90 days ending today (UTC), oldest first, zero-filled: the sum of `activity_daily`. */
  dailyActive: { day: string; count: number }[];
  /**
   * The last 12 ISO weeks of sign-up. `weekN` is the cohort's highest daily count during days
   * 7N..7N+6 after its week (an "at least": the aggregate keeps no user rows); `null` while
   * that week has not ended.
   */
  cohorts: {
    weekStart: string;
    size: number;
    week1: number | null;
    week4: number | null;
    week12: number | null;
  }[];
  installsByPlatform: { platform: (typeof PLATFORMS)[number]; count: number }[];
  /** Users seen in the last 30 days, by platform and app version, most users first. */
  versions: { platform: string; appVersion: string; users: number }[];
}

/** Monday 00:00 UTC of the ISO week that contains `d`. */
function isoWeekStart(d: Date): Date {
  const midnight = Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate());
  const sinceMonday = (d.getUTCDay() + 6) % 7;
  return new Date(midnight - sinceMonday * DAY_MS);
}

/**
 * The home screen's numbers (spec §6): SQL aggregates over `user` and `session` only, so no
 * account row leaves the database. `user` timestamps are UTC without a zone, hence the
 * `::timestamp` casts of ISO strings.
 */
export async function adminMetrics(db: Db, now: Date): Promise<AdminMetrics> {
  const ts = (d: Date) => sql`${d.toISOString()}::timestamp`;
  const ago = (days: number) => ts(new Date(now.getTime() - days * DAY_MS));
  const latest = sql`greatest(
    ${user.lastActiveAt},
    (select max(${session.updatedAt}) from ${session} where ${session.userId} = ${user.id})
  )`;

  const [totals] = await db
    .select({
      total: sql<number>`count(*)::int`,
      guests: sql<number>`(count(*) filter (where ${user.isAnonymous}))::int`,
      active30d: sql<number>`(count(*) filter (where ${latest} >= ${ago(30)}))::int`,
      suspended: sql<number>`(count(*) filter (where ${user.suspendedAt} is not null))::int`,
      signups7d: sql<number>`(count(*) filter (where ${user.createdAt} > ${ago(7)} and ${user.createdAt} <= ${ts(now)}))::int`,
      signupsPrev7d: sql<number>`(count(*) filter (where ${user.createdAt} > ${ago(14)} and ${user.createdAt} <= ${ago(7)}))::int`,
    })
    .from(user);

  const lastWeek = isoWeekStart(now);
  const firstWeek = new Date(lastWeek.getTime() - (WEEKS - 1) * 7 * DAY_MS);
  const rows = await db.execute<{ week_start: string; with_email: number; guests: number }>(sql`
    select to_char(w, 'YYYY-MM-DD') as week_start,
           (count(u.id) filter (where not u.is_anonymous))::int as with_email,
           (count(u.id) filter (where u.is_anonymous))::int as guests
    from generate_series(${ts(firstWeek)}, ${ts(lastWeek)}, interval '1 week') as w
    left join ${user} u
      on u.created_at >= w and u.created_at < w + interval '1 week'
    group by w
    order by w`);

  const today = now.toISOString().slice(0, 10);
  const firstDay = new Date(now.getTime() - (ACTIVE_DAYS - 1) * DAY_MS).toISOString().slice(0, 10);
  const dailyRows = await db.execute<{ day: string; count: number }>(sql`
    select to_char(d, 'YYYY-MM-DD') as day, coalesce(sum(a.count), 0)::int as count
    from generate_series(${firstDay}::date, ${today}::date, interval '1 day') as d
    left join ${activityDaily} a on a.day = d::date
    group by d
    order by d`);

  // Week N of a cohort: the highest daily total in days 7N..7N+6 after its week, null until
  // that week is over (its last day is before today).
  const weekN = (n: number) => {
    const from = sql.raw(String(7 * n));
    const to = sql.raw(String(7 * n + 7));
    return sql`case when w::date + ${to} <= ${today}::date then coalesce((
      select max(t.total) from (
        select sum(a.count) as total from ${activityDaily} a
        where a.cohort_week = w::date and a.day >= w::date + ${from} and a.day < w::date + ${to}
        group by a.day) t), 0)::int end`;
  };
  const cohortRows = await db.execute<{
    week_start: string;
    size: number;
    week1: number | null;
    week4: number | null;
    week12: number | null;
  }>(sql`
    select to_char(w, 'YYYY-MM-DD') as week_start,
           (select count(*)::int from ${user} u
             where u.created_at >= w and u.created_at < w + interval '1 week') as size,
           ${weekN(1)} as week1, ${weekN(4)} as week4, ${weekN(12)} as week12
    from generate_series(${ts(firstWeek)}, ${ts(lastWeek)}, interval '1 week') as w
    order by w`);

  const platformRows = await db
    .select({
      platform: sql<string>`coalesce(${user.platform}, 'unknown')`,
      count: sql<number>`count(*)::int`,
    })
    .from(user)
    .groupBy(sql`1`);
  const installs = new Map(platformRows.map((r) => [r.platform, r.count]));

  const since = new Date(now.getTime() - VERSION_DAYS * DAY_MS).toISOString().slice(0, 10);
  const versions = await db
    .select({
      platform: sql<string>`${user.platform}`,
      appVersion: sql<string>`${user.appVersion}`,
      users: sql<number>`count(*)::int`,
    })
    .from(user)
    .where(
      sql`${user.lastSeenDay} >= ${since} and ${user.platform} is not null and ${user.appVersion} is not null`,
    )
    .groupBy(user.platform, user.appVersion)
    .orderBy(sql`3 desc`, user.platform, user.appVersion);

  const total = totals?.total ?? 0;
  const guests = totals?.guests ?? 0;
  return {
    total,
    withEmail: total - guests,
    guests,
    active30d: totals?.active30d ?? 0,
    suspended: totals?.suspended ?? 0,
    signups7d: totals?.signups7d ?? 0,
    signupsPrev7d: totals?.signupsPrev7d ?? 0,
    weekly: [...rows].map((r) => ({
      weekStart: r.week_start,
      withEmail: r.with_email,
      guests: r.guests,
    })),
    dailyActive: [...dailyRows].map((r) => ({ day: r.day, count: r.count })),
    cohorts: [...cohortRows].map((r) => ({
      weekStart: r.week_start,
      size: r.size,
      week1: r.week1,
      week4: r.week4,
      week12: r.week12,
    })),
    installsByPlatform: PLATFORMS.map((platform) => ({
      platform,
      count: installs.get(platform) ?? 0,
    })),
    versions,
  };
}
