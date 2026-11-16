import { randomUUID } from "node:crypto";
import { deletedUsers, endedSessions, session, user } from "@wambito/db";
import { eq, sql } from "@wambito/db/orm";
import { afterAll, beforeAll, beforeEach, describe, expect, test } from "vitest";
import { purgeEndedSessions, sha256 } from "../src/services/ended.ts";
import { cleanupInactiveEncrypted } from "../src/services/guest-cleanup.ts";
import { createTestApp, type TestApp } from "./harness.ts";

// Telling the 401s apart (spec 2026-11-15 §10): a removed device hears `device_removed`, the phone
// of a user the cleanup deleted hears `user_deleted`, and everything else stays `unauthenticated`.

type Headers = Record<string, string>;
const PHONE = { "x-wambito-client": "android" };
const DAY = 24 * 60 * 60 * 1000;
const bytes = (length: number, fill = 7) => Buffer.alloc(length, fill).toString("base64url");

let t: TestApp;
let people = 0;
beforeAll(async () => {
  t = await createTestApp({ NEW_USERS_ENCRYPTED: true });
});
afterAll(() => t?.stop());
beforeEach(async () => {
  await t.admin.delete(endedSessions);
  await t.admin.delete(deletedUsers);
});

const recovery = (keyV = 1) => ({ kind: "recovery", ref: null, keyV, wrapped: bytes(48) });
const device = (keyV = 1, ref: string = randomUUID()) => ({
  kind: "device",
  ref,
  keyV,
  wrapped: bytes(80),
  publicKey: bytes(32, 9),
  attestation: bytes(32, 5),
  label: "Pixel 9",
});

async function put(headers: Headers, body: unknown, id = randomUUID()): Promise<string> {
  const res = await t.request("PUT", `/v2/keys/${id}`, { headers, body });
  expect(res.status, await res.clone().text()).toBe(200);
  return id;
}

/** The status and problem code of `GET /v2/keys` with these headers. */
async function answer(headers: Headers): Promise<{ status: number; code?: string }> {
  const res = await t.request("GET", "/v2/keys", { headers });
  if (res.status === 200) return { status: 200 };
  return { status: res.status, code: ((await res.json()) as { code: string }).code };
}

/** One person with a recovery wrap, signed in twice from the phone (bearer tokens A and B). */
async function twoDevices() {
  const email = `unauth-${++people}@wambito.test`;
  const a = await t.signIn(email);
  const b = await t.signIn(email);
  await put(a.headers, recovery(1));
  return { email, userId: a.userId, a: a.headers, b: b.headers };
}

/** The session token a bearer carries: `set-auth-token` is `<token>.<signature>`, maybe URL-encoded. */
const tokenOf = (headers: { authorization: string }) =>
  decodeURIComponent(headers.authorization.slice(7)).split(".")[0] as string;
const endedRows = async () =>
  (await t.admin.select({ hash: endedSessions.sessionHash }).from(endedSessions)).map((r) =>
    Buffer.from(r.hash).toString("hex"),
  );

describe("device_removed", () => {
  test("a removed device's bearer gets 401 device_removed", async () => {
    const { a, b } = await twoDevices();
    const wrap = await put(b, device(1));
    await put(a, device(1));
    expect((await t.request("DELETE", `/v2/keys/${wrap}`, { headers: a })).status).toBe(204);
    expect(await answer(b)).toEqual({ status: 401, code: "device_removed" });
    expect(await answer(a)).toEqual({ status: 200 });
  });

  test("a device left out of a rotation gets 401 device_removed", async () => {
    const { a, b } = await twoDevices();
    const keptRef = randomUUID();
    await put(a, device(1, keptRef));
    await put(b, device(1));
    const res = await t.request("POST", "/v2/keys/rotate", {
      headers: a,
      body: {
        keyV: 2,
        wraps: [
          { id: randomUUID(), ...recovery(2) },
          { id: randomUUID(), ...device(2, keptRef) },
        ],
        link: bytes(60, 3),
      },
    });
    expect(res.status, await res.clone().text()).toBe(200);
    expect(await answer(b)).toEqual({ status: 401, code: "device_removed" });
    expect(await answer(a)).toEqual({ status: 200 });
  });

  test("a removed browser's cookie gets 401 device_removed", async () => {
    const { email, a } = await twoDevices();
    const browser = await t.signInCookie(email);
    // The cookie is `<token>.<signature>`, URL-encoded: only the token's hash is recorded.
    expect(decodeURIComponent(browser.headers.cookie)).toMatch(/=[^.;]+\.[^;]+/);
    const wrap = await put(browser.headers, device(1));
    expect((await t.request("DELETE", `/v2/keys/${wrap}`, { headers: a })).status).toBe(204);
    expect(await answer(browser.headers)).toEqual({ status: 401, code: "device_removed" });
  });

  test("the caller's own session is never recorded as ended", async () => {
    const { a, b } = await twoDevices();
    const own = await put(a, device(1));
    const other = await put(b, device(1));
    expect((await t.request("DELETE", `/v2/keys/${own}`, { headers: a })).status).toBe(204);
    expect((await t.request("DELETE", `/v2/keys/${other}`, { headers: a })).status).toBe(204);
    expect(await answer(a)).toEqual({ status: 200 });
    expect(await endedRows()).toEqual([sha256(tokenOf(b)).toString("hex")]);
  });

  test("an ended_sessions row older than 90 days, once purged, answers unauthenticated", async () => {
    const { a, b } = await twoDevices();
    const wrap = await put(b, device(1));
    expect((await t.request("DELETE", `/v2/keys/${wrap}`, { headers: a })).status).toBe(204);
    expect(await answer(b)).toEqual({ status: 401, code: "device_removed" });
    await t.admin.update(endedSessions).set({ endedAt: new Date(Date.now() - 91 * DAY) });
    expect(await purgeEndedSessions(t.db, new Date())).toBe(1);
    expect(await answer(b)).toEqual({ status: 401, code: "unauthenticated" });
  });

  test("a plain account's removed device stays unauthenticated (the codes are for encrypted users)", async () => {
    const { userId, a, b } = await twoDevices();
    await t.admin.update(user).set({ encryption: "plain" }).where(eq(user.id, userId));
    const wrap = await put(b, device(1));
    expect((await t.request("DELETE", `/v2/keys/${wrap}`, { headers: a })).status).toBe(204);
    expect(await answer(b)).toEqual({ status: 401, code: "unauthenticated" });
    expect(await endedRows()).toEqual([]);
  });
});

describe("user_deleted", () => {
  /** An encrypted guest from the phone, idle long enough for the cleanup to delete it. */
  async function deletedGuest() {
    const res = await t.request("POST", "/auth/sign-in/anonymous", { body: {}, headers: PHONE });
    expect(res.status).toBe(200);
    const { user: made } = (await res.json()) as { user: { id: string } };
    const headers = { authorization: `Bearer ${res.headers.get("set-auth-token")}` };
    await put(headers, recovery(1));
    const idle = new Date(Date.now() - 400 * DAY);
    await t.admin.update(session).set({ updatedAt: idle }).where(eq(session.userId, made.id));
    await t.admin.update(user).set({ lastActiveAt: idle }).where(eq(user.id, made.id));
    expect(await cleanupInactiveEncrypted(t.db, new Date())).toBeGreaterThanOrEqual(1);
    return { userId: made.id, headers };
  }

  test("after the cleanup deleted the user, a request with x-wambito-user gets 401 user_deleted", async () => {
    const { userId, headers } = await deletedGuest();
    expect(await answer({ ...headers, "x-wambito-user": userId })).toEqual({
      status: 401,
      code: "user_deleted",
    });
  });

  test("without x-wambito-user it is 401 unauthenticated", async () => {
    const { headers } = await deletedGuest();
    expect(await answer(headers)).toEqual({ status: 401, code: "unauthenticated" });
  });

  test("a live user's id in x-wambito-user with an unknown token is 401 unauthenticated", async () => {
    const { userId } = await twoDevices();
    expect(
      await answer({ authorization: `Bearer ${randomUUID()}`, "x-wambito-user": userId }),
    ).toEqual({ status: 401, code: "unauthenticated" });
  });
});

describe("unauthenticated", () => {
  test("a signed-out or unknown token is 401 unauthenticated", async () => {
    const { a, b } = await twoDevices();
    expect((await t.request("POST", "/auth/sign-out", { headers: b, body: {} })).status).toBe(200);
    expect(await answer(b)).toEqual({ status: 401, code: "unauthenticated" });
    expect(await answer({ authorization: `Bearer ${randomUUID()}` })).toEqual({
      status: 401,
      code: "unauthenticated",
    });
    expect(await answer({})).toEqual({ status: 401, code: "unauthenticated" });
    expect(await answer(a)).toEqual({ status: 200 });
  });

  test("a JWT bearer is never looked up as a session token", async () => {
    const { a, b } = await twoDevices();
    const wrap = await put(b, device(1));
    expect((await t.request("DELETE", `/v2/keys/${wrap}`, { headers: a })).status).toBe(204);
    // An ended token dressed as a JWT (three dot-separated parts) is not a session token.
    const jwtLike = `${tokenOf(b)}.e30.sig`;
    expect(await answer({ authorization: `Bearer ${jwtLike}` })).toEqual({
      status: 401,
      code: "unauthenticated",
    });
    expect(await t.admin.execute(sql`select 1 from ended_sessions`)).toHaveLength(1);
  });
});
