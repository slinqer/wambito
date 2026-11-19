import { randomUUID } from "node:crypto";
import {
  accounts,
  categories,
  categoryBudgets,
  idempotencyKeys,
  imports,
  keyWraps,
  merchantCategories,
  oauthConsent,
  recordPurges,
  records,
  recurrences,
  transactions,
  user,
} from "@wambito/db";
import { and, eq } from "@wambito/db/orm";
import { type MigrationSource, recordsFromSource, uuidv5 } from "@wambito/vault";
import { afterAll, afterEach, beforeAll, describe, expect, test, vi } from "vitest";
import type { SyncHooks } from "../src/deps.ts";
import { createTestApp, type TestApp } from "./harness.ts";

// The switch day (spec 2026-11-19 §2): `/v2/migration/*` moves a plain account's finances into
// end-to-end encrypted records. `start` binds the migration to one session, `source` hands that
// session the plaintext, `finish` deletes the plaintext only when the records hold as many of each
// type as the server does (and as the client says), and `cancel` drops the records to start over.

type Headers = { authorization: string };
type Counts = {
  transaction: number;
  deletedTransaction: number;
  category: number;
  budget: number;
  recurrence: number;
  merchant: number;
};
interface Source {
  profile: {
    timezone: string;
    locale: string;
    onboardingCompletedAt: string | null;
    currency: string;
  };
  categories: { id: string; name: string; archivedAt: string | null }[];
  budgets: { id: string; categoryId: string; amount: number; effectiveFrom: string }[];
  recurrences: { id: string; frequency: string; monthOfYear: number | null }[];
  transactions: {
    id: string;
    name: string;
    amount: number;
    date: string;
    status: string;
    source: string;
    recurrenceId: string | null;
    occurrenceMonth: string | null;
    deletedAt: string | null;
    createdAt: string;
    updatedAt: string;
  }[];
  merchants: { id: string; merchantKey: string; categoryId: string }[];
}

const hooks: SyncHooks = {};
let t: TestApp;
let people = 0;
beforeAll(async () => {
  t = await createTestApp({}, { syncHooks: hooks });
});
afterAll(() => t?.stop());
afterEach(() => {
  hooks.beforeCommit = undefined;
  t.config.MIGRATION_OPEN = false;
  t.config.MIGRATION_OPEN_USER_IDS = [];
  vi.restoreAllMocks();
});

const DAY = 24 * 60 * 60 * 1000;
const filled = (length: number, fill: number) => Buffer.alloc(length, fill).toString("base64url");
/** A sealed body as the test writes it: opaque bytes, at least a nonce and a tag. */
const body = () => filled(40, 7);

async function call(
  method: string,
  path: string,
  headers: Record<string, string>,
  payload?: unknown,
) {
  return t.request(method, path, { headers, ...(payload === undefined ? {} : { body: payload }) });
}

async function ok<T>(res: Response, status = 200): Promise<T> {
  expect(res.status, await res.clone().text()).toBe(status);
  return status === 204 ? (undefined as T) : ((await res.json()) as T);
}

/** A `/v1` seeding call: 200 or 201. */
async function seeded<T>(res: Response): Promise<T> {
  expect([200, 201], await res.clone().text()).toContain(res.status);
  return (await res.json()) as T;
}

async function problem(res: Response, status: number, code: string) {
  expect(res.status, await res.clone().text()).toBe(status);
  const json = (await res.json()) as { code: string; errors?: unknown };
  expect(json.code).toBe(code);
  return json;
}

/**
 * A plain account with an email holding every finance type, seeded through `/v1` (two categories,
 * a budget history, a yearly recurring payment, transactions, one deleted) plus direct rows for an
 * archived category with a transaction, a dismissed month, an old deleted transaction and a
 * merchant rule. The migration is opened to it by id.
 */
async function plainPerson() {
  const email = `migrate-${++people}@wambito.test`;
  const { userId, headers } = await t.signIn(email);
  t.config.MIGRATION_OPEN_USER_IDS = [...t.config.MIGRATION_OPEN_USER_IDS, userId];

  const food = await seeded<{ id: string }>(
    await call("POST", "/v1/categories", headers, {
      name: "Mercado",
      kind: "expense",
      icon: "cart",
      color: "green",
    }),
  );
  await seeded(
    await call("POST", "/v1/categories", headers, {
      name: "Sueldo",
      kind: "income",
      icon: "wallet",
      color: "blue",
    }),
  );
  await seeded(
    await call("PUT", `/v1/categories/${food.id}/budget`, headers, {
      amount: 40_000,
      effectiveFrom: "2026-08",
    }),
  );
  await seeded(
    await call("PUT", `/v1/categories/${food.id}/budget`, headers, {
      amount: 45_000,
      effectiveFrom: "2026-10",
    }),
  );
  const yearly = await seeded<{ id: string }>(
    await call("POST", "/v1/recurrences", headers, {
      name: "Seguro del carro",
      amount: -120_000,
      categoryId: food.id,
      frequency: "yearly",
      dayOfMonth: 5,
      monthOfYear: 3,
      startDate: "2027-03-05",
    }),
  );
  const kept = await seeded<{ id: string }>(
    await call("POST", "/v1/transactions", headers, {
      name: "Panaderia Las Brisas",
      amount: -3_500,
      categoryId: food.id,
      date: "2026-10-12",
    }),
  );
  const gone = await seeded<{ id: string }>(
    await call("POST", "/v1/transactions", headers, {
      name: "Heladeria borrada",
      amount: -2_000,
      categoryId: food.id,
      date: "2026-10-13",
    }),
  );
  await ok(await call("DELETE", `/v1/transactions/${gone.id}`, headers), 204);

  const [account] = await t.admin
    .select({ id: accounts.id })
    .from(accounts)
    .where(and(eq(accounts.userId, userId), eq(accounts.isDefault, true)));
  if (!account) throw new Error("no default account");
  const archivedId = randomUUID();
  await t.admin.insert(categories).values({
    id: archivedId,
    userId,
    name: "Gimnasio viejo",
    kind: "expense",
    icon: "dumbbell",
    color: "red",
    archivedAt: new Date("2026-09-01T00:00:00Z"),
  });
  const base = { userId, accountId: account.id, currency: "COP" };
  await t.admin.insert(transactions).values([
    {
      ...base,
      categoryId: archivedId,
      name: "Mensualidad gimnasio",
      amount: -9_000,
      date: "2026-08-02",
      source: "web",
    },
    {
      // A month of the yearly payment the person dismissed.
      ...base,
      categoryId: food.id,
      name: "Seguro del carro",
      amount: -120_000,
      date: "2028-03-05",
      status: "pending",
      source: "recurrence",
      recurrenceId: yearly.id,
      occurrenceMonth: "2028-03-01",
      deletedAt: new Date("2026-10-01T00:00:00Z"),
    },
    {
      // Deleted long ago: still in the source (the server has no restore window).
      ...base,
      categoryId: food.id,
      name: "Borrado hace mucho",
      amount: -1_000,
      date: "2024-01-02",
      source: "app",
      deletedAt: new Date(Date.now() - 700 * DAY),
    },
  ]);
  await t.admin
    .insert(merchantCategories)
    .values({ userId, merchantKey: "panaderia las brisas", categoryId: food.id });
  return { email, userId, headers, foodId: food.id, keptId: kept.id, goneId: gone.id };
}

/** What the server holds, counted straight from the tables (the expected `start` answer). */
async function tableCounts(userId: string): Promise<Counts> {
  const rows = await t.admin
    .select({ deletedAt: transactions.deletedAt })
    .from(transactions)
    .where(eq(transactions.userId, userId));
  const count = async (
    table:
      | typeof categories
      | typeof categoryBudgets
      | typeof recurrences
      | typeof merchantCategories,
  ) => (await t.admin.select({ id: table.id }).from(table).where(eq(table.userId, userId))).length;
  return {
    transaction: rows.filter((r) => r.deletedAt === null).length,
    deletedTransaction: rows.filter((r) => r.deletedAt !== null).length,
    category: await count(categories),
    budget: await count(categoryBudgets),
    recurrence: await count(recurrences),
    merchant: await count(merchantCategories),
  };
}

const start = (headers: Headers) => call("POST", "/v2/migration/start", headers);
const source = (headers: Headers) => call("GET", "/v2/migration/source", headers);
const finish = (headers: Headers, counts: Counts) =>
  call("POST", "/v2/migration/finish", headers, { counts });
const cancel = (headers: Headers) => call("POST", "/v2/migration/cancel", headers);

/** The recovery wrap the web writes first (the data key, opaque to the server). */
async function recoveryWrap(headers: Headers) {
  await ok(
    await call("PUT", `/v2/keys/${randomUUID()}`, headers, {
      kind: "recovery",
      ref: null,
      keyV: 1,
      wrapped: filled(48, 3),
    }),
  );
}

type Change = {
  id: string;
  type: string;
  baseVersion: null;
  deleted: boolean;
  keyV: number;
  encV: number;
  body: string | null;
};
const change = (type: string, deleted = false): Change => ({
  id: randomUUID(),
  type,
  baseVersion: null,
  deleted,
  keyV: 1,
  encV: 1,
  body: body(),
});

/**
 * The records the web makes from the source (`recordsFromSource` of `@wambito/vault`: the server
 * ids, the derived ids of the settings record, the dismissed months and the merchant rules), with
 * opaque bodies. `settings` is how many settings records (one by default).
 */
async function sourceChanges(
  p: { headers: Headers; userId: string },
  { settings = 1 }: { settings?: number } = {},
): Promise<Change[]> {
  const s = await ok<MigrationSource>(await source(p.headers));
  const made = await recordsFromSource(s, p.userId);
  const out: Change[] = made
    .filter((r) => r.type !== "settings" || settings > 0)
    .map((r) => ({ ...change(r.type, r.deleted), id: r.id }));
  for (let i = 1; i < settings; i++) out.push(change("settings"));
  return out;
}

async function push(headers: Headers, changes: Change[]) {
  const res = await call("POST", "/v2/sync", headers, { changes });
  const json = await ok<{ results: { version?: number; error?: string }[] }>(res);
  expect(json.results.every((r) => typeof r.version === "number")).toBe(true);
}

const userRow = async (userId: string) => {
  const [row] = await t.admin.select().from(user).where(eq(user.id, userId));
  if (!row) throw new Error("no user");
  return row;
};

const sessionIdOf = async (headers: Headers) => {
  const res = await call("GET", "/auth/get-session", headers);
  return ((await res.json()) as { session: { id: string } }).session.id;
};

/** Rows left in the eight plaintext tables for the user. */
async function plaintextLeft(userId: string): Promise<number> {
  const tables = [
    transactions,
    categories,
    categoryBudgets,
    recurrences,
    merchantCategories,
    accounts,
    imports,
  ] as const;
  let n = 0;
  for (const table of tables) {
    n += (await t.admin.select().from(table).where(eq(table.userId, userId))).length;
  }
  n += (await t.admin.select().from(idempotencyKeys).where(eq(idempotencyKeys.userId, userId)))
    .length;
  return n;
}

describe("POST /v2/migration/start", () => {
  test("sets migrating, binds the session and answers the server's counts; a retry answers the same", async () => {
    const p = await plainPerson();
    const counts = await ok<Counts>(await start(p.headers));
    expect(counts).toEqual(await tableCounts(p.userId));
    expect(counts).toMatchObject({ category: 3, budget: 2, recurrence: 1, merchant: 1 });
    // The deleted one from /v1, the dismissed month and the old deleted one.
    expect(counts.deletedTransaction).toBe(3);

    const row = await userRow(p.userId);
    expect(row.encryption).toBe("migrating");
    expect(row.migrationSessionId).toBe(await sessionIdOf(p.headers));

    expect(await ok<Counts>(await start(p.headers))).toEqual(counts);
    const me = await ok<{ migration?: string }>(await call("GET", "/v1/me", p.headers));
    expect(me.migration).toBe("in_progress");
  });

  test("another session takes it over; the first session's push is then refused", async () => {
    const p = await plainPerson();
    const counts = await ok<Counts>(await start(p.headers));
    const second = await t.signIn(p.email);
    expect(await ok<Counts>(await start(second.headers))).toEqual(counts);
    expect((await userRow(p.userId)).migrationSessionId).toBe(await sessionIdOf(second.headers));

    await problem(
      await call("POST", "/v2/sync", p.headers, { changes: [change("settings")] }),
      409,
      "migration_in_progress",
    );
    await push(second.headers, [change("settings")]);
  });

  test("a guest, an encrypted account or a closed gate is not migratable", async () => {
    const guestRes = await t.request("POST", "/auth/sign-in/anonymous", { body: {} });
    const guest = { authorization: `Bearer ${guestRes.headers.get("set-auth-token")}` };
    t.config.MIGRATION_OPEN = true;
    await problem(await start(guest), 409, "not_migratable");

    const encrypted = await t.signIn(`migrate-enc-${++people}@wambito.test`);
    await t.admin
      .update(user)
      .set({ encryption: "encrypted" })
      .where(eq(user.id, encrypted.userId));
    await problem(await start(encrypted.headers), 409, "not_migratable");

    t.config.MIGRATION_OPEN = false;
    const closed = await t.signIn(`migrate-closed-${++people}@wambito.test`);
    await problem(await start(closed.headers), 409, "not_migratable");
    expect((await userRow(closed.userId)).encryption).toBe("plain");
  });

  test("an assistant cannot start it", async () => {
    const p = await plainPerson();
    const { accessToken } = await t.authorize(p.email, { headers: p.headers });
    await problem(
      await start({ authorization: `Bearer ${accessToken}` }),
      403,
      "insufficient_scope",
    );
  });
});

describe("GET /v2/migration/source", () => {
  test("holds every type, every deleted transaction of any age and the dismissed month", async () => {
    const p = await plainPerson();
    const counts = await ok<Counts>(await start(p.headers));
    const s = await ok<Source>(await source(p.headers));

    expect(s.profile).toMatchObject({ timezone: expect.any(String), locale: expect.any(String) });
    const [account] = await t.admin
      .select({ currency: accounts.currency })
      .from(accounts)
      .where(and(eq(accounts.userId, p.userId), eq(accounts.isDefault, true)));
    expect(s.profile.currency).toBe(account?.currency);

    expect(s.categories).toHaveLength(counts.category);
    expect(s.categories.find((c) => c.name === "Gimnasio viejo")?.archivedAt).toBe(
      "2026-09-01T00:00:00.000Z",
    );
    expect(s.budgets.map((b) => [b.effectiveFrom, b.amount]).sort()).toEqual([
      ["2026-08-01", 40_000],
      ["2026-10-01", 45_000],
    ]);
    expect(s.recurrences).toEqual([
      expect.objectContaining({ frequency: "yearly", monthOfYear: 3 }),
    ]);
    expect(s.merchants).toEqual([
      expect.objectContaining({ merchantKey: "panaderia las brisas", categoryId: p.foodId }),
    ]);

    const live = s.transactions.filter((x) => x.deletedAt === null);
    const deleted = s.transactions.filter((x) => x.deletedAt !== null);
    expect(live).toHaveLength(counts.transaction);
    expect(deleted).toHaveLength(counts.deletedTransaction);
    expect(live.find((x) => x.id === p.keptId)).toMatchObject({
      name: "Panaderia Las Brisas",
      amount: -3_500,
      date: "2026-10-12",
      status: "paid",
    });
    expect(deleted.map((x) => x.name).sort()).toEqual([
      "Borrado hace mucho",
      "Heladeria borrada",
      "Seguro del carro",
    ]);
    expect(deleted.find((x) => x.status === "pending")).toMatchObject({
      source: "recurrence",
      occurrenceMonth: "2028-03-01",
    });
    for (const x of s.transactions) {
      expect(x.createdAt).toMatch(/^\d{4}-\d\d-\d\dT.*Z$/);
      expect(x.updatedAt).toMatch(/^\d{4}-\d\d-\d\dT.*Z$/);
    }
  });

  test("is refused to another session, to an assistant and before start", async () => {
    const p = await plainPerson();
    await problem(await source(p.headers), 409, "not_migrating");
    const { accessToken } = await t.authorize(p.email, { headers: p.headers });
    await ok(await start(p.headers));
    const other = await t.signIn(p.email);
    await problem(await source(other.headers), 409, "migration_in_progress");
    await problem(
      await source({ authorization: `Bearer ${accessToken}` }),
      403,
      "insufficient_scope",
    );
  });

  test("the source answer is never logged", async () => {
    const p = await plainPerson();
    const logged: string[] = [];
    const capture = (...args: unknown[]) => {
      logged.push(args.map((a) => (typeof a === "string" ? a : JSON.stringify(a))).join(" "));
    };
    for (const level of ["log", "info", "warn", "error", "debug"] as const) {
      vi.spyOn(console, level).mockImplementation(capture);
    }
    await ok(await start(p.headers));
    const s = await ok<Source>(await source(p.headers));
    expect(s.transactions.some((x) => x.name === "Panaderia Las Brisas")).toBe(true);
    expect(logged.join("\n")).not.toContain("Panaderia");
    expect(logged.join("\n")).not.toContain("Mercado");
  });
});

describe("POST /v2/migration/finish", () => {
  test("with records matching every count, deletes the plaintext, revokes assistants and sets encrypted", async () => {
    const p = await plainPerson();
    await t.authorize(p.email, { headers: p.headers });
    const counts = await ok<Counts>(await start(p.headers));
    await recoveryWrap(p.headers);
    await push(p.headers, await sourceChanges(p));

    const profile = await ok<{ encryption: string; migration?: string }>(
      await finish(p.headers, counts),
    );
    expect(profile.encryption).toBe("preview");
    expect(profile.migration).toBeUndefined();

    expect(await plaintextLeft(p.userId)).toBe(0);
    expect(
      await t.admin.select().from(oauthConsent).where(eq(oauthConsent.userId, p.userId)),
    ).toEqual([]);
    const row = await userRow(p.userId);
    expect(row.encryption).toBe("encrypted");
    expect(row.migrationSessionId).toBeNull();
    // The profile columns stay.
    expect(row.timezone).toBeTruthy();
    const me = await ok<{ migration?: string; encryption: string }>(
      await call("GET", "/v1/me", p.headers),
    );
    expect(me.migration).toBeUndefined();
    expect(me.encryption).toBe("preview");
    // The key wraps and records stay.
    expect(
      (await t.admin.select().from(keyWraps).where(eq(keyWraps.userId, p.userId))).length,
    ).toBe(1);
  });

  test("one record short is a count mismatch that changes nothing", async () => {
    const p = await plainPerson();
    const counts = await ok<Counts>(await start(p.headers));
    await recoveryWrap(p.headers);
    const changes = (await sourceChanges(p)).filter((c) => c.type !== "merchant");
    await push(p.headers, changes);
    const before = await plaintextLeft(p.userId);

    const json = await problem(await finish(p.headers, counts), 409, "count_mismatch");
    expect(json.errors).toEqual({
      server: counts,
      records: { ...counts, merchant: counts.merchant - 1 },
      client: counts,
      missing: [{ type: "merchant", id: expect.any(String) }],
    });
    expect(await plaintextLeft(p.userId)).toBe(before);
    expect((await userRow(p.userId)).encryption).toBe("migrating");
  });

  test("the client's counts must match too", async () => {
    const p = await plainPerson();
    const counts = await ok<Counts>(await start(p.headers));
    await recoveryWrap(p.headers);
    await push(p.headers, await sourceChanges(p));
    await problem(
      await finish(p.headers, { ...counts, budget: counts.budget + 1 }),
      409,
      "count_mismatch",
    );
    expect((await userRow(p.userId)).encryption).toBe("migrating");
  });

  test("no settings record, or two, is a count mismatch", async () => {
    const none = await plainPerson();
    const counts = await ok<Counts>(await start(none.headers));
    await recoveryWrap(none.headers);
    await push(none.headers, await sourceChanges(none, { settings: 0 }));
    await problem(await finish(none.headers, counts), 409, "count_mismatch");

    const two = await plainPerson();
    const twoCounts = await ok<Counts>(await start(two.headers));
    await recoveryWrap(two.headers);
    await push(two.headers, await sourceChanges(two, { settings: 2 }));
    await problem(await finish(two.headers, twoCounts), 409, "count_mismatch");
    expect((await userRow(two.userId)).encryption).toBe("migrating");
  });

  test("is refused without a data key, to another session and before start", async () => {
    const p = await plainPerson();
    const counts = await tableCounts(p.userId);
    await problem(await finish(p.headers, counts), 409, "not_migrating");
    await ok(await start(p.headers));
    await push(p.headers, await sourceChanges(p));
    await problem(await finish(p.headers, counts), 409, "keys_missing");
    const other = await t.signIn(p.email);
    await problem(await finish(other.headers, counts), 409, "migration_in_progress");
    expect((await userRow(p.userId)).encryption).toBe("migrating");
  });

  test("one missing record hidden by a stray one of the same type is refused", async () => {
    const p = await plainPerson();
    const counts = await ok<Counts>(await start(p.headers));
    await recoveryWrap(p.headers);
    const changes = await sourceChanges(p);
    const category = changes.find((c) => c.type === "category") as Change;
    const missingId = category.id;
    category.id = randomUUID();
    await push(p.headers, changes);
    const before = await plaintextLeft(p.userId);

    const json = await problem(await finish(p.headers, counts), 409, "count_mismatch");
    expect(json.errors).toEqual({
      server: counts,
      records: counts,
      client: counts,
      missing: [{ type: "category", id: missingId }],
    });
    expect(await plaintextLeft(p.userId)).toBe(before);
    expect((await userRow(p.userId)).encryption).toBe("migrating");
  });

  test("a dismissed month under its server id instead of the derived id is refused", async () => {
    const p = await plainPerson();
    const counts = await ok<Counts>(await start(p.headers));
    await recoveryWrap(p.headers);
    const s = await ok<MigrationSource>(await source(p.headers));
    const dismissal = s.transactions.find((x) => x.deletedAt !== null && x.status === "pending");
    if (!dismissal?.recurrenceId || !dismissal.occurrenceMonth) throw new Error("no dismissal");
    const derived = await uuidv5(
      dismissal.recurrenceId,
      `${dismissal.occurrenceMonth.slice(0, 7)}:0`,
    );
    const changes = await sourceChanges(p);
    const record = changes.find((c) => c.id === derived) as Change;
    record.id = dismissal.id;
    await push(p.headers, changes);

    const json = await problem(await finish(p.headers, counts), 409, "count_mismatch");
    expect((json.errors as { missing: unknown }).missing).toEqual([
      { type: "transaction", id: derived },
    ]);
    expect((await userRow(p.userId)).encryption).toBe("migrating");
  });

  test("a deleted transaction pushed live, and a live one pushed deleted, are refused", async () => {
    const p = await plainPerson();
    const counts = await ok<Counts>(await start(p.headers));
    await recoveryWrap(p.headers);
    const changes = await sourceChanges(p);
    const gone = changes.find((c) => c.id === p.goneId) as Change;
    const kept = changes.find((c) => c.id === p.keptId) as Change;
    gone.deleted = false;
    kept.deleted = true;
    await push(p.headers, changes);
    const json = await problem(await finish(p.headers, counts), 409, "count_mismatch");
    expect((json.errors as { missing: unknown[] }).missing).toEqual(
      expect.arrayContaining([
        { type: "transaction", id: p.goneId },
        { type: "transaction", id: p.keptId },
      ]),
    );
  });

  test("a push that commits while finish waits on the lock is counted", async () => {
    const p = await plainPerson();
    const counts = await ok<Counts>(await start(p.headers));
    await recoveryWrap(p.headers);
    const changes = await sourceChanges(p);
    const last = changes.pop() as Change;
    await push(p.headers, changes);

    let release!: () => void;
    let held!: () => void;
    const holding = new Promise<void>((resolve) => {
      held = resolve;
    });
    hooks.beforeCommit = () =>
      new Promise<void>((resolve) => {
        release = resolve;
        held();
      });
    const pushing = call("POST", "/v2/sync", p.headers, { changes: [last] });
    await holding;
    hooks.beforeCommit = undefined;
    const finishing = finish(p.headers, counts);
    // finish is waiting on the records lock the push holds.
    await new Promise((resolve) => setTimeout(resolve, 200));
    release();
    await ok(await pushing);
    await ok(await finishing);
    expect(await plaintextLeft(p.userId)).toBe(0);
  });

  test("a push that commits while finish waits, past the counts, gives a mismatch and deletes nothing", async () => {
    const p = await plainPerson();
    const counts = await ok<Counts>(await start(p.headers));
    await recoveryWrap(p.headers);
    await push(p.headers, await sourceChanges(p));

    let release!: () => void;
    let held!: () => void;
    const holding = new Promise<void>((resolve) => {
      held = resolve;
    });
    hooks.beforeCommit = () =>
      new Promise<void>((resolve) => {
        release = resolve;
        held();
      });
    const pushing = call("POST", "/v2/sync", p.headers, { changes: [change("category")] });
    await holding;
    hooks.beforeCommit = undefined;
    const finishing = finish(p.headers, counts);
    await new Promise((resolve) => setTimeout(resolve, 200));
    release();
    await ok(await pushing);
    await problem(await finishing, 409, "count_mismatch");
    expect(await plaintextLeft(p.userId)).toBeGreaterThan(0);
  });
});

describe("POST /v2/migration/cancel", () => {
  test("deletes the records and purge rows, keeps the key wraps, sets plain and clears the session", async () => {
    const p = await plainPerson();
    const counts = await ok<Counts>(await start(p.headers));
    await recoveryWrap(p.headers);
    await push(p.headers, await sourceChanges(p));
    await t.admin.insert(recordPurges).values({ userId: p.userId, throughVersion: 1 });
    const plain = await plaintextLeft(p.userId);

    await ok(await cancel(p.headers), 204);
    expect(await t.admin.select().from(records).where(eq(records.userId, p.userId))).toEqual([]);
    expect(
      await t.admin.select().from(recordPurges).where(eq(recordPurges.userId, p.userId)),
    ).toEqual([]);
    expect(
      (await t.admin.select().from(keyWraps).where(eq(keyWraps.userId, p.userId))).length,
    ).toBe(1);
    expect(await plaintextLeft(p.userId)).toBe(plain);
    const row = await userRow(p.userId);
    expect(row.encryption).toBe("plain");
    expect(row.migrationSessionId).toBeNull();
    // It can start again.
    expect(await ok<Counts>(await start(p.headers))).toEqual(counts);
  });

  test("is refused to another session and to an account that is not migrating", async () => {
    const p = await plainPerson();
    await problem(await cancel(p.headers), 409, "not_migrating");
    await ok(await start(p.headers));
    const other = await t.signIn(p.email);
    await problem(await cancel(other.headers), 409, "migration_in_progress");
  });
});

describe("the write rule while migrating", () => {
  test("another session's key, pairing and recovery writes are refused; the bound session's pass", async () => {
    const p = await plainPerson();
    await ok(await start(p.headers));
    const other = await t.signIn(p.email);
    const wrap = { kind: "recovery", ref: null, keyV: 1, wrapped: filled(48, 3) };
    await problem(
      await call("PUT", `/v2/keys/${randomUUID()}`, other.headers, wrap),
      409,
      "migration_in_progress",
    );
    await problem(
      await call("DELETE", `/v2/keys/${randomUUID()}`, other.headers),
      409,
      "migration_in_progress",
    );
    await problem(
      await call("POST", "/v2/keys/rotate", other.headers, {}),
      409,
      "migration_in_progress",
    );
    await problem(
      await call("POST", "/v2/pairing", other.headers, { commitment: filled(32, 1) }),
      409,
      "migration_in_progress",
    );
    await problem(
      await call("PUT", "/v2/recovery/verifier", other.headers, {
        lookupHash: filled(32, 1),
        authHash: filled(32, 2),
      }),
      409,
      "migration_in_progress",
    );
    // Reads stay open to every session.
    await ok(await call("GET", "/v2/keys", other.headers));
    await ok(await call("GET", "/v2/sync?since=0", other.headers));
    await ok(await call("PUT", `/v2/keys/${randomUUID()}`, p.headers, wrap));
  });

  test("an encrypted account's other sessions are unaffected", async () => {
    const p = await plainPerson();
    await t.admin
      .update(user)
      .set({ encryption: "encrypted", migrationSessionId: "someone-else" })
      .where(eq(user.id, p.userId));
    await push(p.headers, [change("settings")]);
  });
});
