import { rateLimit, session } from "@wambito/db";
import { eq } from "@wambito/db/orm";
import { afterAll, beforeAll, describe, expect, test } from "vitest";
import { createTestApp, type TestApp } from "./harness.ts";

let t: TestApp;
beforeAll(async () => {
  t = await createTestApp();
});
afterAll(() => t?.stop());

const guestFrom = (ip: string) =>
  t.request("POST", "/auth/sign-in/anonymous", {
    body: {},
    headers: { "x-forwarded-for": `${ip}, 10.0.0.1` },
  });

describe("no IP address is stored", () => {
  test("a session created by email sign-in or guest sign-up, and then refreshed, stores no ip_address", async () => {
    const { userId, headers } = await t.signIn("noip@wambito.test");
    const guest = await guestFrom("198.51.100.20");
    expect(guest.status).toBe(200);
    const guestId = ((await guest.json()) as { user: { id: string } }).user.id;

    let rows = await t.admin.select().from(session);
    expect(rows.length).toBeGreaterThanOrEqual(2);
    for (const row of rows) expect(row.ipAddress ?? "").toBe("");

    // Age the email session past the daily refresh, then use it: Better Auth refreshes it.
    const day = 24 * 60 * 60 * 1000;
    const old = new Date(Date.now() - 2 * day);
    await t.admin
      .update(session)
      .set({ updatedAt: old, expiresAt: new Date(Date.now() + 58 * day) })
      .where(eq(session.userId, userId));
    expect((await t.request("GET", "/v1/me", { headers })).status).toBe(200);
    const [refreshed] = await t.admin.select().from(session).where(eq(session.userId, userId));
    expect(refreshed?.updatedAt.getTime()).toBeGreaterThan(old.getTime());

    rows = await t.admin.select().from(session);
    expect(rows.some((r) => r.userId === guestId)).toBe(true);
    for (const row of rows) expect(row.ipAddress ?? "").toBe("");
  });

  test("after sign-ins from several addresses the rate_limit table holds no row", async () => {
    for (const ip of ["198.51.100.31", "198.51.100.32", "198.51.100.33"]) {
      expect((await guestFrom(ip)).status).toBe(200);
    }
    expect(await t.admin.select().from(rateLimit)).toHaveLength(0);
  });

  // Better Auth caps sign-in and sign-up paths tighter (3 per 10 s) than its general 30 per minute;
  // the general rule is shown on a plain endpoint, the tighter one on guest sign-up.
  test("Better Auth still rate-limits per address: 31 requests from one IP in a minute, the 31st is 429", async () => {
    const statuses: number[] = [];
    for (let i = 0; i < 31; i++) {
      const res = await t.request("GET", "/auth/get-session", {
        headers: { "x-forwarded-for": "198.51.100.7, 10.0.0.1" },
      });
      statuses.push(res.status);
    }
    expect(statuses.slice(0, 30).every((s) => s !== 429)).toBe(true);
    expect(statuses[30]).toBe(429);
  });

  test("guest sign-up keeps its tighter per-address limit: the 4th in 10 seconds is 429", async () => {
    const statuses: number[] = [];
    for (let i = 0; i < 4; i++) statuses.push((await guestFrom("198.51.100.8")).status);
    expect(statuses).toEqual([200, 200, 200, 429]);
  });

  test("the email-change confirm still answers 429 on the 11th try from one address", async () => {
    const ip = "198.51.100.9, 10.0.0.1";
    const confirm = (n: number) =>
      t.request("POST", "/v1/email-change/confirm", {
        body: { token: `unknown-${n}` },
        headers: { "x-forwarded-for": ip },
      });
    for (let i = 0; i < 10; i++) expect((await confirm(i)).status).toBe(410);
    expect((await confirm(10)).status).toBe(429);
    expect(await t.admin.select().from(rateLimit)).toHaveLength(0);
  });
});
