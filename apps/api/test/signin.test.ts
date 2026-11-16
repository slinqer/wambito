import { randomUUID } from "node:crypto";
import {
  fromBase64Url,
  generateDataKey,
  generateDeviceKeyPair,
  openFromPairing,
  pairingCommitment,
  sealToDevice,
  toBase64Url,
} from "@wambito/crypto";
import { session, signinRequests, user } from "@wambito/db";
import { eq, sql } from "@wambito/db/orm";
import { afterAll, beforeAll, describe, expect, test, vi } from "vitest";
import { purgeExpiredSignins, SIGNIN_OPEN_LIMIT } from "../src/services/signin.ts";
import { scheduleTombstonePurge } from "../src/services/sync.ts";
import { createTestApp, type TestApp } from "./harness.ts";

// The web sign-in through the phone (spec 2026-11-15 §8): the web opens a request with a
// commitment to its key and a poll secret only it holds, the phone approves it with its session,
// the web reveals its key, the phone seals the data key to it, and the web picks up the sealed key
// and a Better Auth session for the phone's user. Every row lives 2 minutes.

type Phone = { userId: string; headers: { authorization: string } };
interface Started {
  id: string;
  code: string;
  pollSecret: string;
  expiresAt: string;
}

const PHONE = { "x-wambito-client": "android" };
const HOUR = 60 * 60 * 1000;
const TWELVE_HOURS = 12 * HOUR;

let clock = new Date("2026-11-16T12:00:00Z");
let t: TestApp;
let people = 0;
let ips = 0;
beforeAll(async () => {
  t = await createTestApp({ NEW_USERS_ENCRYPTED: true }, { now: () => clock });
});
afterAll(() => t?.stop());

const filled = (length: number, fill = 7) => Buffer.alloc(length, fill).toString("base64url");
/** One client address per test that counts them, behind the trusted proxy. */
const newIp = () => `203.0.113.${++ips}, 10.0.0.1`;

/** An encrypted guest made on the phone, with a recovery wrap at `keyV`. */
async function phone(keyV = 1): Promise<Phone> {
  const res = await t.request("POST", "/auth/sign-in/anonymous", { body: {}, headers: PHONE });
  if (res.status !== 200) throw new Error(`guest failed: ${res.status} ${await res.text()}`);
  const json = (await res.json()) as { user: { id: string } };
  const p = {
    userId: json.user.id,
    headers: { authorization: `Bearer ${res.headers.get("set-auth-token")}` },
  };
  const wrap = await t.request("PUT", `/v2/keys/${randomUUID()}`, {
    headers: p.headers,
    body: { kind: "recovery", ref: null, keyV, wrapped: filled(48, ++people % 200) },
  });
  expect(wrap.status, await wrap.clone().text()).toBe(200);
  return p;
}

const commitmentOf = async (publicKey: Uint8Array) =>
  toBase64Url(await pairingCommitment(publicKey));

const openRaw = (body: unknown, headers: Record<string, string> = {}) =>
  t.request("POST", "/v2/signin", { body, headers });

/** The web opens a request: its key pair and the answer. */
async function open(
  { remember = true, label = "Firefox on Mac" }: { remember?: boolean; label?: string } = {},
  headers: Record<string, string> = {},
) {
  const web = await generateDeviceKeyPair();
  const res = await openRaw(
    { commitment: await commitmentOf(web.publicKey), remember, label },
    headers,
  );
  expect(res.status, await res.clone().text()).toBe(201);
  return { web, started: (await res.json()) as Started };
}

const poll = (secret: string | undefined) =>
  secret === undefined ? {} : ({ "x-wambito-poll": secret } as Record<string, string>);
const find = (p: Phone, code: string) =>
  t.request("GET", `/v2/signin?code=${encodeURIComponent(code)}`, { headers: p.headers });
const view = (p: Phone, id: string) => t.request("GET", `/v2/signin/${id}`, { headers: p.headers });
const pollState = (id: string, secret: string | undefined) =>
  t.request("GET", `/v2/signin/${id}`, { headers: poll(secret) });
const approve = (p: Phone, id: string, publicKey: string) =>
  t.request("POST", `/v2/signin/${id}/approver`, { headers: p.headers, body: { publicKey } });
const reveal = (id: string, secret: string | undefined, publicKey: string) =>
  t.request("POST", `/v2/signin/${id}/reveal`, { headers: poll(secret), body: { publicKey } });
const seal = (p: Phone, id: string, sealed: string, keyV = 1) =>
  t.request("POST", `/v2/signin/${id}/seal`, { headers: p.headers, body: { sealed, keyV } });
const pickup = (id: string, secret: string | undefined) =>
  t.request("POST", `/v2/signin/${id}/pickup`, { headers: poll(secret) });

async function expectProblem(res: Response, status: number, code: string) {
  expect(res.status, await res.clone().text()).toBe(status);
  expect(((await res.json()) as { code: string }).code).toBe(code);
}

/** Runs the flow up to a sealed request; the phone seals a fresh data key at `keyV`. */
async function sealed(p: Phone, opts: { remember?: boolean } = {}, keyV = 1) {
  const { web, started } = await open(opts);
  const eph = await generateDeviceKeyPair();
  expect((await approve(p, started.id, toBase64Url(eph.publicKey))).status).toBe(204);
  expect((await reveal(started.id, started.pollSecret, toBase64Url(web.publicKey))).status).toBe(
    204,
  );
  const ctx = { kind: "device" as const, userId: p.userId, keyV };
  const dataKey = generateDataKey();
  const blob = await sealToDevice(web.publicKey, ctx, dataKey, eph);
  expect((await seal(p, started.id, toBase64Url(blob), keyV)).status).toBe(204);
  return { web, eph, started, ctx, dataKey, blob: toBase64Url(blob) };
}

/** The `name=value` pairs of a response's cookies, as a browser sends them back. */
const cookieOf = (res: Response) =>
  res.headers
    .getSetCookie()
    .map((c) => c.split(";")[0])
    .join("; ");
const sessionCookieLine = (res: Response) =>
  res.headers.getSetCookie().find((c) => c.includes("session_token="));

const sessionsOf = (userId: string) =>
  t.admin.select().from(session).where(eq(session.userId, userId));
const sessionByToken = async (token: string) => {
  const [row] = await t.admin
    .select()
    .from(session)
    .where(eq(session.token, token.split(".")[0] ?? ""));
  if (!row) throw new Error("no session for the token");
  return row;
};

/** Runs `body` with the pinned clock moved by `ms`. */
async function later<T>(ms: number, body: () => Promise<T>): Promise<T> {
  const real = clock;
  clock = new Date(real.getTime() + ms);
  try {
    return await body();
  } finally {
    clock = real;
  }
}

describe("/v2/signin", () => {
  test("the happy path: open, find by code, approve, poll sees the approver key, reveal, seal, pickup returns { sealed, keyV, userId } of the phone's user and a cookie that opens GET /v1/me as that user", async () => {
    const p = await phone(3);
    const { web, started } = await open();
    expect(started.code).toMatch(/^[0-9A-HJKMNP-TV-Z]{8}$/);
    expect(Date.parse(started.expiresAt)).toBe(clock.getTime() + 2 * 60_000);
    expect(fromBase64Url(started.pollSecret)).toHaveLength(32);

    const typed = `${started.code.slice(0, 4)}-${started.code.slice(4)}`.toLowerCase();
    const found = await find(p, typed);
    expect(found.status, await found.clone().text()).toBe(200);
    const commitment = await commitmentOf(web.publicKey);
    expect(await found.json()).toEqual({
      id: started.id,
      commitment,
      label: "Firefox on Mac",
      expiresAt: started.expiresAt,
    });
    const viewed = await view(p, started.id);
    expect(await viewed.json()).toEqual({
      id: started.id,
      commitment,
      label: "Firefox on Mac",
      expiresAt: started.expiresAt,
      publicKey: null,
    });

    const before = await pollState(started.id, started.pollSecret);
    expect(await before.json()).toEqual({
      approverKey: null,
      ready: false,
      expiresAt: started.expiresAt,
    });

    const eph = await generateDeviceKeyPair();
    expect((await approve(p, started.id, toBase64Url(eph.publicKey))).status).toBe(204);
    const polled = await pollState(started.id, started.pollSecret);
    expect(await polled.json()).toEqual({
      approverKey: toBase64Url(eph.publicKey),
      ready: false,
      expiresAt: started.expiresAt,
    });

    expect((await reveal(started.id, started.pollSecret, toBase64Url(web.publicKey))).status).toBe(
      204,
    );
    expect(((await (await view(p, started.id)).json()) as { publicKey: string }).publicKey).toBe(
      toBase64Url(web.publicKey),
    );

    const ctx = { kind: "device" as const, userId: p.userId, keyV: 3 };
    const dataKey = generateDataKey();
    const blob = await sealToDevice(web.publicKey, ctx, dataKey, eph);
    expect((await seal(p, started.id, toBase64Url(blob), 3)).status).toBe(204);
    expect(
      ((await (await pollState(started.id, started.pollSecret)).json()) as { ready: boolean })
        .ready,
    ).toBe(true);

    const taken = await pickup(started.id, started.pollSecret);
    expect(taken.status, await taken.clone().text()).toBe(200);
    const picked = (await taken.json()) as { sealed: string; keyV: number; userId: string };
    expect(picked).toEqual({ sealed: toBase64Url(blob), keyV: 3, userId: p.userId });
    expect(
      await openFromPairing(web.privateKey, ctx, fromBase64Url(picked.sealed), eph.publicKey),
    ).toEqual(dataKey);

    const me = await t.request("GET", "/v1/me", { headers: { cookie: cookieOf(taken) } });
    expect(me.status).toBe(200);
    expect(((await me.json()) as { id: string }).id).toBe(p.userId);
  });

  test("the row is gone after pickup: a second pickup is 404", async () => {
    const p = await phone();
    const { started } = await sealed(p);
    expect((await pickup(started.id, started.pollSecret)).status).toBe(200);
    await expectProblem(await pickup(started.id, started.pollSecret), 404, "not_found");
    const left = await t.admin
      .select()
      .from(signinRequests)
      .where(eq(signinRequests.id, started.id));
    expect(left).toHaveLength(0);
  });

  test("poll, reveal and pickup without x-wambito-poll, or with a wrong one, are 404", async () => {
    const p = await phone();
    const { started, web } = await sealed(p);
    const wrong = filled(32, 9);
    for (const secret of [undefined, wrong, "not base64url!"]) {
      // Without the header, GET /v2/signin/{id} is the phone's view and needs a session.
      if (secret !== undefined)
        await expectProblem(await pollState(started.id, secret), 404, "not_found");
      await expectProblem(
        await reveal(started.id, secret, toBase64Url(web.publicKey)),
        404,
        "not_found",
      );
      await expectProblem(await pickup(started.id, secret), 404, "not_found");
    }
    // No header and no session: the view needs a session.
    await expectProblem(await pollState(started.id, undefined), 401, "unauthenticated");
    expect((await pickup(started.id, started.pollSecret)).status).toBe(200);
  });

  test("the poll secret is stored hashed: no column of the row equals its bytes", async () => {
    const { started } = await open();
    const [row] = await t.admin
      .select()
      .from(signinRequests)
      .where(eq(signinRequests.id, started.id));
    expect(row).toBeDefined();
    const secret = Buffer.from(started.pollSecret, "base64url");
    for (const value of Object.values(row ?? {})) {
      if (value instanceof Uint8Array) expect(Buffer.from(value).equals(secret)).toBe(false);
      else expect(String(value)).not.toContain(started.pollSecret);
    }
    expect(row?.pollHash).toHaveLength(32);
  });

  test("a request expires at 2 minutes: at 1:59 it is found, at 2:00 every route is 404", async () => {
    const p = await phone();
    const { started, web } = await open();
    await later(119_000, async () => {
      expect((await find(p, started.code)).status).toBe(200);
      expect((await pollState(started.id, started.pollSecret)).status).toBe(200);
    });
    await later(120_000, async () => {
      const key = toBase64Url(web.publicKey);
      await expectProblem(await find(p, started.code), 404, "not_found");
      await expectProblem(await view(p, started.id), 404, "not_found");
      await expectProblem(await pollState(started.id, started.pollSecret), 404, "not_found");
      await expectProblem(await approve(p, started.id, filled(32)), 404, "not_found");
      await expectProblem(await reveal(started.id, started.pollSecret, key), 404, "not_found");
      await expectProblem(await seal(p, started.id, filled(80)), 404, "not_found");
      await expectProblem(await pickup(started.id, started.pollSecret), 404, "not_found");
    });
  });

  test("approver bound once: a second approver call, from the same or another user, is 409 already_set", async () => {
    const p = await phone();
    const other = await phone();
    const { started } = await open();
    expect((await approve(p, started.id, filled(32, 1))).status).toBe(204);
    await expectProblem(await approve(p, started.id, filled(32, 2)), 409, "already_set");
    await expectProblem(await approve(other, started.id, filled(32, 3)), 409, "already_set");
    const [row] = await t.admin
      .select()
      .from(signinRequests)
      .where(eq(signinRequests.id, started.id));
    expect(row?.userId).toBe(p.userId);
    expect(Buffer.from(row?.approverKey ?? []).toString("base64url")).toBe(filled(32, 1));
  });

  test("after approval, GET /v2/signin/{id} and seal from another user are 404", async () => {
    const p = await phone();
    const other = await phone();
    const { started, web } = await open();
    // Before approval, any phone that scanned the QR may look.
    expect((await view(other, started.id)).status).toBe(200);
    const eph = await generateDeviceKeyPair();
    expect((await approve(p, started.id, toBase64Url(eph.publicKey))).status).toBe(204);
    expect((await reveal(started.id, started.pollSecret, toBase64Url(web.publicKey))).status).toBe(
      204,
    );
    await expectProblem(await view(other, started.id), 404, "not_found");
    const blob = toBase64Url(Buffer.concat([eph.publicKey, Buffer.alloc(48, 5)]));
    await expectProblem(await seal(other, started.id, blob), 404, "not_found");
    expect((await view(p, started.id)).status).toBe(200);
    expect((await seal(p, started.id, blob)).status).toBe(204);
  });

  test("find by code is 404 once an approver is set", async () => {
    const p = await phone();
    const { started } = await open();
    expect((await find(p, started.code)).status).toBe(200);
    expect((await approve(p, started.id, filled(32))).status).toBe(204);
    await expectProblem(await find(p, started.code), 404, "not_found");
  });

  test("out of order: reveal before approver 409 not_ready; seal before reveal 409 not_ready; pickup before seal 409 not_ready; reveal with a key that misses the commitment 422 commitment_mismatch; seal not starting with the approver key 422 approver_mismatch; seal at the wrong keyV 409 key_version_mismatch", async () => {
    const p = await phone(2);
    const { started, web } = await open();
    const webKey = toBase64Url(web.publicKey);
    await expectProblem(await reveal(started.id, started.pollSecret, webKey), 409, "not_ready");

    const eph = await generateDeviceKeyPair();
    expect((await approve(p, started.id, toBase64Url(eph.publicKey))).status).toBe(204);
    const blob = toBase64Url(Buffer.concat([eph.publicKey, Buffer.alloc(48, 5)]));
    await expectProblem(await seal(p, started.id, blob, 2), 409, "not_ready");
    await expectProblem(await pickup(started.id, started.pollSecret), 409, "not_ready");

    const stranger = toBase64Url((await generateDeviceKeyPair()).publicKey);
    await expectProblem(
      await reveal(started.id, started.pollSecret, stranger),
      422,
      "commitment_mismatch",
    );
    expect((await reveal(started.id, started.pollSecret, webKey)).status).toBe(204);
    await expectProblem(await reveal(started.id, started.pollSecret, webKey), 409, "already_set");
    await expectProblem(await pickup(started.id, started.pollSecret), 409, "not_ready");

    await expectProblem(await seal(p, started.id, filled(80), 2), 422, "approver_mismatch");
    await expectProblem(await seal(p, started.id, blob, 1), 409, "key_version_mismatch");
    expect((await seal(p, started.id, blob, 2)).status).toBe(204);
    await expectProblem(await seal(p, started.id, blob, 2), 409, "already_sealed");
  });

  test("assistant tokens get 403 on every /v2/signin route", async () => {
    const email = `signin-assistant-${++people}@wambito.test`;
    const signedIn = await t.signIn(email);
    const { started, web } = await open();
    const token = await t.authorize(email, { headers: signedIn.headers });
    const h = { authorization: `Bearer ${token.accessToken}` };
    const key = toBase64Url(web.publicKey);
    for (const res of [
      await t.request("POST", "/v2/signin", {
        headers: h,
        body: { commitment: await commitmentOf(web.publicKey), remember: true, label: "x" },
      }),
      await t.request("GET", `/v2/signin?code=${started.code}`, { headers: h }),
      await t.request("GET", `/v2/signin/${started.id}`, { headers: h }),
      await t.request("POST", `/v2/signin/${started.id}/approver`, {
        headers: h,
        body: { publicKey: key },
      }),
      await t.request("POST", `/v2/signin/${started.id}/reveal`, {
        headers: { ...h, ...poll(started.pollSecret) },
        body: { publicKey: key },
      }),
      await t.request("POST", `/v2/signin/${started.id}/seal`, {
        headers: h,
        body: { sealed: filled(80), keyV: 1 },
      }),
      await t.request("POST", `/v2/signin/${started.id}/pickup`, {
        headers: { ...h, ...poll(started.pollSecret) },
      }),
    ]) {
      await expectProblem(res, 403, "insufficient_scope");
    }
    // Nothing was bound or revealed.
    const [row] = await t.admin
      .select()
      .from(signinRequests)
      .where(eq(signinRequests.id, started.id));
    expect(row?.approverKey).toBeNull();
    expect(row?.publicKey).toBeNull();
  });

  test("the 6th open request from one IP is 429 too_many_signins; one expiring frees a slot", async () => {
    const ip = { "x-forwarded-for": newIp() };
    await open({}, ip);
    await later(60_000, async () => {
      for (let i = 0; i < 4; i++) await open({}, ip);
      const web = await generateDeviceKeyPair();
      const body = { commitment: await commitmentOf(web.publicKey), remember: true, label: "x" };
      await expectProblem(await openRaw(body, ip), 429, "too_many_signins");
      // Another address is not held up.
      await open({}, { "x-forwarded-for": newIp() });
    });
    await later(120_000, async () => {
      await open({}, ip);
      const web = await generateDeviceKeyPair();
      const body = { commitment: await commitmentOf(web.publicKey), remember: true, label: "x" };
      await expectProblem(await openRaw(body, ip), 429, "too_many_signins");
    });
  });

  test("a picked-up request frees its slot", async () => {
    const ip = { "x-forwarded-for": newIp() };
    const p = await phone();
    const first = await open({}, ip);
    for (let i = 0; i < 4; i++) await open({}, ip);
    const eph = await generateDeviceKeyPair();
    const { started, web } = first;
    expect((await approve(p, started.id, toBase64Url(eph.publicKey))).status).toBe(204);
    expect((await reveal(started.id, started.pollSecret, toBase64Url(web.publicKey))).status).toBe(
      204,
    );
    const blob = toBase64Url(Buffer.concat([eph.publicKey, Buffer.alloc(48, 5)]));
    expect((await seal(p, started.id, blob)).status).toBe(204);
    expect((await pickup(started.id, started.pollSecret)).status).toBe(200);
    await open({}, ip);
  });

  test("the 31st open in 10 minutes from one IP is 429 too_many_requests", async () => {
    expect(SIGNIN_OPEN_LIMIT).toEqual({ max: 30, windowMs: 10 * 60 * 1000 });
    const ip = { "x-forwarded-for": newIp() };
    // Five at a time, each batch expired (pinned clock) before the next: only the window counts.
    for (let batch = 0; batch < 6; batch++) {
      await later(batch * 2 * 60_000, async () => {
        for (let i = 0; i < 5; i++) await open({}, ip);
      });
    }
    await later(6 * 2 * 60_000, async () => {
      const web = await generateDeviceKeyPair();
      const body = { commitment: await commitmentOf(web.publicKey), remember: true, label: "x" };
      const res = await openRaw(body, ip);
      await expectProblem(res, 429, "too_many_requests");
    });
  });

  test("validates the open request", async () => {
    const web = await generateDeviceKeyPair();
    const commitment = await commitmentOf(web.publicKey);
    const invalid = async (body: unknown) =>
      expectProblem(await openRaw(body), 422, "validation_failed");
    await invalid({ commitment, remember: true });
    await invalid({ commitment, remember: true, label: "" });
    await invalid({ commitment, remember: true, label: "x".repeat(65) });
    await invalid({ commitment, label: "x" });
    await invalid({ commitment: filled(31), remember: true, label: "x" });
    expect((await openRaw({ commitment, remember: false, label: "x".repeat(64) })).status).toBe(
      201,
    );
  });

  test("ticked: the cookie has Max-Age 5184000 and the session lifetime standard; unticked: no Max-Age, a dont_remember cookie, lifetime short, expires_at = now + 12 h", async () => {
    const p = await phone();
    const ticked = await sealed(p, { remember: true });
    const tickedRes = await pickup(ticked.started.id, ticked.started.pollSecret);
    expect(tickedRes.status).toBe(200);
    expect(sessionCookieLine(tickedRes)).toMatch(/Max-Age=5184000/i);
    const tickedToken = tickedRes.headers.get("set-auth-token") ?? "";
    expect((await sessionByToken(tickedToken)).lifetime).toBe("standard");

    const unticked = await sealed(p, { remember: false });
    const before = Date.now();
    const untickedRes = await pickup(unticked.started.id, unticked.started.pollSecret);
    const after = Date.now();
    expect(untickedRes.status).toBe(200);
    expect(sessionCookieLine(untickedRes)).toBeDefined();
    for (const line of untickedRes.headers.getSetCookie()) expect(line).not.toMatch(/Max-Age/i);
    expect(untickedRes.headers.getSetCookie().some((c) => c.includes("dont_remember="))).toBe(true);
    const row = await sessionByToken(untickedRes.headers.get("set-auth-token") ?? "");
    expect(row.lifetime).toBe("short");
    expect(row.expiresAt.getTime()).toBeGreaterThanOrEqual(before + TWELVE_HOURS - 1000);
    expect(row.expiresAt.getTime()).toBeLessThanOrEqual(after + TWELVE_HOURS + 1000);
  });

  test("a ticked pickup sent with a stale dont_remember cookie expires it", async () => {
    const p = await phone();
    const unticked = await sealed(p, { remember: false });
    const first = await pickup(unticked.started.id, unticked.started.pollSecret);
    expect(first.status).toBe(200);
    const stale = cookieOf(first)
      .split("; ")
      .filter((c) => c.includes("dont_remember="))
      .join("; ");
    expect(stale).not.toBe("");

    const ticked = await sealed(p, { remember: true });
    const res = await t.request("POST", `/v2/signin/${ticked.started.id}/pickup`, {
      headers: { ...poll(ticked.started.pollSecret), cookie: stale },
    });
    expect(res.status, await res.clone().text()).toBe(200);
    expect(sessionCookieLine(res)).toMatch(/Max-Age=5184000/i);
    const dontRemember = res.headers.getSetCookie().filter((c) => c.includes("dont_remember="));
    expect(dontRemember).toHaveLength(1);
    expect(dontRemember[0]).toMatch(/dont_remember=;/);
    expect(dontRemember[0]).toMatch(/Max-Age=0/i);
  });

  for (const client of ["android", "ios"]) {
    test(`a ticked pickup sent with x-wambito-client: ${client} still gets a standard session, never the phone's long one`, async () => {
      const p = await phone();
      const { started } = await sealed(p, { remember: true });
      const res = await t.request("POST", `/v2/signin/${started.id}/pickup`, {
        headers: { ...poll(started.pollSecret), "x-wambito-client": client },
      });
      expect(res.status, await res.clone().text()).toBe(200);
      expect(sessionCookieLine(res)).toMatch(/Max-Age=5184000/i);
      const row = await sessionByToken(res.headers.get("set-auth-token") ?? "");
      expect(row.lifetime).toBe("standard");
      expect(row.expiresAt.getTime()).toBeLessThanOrEqual(Date.now() + 60 * 24 * HOUR + 1000);
    });
  }

  test("an unticked session is 401 after 13 hours, and no response to it ever sets Max-Age", async () => {
    const p = await phone();
    const { started } = await sealed(p, { remember: false });
    const res = await pickup(started.id, started.pollSecret);
    expect(res.status).toBe(200);
    const token = res.headers.get("set-auth-token") ?? "";
    const cookie = cookieOf(res);
    // A client that drops the dont_remember cookie still gets no refresh.
    const sessionOnly = cookie
      .split("; ")
      .filter((c) => c.includes("session_token="))
      .join("; ");
    const created = await sessionByToken(token);
    const limit = created.createdAt.getTime() + TWELVE_HOURS + 1000;

    const ways: Record<string, string>[] = [
      { cookie },
      { cookie: sessionOnly },
      { authorization: `Bearer ${token}` },
    ];
    for (const headers of ways) {
      for (const path of ["/v1/me", "/auth/get-session", "/v2/keys"]) {
        const r = await t.request("GET", path, { headers });
        expect(r.status, `${path} ${Object.keys(headers)}`).toBe(200);
        for (const line of r.headers.getSetCookie()) expect(line).not.toMatch(/Max-Age/i);
        expect((await sessionByToken(token)).expiresAt.getTime()).toBeLessThanOrEqual(limit);
      }
    }

    // 13 hours on: the session has expired.
    await t.admin.execute(sql`update ${session}
      set expires_at = expires_at - interval '13 hours', updated_at = updated_at - interval '13 hours',
        created_at = created_at - interval '13 hours'
      where ${session.id} = ${created.id}`);
    for (const headers of ways) {
      const r = await t.request("GET", "/v1/me", { headers });
      expect(r.status).toBe(401);
      for (const line of r.headers.getSetCookie()) expect(line).not.toMatch(/Max-Age=[1-9]/i);
    }
  });

  test("two pickups at once: exactly one 200 and one 404, one session row", async () => {
    const p = await phone();
    const { started, blob } = await sealed(p);
    const before = (await sessionsOf(p.userId)).length;
    const results = await Promise.all([
      pickup(started.id, started.pollSecret),
      pickup(started.id, started.pollSecret),
    ]);
    expect(results.map((r) => r.status).sort()).toEqual([200, 404]);
    const ok = results.find((r) => r.status === 200);
    expect(await ok?.json()).toEqual({ sealed: blob, keyV: 1, userId: p.userId });
    const lost = results.find((r) => r.status === 404);
    expect(lost?.headers.getSetCookie()).toEqual([]);
    expect((await sessionsOf(p.userId)).length).toBe(before + 1);
  });

  test("a pickup for a suspended user is 403 account_suspended and creates no session", async () => {
    const p = await phone();
    const { started } = await sealed(p);
    const before = (await sessionsOf(p.userId)).length;
    await t.admin.update(user).set({ suspendedAt: new Date() }).where(eq(user.id, p.userId));
    const res = await pickup(started.id, started.pollSecret);
    await expectProblem(res, 403, "account_suspended");
    expect(res.headers.getSetCookie()).toEqual([]);
    expect(res.headers.get("set-auth-token")).toBeNull();
    expect((await sessionsOf(p.userId)).length).toBe(before);
  });

  test("purgeExpiredSignins deletes only expired rows", async () => {
    const { started: live } = await open();
    const oldId = randomUUID();
    await t.admin.execute(sql`insert into ${signinRequests}
      (id, code, commitment, poll_hash, label, remember, expires_at)
      values (${oldId}, 'OLDSIGN1', ${Buffer.alloc(32, 1)}, ${Buffer.alloc(32, 2)}, 'Old', true,
        ${new Date(clock.getTime() - 1000).toISOString()}::timestamptz)`);
    expect(await purgeExpiredSignins(t.db, clock)).toBeGreaterThanOrEqual(1);
    const ids = (await t.admin.select({ id: signinRequests.id }).from(signinRequests)).map(
      (r) => r.id,
    );
    expect(ids).toContain(live.id);
    expect(ids).not.toContain(oldId);
  });

  test("the daily purge also purges sign-in requests, and goes on when that fails", async () => {
    const purge = vi.fn(async () => 0);
    const purgePairings = vi.fn(async () => 0);
    const purgeSignins = vi.fn(async () => {
      throw new Error("boom");
    });
    const logError = vi.fn();
    const stop = scheduleTombstonePurge({ db: t.db, purge, purgePairings, purgeSignins, logError });
    await vi.waitFor(() => expect(purge).toHaveBeenCalled());
    stop();
    expect(purgeSignins).toHaveBeenCalledTimes(1);
    expect(logError).toHaveBeenCalledWith("Sign-in request purge failed", expect.any(Error));
  });
});
