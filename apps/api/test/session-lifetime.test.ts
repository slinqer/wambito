import { session, user } from "@wambito/db";
import { eq } from "@wambito/db/orm";
import { afterAll, beforeAll, describe, expect, test } from "vitest";
import { cleanupInactiveGuests } from "../src/services/guest-cleanup.ts";
import { codeFrom, createTestApp, type TestApp } from "./harness.ts";

// Session lifetimes (spec 2026-11-15): an encrypted user without an email keeps a 25-month (760-day)
// session on the phone; every other session is the standard 60 days. Better Auth never refreshes a
// 760-day session (its refresh window is the last 59 days), so `requireUser` slides it, at most once
// a day, and stamps the user's activity: the "two clocks".

const DAY = 24 * 60 * 60 * 1000;
const PHONE = { "x-wambito-client": "android" };

type Auth = { userId: string; headers: { authorization: string } };

async function guest(t: TestApp, headers: Record<string, string> = {}): Promise<Auth> {
  const res = await t.request("POST", "/auth/sign-in/anonymous", { body: {}, headers });
  if (res.status !== 200) throw new Error(`guest failed: ${res.status} ${await res.text()}`);
  const json = (await res.json()) as { user: { id: string } };
  return {
    userId: json.user.id,
    headers: { authorization: `Bearer ${res.headers.get("set-auth-token")}` },
  };
}

/** The email-code sign-in with extra headers (a new email makes a new user). */
async function emailUser(t: TestApp, email: string, headers: Record<string, string>) {
  await t.request("POST", "/auth/email-otp/send-verification-otp", {
    body: { email, type: "sign-in" },
    headers,
  });
  const mail = t.mailer.lastTo(email);
  if (!mail) throw new Error("no sign-in mail");
  const res = await t.request("POST", "/auth/sign-in/email-otp", {
    body: { email, otp: codeFrom(mail.subject) },
    headers,
  });
  if (res.status !== 200) throw new Error(`sign-in failed: ${res.status} ${await res.text()}`);
  return ((await res.json()) as { user: { id: string } }).user.id;
}

const sessionOf = async (t: TestApp, userId: string) => {
  const rows = await t.admin.select().from(session).where(eq(session.userId, userId));
  expect(rows).toHaveLength(1);
  const [row] = rows;
  if (!row) throw new Error("no session");
  return row;
};

/** Days from now until `at`. */
const daysUntil = (at: Date) => (at.getTime() - Date.now()) / DAY;
const recent = (at: Date | null | undefined) =>
  expect(Math.abs(Date.now() - (at?.getTime() ?? 0))).toBeLessThan(60_000);

describe("session lifetimes, NEW_USERS_ENCRYPTED on", () => {
  let t: TestApp;
  beforeAll(async () => {
    t = await createTestApp({ NEW_USERS_ENCRYPTED: true });
  });
  afterAll(() => t?.stop());

  test("an encrypted guest signing up from the phone (x-wambito-client: android) gets a 760-day long session", async () => {
    const g = await guest(t, PHONE);
    const row = await sessionOf(t, g.userId);
    expect(row.lifetime).toBe("long");
    expect(daysUntil(row.expiresAt)).toBeGreaterThan(760 - 0.01);
    expect(daysUntil(row.expiresAt)).toBeLessThanOrEqual(760);
  });

  test("the same from ios too; from no client header (web) a 60-day standard one", async () => {
    const ios = await sessionOf(t, (await guest(t, { "x-wambito-client": "ios" })).userId);
    expect(ios.lifetime).toBe("long");
    expect(daysUntil(ios.expiresAt)).toBeGreaterThan(760 - 0.01);

    const web = await sessionOf(t, (await guest(t)).userId);
    expect(web.lifetime).toBe("standard");
    expect(daysUntil(web.expiresAt)).toBeGreaterThan(60 - 0.01);
    expect(daysUntil(web.expiresAt)).toBeLessThanOrEqual(60);
  });

  test("an email user's phone session stays 60 days", async () => {
    const userId = await emailUser(t, "phone@wambito.test", PHONE);
    const [born] = await t.admin.select().from(user).where(eq(user.id, userId));
    expect(born?.encryption).toBe("encrypted");
    const row = await sessionOf(t, userId);
    expect(row.lifetime).toBe("standard");
    expect(daysUntil(row.expiresAt)).toBeLessThanOrEqual(60);
  });

  /** As a long session last used 400 days ago looks: 360 days left, the user idle as long. */
  async function age(userId: string) {
    const long = new Date(Date.now() - 400 * DAY);
    await t.admin
      .update(session)
      .set({ updatedAt: long, expiresAt: new Date(Date.now() + 360 * DAY) })
      .where(eq(session.userId, userId));
    await t.admin.update(user).set({ lastActiveAt: long }).where(eq(user.id, userId));
  }

  test("a long session used daily is slid once a day and keeps the user from the cleanup", async () => {
    const g = await guest(t, PHONE);
    await age(g.userId);

    expect((await t.request("GET", "/v1/me", { headers: g.headers })).status).toBe(200);

    const slid = await sessionOf(t, g.userId);
    recent(slid.updatedAt);
    expect(daysUntil(slid.expiresAt)).toBeGreaterThan(760 - 0.01);
    expect(daysUntil(slid.expiresAt)).toBeLessThanOrEqual(760);
    const [stamped] = await t.admin.select().from(user).where(eq(user.id, g.userId));
    recent(stamped?.lastActiveAt);

    // A second request the same day moves neither clock.
    expect((await t.request("GET", "/v1/me", { headers: g.headers })).status).toBe(200);
    const again = await sessionOf(t, g.userId);
    expect(again.updatedAt).toEqual(slid.updatedAt);
    expect(again.expiresAt).toEqual(slid.expiresAt);
    const [still] = await t.admin.select().from(user).where(eq(user.id, g.userId));
    expect(still?.lastActiveAt).toEqual(stamped?.lastActiveAt);

    // Without the slide this guest would look 400 days idle.
    await cleanupInactiveGuests(t.db, new Date());
    expect(await t.admin.select().from(user).where(eq(user.id, g.userId))).toHaveLength(1);
  });

  test("a long session Better Auth shortened (30 days left, updated now) is slid back to 760 days", async () => {
    const g = await guest(t, PHONE);
    // As Better Auth's own refresh leaves it: updated_at now, expires_at within its 60-day window.
    await t.admin
      .update(session)
      .set({ updatedAt: new Date(), expiresAt: new Date(Date.now() + 30 * DAY) })
      .where(eq(session.userId, g.userId));

    expect((await t.request("GET", "/v1/me", { headers: g.headers })).status).toBe(200);

    const slid = await sessionOf(t, g.userId);
    expect(slid.lifetime).toBe("long");
    expect(daysUntil(slid.expiresAt)).toBeGreaterThan(760 - 0.01);
    expect(daysUntil(slid.expiresAt)).toBeLessThanOrEqual(760);
  });

  test("a long session is never slid once its user has an email or is plain", async () => {
    const withEmail = await guest(t, PHONE);
    const plain = await guest(t, PHONE);
    await t.admin
      .update(user)
      .set({ email: "slide-email@wambito.test", isAnonymous: false })
      .where(eq(user.id, withEmail.userId));
    await t.admin.update(user).set({ encryption: "plain" }).where(eq(user.id, plain.userId));
    for (const g of [withEmail, plain]) {
      await age(g.userId);
      const before = await sessionOf(t, g.userId);
      expect(before.lifetime).toBe("long");

      expect((await t.request("GET", "/v1/me", { headers: g.headers })).status).toBe(200);

      const after = await sessionOf(t, g.userId);
      expect(after.updatedAt).toEqual(before.updatedAt);
      expect(after.expiresAt).toEqual(before.expiresAt);
    }
  });

  test("a background request (x-wambito-background: 1) never slides a long session", async () => {
    const g = await guest(t, PHONE);
    await age(g.userId);
    const before = await sessionOf(t, g.userId);
    const [idle] = await t.admin.select().from(user).where(eq(user.id, g.userId));

    const res = await t.request("GET", "/v1/me", {
      headers: { ...g.headers, "x-wambito-background": "1" },
    });
    expect(res.status).toBe(200);

    const after = await sessionOf(t, g.userId);
    expect(after.updatedAt).toEqual(before.updatedAt);
    expect(after.expiresAt).toEqual(before.expiresAt);
    const [still] = await t.admin.select().from(user).where(eq(user.id, g.userId));
    expect(still?.lastActiveAt).toEqual(idle?.lastActiveAt);
  });
});

describe("session lifetimes, NEW_USERS_ENCRYPTED off", () => {
  let t: TestApp;
  beforeAll(async () => {
    t = await createTestApp();
  });
  afterAll(() => t?.stop());

  test("a plain guest's phone session stays 60 days (flag off)", async () => {
    const row = await sessionOf(t, (await guest(t, PHONE)).userId);
    expect(row.lifetime).toBe("standard");
    expect(daysUntil(row.expiresAt)).toBeGreaterThan(60 - 0.01);
    expect(daysUntil(row.expiresAt)).toBeLessThanOrEqual(60);
  });
});
