import { randomUUID } from "node:crypto";
import { newRecoverySecret, recoveryVerifier, verifierHash } from "@wambito/crypto";
import { endedSessions, session, user } from "@wambito/db";
import { desc, eq } from "@wambito/db/orm";
import { afterAll, afterEach, beforeAll, describe, expect, test } from "vitest";
import { cleanupInactiveEncrypted, cleanupInactiveGuests } from "../src/services/guest-cleanup.ts";
import { codeFrom, createTestApp, type TestApp } from "./harness.ts";

// The switch day (spec 2026-11-19 §1): `user.encryption` gains `migrating`, the state between
// `plain` and `encrypted` while the web moves an account's finances into records. `GET /v1/me`
// says whether the migration is open to the account (`migration`). Elsewhere a migrating account
// behaves as a plain one: session length, the cleanup tiers, the 401 codes and recovery sign-in.

type Auth = { userId: string; headers: { authorization: string } };
const PHONE = { "x-wambito-client": "android" };
const DAY = 24 * 60 * 60 * 1000;
const filled = (length: number, fill: number) => Buffer.alloc(length, fill).toString("base64url");
const b64 = (bytes: Uint8Array) => Buffer.from(bytes).toString("base64url");

let t: TestApp;
let people = 0;
beforeAll(async () => {
  t = await createTestApp();
});
afterAll(() => t?.stop());
afterEach(() => {
  t.config.MIGRATION_OPEN = false;
  t.config.MIGRATION_OPEN_USER_IDS = [];
  t.config.NEW_USERS_ENCRYPTED = false;
});

const nextEmail = () => `migration-${++people}@wambito.test`;

const setEncryption = (userId: string, encryption: string, extra: Record<string, unknown> = {}) =>
  t.admin
    .update(user)
    .set({ encryption, ...extra })
    .where(eq(user.id, userId));

async function me(headers: Record<string, string>) {
  const res = await t.request("GET", "/v1/me", { headers });
  expect(res.status).toBe(200);
  return (await res.json()) as { encryption: string; migration?: string };
}

async function guest(headers: Record<string, string> = {}): Promise<Auth> {
  const res = await t.request("POST", "/auth/sign-in/anonymous", { body: {}, headers });
  if (res.status !== 200) throw new Error(`guest failed: ${res.status} ${await res.text()}`);
  const json = (await res.json()) as { user: { id: string } };
  return {
    userId: json.user.id,
    headers: { authorization: `Bearer ${res.headers.get("set-auth-token")}` },
  };
}

/** The email-code sign-in with extra headers; returns the user id. */
async function emailSignIn(email: string, headers: Record<string, string>) {
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

const latestSession = async (userId: string) => {
  const [row] = await t.admin
    .select()
    .from(session)
    .where(eq(session.userId, userId))
    .orderBy(desc(session.createdAt))
    .limit(1);
  if (!row) throw new Error("no session");
  return row;
};

/** The session token a bearer carries: `set-auth-token` is `<token>.<signature>`, maybe URL-encoded. */
const tokenOf = (headers: { authorization: string }) =>
  decodeURIComponent(headers.authorization.slice(7)).split(".")[0] as string;

const sessionIdOf = async (headers: { authorization: string }) => {
  const [row] = await t.admin
    .select({ id: session.id })
    .from(session)
    .where(eq(session.token, tokenOf(headers)));
  if (!row) throw new Error("no session for that token");
  return row.id;
};

async function putWrap(headers: Record<string, string>, body: unknown, id = randomUUID()) {
  const res = await t.request("PUT", `/v2/keys/${id}`, { headers, body });
  expect(res.status, await res.clone().text()).toBe(200);
  return id;
}

const recoveryWrap = { kind: "recovery", ref: null, keyV: 1, wrapped: filled(48, 1) };

describe("GET /v1/me migration", () => {
  test("migration is absent for a plain user while MIGRATION_OPEN is off", async () => {
    const { headers } = await t.signIn(nextEmail());
    const profile = await me(headers);
    expect(profile.encryption).toBe("plain");
    expect(profile).not.toHaveProperty("migration");
  });

  test('migration is "available" for a plain user with an email when MIGRATION_OPEN is on, and for an id in MIGRATION_OPEN_USER_IDS', async () => {
    const open = await t.signIn(nextEmail());
    t.config.MIGRATION_OPEN = true;
    expect(await me(open.headers)).toMatchObject({ encryption: "plain", migration: "available" });

    t.config.MIGRATION_OPEN = false;
    const listed = await t.signIn(nextEmail());
    const other = await t.signIn(nextEmail());
    t.config.MIGRATION_OPEN_USER_IDS = [listed.userId];
    expect(await me(listed.headers)).toMatchObject({ migration: "available" });
    expect(await me(other.headers)).not.toHaveProperty("migration");
  });

  test('a guest never gets "available"', async () => {
    const g = await guest();
    t.config.MIGRATION_OPEN = true;
    t.config.MIGRATION_OPEN_USER_IDS = [g.userId];
    const profile = await me(g.headers);
    expect(profile.encryption).toBe("plain");
    expect(profile).not.toHaveProperty("migration");
  });

  test('a migrating user gets encryption "preview" and migration "in_progress"', async () => {
    const { userId, headers } = await t.signIn(nextEmail());
    await setEncryption(userId, "migrating");
    expect(await me(headers)).toMatchObject({ encryption: "preview", migration: "in_progress" });
  });

  test("an encrypted user gets no migration field", async () => {
    const { userId, headers } = await t.signIn(nextEmail());
    await setEncryption(userId, "encrypted");
    t.config.MIGRATION_OPEN = true;
    t.config.MIGRATION_OPEN_USER_IDS = [userId];
    const profile = await me(headers);
    expect(profile.encryption).toBe("preview");
    expect(profile).not.toHaveProperty("migration");
  });

  test("the database refuses an unknown encryption and stores a migration session id", async () => {
    const { userId, headers } = await t.signIn(nextEmail());
    await expect(setEncryption(userId, "halfway")).rejects.toThrow();
    const sessionId = await sessionIdOf(headers);
    await setEncryption(userId, "migrating", { migrationSessionId: sessionId });
    const [row] = await t.admin.select().from(user).where(eq(user.id, userId));
    expect(row).toMatchObject({ encryption: "migrating", migrationSessionId: sessionId });
  });
});

// Each place that reads `user.encryption` raw: `migrating` gets what `plain` gets.
describe("a migrating user keeps plain session length, cleanup and 401 codes", () => {
  test("session create hook: a migrating user without an email gets a standard phone session, not a long one", async () => {
    const email = nextEmail();
    const userId = await emailSignIn(email, PHONE);
    await t.admin.delete(session).where(eq(session.userId, userId));
    await setEncryption(userId, "migrating", { isAnonymous: true });
    await emailSignIn(email, PHONE);
    expect((await latestSession(userId)).lifetime).toBe("standard");

    // The same person encrypted gets the long one: the test tells the two apart.
    await setEncryption(userId, "encrypted", { isAnonymous: true });
    await emailSignIn(email, PHONE);
    expect((await latestSession(userId)).lifetime).toBe("long");
  });

  test("recovery sign-in: a migrating user without an email gets a standard phone session", async () => {
    const g = await guest(PHONE);
    await putWrap(g.headers, recoveryWrap);
    const v = await recoveryVerifier(newRecoverySecret());
    const put = await t.request("PUT", "/v2/recovery/verifier", {
      headers: g.headers,
      body: {
        lookupHash: b64(await verifierHash(v.lookup)),
        authHash: b64(await verifierHash(v.auth)),
      },
    });
    expect(put.status).toBe(204);
    await setEncryption(g.userId, "migrating");
    const res = await t.request("POST", "/v2/recovery/sign-in", {
      body: { lookup: b64(v.lookup), auth: b64(v.auth) },
      headers: PHONE,
    });
    expect(res.status).toBe(200);
    expect((await latestSession(g.userId)).lifetime).toBe("standard");
  });

  test("long session slide: a migrating user's long session is not slid", async () => {
    const g = await guest(PHONE);
    const sessionId = await sessionIdOf(g.headers);
    const expiresAt = new Date(Date.now() + 700 * DAY);
    await t.admin
      .update(session)
      .set({ lifetime: "long", expiresAt, updatedAt: new Date(Date.now() - 2 * DAY) })
      .where(eq(session.id, sessionId));
    await setEncryption(g.userId, "migrating");
    await me(g.headers);
    const [row] = await t.admin.select().from(session).where(eq(session.id, sessionId));
    expect(Math.abs((row?.expiresAt.getTime() ?? 0) - expiresAt.getTime())).toBeLessThan(1000);
  });

  test("plain guest cleanup: a migrating guest idle 61 days goes like a plain one", async () => {
    const g = await guest();
    await setEncryption(g.userId, "migrating", { lastActiveAt: new Date(Date.now() - 61 * DAY) });
    await t.admin
      .update(session)
      .set({ updatedAt: new Date(Date.now() - 61 * DAY) })
      .where(eq(session.userId, g.userId));
    await cleanupInactiveGuests(t.db, new Date());
    expect(await t.admin.select().from(user).where(eq(user.id, g.userId))).toHaveLength(0);
  });

  test("encrypted cleanup: a migrating guest is not in the encrypted tier", async () => {
    const g = await guest();
    await setEncryption(g.userId, "migrating", { lastActiveAt: new Date(Date.now() - 400 * DAY) });
    await t.admin
      .update(session)
      .set({ updatedAt: new Date(Date.now() - 400 * DAY) })
      .where(eq(session.userId, g.userId));
    await cleanupInactiveEncrypted(t.db, new Date());
    // The plain tier would have taken it; here only the encrypted tier ran.
    expect(await t.admin.select().from(user).where(eq(user.id, g.userId))).toHaveLength(1);
  });

  test("401 codes: a migrating account's removed device stays unauthenticated", async () => {
    const email = nextEmail();
    const a = await t.signIn(email);
    const b = await t.signIn(email);
    await putWrap(a.headers, recoveryWrap);
    const device = (fill: number) => ({
      kind: "device",
      ref: randomUUID(),
      keyV: 1,
      wrapped: filled(80, fill),
      publicKey: filled(32, 9),
      attestation: filled(32, 5),
      label: "Pixel 9",
    });
    const wrap = await putWrap(b.headers, device(2));
    await putWrap(a.headers, device(3));
    await setEncryption(a.userId, "migrating", {
      migrationSessionId: await sessionIdOf(a.headers),
    });
    const removed = await t.request("DELETE", `/v2/keys/${wrap}`, { headers: a.headers });
    expect(removed.status).toBe(204);
    const res = await t.request("GET", "/v2/keys", { headers: b.headers });
    expect(res.status).toBe(401);
    expect(((await res.json()) as { code: string }).code).toBe("unauthenticated");
    expect(await t.admin.select().from(endedSessions)).toEqual([]);
  });
});
