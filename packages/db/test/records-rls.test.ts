import { eq, sql } from "drizzle-orm";
import { afterAll, beforeAll, describe, expect, test } from "vitest";
import {
  createDb,
  type Db,
  keyWraps,
  pairingRequests,
  records,
  user,
  withUser,
} from "../src/index.ts";
import { startTestDatabase } from "../src/testing.ts";

let stop: () => Promise<void>;
let admin: { db: Db; close(): Promise<void> };
let app: { db: Db; close(): Promise<void> };

const A = "11111111-1111-4111-8111-111111111111";
const B = "22222222-2222-4222-8222-222222222222";
const bytes = (...n: number[]) => new Uint8Array(n);

const record = (userId: string, id: string) => ({
  id,
  userId,
  type: "transaction",
  keyV: 1,
  encV: 1,
  body: bytes(1, 2, 3),
});
const wrap = (userId: string, id: string) => ({
  id,
  userId,
  kind: "device",
  ref: `device-${id}`,
  keyV: 1,
  wrapped: bytes(9, 9),
});
const pairing = (userId: string, id: string) => ({
  id,
  userId,
  code: `code-${id}`,
  publicKey: bytes(7),
  expiresAt: new Date(Date.now() + 60_000),
});

const rlsError = async (p: Promise<unknown>) => {
  const e = (await p.catch((x: Error) => x)) as Error;
  return String(e.cause ?? e);
};

beforeAll(async () => {
  const database = await startTestDatabase();
  stop = database.stop;
  admin = createDb(database.adminUrl);
  app = createDb(database.appUrl);
  await admin.db.insert(user).values([
    { id: "user-a", name: "A", email: "a@wambito.test" },
    { id: "user-b", name: "B", email: "b@wambito.test" },
  ]);
  await withUser(app.db, "user-b", async (tx) => {
    await tx.insert(records).values(record("user-b", B));
    await tx.insert(keyWraps).values(wrap("user-b", B));
    await tx.insert(pairingRequests).values(pairing("user-b", B));
  });
}, 120_000);

afterAll(async () => {
  await app?.close();
  await admin?.close();
  await stop?.();
});

describe.each([
  ["records", records],
  ["key_wraps", keyWraps],
  ["pairing_requests", pairingRequests],
] as const)("%s row-level security", (_name, table) => {
  test("user A cannot see, update or delete B's rows", async () => {
    expect(await withUser(app.db, "user-a", (tx) => tx.select().from(table))).toEqual([]);
    const updated = await withUser(app.db, "user-a", (tx) =>
      tx.update(table).set({ userId: "user-a" }).where(eq(table.id, B)).returning(),
    ).catch(() => []);
    expect(updated).toEqual([]);
    const deleted = await withUser(app.db, "user-a", (tx) =>
      tx.delete(table).where(eq(table.id, B)).returning(),
    );
    expect(deleted).toEqual([]);
    expect(await withUser(app.db, "user-b", (tx) => tx.select().from(table))).toHaveLength(1);
  });
});

describe("inserting for someone else", () => {
  test("records", async () => {
    const e = await rlsError(
      withUser(app.db, "user-a", (tx) => tx.insert(records).values(record("user-b", A))),
    );
    expect(e).toMatch(/row-level security/);
  });
  test("key_wraps", async () => {
    const e = await rlsError(
      withUser(app.db, "user-a", (tx) => tx.insert(keyWraps).values(wrap("user-b", A))),
    );
    expect(e).toMatch(/row-level security/);
  });
  test("pairing_requests", async () => {
    const e = await rlsError(
      withUser(app.db, "user-a", (tx) => tx.insert(pairingRequests).values(pairing("user-b", A))),
    );
    expect(e).toMatch(/row-level security/);
  });
});

describe("records", () => {
  test("bytea round-trips as a plain Uint8Array", async () => {
    const [row] = await withUser(app.db, "user-b", (tx) =>
      tx.select().from(records).where(eq(records.id, B)),
    );
    expect(row?.body).toBeInstanceOf(Uint8Array);
    expect(Buffer.isBuffer(row?.body)).toBe(false);
    expect(Array.from(row?.body ?? [])).toEqual([1, 2, 3]);
  });

  test("version grows across inserts and updates", async () => {
    const id1 = "33333333-3333-4333-8333-333333333333";
    const id2 = "44444444-4444-4444-8444-444444444444";
    const [r1] = await withUser(app.db, "user-a", (tx) =>
      tx.insert(records).values(record("user-a", id1)).returning(),
    );
    const [r2] = await withUser(app.db, "user-a", (tx) =>
      tx.insert(records).values(record("user-a", id2)).returning(),
    );
    expect(r2?.version).toBeGreaterThan(r1?.version ?? 0);
    const [r1b] = await withUser(app.db, "user-a", (tx) =>
      tx
        .update(records)
        .set({ version: sql`nextval('records_version_seq')` })
        .where(eq(records.id, id1))
        .returning(),
    );
    expect(r1b?.version).toBeGreaterThan(r2?.version ?? 0);
  });

  test("deleted must match a null body", async () => {
    const id = "55555555-5555-4555-8555-555555555555";
    const bad = await rlsError(
      withUser(app.db, "user-a", (tx) =>
        tx.insert(records).values({ ...record("user-a", id), deleted: true }),
      ),
    );
    expect(bad).toMatch(/check constraint/);
    const bad2 = await rlsError(
      withUser(app.db, "user-a", (tx) =>
        tx.insert(records).values({ ...record("user-a", id), body: null }),
      ),
    );
    expect(bad2).toMatch(/check constraint/);
    await withUser(app.db, "user-a", (tx) =>
      tx.insert(records).values({ ...record("user-a", id), deleted: true, body: null }),
    );
  });
});

describe("key_wraps", () => {
  test("rejects unknown kinds and a second recovery wrap", async () => {
    const bad = await rlsError(
      withUser(app.db, "user-a", (tx) =>
        tx
          .insert(keyWraps)
          .values({ ...wrap("user-a", "66666666-6666-4666-8666-666666666666"), kind: "other" }),
      ),
    );
    expect(bad).toMatch(/check constraint/);
    const rec = (id: string) => ({ ...wrap("user-a", id), kind: "recovery", ref: null });
    await withUser(app.db, "user-a", (tx) =>
      tx.insert(keyWraps).values(rec("77777777-7777-4777-8777-777777777777")),
    );
    const dup = await rlsError(
      withUser(app.db, "user-a", (tx) =>
        tx.insert(keyWraps).values(rec("88888888-8888-4888-8888-888888888888")),
      ),
    );
    expect(dup).toMatch(/duplicate key/);
  });
});
