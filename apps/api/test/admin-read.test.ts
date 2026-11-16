import { adminAudit, oauthClient, oauthConsent, passkey, session, user } from "@wambito/db";
import { eq } from "@wambito/db/orm";
import { afterAll, beforeAll, describe, expect, test } from "vitest";
import { ADMIN_ID, seedAdmin, verifiedAdmin } from "./admin-helpers.ts";
import { createTestApp, type TestApp } from "./harness.ts";

const NOW = new Date("2026-11-04T12:00:00.000Z");
const day = (iso: string) => new Date(`${iso}T10:00:00.000Z`);

const VIEW_KEYS = [
  "assistants",
  "createdAt",
  "email",
  "id",
  "isAnonymous",
  "lastActiveAt",
  "locale",
  "passkeys",
  "sessionCount",
  "suspendedAt",
];

describe("admin look-up, metrics and audit list", () => {
  let t: TestApp;
  let headers: { cookie: string };

  beforeAll(async () => {
    t = await createTestApp({ ADMIN_USER_IDS: [ADMIN_ID] }, { now: () => NOW });
    const key = await seedAdmin(t);
    headers = await verifiedAdmin(t, key);

    // Fixture, on the pinned clock: 3 people with an email (the admin, u1, u2 suspended), 2 guests.
    // The admin's sign-in stamped its activity on the real clock; its session is the only one.
    await t.admin
      .update(user)
      .set({ createdAt: day("2026-09-01"), lastActiveAt: null })
      .where(eq(user.id, ADMIN_ID));
    await t.admin.update(session).set({ updatedAt: day("2026-11-03") });
    await t.admin.insert(user).values([
      {
        id: "u1",
        name: "One",
        email: "one@wambito.test",
        createdAt: day("2026-10-30"),
        lastActiveAt: day("2026-10-30"),
        locale: "en",
      },
      {
        id: "u2",
        name: "Two",
        email: "two@wambito.test",
        createdAt: day("2026-10-25"),
        lastActiveAt: day("2026-08-01"),
        suspendedAt: day("2026-10-26"),
      },
      {
        id: "g1",
        name: "Guest",
        email: "g1@guest.wambito.invalid",
        isAnonymous: true,
        createdAt: day("2026-09-25"),
      },
      {
        id: "g2",
        name: "Guest",
        email: "g2@guest.wambito.invalid",
        isAnonymous: true,
        createdAt: day("2026-11-03"),
        lastActiveAt: day("2026-11-03"),
      },
    ]);
    await t.admin.insert(passkey).values({
      id: "pk1",
      name: "Laptop",
      publicKey: "x",
      userId: "u1",
      credentialID: "cred-u1",
      counter: 0,
      deviceType: "multiDevice",
      backedUp: true,
      createdAt: day("2026-10-01"),
    });
    await t.admin.insert(oauthClient).values({
      id: "oc1",
      clientId: "client-1",
      name: "Claude",
      redirectUris: ["https://claude.ai/cb"],
    });
    await t.admin.insert(oauthConsent).values({
      id: "co1",
      clientId: "client-1",
      userId: "u1",
      scopes: ["finance:read"],
      createdAt: day("2026-10-02"),
      updatedAt: day("2026-10-02"),
    });
  });
  afterAll(() => t?.stop());

  const get = (path: string) => t.request("GET", path, { headers });

  test("look-up by email ignores case and spaces, and returns exactly the view's keys", async () => {
    const res = await get(`/v1/admin/users?email=${encodeURIComponent("  One@Wambito.TEST ")}`);
    expect(res.status).toBe(200);
    const body = (await res.json()) as Record<string, unknown>;
    expect(Object.keys(body).sort()).toEqual(VIEW_KEYS);
    expect(body).toMatchObject({
      id: "u1",
      email: "one@wambito.test",
      isAnonymous: false,
      locale: "en",
      suspendedAt: null,
      sessionCount: 0,
      lastActiveAt: day("2026-10-30").toISOString(),
      passkeys: [
        {
          id: "pk1",
          name: "Laptop",
          deviceType: "multiDevice",
          createdAt: day("2026-10-01").toISOString(),
        },
      ],
      assistants: [
        { clientId: "client-1", name: "Claude", consentedAt: day("2026-10-02").toISOString() },
      ],
    });
  });

  test("look-up by id; a guest's email is null; a suspended one shows when", async () => {
    const guest = (await (await get("/v1/admin/users?id=g1")).json()) as Record<string, unknown>;
    expect(Object.keys(guest).sort()).toEqual(VIEW_KEYS);
    expect(guest).toMatchObject({ id: "g1", email: null, isAnonymous: true, lastActiveAt: null });
    const two = (await (await get("/v1/admin/users?id=u2")).json()) as { suspendedAt: string };
    expect(two.suspendedAt).toBe(day("2026-10-26").toISOString());
  });

  test("look-up counts sessions and takes the newest session as activity", async () => {
    const admin = (await (await get(`/v1/admin/users?id=${ADMIN_ID}`)).json()) as {
      sessionCount: number;
      lastActiveAt: string;
    };
    expect(admin.sessionCount).toBe(1);
    expect(admin.lastActiveAt).toBe(day("2026-11-03").toISOString());
  });

  test("an unknown email or id → 404 user_not_found; no parameter → 422", async () => {
    for (const q of ["email=nobody@wambito.test", "id=nope"]) {
      const res = await get(`/v1/admin/users?${q}`);
      expect(res.status).toBe(404);
      expect(((await res.json()) as { code: string }).code).toBe("user_not_found");
    }
    expect((await get("/v1/admin/users")).status).toBe(422);
  });

  test("the look-up carries nothing from the finance tables and writes no audit row", async () => {
    const before = await t.admin.select().from(adminAudit);
    const text = await (await get("/v1/admin/users?id=u1")).text();
    for (const word of [
      "transactions",
      "categories",
      "budgets",
      "recurrences",
      "imports",
      "accounts",
      "idempotency",
    ])
      expect(text).not.toContain(word);
    expect(await t.admin.select().from(adminAudit)).toHaveLength(before.length);
  });

  test("metrics over the fixture, on the pinned clock", async () => {
    const res = await get("/v1/admin/metrics");
    expect(res.status).toBe(200);
    const m = (await res.json()) as {
      weekly: { weekStart: string; withEmail: number; guests: number }[];
    };
    expect(m).toMatchObject({
      total: 5,
      withEmail: 3,
      guests: 2,
      active30d: 3,
      suspended: 1,
      signups7d: 2,
      signupsPrev7d: 1,
    });
    expect(m.weekly).toHaveLength(12);
    expect(m.weekly[0]?.weekStart).toBe("2026-08-17");
    expect(m.weekly[11]?.weekStart).toBe("2026-11-02");
    const nonZero = m.weekly.filter((w) => w.withEmail + w.guests > 0);
    expect(nonZero).toEqual([
      { weekStart: "2026-08-31", withEmail: 1, guests: 0 },
      { weekStart: "2026-09-21", withEmail: 0, guests: 1 },
      { weekStart: "2026-10-19", withEmail: 1, guests: 0 },
      { weekStart: "2026-10-26", withEmail: 1, guests: 0 },
      { weekStart: "2026-11-02", withEmail: 0, guests: 1 },
    ]);
  });

  test("the audit list: newest first, 50 per page, next until the end, filtered by target", async () => {
    const rows = Array.from({ length: 120 }, (_, i) => ({
      at: new Date(NOW.getTime() - (i + 1) * 60_000),
      adminUserId: ADMIN_ID,
      action: "account.suspend",
      targetUserId: "u2",
      reason: `r${i}`,
    }));
    await t.admin.insert(adminAudit).values(rows);

    const page1 = (await (await get("/v1/admin/audit?targetUserId=u2")).json()) as {
      entries: { at: string; reason: string }[];
      next: string | null;
    };
    expect(page1.entries).toHaveLength(50);
    expect(page1.entries[0]?.reason).toBe("r0");
    expect(page1.next).toEqual(expect.any(String));

    const page2 = (await (
      await get(`/v1/admin/audit?targetUserId=u2&before=${encodeURIComponent(page1.next ?? "")}`)
    ).json()) as { entries: { reason: string }[]; next: string | null };
    expect(page2.entries).toHaveLength(50);
    expect(page2.entries[0]?.reason).toBe("r50");

    const page3 = (await (
      await get(`/v1/admin/audit?targetUserId=u2&before=${encodeURIComponent(page2.next ?? "")}`)
    ).json()) as { entries: unknown[]; next: string | null };
    expect(page3.entries).toHaveLength(20);
    expect(page3.next).toBeNull();

    const all = (await (await get("/v1/admin/audit")).json()) as { entries: { action: string }[] };
    expect(all.entries).toHaveLength(50);
    expect(Object.keys(all.entries[0] ?? {}).sort()).toEqual([
      "action",
      "adminUserId",
      "at",
      "detail",
      "emailHash",
      "id",
      "reason",
      "targetUserId",
    ]);
  });

  test("rows sharing one `at` are all paged through exactly once", async () => {
    const at = new Date(NOW.getTime() + 60_000);
    await t.admin.insert(adminAudit).values(
      Array.from({ length: 120 }, (_, i) => ({
        at,
        adminUserId: ADMIN_ID,
        action: "account.reactivate",
        targetUserId: "same-at",
        reason: `s${i}`,
      })),
    );
    const seen: string[] = [];
    let before = "";
    for (let page = 0; page < 5; page++) {
      const q = `targetUserId=same-at${before ? `&before=${encodeURIComponent(before)}` : ""}`;
      const body = (await (await get(`/v1/admin/audit?${q}`)).json()) as {
        entries: { id: string }[];
        next: string | null;
      };
      seen.push(...body.entries.map((e) => e.id));
      if (!body.next) break;
      before = body.next;
    }
    expect(seen).toHaveLength(120);
    expect(new Set(seen).size).toBe(120);
  });

  test("a bad `before` → 422", async () => {
    expect((await get("/v1/admin/audit?before=yesterday")).status).toBe(422);
  });

  test("the admin routes need verification: no cookie → 404", async () => {
    for (const p of ["/v1/admin/users?id=u1", "/v1/admin/metrics", "/v1/admin/audit"])
      expect((await t.request("GET", p)).status).toBe(404);
  });
});
