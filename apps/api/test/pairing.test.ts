import { randomUUID } from "node:crypto";
import {
  fromBase64Url,
  generateDataKey,
  generateDeviceKeyPair,
  openFromPairing,
  pairingCode,
  pairingCommitment,
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
interface State {
  commitment: string;
  approverKey: string | null;
  publicKey: string | null;
  sealed: string | null;
  keyV: number | null;
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
async function start(headers: Headers, commitment = bytes(32)): Promise<Started> {
  const res = await startRaw(headers, { commitment });
  expect(res.status, await res.clone().text()).toBe(201);
  return (await res.json()) as Started;
}
const find = (headers: Headers, code: string) =>
  t.request("GET", `/v2/pairing?code=${encodeURIComponent(code)}`, { headers });
const approver = (headers: Headers, id: string, publicKey: unknown) =>
  t.request("POST", `/v2/pairing/${id}/approver`, { headers, body: { publicKey } });
const reveal = (headers: Headers, id: string, publicKey: unknown) =>
  t.request("POST", `/v2/pairing/${id}/reveal`, { headers, body: { publicKey } });
const seal = (headers: Headers, id: string, sealed: unknown, keyV: unknown = 1) =>
  t.request("POST", `/v2/pairing/${id}/seal`, { headers, body: { sealed, keyV } });
const take = (headers: Headers, id: string) => t.request("GET", `/v2/pairing/${id}`, { headers });
const pickup = (headers: Headers, id: string) =>
  t.request("POST", `/v2/pairing/${id}/pickup`, { headers });

/** Gives the account a recovery wrap at `keyV`, so a seal for that version is accepted. */
async function withKeys(headers: Headers, keyV: number) {
  const res = await t.request("PUT", `/v2/keys/${randomUUID()}`, {
    headers,
    body: { kind: "recovery", ref: null, keyV, wrapped: bytes(48) },
  });
  expect(res.status, await res.clone().text()).toBe(200);
}
const commitmentOf = async (publicKey: Uint8Array) =>
  toBase64Url(await pairingCommitment(publicKey));

/** A request that got through the approver step: returns the keys involved. */
async function approved(headers: Headers) {
  const fresh = await generateDeviceKeyPair();
  const eph = await generateDeviceKeyPair();
  const started = await start(headers, await commitmentOf(fresh.publicKey));
  expect((await approver(headers, started.id, toBase64Url(eph.publicKey))).status).toBe(204);
  return { started, fresh, eph };
}

async function expectProblem(res: Response, status: number, code: string) {
  expect(res.status).toBe(status);
  expect(((await res.json()) as { code: string }).code).toBe(code);
}

describe("/v2/pairing", () => {
  test("the whole flow: commit, approver key, reveal, seal, the new device opens it", async () => {
    const old = await person();
    await withKeys(old.headers, 3);
    const fresh = await generateDeviceKeyPair();
    const eph = await generateDeviceKeyPair();
    const started = await start(old.headers, await commitmentOf(fresh.publicKey));
    expect(started.code).toMatch(/^[0-9A-HJKMNP-TV-Z]{8}$/);
    expect(Date.parse(started.expiresAt)).toBe(clock.getTime() + 10 * 60_000);

    const state = async () => (await (await take(old.headers, started.id)).json()) as State;
    expect(await state()).toEqual({
      commitment: await commitmentOf(fresh.publicKey),
      approverKey: null,
      publicKey: null,
      sealed: null,
      keyV: null,
      expiresAt: started.expiresAt,
    });

    // The unlocked device types the code (sloppily) and finds the commitment.
    const typed = `${started.code.slice(0, 4)}-${started.code.slice(4)}`.toLowerCase();
    const found = await find(old.headers, typed);
    expect(found.status).toBe(200);
    expect(await found.json()).toEqual({
      id: started.id,
      commitment: await commitmentOf(fresh.publicKey),
      expiresAt: started.expiresAt,
    });

    expect((await approver(old.headers, started.id, toBase64Url(eph.publicKey))).status).toBe(204);
    // Once an approver key is set the code no longer finds it.
    await expectProblem(await find(old.headers, started.code), 404, "not_found");
    expect((await state()).approverKey).toBe(toBase64Url(eph.publicKey));

    expect((await reveal(old.headers, started.id, toBase64Url(fresh.publicKey))).status).toBe(204);
    expect((await state()).publicKey).toBe(toBase64Url(fresh.publicKey));

    const ctx = { kind: "device" as const, userId: old.userId, keyV: 3 };
    const dataKey = generateDataKey();
    const sealed = await sealToDevice(fresh.publicKey, ctx, dataKey, eph);
    expect((await seal(old.headers, started.id, toBase64Url(sealed), 3)).status).toBe(204);
    await expectProblem(
      await seal(old.headers, started.id, toBase64Url(sealed), 3),
      409,
      "already_sealed",
    );

    // Polling after the seal shows it and never consumes it.
    for (let i = 0; i < 2; i++) {
      const polled = (await (await take(old.headers, started.id)).json()) as State;
      expect(polled.sealed).not.toBeNull();
      expect(polled.keyV).toBe(3);
    }
    const taken = await pickup(old.headers, started.id);
    expect(taken.status).toBe(200);
    const picked = (await taken.json()) as { sealed: string; keyV: number };
    expect(picked.keyV).toBe(3);
    expect(
      await openFromPairing(fresh.privateKey, ctx, fromBase64Url(picked.sealed), eph.publicKey),
    ).toEqual(dataKey);

    // Picked up once, and the row is gone.
    await expectProblem(await pickup(old.headers, started.id), 404, "not_found");
    await expectProblem(await take(old.headers, started.id), 404, "not_found");
    const left = await t.admin.select().from(pairingRequests).where(sql`id = ${started.id}`);
    expect(left).toHaveLength(0);
  });

  test("out of order and repeated calls", async () => {
    const { headers } = await person();
    const fresh = await generateDeviceKeyPair();
    const eph = await generateDeviceKeyPair();
    const started = await start(headers, await commitmentOf(fresh.publicKey));
    const freshB64 = toBase64Url(fresh.publicKey);
    const ephB64 = toBase64Url(eph.publicKey);
    const blob = (key: string) =>
      toBase64Url(Buffer.concat([Buffer.from(key, "base64url"), Buffer.alloc(40, 1)]));

    // Reveal and seal both need the approver key first.
    await expectProblem(await reveal(headers, started.id, freshB64), 409, "not_ready");
    await expectProblem(await seal(headers, started.id, blob(ephB64)), 409, "not_ready");

    expect((await approver(headers, started.id, ephB64)).status).toBe(204);
    await expectProblem(await approver(headers, started.id, ephB64), 409, "already_set");
    await expectProblem(
      await approver(headers, started.id, toBase64Url((await generateDeviceKeyPair()).publicKey)),
      409,
      "already_set",
    );

    // Seal needs the revealed key.
    await expectProblem(await seal(headers, started.id, blob(ephB64)), 409, "not_ready");
    // Nothing to pick up before the seal.
    await expectProblem(await pickup(headers, started.id), 409, "not_ready");

    expect((await reveal(headers, started.id, freshB64)).status).toBe(204);
    await expectProblem(await reveal(headers, started.id, freshB64), 409, "already_set");
  });

  test("a revealed key that does not match the commitment is 422 commitment_mismatch", async () => {
    const { headers } = await person();
    const { started } = await approved(headers);
    const other = await generateDeviceKeyPair();
    await expectProblem(
      await reveal(headers, started.id, toBase64Url(other.publicKey)),
      422,
      "commitment_mismatch",
    );
    // Nothing was stored, so the right key still goes through.
    const row = await t.admin.select().from(pairingRequests).where(sql`id = ${started.id}`);
    expect(row[0]?.publicKey).toBeNull();
  });

  test("a seal that does not start with the approver key is 422 approver_mismatch", async () => {
    const { headers } = await person();
    const { started, fresh } = await approved(headers);
    expect((await reveal(headers, started.id, toBase64Url(fresh.publicKey))).status).toBe(204);
    await expectProblem(await seal(headers, started.id, bytes(80)), 422, "approver_mismatch");
    // A blob shorter than the key cannot start with it either.
    await expectProblem(await seal(headers, started.id, bytes(16)), 422, "approver_mismatch");
  });

  test("another person's request is 404 on every route", async () => {
    const a = await person();
    const b = await person();
    const started = await start(a.headers);
    const key = bytes(32);
    await expectProblem(await find(b.headers, started.code), 404, "not_found");
    await expectProblem(await approver(b.headers, started.id, key), 404, "not_found");
    await expectProblem(await reveal(b.headers, started.id, key), 404, "not_found");
    await expectProblem(await seal(b.headers, started.id, bytes(100)), 404, "not_found");
    await expectProblem(await take(b.headers, started.id), 404, "not_found");
    await expectProblem(await pickup(b.headers, started.id), 404, "not_found");
    expect((await find(a.headers, started.code)).status).toBe(200);
  });

  test("an expired request is 404 everywhere", async () => {
    const { headers } = await person();
    const started = await start(headers);
    const real = clock;
    clock = new Date(real.getTime() + 11 * 60_000);
    try {
      const key = bytes(32);
      await expectProblem(await find(headers, started.code), 404, "not_found");
      await expectProblem(await approver(headers, started.id, key), 404, "not_found");
      await expectProblem(await reveal(headers, started.id, key), 404, "not_found");
      await expectProblem(await seal(headers, started.id, bytes(100)), 404, "not_found");
      await expectProblem(await take(headers, started.id), 404, "not_found");
      await expectProblem(await pickup(headers, started.id), 404, "not_found");
    } finally {
      clock = real;
    }
  });

  test("the sixth open request is 429; expired ones do not count", async () => {
    const { headers } = await person();
    for (let i = 0; i < 5; i++) await start(headers);
    await expectProblem(
      await startRaw(headers, { commitment: bytes(32) }),
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
    await invalid(await startRaw(headers, { commitment: bytes(31) }));
    await invalid(await startRaw(headers, { commitment: bytes(33) }));
    await invalid(await startRaw(headers, {}));
    await invalid(await startRaw(headers, { commitment: "not base64url!" }));
    await invalid(await t.request("GET", "/v2/pairing", { headers }));
    await invalid(await find(headers, "x".repeat(40)));
    const { started, fresh } = await approved(headers);
    await invalid(await approver(headers, started.id, bytes(31)));
    await invalid(await reveal(headers, started.id, bytes(33)));
    expect((await reveal(headers, started.id, toBase64Url(fresh.publicKey))).status).toBe(204);
    await invalid(await seal(headers, started.id, ""));
    await invalid(await seal(headers, started.id, bytes(1025)));
    await invalid(await seal(headers, started.id, bytes(80), -1));
    await invalid(await seal(headers, started.id, bytes(80), 32768));
    await invalid(await seal(headers, started.id, bytes(80), 1.5));
    await invalid(await t.request("GET", "/v2/pairing/not-a-uuid", { headers }));
  });

  test("purgeExpiredPairings deletes expired rows only", async () => {
    const { headers, userId } = await person();
    const live = await start(headers);
    await t.admin.execute(sql`insert into ${pairingRequests} (id, user_id, code, commitment, expires_at)
      values (${randomUUID()}, ${userId}, 'OLDOLDOL', ${Buffer.alloc(32, 1)}, ${new Date(clock.getTime() - 1000).toISOString()}::timestamptz)`);
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

  test("two concurrent pickups of a sealed request: one gets the blob, the other 404", async () => {
    const { headers } = await person();
    await withKeys(headers, 2);
    const { started, fresh, eph } = await approved(headers);
    expect((await reveal(headers, started.id, toBase64Url(fresh.publicKey))).status).toBe(204);
    const blob = toBase64Url(Buffer.concat([eph.publicKey, Buffer.alloc(48, 5)]));
    expect((await seal(headers, started.id, blob, 2)).status).toBe(204);
    const results = await Promise.all([pickup(headers, started.id), pickup(headers, started.id)]);
    expect(results.map((r) => r.status).sort()).toEqual([200, 404]);
    const ok = results.find((r) => r.status === 200);
    expect(await ok?.json()).toEqual({ sealed: blob, keyV: 2 });
  });

  test("a seal for another key version is 409 key_version_mismatch", async () => {
    const { headers } = await person();
    await withKeys(headers, 2);
    const { started, fresh, eph } = await approved(headers);
    expect((await reveal(headers, started.id, toBase64Url(fresh.publicKey))).status).toBe(204);
    const blob = toBase64Url(Buffer.concat([eph.publicKey, Buffer.alloc(48, 5)]));
    await expectProblem(await seal(headers, started.id, blob, 1), 409, "key_version_mismatch");
    await expectProblem(await seal(headers, started.id, blob, 3), 409, "key_version_mismatch");
    expect((await seal(headers, started.id, blob, 2)).status).toBe(204);
    // An account with no wraps has no key version to seal for.
    const bare = await person();
    const second = await approved(bare.headers);
    expect(
      (await reveal(bare.headers, second.started.id, toBase64Url(second.fresh.publicKey))).status,
    ).toBe(204);
    const bareBlob = toBase64Url(Buffer.concat([second.eph.publicKey, Buffer.alloc(48, 5)]));
    await expectProblem(
      await seal(bare.headers, second.started.id, bareBlob, 1),
      409,
      "key_version_mismatch",
    );
  });

  test("two concurrent approver calls: one stores, the other is 409 already_set", async () => {
    const { headers } = await person();
    const started = await start(headers);
    const results = await Promise.all([
      approver(headers, started.id, bytes(32, 1)),
      approver(headers, started.id, bytes(32, 2)),
    ]);
    expect(results.map((r) => r.status).sort()).toEqual([204, 409]);
    const lost = results.find((r) => r.status === 409);
    expect(((await lost?.json()) as { code: string }).code).toBe("already_set");
  });

  test("a seal on an expired request is 404", async () => {
    const { headers } = await person();
    await withKeys(headers, 1);
    const { started, fresh, eph } = await approved(headers);
    expect((await reveal(headers, started.id, toBase64Url(fresh.publicKey))).status).toBe(204);
    const real = clock;
    clock = new Date(real.getTime() + 11 * 60_000);
    try {
      const blob = toBase64Url(Buffer.concat([eph.publicKey, Buffer.alloc(48, 5)]));
      await expectProblem(await seal(headers, started.id, blob, 1), 404, "not_found");
    } finally {
      clock = real;
    }
  });

  test("a database failure logs no request bytes", async () => {
    const { headers } = await person();
    const marker = Buffer.from("MARKER-pairing-9d2e-do-not-log!!").toString("base64url");
    await t.admin.execute(sql`create or replace function fail_pairing_insert() returns trigger
      language plpgsql as $$ begin raise exception 'forced failure'; end $$`);
    await t.admin.execute(sql`create trigger fail_pairing before insert on pairing_requests
      for each row execute function fail_pairing_insert()`);
    const spies = (["log", "info", "warn", "error", "debug"] as const).map((level) =>
      vi.spyOn(console, level).mockImplementation(() => {}),
    );
    try {
      const res = await startRaw(headers, { commitment: marker });
      expect(res.status).toBe(500);
      const logged = JSON.stringify(spies.flatMap((spy) => spy.mock.calls));
      expect(logged).toContain("database query failed");
      expect(logged).not.toContain("MARKER-pairing");
      expect(logged).not.toContain(marker);
    } finally {
      vi.restoreAllMocks();
      await t.admin.execute(sql`drop trigger fail_pairing on pairing_requests`);
    }
  });

  test("assistant tokens get 403 on every route", async () => {
    const { email, headers } = await person();
    const started = await start(headers);
    for (const scope of ["finance:read", "finance:read finance:write"]) {
      const token = await t.authorize(email, { scope, headers });
      const h = bearer(token.accessToken);
      for (const res of [
        await startRaw(h, { commitment: bytes(32) }),
        await find(h, started.code),
        await approver(h, started.id, bytes(32)),
        await reveal(h, started.id, bytes(32)),
        await seal(h, started.id, bytes(100)),
        await take(h, started.id),
        await pickup(h, started.id),
      ]) {
        await expectProblem(res, 403, "insufficient_scope");
      }
    }
  });

  test("pairingCode is what the server hands out", () => {
    expect(pairingCode()).toHaveLength(8);
  });
});
