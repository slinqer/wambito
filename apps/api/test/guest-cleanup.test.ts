import { accounts, categories, session, transactions, user } from "@wambito/db";
import { eq, inArray, sql } from "@wambito/db/orm";
import { afterAll, beforeAll, beforeEach, describe, expect, test, vi } from "vitest";
import {
  cleanupInactiveGuests,
  GUEST_CLEANUP_BATCH,
  GUEST_CLEANUP_LOCK,
  scheduleGuestCleanup,
} from "../src/services/guest-cleanup.ts";
import { createTestApp, type TestApp } from "./harness.ts";

const DAY = 24 * 60 * 60 * 1000;
const NOW = new Date("2026-10-22T12:00:00.000Z");
const daysAgo = (days: number) => new Date(NOW.getTime() - days * DAY);

let t: TestApp;
beforeAll(async () => {
  t = await createTestApp();
});
afterAll(() => t?.stop());

/** Removes everything the previous test left, so each test counts from zero. */
beforeEach(async () => {
  await t.admin.delete(user);
});

async function newGuest() {
  const res = await t.request("POST", "/auth/sign-in/anonymous", { body: {} });
  if (res.status !== 200) throw new Error(`guest sign-up failed: ${res.status}`);
  const token = res.headers.get("set-auth-token");
  const json = (await res.json()) as { user: { id: string } };
  return { userId: json.user.id, headers: { authorization: `Bearer ${token}` } };
}

/** Makes the user, and its sessions, last active `days` days before NOW. */
async function lastActive(userId: string, days: number) {
  await t.admin
    .update(session)
    .set({ updatedAt: daysAgo(days) })
    .where(eq(session.userId, userId));
  await t.admin
    .update(user)
    .set({ lastActiveAt: daysAgo(days) })
    .where(eq(user.id, userId));
}

const lastActiveAt = async (userId: string) =>
  (await t.admin.select({ at: user.lastActiveAt }).from(user).where(eq(user.id, userId)))[0]?.at;

const exists = async (userId: string) =>
  (await t.admin.select({ id: user.id }).from(user).where(eq(user.id, userId))).length === 1;

describe("cleanupInactiveGuests", () => {
  test("deletes a guest inactive for 61 days with its data", async () => {
    const g = await newGuest();
    const cat = await t.request("POST", "/v1/categories", {
      headers: g.headers,
      body: { name: "Food", kind: "expense", icon: "tag", color: "gray" },
    });
    const categoryId = ((await cat.json()) as { id: string }).id;
    const tx = await t.request("POST", "/v1/transactions", {
      headers: g.headers,
      body: { categoryId, name: "Lunch", amount: -1200, date: "2026-10-01" },
    });
    expect(tx.status).toBe(201);
    await lastActive(g.userId, 61);

    expect(await cleanupInactiveGuests(t.db, NOW)).toBe(1);

    expect(await exists(g.userId)).toBe(false);
    for (const table of [accounts, categories, transactions]) {
      expect(await t.admin.select().from(table).where(eq(table.userId, g.userId))).toHaveLength(0);
    }
    expect(await t.admin.select().from(session).where(eq(session.userId, g.userId))).toHaveLength(
      0,
    );
  });

  test("keeps a guest active 59 days ago", async () => {
    const g = await newGuest();
    await lastActive(g.userId, 59);

    expect(await cleanupInactiveGuests(t.db, NOW)).toBe(0);

    expect(await exists(g.userId)).toBe(true);
    expect(await t.admin.select().from(accounts).where(eq(accounts.userId, g.userId))).toHaveLength(
      1,
    );
  });

  test("goes by the latest session, not the oldest", async () => {
    const g = await newGuest();
    await lastActive(g.userId, 90);
    // A second device signed in later.
    const [first] = await t.admin.select().from(session).where(eq(session.userId, g.userId));
    await t.admin.insert(session).values({
      ...(first as typeof session.$inferSelect),
      id: "second-session",
      token: "second-token",
      updatedAt: daysAgo(3),
    });

    expect(await cleanupInactiveGuests(t.db, NOW)).toBe(0);
    expect(await exists(g.userId)).toBe(true);
  });

  test("a guest without any session counts from when it was created", async () => {
    const old = await newGuest();
    const recent = await newGuest();
    await t.admin.delete(session);
    await t.admin
      .update(user)
      .set({ createdAt: daysAgo(70), lastActiveAt: null })
      .where(eq(user.id, old.userId));
    await t.admin
      .update(user)
      .set({ createdAt: daysAgo(10), lastActiveAt: null })
      .where(eq(user.id, recent.userId));

    expect(await cleanupInactiveGuests(t.db, NOW)).toBe(1);

    expect(await exists(old.userId)).toBe(false);
    expect(await exists(recent.userId)).toBe(true);
  });

  test("never deletes a user with an email, however old", async () => {
    const member = await t.signIn("old-timer@wambito.test");
    await lastActive(member.userId, 5000);
    await t.admin
      .update(user)
      .set({ createdAt: daysAgo(5000) })
      .where(eq(user.id, member.userId));
    // A guest that claimed an email is a member from then on.
    const claimed = await newGuest();
    await t.admin
      .update(user)
      .set({ email: "claimed@wambito.test", isAnonymous: false })
      .where(eq(user.id, claimed.userId));
    await lastActive(claimed.userId, 400);

    expect(await cleanupInactiveGuests(t.db, NOW)).toBe(0);

    expect(await exists(member.userId)).toBe(true);
    expect(await exists(claimed.userId)).toBe(true);
  });

  test("two runs at once delete once", async () => {
    const guests = await Promise.all([newGuest(), newGuest(), newGuest()]);
    for (const g of guests) await lastActive(g.userId, 100);

    const counts = await Promise.all([
      cleanupInactiveGuests(t.db, NOW),
      cleanupInactiveGuests(t.db, NOW),
    ]);

    expect(counts.reduce((a, b) => a + b, 0)).toBe(3);
    const left = await t.admin
      .select({ id: user.id })
      .from(user)
      .where(
        inArray(
          user.id,
          guests.map((g) => g.userId),
        ),
      );
    expect(left).toHaveLength(0);
  });

  test("a run does nothing while another holds the advisory lock", async () => {
    const g = await newGuest();
    await lastActive(g.userId, 100);

    await t.admin.transaction(async (tx) => {
      await tx.execute(sql`select pg_advisory_xact_lock(${GUEST_CLEANUP_LOCK})`);
      expect(await cleanupInactiveGuests(t.db, NOW)).toBe(0);
      expect(await exists(g.userId)).toBe(true);
    });

    // The lock is gone with that transaction: the next run goes through.
    expect(await cleanupInactiveGuests(t.db, NOW)).toBe(1);
    expect(await exists(g.userId)).toBe(false);
  });

  test("the lock key is the one the brief names", () => {
    expect(GUEST_CLEANUP_LOCK).toBe(0x6c756b61);
  });
});

describe("NEW_USERS_ENCRYPTED on", () => {
  let on: TestApp;
  beforeAll(async () => {
    on = await createTestApp({ NEW_USERS_ENCRYPTED: true });
  });
  afterAll(() => on?.stop());

  test("a plain guest is still deleted at 61 days with the flag on", async () => {
    // A guest from before the switch: plain. A guest from after: encrypted, on the 12/24 months.
    const old = daysAgo(61);
    await on.admin.insert(user).values({
      id: "plain-guest",
      name: "Plain guest",
      email: "plain-guest@guest.wambito.invalid",
      isAnonymous: true,
      encryption: "plain",
      createdAt: old,
      updatedAt: old,
      lastActiveAt: old,
    });
    const res = await on.request("POST", "/auth/sign-in/anonymous", { body: {} });
    const encryptedId = ((await res.json()) as { user: { id: string } }).user.id;
    await on.admin.update(session).set({ updatedAt: old }).where(eq(session.userId, encryptedId));
    await on.admin.update(user).set({ lastActiveAt: old }).where(eq(user.id, encryptedId));

    expect(await cleanupInactiveGuests(on.db, NOW)).toBe(1);

    const left = await on.admin.select({ id: user.id, encryption: user.encryption }).from(user);
    expect(left).toEqual([{ id: encryptedId, encryption: "encrypted" }]);
  });
});

describe("batches", () => {
  test("1200 inactive guests are all deleted across 3 batches, a user with an email untouched", async () => {
    expect(GUEST_CLEANUP_BATCH).toBe(500);
    const old = daysAgo(90);
    const row = (i: number, guest: boolean) => ({
      id: `bulk-${String(i).padStart(4, "0")}`,
      name: `Bulk ${i}`,
      email: guest ? `bulk-${i}@guest.wambito.invalid` : "member-in-the-middle@wambito.test",
      isAnonymous: guest,
      createdAt: old,
      updatedAt: old,
    });
    // 1 200 guests with the member's row in the middle of the id order, all with no session.
    const rows = Array.from({ length: 1201 }, (_, i) => row(i, i !== 600));
    for (let i = 0; i < rows.length; i += 300) {
      await t.admin.insert(user).values(rows.slice(i, i + 300));
    }

    const transaction = vi.spyOn(t.db, "transaction");
    try {
      expect(await cleanupInactiveGuests(t.db, NOW)).toBe(1200);
      expect(transaction).toHaveBeenCalledTimes(3);
    } finally {
      transaction.mockRestore();
    }

    const left = await t.admin.select({ id: user.id }).from(user);
    expect(left).toEqual([{ id: "bulk-0600" }]);
  });

  test("a batch that finds the lock taken ends the run", async () => {
    const guests = await Promise.all([newGuest(), newGuest()]);
    for (const g of guests) await lastActive(g.userId, 100);
    await t.admin.transaction(async (tx) => {
      await tx.execute(sql`select pg_advisory_xact_lock(${GUEST_CLEANUP_LOCK})`);
      expect(await cleanupInactiveGuests(t.db, NOW)).toBe(0);
    });
    expect(await cleanupInactiveGuests(t.db, NOW)).toBe(2);
  });
});

describe("guest session lifetime", () => {
  const SESSION_DAYS = 60;
  const me = (headers: { authorization: string }) => t.request("GET", "/v1/me", { headers });

  test("a session lasts 60 days from its last use", async () => {
    const g = await newGuest();
    const [row] = await t.admin.select().from(session).where(eq(session.userId, g.userId));
    const days = ((row?.expiresAt.getTime() ?? 0) - Date.now()) / DAY;
    expect(days).toBeGreaterThan(SESSION_DAYS - 0.01);
    expect(days).toBeLessThanOrEqual(SESSION_DAYS);
  });

  test("a session used on day 59 is still valid, and slides forward", async () => {
    const g = await newGuest();
    // As a session last used 59 days ago looks: its expiry is a day away.
    await t.admin
      .update(session)
      .set({
        createdAt: new Date(Date.now() - 59 * DAY),
        updatedAt: new Date(Date.now() - 59 * DAY),
        expiresAt: new Date(Date.now() + 1 * DAY),
      })
      .where(eq(session.userId, g.userId));

    expect((await me(g.headers)).status).toBe(200);

    const [row] = await t.admin.select().from(session).where(eq(session.userId, g.userId));
    const days = ((row?.expiresAt.getTime() ?? 0) - Date.now()) / DAY;
    expect(days).toBeGreaterThan(SESSION_DAYS - 0.01);
  });

  /** A guest, and its session, last active 59 days ago: the session's expiry is a day away. */
  async function ageSession(userId: string) {
    const updatedAt = new Date(Date.now() - 59 * DAY);
    const expiresAt = new Date(Date.now() + 1 * DAY);
    await t.admin
      .update(session)
      .set({ createdAt: updatedAt, updatedAt, expiresAt })
      .where(eq(session.userId, userId));
    await t.admin.update(user).set({ lastActiveAt: updatedAt }).where(eq(user.id, userId));
    return { updatedAt, expiresAt };
  }

  test("a background request (x-wambito-background: 1) reads the session without sliding it", async () => {
    const g = await newGuest();
    const aged = await ageSession(g.userId);

    const res = await t.request("GET", "/v1/me", {
      headers: { ...g.headers, "x-wambito-background": "1" },
    });
    expect(res.status).toBe(200);

    const [row] = await t.admin.select().from(session).where(eq(session.userId, g.userId));
    expect(row?.updatedAt).toEqual(aged.updatedAt);
    expect(row?.expiresAt).toEqual(aged.expiresAt);
    // It sets no new cookie either: nothing about the session changes.
    expect(res.headers.get("set-cookie")).toBeNull();
  });

  test("only the value 1 marks a background request; a normal request still slides", async () => {
    const g = await newGuest();
    await ageSession(g.userId);
    // Not "1": an ordinary request.
    expect(
      (await t.request("GET", "/v1/me", { headers: { ...g.headers, "x-wambito-background": "0" } }))
        .status,
    ).toBe(200);
    const [row] = await t.admin.select().from(session).where(eq(session.userId, g.userId));
    expect(((row?.expiresAt.getTime() ?? 0) - Date.now()) / DAY).toBeGreaterThan(
      SESSION_DAYS - 0.01,
    );
    expect(Date.now() - (row?.updatedAt.getTime() ?? 0)).toBeLessThan(DAY);
  });

  test("a background request from a guest idle for 59 days does not postpone its deletion", async () => {
    const g = await newGuest();
    await ageSession(g.userId);
    for (let i = 0; i < 3; i++) {
      await t.request("GET", "/v1/me", { headers: { ...g.headers, "x-wambito-background": "1" } });
    }
    // Two days later the guest is past 60 days idle, as if the phone had only run background jobs.
    expect(await cleanupInactiveGuests(t.db, new Date(Date.now() + 2 * DAY))).toBe(1);
    expect(await exists(g.userId)).toBe(false);
  });

  test("the background header leaves expiry checks in place: an expired session is still a 401", async () => {
    const g = await newGuest();
    await t.admin
      .update(session)
      .set({
        createdAt: new Date(Date.now() - 61 * DAY),
        updatedAt: new Date(Date.now() - 61 * DAY),
        expiresAt: new Date(Date.now() - 1 * DAY),
      })
      .where(eq(session.userId, g.userId));

    const res = await t.request("GET", "/v1/me", {
      headers: { ...g.headers, "x-wambito-background": "1" },
    });
    expect(res.status).toBe(401);
  });

  test("a session idle for 61 days is no longer valid", async () => {
    const g = await newGuest();
    await t.admin
      .update(session)
      .set({
        createdAt: new Date(Date.now() - 61 * DAY),
        updatedAt: new Date(Date.now() - 61 * DAY),
        expiresAt: new Date(Date.now() - 1 * DAY),
      })
      .where(eq(session.userId, g.userId));

    expect((await me(g.headers)).status).toBe(401);
  });
});

describe("a guest's last activity outlives its sessions", () => {
  const signOut = (headers: { authorization: string }) =>
    t.request("POST", "/auth/sign-out", { headers, body: {} });
  const recent = (at: Date | null | undefined) =>
    expect(Date.now() - (at?.getTime() ?? 0)).toBeLessThan(60_000);

  /** The guest, and its session, last active `days` ago; the session expires `expiresIn` days on. */
  async function idle(userId: string, days: number, expiresIn: number) {
    const at = new Date(Date.now() - days * DAY);
    await t.admin
      .update(session)
      .set({ createdAt: at, updatedAt: at, expiresAt: new Date(Date.now() + expiresIn * DAY) })
      .where(eq(session.userId, userId));
    await t.admin.update(user).set({ lastActiveAt: at }).where(eq(user.id, userId));
    return at;
  }

  test("a new guest session stamps the user", async () => {
    const g = await newGuest();
    recent(await lastActiveAt(g.userId));
  });

  test("a guest who signs out is kept for 60 days from then (a passkey can bring them back)", async () => {
    const g = await newGuest();
    // An old account, used yesterday.
    await t.admin
      .update(user)
      .set({ createdAt: new Date(Date.now() - 70 * DAY) })
      .where(eq(user.id, g.userId));
    await idle(g.userId, 1, 59);
    expect((await signOut(g.headers)).status).toBe(200);
    expect(await t.admin.select().from(session).where(eq(session.userId, g.userId))).toHaveLength(
      0,
    );
    recent(await lastActiveAt(g.userId));

    expect(await cleanupInactiveGuests(t.db, new Date(Date.now() + 59 * DAY))).toBe(0);
    expect(await exists(g.userId)).toBe(true);
    expect(await cleanupInactiveGuests(t.db, new Date(Date.now() + 61 * DAY))).toBe(1);
    expect(await exists(g.userId)).toBe(false);
  });

  test("a refreshed guest session stamps the user", async () => {
    const g = await newGuest();
    await idle(g.userId, 59, 1);
    expect((await t.request("GET", "/v1/me", { headers: g.headers })).status).toBe(200);
    recent(await lastActiveAt(g.userId));
  });

  test("a background request never stamps the user", async () => {
    const g = await newGuest();
    const at = await idle(g.userId, 59, 1);
    const res = await t.request("GET", "/v1/me", {
      headers: { ...g.headers, "x-wambito-background": "1" },
    });
    expect(res.status).toBe(200);
    expect(await lastActiveAt(g.userId)).toEqual(at);
  });

  test("an expired session ended by a background request does not count as activity", async () => {
    const g = await newGuest();
    const at = await idle(g.userId, 61, -1);
    const res = await t.request("GET", "/v1/me", {
      headers: { ...g.headers, "x-wambito-background": "1" },
    });
    expect(res.status).toBe(401);
    expect(await lastActiveAt(g.userId)).toEqual(at);
    expect(await cleanupInactiveGuests(t.db, new Date())).toBe(1);
  });

  test("the cleanup reads the later of the stamp and the latest session", async () => {
    const stamped = await newGuest();
    await lastActive(stamped.userId, 90);
    await t.admin
      .update(user)
      .set({ lastActiveAt: daysAgo(5) })
      .where(eq(user.id, stamped.userId));
    const sessionOnly = await newGuest();
    await lastActive(sessionOnly.userId, 90);
    await t.admin
      .update(session)
      .set({ updatedAt: daysAgo(5) })
      .where(eq(session.userId, sessionOnly.userId));

    expect(await cleanupInactiveGuests(t.db, NOW)).toBe(0);
  });

  test("an email user is stamped too", async () => {
    const member = await t.signIn("stamp@wambito.test");
    recent(await lastActiveAt(member.userId));
  });
});

describe("scheduleGuestCleanup", () => {
  /** The three daily steps, as mocks that record the order they ran in. */
  function steps(counts: { plain: number; encrypted: number; ended: number }) {
    const order: string[] = [];
    const step = (name: keyof typeof counts) =>
      vi.fn(async () => {
        order.push(name);
        return counts[name];
      });
    return {
      order,
      cleanup: step("plain"),
      cleanupEncrypted: step("encrypted"),
      purgeEnded: step("ended"),
    };
  }

  test("runs at start and then once a day, and stops when asked", async () => {
    vi.useFakeTimers();
    try {
      const s = steps({ plain: 2, encrypted: 0, ended: 0 });
      const log = vi.fn();
      const stop = scheduleGuestCleanup({ db: t.db, ...s, log });
      await vi.advanceTimersByTimeAsync(0);
      expect(s.cleanup).toHaveBeenCalledTimes(1);
      expect(log).toHaveBeenCalledWith(expect.stringContaining("2"));

      await vi.advanceTimersByTimeAsync(DAY - 1);
      expect(s.cleanup).toHaveBeenCalledTimes(1);
      await vi.advanceTimersByTimeAsync(1);
      expect(s.cleanup).toHaveBeenCalledTimes(2);

      stop();
      await vi.advanceTimersByTimeAsync(3 * DAY);
      expect(s.cleanup).toHaveBeenCalledTimes(2);
    } finally {
      vi.useRealTimers();
    }
  });

  test("runs the plain cleanup, then the encrypted one, then purges ended sessions; one log line each", async () => {
    vi.useFakeTimers();
    try {
      const s = steps({ plain: 2, encrypted: 3, ended: 4 });
      const log = vi.fn();
      const stop = scheduleGuestCleanup({ db: t.db, ...s, log });
      await vi.advanceTimersByTimeAsync(0);
      stop();

      expect(s.order).toEqual(["plain", "encrypted", "ended"]);
      for (const fn of [s.cleanup, s.cleanupEncrypted, s.purgeEnded]) {
        expect(fn).toHaveBeenCalledWith(t.db, expect.any(Date));
      }
      expect(log.mock.calls.map(([m]) => m)).toEqual([
        expect.stringMatching(/deleted 2 .*60 days/),
        expect.stringMatching(/deleted 3 .*365 days.*730/),
        expect.stringMatching(/4 .*90 days/),
      ]);
    } finally {
      vi.useRealTimers();
    }
  });

  test("a failed run is logged and the next day's run still happens", async () => {
    vi.useFakeTimers();
    try {
      const cleanup = vi
        .fn<() => Promise<number>>()
        .mockRejectedValueOnce(new Error("db down"))
        .mockResolvedValue(0);
      const s = steps({ plain: 0, encrypted: 0, ended: 0 });
      const logError = vi.fn();
      const stop = scheduleGuestCleanup({ db: t.db, ...s, cleanup, logError });
      await vi.advanceTimersByTimeAsync(0);
      expect(logError).toHaveBeenCalledTimes(1);
      // One step failing does not skip the others.
      expect(s.cleanupEncrypted).toHaveBeenCalledTimes(1);
      expect(s.purgeEnded).toHaveBeenCalledTimes(1);

      await vi.advanceTimersByTimeAsync(DAY);
      expect(cleanup).toHaveBeenCalledTimes(2);
      stop();
    } finally {
      vi.useRealTimers();
    }
  });
});
