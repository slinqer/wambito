import { activityDaily, user } from "@wambito/db";
import { eq } from "@wambito/db/orm";
import { afterAll, beforeAll, describe, expect, test } from "vitest";
import { ADMIN_ID, seedAdmin, verifiedAdmin } from "./admin-helpers.ts";
import { createTestApp, type TestApp } from "./harness.ts";

// A Wednesday: the current ISO week starts on 2026-11-02.
const NOW = new Date("2026-11-04T12:00:00.000Z");
const at = (iso: string) => new Date(`${iso}T10:00:00.000Z`);

interface Metrics {
  withEmail: number;
  guests: number;
  dailyActive: { day: string; count: number }[];
  cohorts: {
    weekStart: string;
    size: number;
    week1: number | null;
    week4: number | null;
    week12: number | null;
  }[];
  installsByPlatform: { platform: string; count: number }[];
  versions: { platform: string; appVersion: string; users: number }[];
}

describe("admin metrics: installs, daily actives, cohorts, versions", () => {
  let t: TestApp;
  let headers: { cookie: string };

  beforeAll(async () => {
    t = await createTestApp({ ADMIN_USER_IDS: [ADMIN_ID] }, { now: () => NOW });
    headers = await verifiedAdmin(t, await seedAdmin(t));

    // The admin has no platform: it is the one "unknown" install, created in 2026-08-31's week.
    await t.admin
      .update(user)
      .set({ createdAt: at("2026-09-01"), lastActiveAt: null })
      .where(eq(user.id, ADMIN_ID));
    const make = (
      id: string,
      createdAt: string,
      extra: Partial<typeof user.$inferInsert> = {},
    ): typeof user.$inferInsert => ({
      id,
      name: id,
      email: `${id}@wambito.test`,
      createdAt: at(createdAt),
      ...extra,
    });
    await t.admin.insert(user).values([
      // Cohort of the week of 2026-09-14: three people.
      make("a1", "2026-09-16", {
        platform: "android",
        appVersion: "1.2.0",
        lastSeenDay: "2026-11-03",
      }),
      make("a2", "2026-09-17", {
        platform: "android",
        appVersion: "1.2.0",
        lastSeenDay: "2026-10-20",
      }),
      make("a3", "2026-09-18", {
        platform: "android",
        appVersion: "1.1.0",
        lastSeenDay: "2026-08-01",
      }),
      // Cohort of the week of 2026-10-26: one person, without an email.
      make("i1", "2026-10-28", {
        platform: "ios",
        appVersion: "2.0.0",
        lastSeenDay: "2026-11-04",
        isAnonymous: true,
      }),
    ]);

    const row = (
      day: string,
      platform: string,
      appVersion: string,
      cohortWeek: string,
      count: number,
    ) => ({ day, platform, appVersion, cohortWeek, hasEmail: true, count });
    await t.admin.insert(activityDaily).values([
      // Two rows on one day add up; the 91st day back (2026-08-06) is outside the 90.
      row("2026-11-03", "android", "1.2.0", "2026-09-14", 4),
      row("2026-11-03", "ios", "2.0.0", "2026-10-26", 2),
      row("2026-11-04", "ios", "2.0.0", "2026-10-26", 1),
      row("2026-08-07", "android", "1.0.0", "2026-08-03", 2),
      row("2026-08-06", "android", "1.0.0", "2026-08-03", 9),
      // Cohort 2026-09-14: week 1 is 09-21..09-27 (highest day 3), week 4 is 10-12..10-18.
      row("2026-09-22", "android", "1.2.0", "2026-09-14", 2),
      row("2026-09-25", "android", "1.2.0", "2026-09-14", 3),
      row("2026-10-13", "android", "1.2.0", "2026-09-14", 1),
    ]);
  });

  afterAll(async () => {
    await t.stop();
  });

  const metrics = async () => {
    const res = await t.request("GET", "/v1/admin/metrics", { headers });
    expect(res.status).toBe(200);
    return (await res.json()) as Metrics;
  };

  test("metrics: dailyActive, cohorts, installs by platform and versions on seeded users", async () => {
    const m = await metrics();

    // guests still counts the users without an email.
    expect(m.guests).toBe(1);
    expect(m.withEmail).toBe(4);

    expect(m.dailyActive).toHaveLength(90);
    expect(m.dailyActive[0]).toEqual({ day: "2026-08-07", count: 2 });
    expect(m.dailyActive[89]).toEqual({ day: "2026-11-04", count: 1 });
    const byDay = new Map(m.dailyActive.map((d) => [d.day, d.count]));
    expect(byDay.get("2026-11-03")).toBe(6);
    expect(byDay.get("2026-09-22")).toBe(2);
    expect(byDay.get("2026-08-06")).toBeUndefined();
    expect(m.dailyActive.reduce((sum, d) => sum + d.count, 0)).toBe(2 + 6 + 1 + 2 + 3 + 1);
    expect(m.dailyActive.filter((d) => d.count === 0)).toHaveLength(90 - 6);

    expect(m.cohorts).toHaveLength(12);
    expect(m.cohorts[0]?.weekStart).toBe("2026-08-17");
    expect(m.cohorts[11]?.weekStart).toBe("2026-11-02");
    const cohort = (week: string) => m.cohorts.find((c) => c.weekStart === week);
    expect(cohort("2026-09-14")).toEqual({
      weekStart: "2026-09-14",
      size: 3,
      week1: 3,
      week4: 1,
      week12: null,
    });
    // Ended weeks without activity are 0; weeks that have not ended are null.
    expect(cohort("2026-08-31")).toEqual({
      weekStart: "2026-08-31",
      size: 1,
      week1: 0,
      week4: 0,
      week12: null,
    });
    expect(cohort("2026-10-26")).toEqual({
      weekStart: "2026-10-26",
      size: 1,
      week1: null,
      week4: null,
      week12: null,
    });
    expect(cohort("2026-08-17")?.size).toBe(0);

    expect(m.installsByPlatform).toEqual([
      { platform: "android", count: 3 },
      { platform: "ios", count: 1 },
      { platform: "web", count: 0 },
      { platform: "unknown", count: 1 },
    ]);

    // Seen within 30 days only: a3 (2026-08-01) is out.
    expect(m.versions).toEqual([
      { platform: "android", appVersion: "1.2.0", users: 2 },
      { platform: "ios", appVersion: "2.0.0", users: 1 },
    ]);
  });
});
