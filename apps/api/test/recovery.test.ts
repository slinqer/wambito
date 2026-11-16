import { randomUUID } from "node:crypto";
import { newRecoverySecret, recoveryVerifier, verifierHash } from "@wambito/crypto";
import { recoveryVerifiers, session, user } from "@wambito/db";
import { desc, eq } from "@wambito/db/orm";
import { afterAll, beforeAll, describe, expect, test } from "vitest";
import { RECOVERY_SIGNIN_LIMIT } from "../src/routes/recovery.ts";
import { createTestApp, type TestApp } from "./harness.ts";

// Recovery-key sign-in (spec 2026-11-15): the phone derives a lookup (16 bytes) and an auth (32
// bytes) from the recovery secret; the server keeps only their SHA-256 hashes (`recovery_verifiers`)
// and signs in whoever presents both. A new recovery wrap with other bytes is a new recovery key:
// the old verifier goes with it, so the old key no longer signs in.

type Auth = { userId: string; headers: { authorization: string } };
const PHONE = { "x-wambito-client": "android" };
const DAY = 24 * 60 * 60 * 1000;

const b64 = (bytes: Uint8Array) => Buffer.from(bytes).toString("base64url");
const filled = (length: number, fill: number) => Buffer.alloc(length, fill).toString("base64url");

let t: TestApp;
let people = 0;
beforeAll(async () => {
  t = await createTestApp({ NEW_USERS_ENCRYPTED: true });
});
afterAll(() => t?.stop());

/** An encrypted guest signed up from the phone. */
async function guest(): Promise<Auth> {
  const res = await t.request("POST", "/auth/sign-in/anonymous", { body: {}, headers: PHONE });
  if (res.status !== 200) throw new Error(`guest failed: ${res.status} ${await res.text()}`);
  const json = (await res.json()) as { user: { id: string } };
  return {
    userId: json.user.id,
    headers: { authorization: `Bearer ${res.headers.get("set-auth-token")}` },
  };
}

const recoveryWrap = (fill: number, keyV = 1) => ({
  kind: "recovery",
  ref: null,
  keyV,
  wrapped: filled(48, fill),
});

async function putWrap(auth: Auth, id: string, body: unknown) {
  const res = await t.request("PUT", `/v2/keys/${id}`, { headers: auth.headers, body });
  expect(res.status, await res.clone().text()).toBe(200);
}

/** A fresh recovery key: its verifier as sent to the server and as presented to sign in. */
async function newKey() {
  const v = await recoveryVerifier(newRecoverySecret());
  return {
    put: {
      lookupHash: b64(await verifierHash(v.lookup)),
      authHash: b64(await verifierHash(v.auth)),
    },
    signIn: { lookup: b64(v.lookup), auth: b64(v.auth) },
  };
}
type Key = Awaited<ReturnType<typeof newKey>>;

const putVerifier = (auth: Auth, key: Key) =>
  t.request("PUT", "/v2/recovery/verifier", { headers: auth.headers, body: key.put });

const signIn = (body: unknown, headers: Record<string, string> = {}) =>
  t.request("POST", "/v2/recovery/sign-in", { body, headers });

/** A guest with a recovery wrap and the verifier of a fresh key. */
async function withKey(): Promise<Auth & { key: Key; wrapId: string }> {
  const g = await guest();
  const wrapId = randomUUID();
  await putWrap(g, wrapId, recoveryWrap(++people % 200));
  const key = await newKey();
  expect((await putVerifier(g, key)).status).toBe(204);
  return { ...g, key, wrapId };
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

const verifierRows = (userId: string) =>
  t.admin.select().from(recoveryVerifiers).where(eq(recoveryVerifiers.userId, userId));

describe("recovery-key sign-in", () => {
  test("a verifier is stored, and the key signs in: 200 { userId }, a set-auth-token that opens GET /v2/keys, and a cookie that opens GET /v1/me", async () => {
    const g = await withKey();
    const [stored] = await verifierRows(g.userId);
    expect(b64(stored?.lookupHash ?? new Uint8Array())).toBe(g.key.put.lookupHash);
    expect(b64(stored?.authHash ?? new Uint8Array())).toBe(g.key.put.authHash);

    const res = await signIn(g.key.signIn, PHONE);
    expect(res.status, await res.clone().text()).toBe(200);
    expect(await res.json()).toEqual({ userId: g.userId });

    const token = res.headers.get("set-auth-token");
    expect(token).toBeTruthy();
    const keys = await t.request("GET", "/v2/keys", {
      headers: { authorization: `Bearer ${token}` },
    });
    expect(keys.status).toBe(200);

    const cookie = res.headers
      .getSetCookie()
      .map((c) => c.split(";")[0])
      .join("; ");
    expect(cookie).toContain("session_token");
    const me = await t.request("GET", "/v1/me", { headers: { cookie } });
    expect(me.status).toBe(200);
    expect(((await me.json()) as { id: string }).id).toBe(g.userId);
  });

  test("wrong auth and unknown lookup give the same 401 recovery_key_invalid, byte for byte", async () => {
    const g = await withKey();
    const other = await newKey();
    const wrongAuth = await signIn({ lookup: g.key.signIn.lookup, auth: other.signIn.auth });
    const unknown = await signIn(other.signIn);
    expect(wrongAuth.status).toBe(401);
    expect(unknown.status).toBe(401);
    const a = await wrongAuth.text();
    expect(a).toBe(await unknown.text());
    expect(JSON.parse(a).code).toBe("recovery_key_invalid");
    expect(wrongAuth.headers.get("content-type")).toBe(unknown.headers.get("content-type"));
    expect(wrongAuth.headers.getSetCookie()).toEqual([]);
    expect(wrongAuth.headers.get("set-auth-token")).toBeNull();
  });

  test("the 11th sign-in from one address in 10 minutes is 429 with retry-after", async () => {
    expect(RECOVERY_SIGNIN_LIMIT).toEqual({ max: 10, windowMs: 10 * 60 * 1000 });
    const from = { "x-forwarded-for": "203.0.113.77, 10.0.0.1" };
    const g = await withKey();
    const wrong = { lookup: g.key.signIn.lookup, auth: filled(32, 1) };
    for (let i = 0; i < 10; i++) expect((await signIn(wrong, from)).status).toBe(401);
    // Even the right key is refused once the address is over the limit.
    const over = await signIn(g.key.signIn, from);
    expect(over.status).toBe(429);
    expect(over.headers.get("retry-after")).toBe("600");
    // Another address is untouched.
    expect((await signIn(g.key.signIn)).status).toBe(200);
  });

  test("from the phone (x-wambito-client: android) an encrypted user without email gets a long session; from the web a standard one", async () => {
    const g = await withKey();
    expect((await signIn(g.key.signIn, PHONE)).status).toBe(200);
    const phone = await latestSession(g.userId);
    expect(phone.lifetime).toBe("long");
    expect((phone.expiresAt.getTime() - Date.now()) / DAY).toBeGreaterThan(760 - 0.01);

    expect((await signIn(g.key.signIn)).status).toBe(200);
    const web = await latestSession(g.userId);
    expect(web.id).not.toBe(phone.id);
    expect(web.lifetime).toBe("standard");
    expect((web.expiresAt.getTime() - Date.now()) / DAY).toBeLessThanOrEqual(60);
  });

  test("a suspended account gets 403 account_suspended and no session", async () => {
    const g = await withKey();
    await t.admin.update(user).set({ suspendedAt: new Date() }).where(eq(user.id, g.userId));
    const before = await t.admin.select().from(session).where(eq(session.userId, g.userId));

    const res = await signIn(g.key.signIn, PHONE);
    expect(res.status).toBe(403);
    expect(((await res.json()) as { code: string }).code).toBe("account_suspended");
    expect(res.headers.getSetCookie()).toEqual([]);
    expect(res.headers.get("set-auth-token")).toBeNull();
    const after = await t.admin.select().from(session).where(eq(session.userId, g.userId));
    expect(after).toHaveLength(before.length);
  });
});

describe("PUT /v2/recovery/verifier", () => {
  test("PUT /v2/recovery/verifier without a recovery wrap is 409 recovery_required", async () => {
    const g = await guest();
    const res = await putVerifier(g, await newKey());
    expect(res.status).toBe(409);
    expect(((await res.json()) as { code: string }).code).toBe("recovery_required");
    expect(await verifierRows(g.userId)).toHaveLength(0);
  });

  test("a second PUT replaces the verifier: the old key no longer signs in", async () => {
    const g = await withKey();
    const next = await newKey();
    expect((await putVerifier(g, next)).status).toBe(204);
    expect(await verifierRows(g.userId)).toHaveLength(1);

    expect((await signIn(g.key.signIn)).status).toBe(401);
    expect((await signIn(next.signIn)).status).toBe(200);
  });

  test("a lookup hash another user holds is 409 verifier_taken", async () => {
    const a = await withKey();
    const b = await withKey();
    const res = await t.request("PUT", "/v2/recovery/verifier", {
      headers: b.headers,
      body: { lookupHash: a.key.put.lookupHash, authHash: b.key.put.authHash },
    });
    expect(res.status).toBe(409);
    expect(((await res.json()) as { code: string }).code).toBe("verifier_taken");
    // Both keys still sign in to their own accounts.
    expect(await (await signIn(a.key.signIn)).json()).toEqual({ userId: a.userId });
    expect(await (await signIn(b.key.signIn)).json()).toEqual({ userId: b.userId });
  });

  test("replacing the recovery wrap with new bytes deletes the verifier; a retry of the same PUT and a rotation keep it", async () => {
    const g = await guest();
    const wrapId = randomUUID();
    await putWrap(g, wrapId, recoveryWrap(31));
    const key = await newKey();
    expect((await putVerifier(g, key)).status).toBe(204);

    // A retry of the same PUT (same bytes): the key still signs in.
    await putWrap(g, wrapId, recoveryWrap(31));
    expect(await verifierRows(g.userId)).toHaveLength(1);
    expect((await signIn(key.signIn)).status).toBe(200);

    // A rotation re-wraps a new data key under the same recovery key: kept.
    const rotated = await t.request("POST", "/v2/keys/rotate", {
      headers: g.headers,
      body: { keyV: 2, wraps: [{ id: randomUUID(), ...recoveryWrap(32, 2) }], link: filled(60, 3) },
    });
    expect(rotated.status, await rotated.clone().text()).toBe(200);
    expect(await verifierRows(g.userId)).toHaveLength(1);
    expect((await signIn(key.signIn)).status).toBe(200);

    // A new recovery wrap with other bytes is a new recovery key: the old one no longer signs in.
    await putWrap(g, randomUUID(), recoveryWrap(33, 2));
    expect(await verifierRows(g.userId)).toHaveLength(0);
    expect((await signIn(key.signIn)).status).toBe(401);

    // Until the new key's verifier is stored, which then signs in.
    const next = await newKey();
    expect((await putVerifier(g, next)).status).toBe(204);
    expect((await signIn(next.signIn)).status).toBe(200);
    expect((await signIn(key.signIn)).status).toBe(401);
  });

  test("deleting the user deletes its verifier", async () => {
    const g = await withKey();
    expect(await verifierRows(g.userId)).toHaveLength(1);
    await t.admin.delete(user).where(eq(user.id, g.userId));
    expect(await verifierRows(g.userId)).toHaveLength(0);
    expect((await signIn(g.key.signIn)).status).toBe(401);
  });

  test("an assistant token gets 403 on PUT /v2/recovery/verifier", async () => {
    const tokens = await t.authorize("recovery-assistant@wambito.test");
    const res = await t.request("PUT", "/v2/recovery/verifier", {
      headers: { authorization: `Bearer ${tokens.accessToken}` },
      body: (await newKey()).put,
    });
    expect(res.status).toBe(403);
  });

  test("a body that is not 32 bytes of base64url is 422", async () => {
    const g = await withKey();
    const res = await t.request("PUT", "/v2/recovery/verifier", {
      headers: g.headers,
      body: { lookupHash: filled(16, 1), authHash: g.key.put.authHash },
    });
    expect(res.status).toBe(422);
    const bad = await signIn({ lookup: filled(32, 1), auth: filled(32, 1) });
    expect(bad.status).toBe(422);
  });
});
