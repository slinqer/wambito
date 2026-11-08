import { randomUUID } from "node:crypto";
import {
  fromBase64Url,
  generateDataKey,
  generateDeviceKeyPair,
  openFromDevice,
  pairingCode,
  sealToDevice,
  toBase64Url,
} from "@wambito/crypto";
import { pairingRequests } from "@wambito/db";
import { sql } from "@wambito/db/orm";
import { afterAll, beforeAll, describe, expect, test, vi } from "vitest";
import { purgeExpiredPairings } from "../src/services/pairing.ts";
import { scheduleTombstonePurge } from "../src/services/sync.ts";
import { createTestApp, type TestApp } from "./harness.ts";

type Headers = { authorization: string };
interface Started {
  id: string;
  code: string;
  expiresAt: string;
}

let clock = new Date("2026-11-08T12:00:00Z");
let t: TestApp;
let people = 0;
beforeAll(async () => {
  t = await createTestApp({}, { now: () => clock });
});
afterAll(() => t?.stop());

const bytes = (length: number, fill = 7) => Buffer.alloc(length, fill).toString("base64url");
const bearer = (token: string): Headers => ({ authorization: `Bearer ${token}` });

async function person(): Promise<{ email: string; headers: Headers; userId: string }> {
  const email = `pairing-${++people}@wambito.test`;
  return { email, ...(await t.signIn(email)) };
}

const startRaw = (headers: Headers, body: unknown) =>
  t.request("POST", "/v2/pairing", { headers, body });
async function start(headers: Headers, publicKey = bytes(32)): Promise<Started> {
  const res = await startRaw(headers, { publicKey });
  expect(res.status, await res.clone().text()).toBe(201);
  return (await res.json()) as Started;
}
const find = (headers: Headers, code: string) =>
  t.request("GET", `/v2/pairing?code=${encodeURIComponent(code)}`, { headers });
const seal = (headers: Headers, id: string, sealed: unknown) =>
  t.request("POST", `/v2/pairing/${id}/seal`, { headers, body: { sealed } });
const take = (headers: Headers, id: string) => t.request("GET", `/v2/pairing/${id}`, { headers });

async function expectProblem(res: Response, status: number, code: string) {
  expect(res.status).toBe(status);
  expect(((await res.json()) as { code: string }).code).toBe(code);
}

describe("/v2/pairing", () => {
  test("the whole flow: the new device opens the data key the old one sealed", async () => {
    const old = await person();
    const fresh = await generateDeviceKeyPair();
    const started = await start(old.headers, toBase64Url(fresh.publicKey));
    expect(started.code).toMatch(/^[0-9A-HJKMNP-TV-Z]{8}$/);
    expect(Date.parse(started.expiresAt)).toBe(clock.getTime() + 10 * 60_000);

    // Nothing sealed yet.
    const waiting = await take(old.headers, started.id);
    expect(waiting.status).toBe(200);
    expect(await waiting.json()).toEqual({ sealed: null });

    // The unlocked device types the code (sloppily: lower case, a dash) and finds the public key.
    const typed = `${started.code.slice(0, 4)}-${started.code.slice(4)}`.toLowerCase();
    const found = await find(old.headers, typed);
    expect(found.status).toBe(200);
    expect(await found.json()).toEqual({
      id: started.id,
      publicKey: toBase64Url(fresh.publicKey),
      expiresAt: started.expiresAt,
    });

    const ctx = { kind: "device" as const, userId: old.userId, keyV: 1 };
    const dataKey = generateDataKey();
    const sealed = await sealToDevice(fresh.publicKey, ctx, dataKey);
    expect((await seal(old.headers, started.id, toBase64Url(sealed))).status).toBe(204);

    // Once sealed it is no longer findable, and sealing again is refused.
    await expectProblem(await find(old.headers, started.code), 404, "not_found");
    await expectProblem(
      await seal(old.headers, started.id, toBase64Url(sealed)),
      409,
      "already_sealed",
    );

    const picked = await take(old.headers, started.id);
    expect(picked.status).toBe(200);
    const { sealed: got } = (await picked.json()) as { sealed: string };
    expect(await openFromDevice(fresh.privateKey, ctx, fromBase64Url(got))).toEqual(dataKey);

    // Picked up once.
    await expectProblem(await take(old.headers, started.id), 404, "not_found");
    const left = await t.admin.select().from(pairingRequests).where(sql`id = ${started.id}`);
    expect(left).toHaveLength(0);
  });

  test("another person's code is not found, and their request cannot be sealed or taken", async () => {
    const a = await person();
    const b = await person();
    const started = await start(a.headers);
    await expectProblem(await find(b.headers, started.code), 404, "not_found");
    await expectProblem(await seal(b.headers, started.id, bytes(100)), 404, "not_found");
    await expectProblem(await take(b.headers, started.id), 404, "not_found");
    expect((await find(a.headers, started.code)).status).toBe(200);
  });

  test("an expired request is 404 everywhere", async () => {
    const { headers } = await person();
    const started = await start(headers);
    const sealedOne = await start(headers);
    expect((await seal(headers, sealedOne.id, bytes(100))).status).toBe(204);
    const real = clock;
    clock = new Date(real.getTime() + 11 * 60_000);
    try {
      await expectProblem(await find(headers, started.code), 404, "not_found");
      await expectProblem(await seal(headers, started.id, bytes(100)), 404, "not_found");
      await expectProblem(await take(headers, started.id), 404, "not_found");
      await expectProblem(await take(headers, sealedOne.id), 404, "not_found");
    } finally {
      clock = real;
    }
  });

  test("the sixth open request is 429; expired ones do not count", async () => {
    const { headers } = await person();
    for (let i = 0; i < 5; i++) await start(headers);
    await expectProblem(
      await startRaw(headers, { publicKey: bytes(32) }),
      429,
      "too_many_pairings",
    );
    const real = clock;
    clock = new Date(real.getTime() + 11 * 60_000);
    try {
      await start(headers);
    } finally {
      clock = real;
    }
  });

  test("validates bodies and codes", async () => {
    const { headers } = await person();
    const invalid = async (res: Response) => expectProblem(res, 422, "validation_failed");
    await invalid(await startRaw(headers, { publicKey: bytes(31) }));
    await invalid(await startRaw(headers, { publicKey: bytes(33) }));
    await invalid(await startRaw(headers, {}));
    await invalid(await startRaw(headers, { publicKey: "not base64url!" }));
    await invalid(await t.request("GET", "/v2/pairing", { headers }));
    await invalid(await find(headers, "x".repeat(40)));
    const started = await start(headers);
    await invalid(await seal(headers, started.id, ""));
    await invalid(await seal(headers, started.id, bytes(1025)));
    await invalid(await t.request("GET", "/v2/pairing/not-a-uuid", { headers }));
    expect((await seal(headers, started.id, bytes(1024))).status).toBe(204);
  });

  test("purgeExpiredPairings deletes expired rows only", async () => {
    const { headers, userId } = await person();
    const live = await start(headers);
    await t.admin.execute(sql`insert into ${pairingRequests} (id, user_id, code, public_key, expires_at)
      values (${randomUUID()}, ${userId}, 'OLDOLDOL', '\\x01'::bytea, ${new Date(clock.getTime() - 1000).toISOString()}::timestamptz)`);
    expect(await purgeExpiredPairings(t.db, clock)).toBeGreaterThanOrEqual(1);
    const rows = await t.admin.select().from(pairingRequests).where(sql`user_id = ${userId}`);
    expect(rows.map((r) => r.id)).toEqual([live.id]);
  });

  test("the daily tombstone purge also purges pairing requests", async () => {
    const purge = vi.fn(async () => 0);
    const purgePairings = vi.fn(async () => 2);
    const stop = scheduleTombstonePurge({ db: t.db, purge, purgePairings });
    await vi.waitFor(() => expect(purge).toHaveBeenCalled());
    stop();
    expect(purgePairings).toHaveBeenCalledTimes(1);
  });

  test("a failing pairing purge does not skip the tombstone purge", async () => {
    const purge = vi.fn(async () => 0);
    const purgePairings = vi.fn(async () => {
      throw new Error("boom");
    });
    const logError = vi.fn();
    const stop = scheduleTombstonePurge({ db: t.db, purge, purgePairings, logError });
    await vi.waitFor(() => expect(purge).toHaveBeenCalled());
    stop();
    expect(logError).toHaveBeenCalledWith("Pairing purge failed", expect.any(Error));
  });

  test("two concurrent takes of a sealed request: one gets the blob, the other 404", async () => {
    const { headers } = await person();
    const started = await start(headers);
    const blob = bytes(80, 5);
    expect((await seal(headers, started.id, blob)).status).toBe(204);
    const results = await Promise.all([take(headers, started.id), take(headers, started.id)]);
    expect(results.map((r) => r.status).sort()).toEqual([200, 404]);
    const ok = results.find((r) => r.status === 200);
    expect(await ok?.json()).toEqual({ sealed: blob });
  });

  test("assistant tokens get 403 on every route", async () => {
    const { email, headers } = await person();
    const started = await start(headers);
    for (const scope of ["finance:read", "finance:read finance:write"]) {
      const token = await t.authorize(email, { scope, headers });
      const h = bearer(token.accessToken);
      for (const res of [
        await startRaw(h, { publicKey: bytes(32) }),
        await find(h, started.code),
        await seal(h, started.id, bytes(100)),
        await take(h, started.id),
      ]) {
        await expectProblem(res, 403, "insufficient_scope");
      }
    }
  });

  test("pairingCode is what the server hands out", () => {
    expect(pairingCode()).toHaveLength(8);
  });
});
