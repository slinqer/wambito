import { createHash, randomUUID } from "node:crypto";
import { newRecoverySecret, recoveryVerifier, verifierHash } from "@wambito/crypto";
import { deletedUsers, endedSessions, recoveryVerifiers, session, user } from "@wambito/db";
import { eq, sql } from "@wambito/db/orm";
import { afterAll, beforeAll, beforeEach, describe, expect, test } from "vitest";
import {
  purgeEndedSessions,
  recordDeletedUsers,
  recordEndedSessions,
  sha256,
} from "../src/services/ended.ts";
import {
  cleanupInactiveEncrypted,
  cleanupInactiveGuests,
  GUEST_CLEANUP_BATCH,
  GUEST_CLEANUP_LOCK,
  PROTECTED_IDLE_DAYS,
  UNPROTECTED_IDLE_DAYS,
} from "../src/services/guest-cleanup.ts";
import { createTestApp, type TestApp } from "./harness.ts";
import { createSoftPasskey } from "./soft-passkey.ts";

// The cleanup of encrypted users without an email (spec 2026-11-15 §10): idle 12 months (365 days)
// when nothing but the phone opens the account (no recovery verifier, no passkey wrap), else idle
// 24 months (730 days). A user with an email is never deleted for inactivity; plain guests stay on
// the 60-day cleanup, which leaves encrypted users alone.

type Auth = { userId: string; headers: { authorization: string } };
const PHONE = { "x-wambito-client": "android" };
const DAY = 24 * 60 * 60 * 1000;
const NOW = new Date("2027-12-01T12:00:00.000Z");
const daysAgo = (days: number) => new Date(NOW.getTime() - days * DAY);
const filled = (length: number, fill: number) => Buffer.alloc(length, fill).toString("base64url");
const b64 = (bytes: Uint8Array) => Buffer.from(bytes).toString("base64url");

let t: TestApp;
beforeAll(async () => {
  t = await createTestApp({ NEW_USERS_ENCRYPTED: true });
});
afterAll(() => t?.stop());

beforeEach(async () => {
  await t.admin.delete(user);
  await t.admin.delete(deletedUsers);
  await t.admin.delete(endedSessions);
});

/** An encrypted guest signed up from the phone, with its recovery wrap (every set-up account has one). */
async function guest(): Promise<Auth> {
  const res = await t.request("POST", "/auth/sign-in/anonymous", { body: {}, headers: PHONE });
  if (res.status !== 200) throw new Error(`guest failed: ${res.status} ${await res.text()}`);
  const json = (await res.json()) as { user: { id: string } };
  const auth = {
    userId: json.user.id,
    headers: { authorization: `Bearer ${res.headers.get("set-auth-token")}` },
  };
  await putWrap(auth, { kind: "recovery", ref: null, keyV: 1, wrapped: filled(48, 1) });
  return auth;
}

async function putWrap(auth: Auth, body: unknown) {
  const res = await t.request("PUT", `/v2/keys/${randomUUID()}`, { headers: auth.headers, body });
  expect(res.status, await res.clone().text()).toBe(200);
}

async function addVerifier(auth: Auth) {
  const v = await recoveryVerifier(newRecoverySecret());
  const res = await t.request("PUT", "/v2/recovery/verifier", {
    headers: auth.headers,
    body: {
      lookupHash: b64(await verifierHash(v.lookup)),
      authHash: b64(await verifierHash(v.auth)),
    },
  });
  expect(res.status).toBe(204);
}

async function addPasskeyWrap(auth: Auth) {
  const key = await createSoftPasskey(t.admin, auth.userId, "localhost");
  await putWrap(auth, { kind: "passkey", ref: key.credentialId, keyV: 1, wrapped: filled(60, 2) });
}

/** Makes the user, and its sessions, last active `days` days before NOW. */
async function lastActive(userId: string, days: number) {
  await t.admin
    .update(session)
    .set({ updatedAt: daysAgo(days) })
    .where(eq(session.userId, userId));
  await t.admin
    .update(user)
    .set({ lastActiveAt: daysAgo(days), createdAt: daysAgo(days + 10) })
    .where(eq(user.id, userId));
}

const exists = async (userId: string) =>
  (await t.admin.select({ id: user.id }).from(user).where(eq(user.id, userId))).length === 1;

/** Idle `days`, then one run of the encrypted cleanup: is the user still there? */
async function keptAfter(auth: Auth, days: number) {
  await lastActive(auth.userId, days);
  await cleanupInactiveEncrypted(t.db, NOW);
  return exists(auth.userId);
}

describe("cleanupInactiveEncrypted", () => {
  test("the tiers are 12 and 24 months in days", () => {
    expect(UNPROTECTED_IDLE_DAYS).toBe(365);
    expect(PROTECTED_IDLE_DAYS).toBe(730);
  });

  test("no verifier, no passkey wrap: kept at 364 days idle, deleted at 366", async () => {
    const g = await guest();
    expect(await keptAfter(g, 364)).toBe(true);
    await lastActive(g.userId, 366);
    expect(await cleanupInactiveEncrypted(t.db, NOW)).toBe(1);
    expect(await exists(g.userId)).toBe(false);
  });

  test("with a verifier: kept at 729 days, deleted at 731", async () => {
    const g = await guest();
    await addVerifier(g);
    expect(await keptAfter(g, 366)).toBe(true);
    expect(await keptAfter(g, 729)).toBe(true);
    expect(await keptAfter(g, 731)).toBe(false);
  });

  test("with a passkey wrap only: the same", async () => {
    const g = await guest();
    await addPasskeyWrap(g);
    expect(await keptAfter(g, 366)).toBe(true);
    expect(await keptAfter(g, 729)).toBe(true);
    expect(await keptAfter(g, 731)).toBe(false);
  });

  test("a passkey without a passkey wrap does not protect", async () => {
    const g = await guest();
    await createSoftPasskey(t.admin, g.userId, "localhost");
    expect(await keptAfter(g, 366)).toBe(false);
  });

  test("a hidden recovery wrap without a verifier counts as unprotected", async () => {
    // guest() already stored the recovery wrap; no verifier was ever sent.
    const g = await guest();
    expect(await keptAfter(g, 366)).toBe(false);
  });

  test("an encrypted user with an email is never deleted, however old", async () => {
    const member = await t.signIn("encrypted-old-timer@wambito.test");
    const [row] = await t.admin
      .select({ encryption: user.encryption })
      .from(user)
      .where(eq(user.id, member.userId));
    expect(row?.encryption).toBe("encrypted");
    await lastActive(member.userId, 5000);

    expect(await cleanupInactiveEncrypted(t.db, NOW)).toBe(0);
    expect(await exists(member.userId)).toBe(true);
  });

  test("a plain guest is left to the 60-day cleanup", async () => {
    const id = "plain-old-guest";
    await t.admin.insert(user).values({
      id,
      name: "Plain",
      email: `${id}@guest.wambito.invalid`,
      isAnonymous: true,
      encryption: "plain",
      createdAt: daysAgo(900),
      updatedAt: daysAgo(900),
    });
    expect(await cleanupInactiveEncrypted(t.db, NOW)).toBe(0);
    expect(await exists(id)).toBe(true);
  });

  test("an encrypted guest idle 61 days is not touched by the 60-day plain cleanup", async () => {
    const g = await guest();
    await lastActive(g.userId, 61);
    expect(await cleanupInactiveGuests(t.db, NOW)).toBe(0);
    expect(await exists(g.userId)).toBe(true);
  });

  test("each deleted user's SHA-256 id hash is in deleted_users", async () => {
    const gone = await Promise.all([guest(), guest()]);
    const kept = await guest();
    for (const g of gone) await lastActive(g.userId, 400);
    await lastActive(kept.userId, 10);

    expect(await cleanupInactiveEncrypted(t.db, NOW)).toBe(2);

    const hashes = (await t.admin.select().from(deletedUsers)).map((r) =>
      Buffer.from(r.userHash).toString("hex"),
    );
    const hashOf = (id: string) => createHash("sha256").update(id).digest("hex");
    expect(hashes.sort()).toEqual(gone.map((g) => hashOf(g.userId)).sort());
  });

  test("a protected candidate does not stop the walk: the batches move on by id", async () => {
    // A full batch of protected users idle 400 days (ids first in order), then one unprotected.
    const old = daysAgo(400);
    const ids = Array.from(
      { length: GUEST_CLEANUP_BATCH + 1 },
      (_, i) => `enc-${String(i).padStart(4, "0")}`,
    );
    const rows = ids.map((id) => ({
      id,
      name: id,
      email: `${id}@guest.wambito.invalid`,
      isAnonymous: true,
      encryption: "encrypted",
      createdAt: old,
      updatedAt: old,
    }));
    for (let i = 0; i < rows.length; i += 300)
      await t.admin.insert(user).values(rows.slice(i, i + 300));
    const verifiers = ids.slice(0, GUEST_CLEANUP_BATCH).map((id) => ({
      userId: id,
      lookupHash: sha256(`lookup-${id}`),
      authHash: sha256(`auth-${id}`),
    }));
    for (let i = 0; i < verifiers.length; i += 300) {
      await t.admin.insert(recoveryVerifiers).values(verifiers.slice(i, i + 300));
    }

    expect(await cleanupInactiveEncrypted(t.db, NOW)).toBe(1);
    expect(await exists(ids[GUEST_CLEANUP_BATCH] as string)).toBe(false);
    expect((await t.admin.select({ id: user.id }).from(user)).length).toBe(GUEST_CLEANUP_BATCH);
  });

  test("a run does nothing while another holds the advisory lock", async () => {
    const g = await guest();
    await lastActive(g.userId, 400);
    await t.admin.transaction(async (tx) => {
      await tx.execute(sql`select pg_advisory_xact_lock(${GUEST_CLEANUP_LOCK})`);
      expect(await cleanupInactiveEncrypted(t.db, NOW)).toBe(0);
    });
    expect(await exists(g.userId)).toBe(true);
    expect(await cleanupInactiveEncrypted(t.db, NOW)).toBe(1);
  });
});

describe("ended.ts", () => {
  test("sha256 is the SHA-256 of the text's UTF-8 bytes", () => {
    expect(sha256("abc").toString("hex")).toBe(
      "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
    );
  });

  test("recordDeletedUsers stores each hash once", async () => {
    await t.db.transaction((tx) => recordDeletedUsers(tx, ["a", "b"]));
    await t.db.transaction((tx) => recordDeletedUsers(tx, ["a"]));
    await t.db.transaction((tx) => recordDeletedUsers(tx, []));
    expect(await t.admin.select().from(deletedUsers)).toHaveLength(2);
  });

  test("recordEndedSessions stores each token's hash once, as device_removed", async () => {
    await t.db.transaction((tx) => recordEndedSessions(tx, ["tok-1", "tok-2"]));
    await t.db.transaction((tx) => recordEndedSessions(tx, ["tok-1"]));
    await t.db.transaction((tx) => recordEndedSessions(tx, []));
    const rows = await t.admin.select().from(endedSessions);
    expect(rows.map((r) => Buffer.from(r.sessionHash).toString("hex")).sort()).toEqual(
      [sha256("tok-1"), sha256("tok-2")].map((b) => b.toString("hex")).sort(),
    );
    expect(rows.every((r) => r.reason === "device_removed")).toBe(true);
  });

  test("purgeEndedSessions deletes rows older than 90 days only", async () => {
    await t.admin.insert(endedSessions).values([
      { sessionHash: sha256("old"), reason: "device_removed", endedAt: daysAgo(91) },
      { sessionHash: sha256("recent"), reason: "device_removed", endedAt: daysAgo(89) },
    ]);

    expect(await purgeEndedSessions(t.db, NOW)).toBe(1);

    const left = await t.admin.select().from(endedSessions);
    expect(left.map((r) => Buffer.from(r.sessionHash).toString("hex"))).toEqual([
      sha256("recent").toString("hex"),
    ]);
  });
});
