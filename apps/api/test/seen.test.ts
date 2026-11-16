import { activityDaily, user } from "@wambito/db";
import { eq, sql } from "@wambito/db/orm";
import { afterAll, beforeAll, describe, expect, test } from "vitest";
import { createTestApp, type TestApp } from "./harness.ts";

// POST /v2/me/seen (spec 2026-11-15 §9): the first call of a person's local day counts one in
// `activity_daily`, an aggregate with no user id. `user.last_seen_day` is the person's own
// marker, so a second call the same day counts nothing, and it only moves forward.

let clock = new Date("2026-03-10T12:00:00Z");
let t: TestApp;
let people = 0;
beforeAll(async () => {
  t = await createTestApp({}, { now: () => clock });
});
afterAll(() => t?.stop());

type Person = { userId: string; headers: { authorization: string } };
const person = () => t.signIn(`seen-${++people}@wambito.test`);

const seen = (p: Person, headers: Record<string, string> = {}) =>
  t.request("POST", "/v2/me/seen", { headers: { ...p.headers, ...headers } });

const rows = () => t.admin.select().from(activityDaily);
const reset = () => t.admin.delete(activityDaily);
const userRow = async (id: string) => {
  const [row] = await t.admin.select().from(user).where(eq(user.id, id));
  if (!row) throw new Error("no user");
  return row;
};
const at = (iso: string) => {
  clock = new Date(iso);
};

describe("POST /v2/me/seen", () => {
  test("the first call of a day counts one in activity_daily with platform, version, cohort week and has_email", async () => {
    await reset();
    at("2026-03-10T12:00:00Z");
    const p = await person();
    // Created on Wednesday 2026-03-11 of that week's Monday 2026-03-09.
    await t.admin
      .update(user)
      .set({ createdAt: new Date("2026-03-11T08:00:00Z") })
      .where(eq(user.id, p.userId));
    const res = await seen(p, { "x-wambito-client": "ios", "x-wambito-version": "1.4.0" });
    expect(res.status).toBe(204);
    expect(await rows()).toEqual([
      {
        day: "2026-03-10",
        platform: "ios",
        appVersion: "1.4.0",
        cohortWeek: "2026-03-09",
        hasEmail: true,
        count: 1,
      },
    ]);
    expect((await userRow(p.userId)).lastSeenDay).toBe("2026-03-10");
  });

  test("a guest counts as has_email false, a web call as platform web with no version", async () => {
    await reset();
    at("2026-03-10T12:00:00Z");
    const res = await t.request("POST", "/auth/sign-in/anonymous", { body: {} });
    const g = {
      userId: ((await res.json()) as { user: { id: string } }).user.id,
      headers: { authorization: `Bearer ${res.headers.get("set-auth-token")}` },
    };
    expect((await seen(g)).status).toBe(204);
    const [row] = await rows();
    expect(row).toMatchObject({ platform: "web", appVersion: "", hasEmail: false, count: 1 });
  });

  test("a second call the same day counts nothing more", async () => {
    await reset();
    at("2026-03-10T12:00:00Z");
    const p = await person();
    await seen(p);
    at("2026-03-10T20:00:00Z");
    expect((await seen(p)).status).toBe(204);
    expect((await rows()).map((r) => r.count)).toEqual([1]);
  });

  test("two people on the same day share one row", async () => {
    await reset();
    at("2026-03-10T12:00:00Z");
    const [a, b] = [await person(), await person()];
    await Promise.all([a, b].map((p) => seen(p)));
    expect((await rows()).map((r) => r.count)).toEqual([2]);
  });

  test("two concurrent first calls of a day count once", async () => {
    await reset();
    at("2026-03-10T12:00:00Z");
    const p = await person();
    await Promise.all([seen(p), seen(p), seen(p)]);
    expect((await rows()).map((r) => r.count)).toEqual([1]);
  });

  test("the next local day counts again, in the next day's row", async () => {
    await reset();
    at("2026-03-10T12:00:00Z");
    const p = await person();
    await seen(p);
    at("2026-03-11T12:00:00Z");
    await seen(p);
    expect((await rows()).map((r) => [r.day, r.count]).sort()).toEqual([
      ["2026-03-10", 1],
      ["2026-03-11", 1],
    ]);
    expect((await userRow(p.userId)).lastSeenDay).toBe("2026-03-11");
  });

  test("a user in America/Bogota calling at 23:30 and 00:30 UTC on the same local day counts once", async () => {
    await reset();
    const p = await person();
    await t.admin.update(user).set({ timezone: "America/Bogota" }).where(eq(user.id, p.userId));
    // Bogota is UTC-5: 2026-03-10 23:30 UTC and 2026-03-11 00:30 UTC are both 2026-03-10 locally.
    at("2026-03-10T23:30:00Z");
    await seen(p);
    at("2026-03-11T00:30:00Z");
    await seen(p);
    expect(await rows()).toMatchObject([{ day: "2026-03-10", count: 1 }]);
    expect((await userRow(p.userId)).lastSeenDay).toBe("2026-03-10");
  });

  test("moving the user to a zone where today is earlier neither counts nor moves last_seen_day back", async () => {
    await reset();
    const p = await person();
    await t.admin.update(user).set({ timezone: "Pacific/Auckland" }).where(eq(user.id, p.userId));
    at("2026-03-10T20:00:00Z"); // 2026-03-11 in Auckland
    await seen(p);
    expect((await userRow(p.userId)).lastSeenDay).toBe("2026-03-11");
    await t.admin.update(user).set({ timezone: "America/Bogota" }).where(eq(user.id, p.userId));
    expect((await seen(p)).status).toBe(204); // 2026-03-10 in Bogota
    expect((await userRow(p.userId)).lastSeenDay).toBe("2026-03-11");
    expect(await rows()).toMatchObject([{ day: "2026-03-11", count: 1 }]);
  });

  test("x-wambito-version sets user.app_version; a 65-character value is ignored", async () => {
    await reset();
    at("2026-03-10T12:00:00Z");
    const p = await person();
    await seen(p, { "x-wambito-version": " 2.0.1 " });
    expect((await userRow(p.userId)).appVersion).toBe("2.0.1");
    at("2026-03-11T12:00:00Z");
    await seen(p, { "x-wambito-version": "x".repeat(65) });
    const row = await userRow(p.userId);
    expect(row.appVersion).toBe("2.0.1");
    expect((await rows()).map((r) => r.appVersion).sort()).toEqual(["", "2.0.1"]);
  });

  test("x-wambito-version keeps only [0-9A-Za-z.+_-]: a space or a control character is ignored", async () => {
    await reset();
    at("2026-03-10T12:00:00Z");
    const p = await person();
    await seen(p, { "x-wambito-version": "1.2.0+12" });
    expect((await userRow(p.userId)).appVersion).toBe("1.2.0+12");
    at("2026-03-11T12:00:00Z");
    await seen(p, { "x-wambito-version": "1.2 beta" });
    at("2026-03-12T12:00:00Z");
    await seen(p, { "x-wambito-version": "1.2\u0001" });
    expect((await userRow(p.userId)).appVersion).toBe("1.2.0+12");
    expect((await rows()).map((r) => r.appVersion).sort()).toEqual(["", "", "1.2.0+12"]);
  });

  test("a background request changes nothing: no row, last_seen_day unchanged", async () => {
    await reset();
    at("2026-03-10T12:00:00Z");
    const p = await person();
    await t.admin.update(user).set({ lastActiveAt: null }).where(eq(user.id, p.userId));
    const res = await seen(p, { "x-wambito-background": "1", "x-wambito-version": "9.9.9" });
    expect(res.status).toBe(204);
    expect(await rows()).toEqual([]);
    const row = await userRow(p.userId);
    expect(row.lastSeenDay).toBeNull();
    expect(row.appVersion).toBeNull();
    expect(row.lastActiveAt).toBeNull();
  });

  test("seen moves user.last_active_at", async () => {
    await reset();
    at("2026-03-10T12:00:00Z");
    const p = await person();
    await t.admin
      .update(user)
      .set({ lastActiveAt: new Date("2020-01-01T00:00:00Z") })
      .where(eq(user.id, p.userId));
    await seen(p);
    expect((await userRow(p.userId)).lastActiveAt).toEqual(clock);
    // A second call the same day counts nothing but still stamps.
    at("2026-03-10T18:00:00Z");
    await seen(p);
    expect((await userRow(p.userId)).lastActiveAt).toEqual(clock);
  });

  test("an assistant token gets 403", async () => {
    const tokens = await t.authorize("seen-assistant@wambito.test");
    const res = await t.request("POST", "/v2/me/seen", {
      headers: { authorization: `Bearer ${tokens.accessToken}` },
    });
    expect(res.status).toBe(403);
  });

  test("signed out gets 401", async () => {
    expect((await t.request("POST", "/v2/me/seen")).status).toBe(401);
  });

  test("activity_daily has no user id column", async () => {
    const cols = await t.admin.execute<{ column_name: string }>(
      sql`select column_name from information_schema.columns where table_name = 'activity_daily'`,
    );
    expect(cols.map((c) => c.column_name).sort()).toEqual([
      "app_version",
      "cohort_week",
      "count",
      "day",
      "has_email",
      "platform",
    ]);
  });
});
