import {
  accounts,
  categories,
  categoryBudgets,
  type Db,
  idempotencyKeys,
  imports,
  keyLinks,
  keyWraps,
  merchantCategories,
  recordPurges,
  records,
  recurrences,
  type Tx,
  transactions,
  user,
  withUser,
} from "@wambito/db";
import { and, asc, eq, sql } from "@wambito/db/orm";
import { merchantRecordId, uuidv5 } from "@wambito/vault";
import type { Config } from "../config.ts";
import { ApiError } from "../http/problem.ts";
import { revokeAllAssistants } from "./account.ts";
import { migrationOf, toEncryption } from "./encryption.ts";
import { currentKeyV, lockWraps } from "./keys.ts";
import { lockRecords } from "./sync.ts";

/**
 * The switch day (spec 2026-11-19 §2): a plain account's finances move into end-to-end encrypted
 * records, made by the web from `migrationSource`. The plaintext is deleted only by
 * `finishMigration`, under the records and wraps locks, once the records hold as many of each
 * type as the server does and as the client says. Nothing here logs a row.
 */

/**
 * Per type, what the server holds and what the records hold: live rows, and the soft-deleted
 * transactions apart (every one the server still has, dismissed months among them; a record:
 * deleted with a body). The shape of `MigrationCounts` in `@wambito/vault`.
 */
export interface MigrationCounts {
  transaction: number;
  deletedTransaction: number;
  category: number;
  budget: number;
  recurrence: number;
  merchant: number;
}

const COUNT_KEYS = [
  "transaction",
  "deletedTransaction",
  "category",
  "budget",
  "recurrence",
  "merchant",
] as const satisfies readonly (keyof MigrationCounts)[];

const sameCounts = (a: MigrationCounts, b: MigrationCounts) =>
  COUNT_KEYS.every((key) => a[key] === b[key]);

const notMigrating = () =>
  new ApiError(409, "not_migrating", "This account is not moving to end-to-end encryption");
export const migrationInProgress = () =>
  new ApiError(
    409,
    "migration_in_progress",
    "Another session is moving this account to end-to-end encryption",
  );

const iso = (at: Date | null) => at?.toISOString() ?? null;

async function userState(tx: Tx, userId: string, { lock = false } = {}) {
  const query = tx
    .select({
      encryption: user.encryption,
      migrationSessionId: user.migrationSessionId,
      isAnonymous: user.isAnonymous,
      timezone: user.timezone,
      locale: user.locale,
      onboardingCompletedAt: user.onboardingCompletedAt,
    })
    .from(user)
    .where(eq(user.id, userId));
  const [row] = await (lock ? query.for("update") : query);
  if (!row) throw new ApiError(401, "unauthenticated", "Sign in to continue");
  return { ...row, encryption: toEncryption(row.encryption), isAnonymous: !!row.isAnonymous };
}

/** A migrating account, called from the session bound to the migration; else 409. */
function requireBound(
  state: { encryption: string; migrationSessionId: string | null },
  sessionId: string | null,
) {
  if (state.encryption !== "migrating") throw notMigrating();
  if (sessionId === null || state.migrationSessionId !== sessionId) throw migrationInProgress();
}

const countOf = async (query: Promise<{ n: string }[]>) => Number((await query)[0]?.n ?? 0);

/** What the plaintext tables hold for the user (inside `withUser`). */
export async function serverCounts(tx: Tx, userId: string): Promise<MigrationCounts> {
  const [moves] = await tx
    .select({
      live: sql<string>`count(*) filter (where ${transactions.deletedAt} is null)`,
      deleted: sql<string>`count(*) filter (where ${transactions.deletedAt} is not null)`,
    })
    .from(transactions)
    .where(eq(transactions.userId, userId));
  const n = sql<string>`count(*)`;
  return {
    transaction: Number(moves?.live ?? 0),
    deletedTransaction: Number(moves?.deleted ?? 0),
    category: await countOf(tx.select({ n }).from(categories).where(eq(categories.userId, userId))),
    budget: await countOf(
      tx.select({ n }).from(categoryBudgets).where(eq(categoryBudgets.userId, userId)),
    ),
    recurrence: await countOf(
      tx.select({ n }).from(recurrences).where(eq(recurrences.userId, userId)),
    ),
    merchant: await countOf(
      tx.select({ n }).from(merchantCategories).where(eq(merchantCategories.userId, userId)),
    ),
  };
}

/**
 * What the records hold: live records per type, deleted `transaction` records that keep a body
 * apart, and the live `settings` records (exactly one is expected). Other types are not counted.
 */
async function recordCounts(
  tx: Tx,
  userId: string,
): Promise<{ counts: MigrationCounts; settings: number }> {
  const rows = await tx
    .select({
      type: records.type,
      deleted: records.deleted,
      withBody: sql<boolean>`${records.body} is not null`,
      n: sql<string>`count(*)`,
    })
    .from(records)
    .where(eq(records.userId, userId))
    .groupBy(records.type, records.deleted, sql`${records.body} is not null`);
  const counts: MigrationCounts = {
    transaction: 0,
    deletedTransaction: 0,
    category: 0,
    budget: 0,
    recurrence: 0,
    merchant: 0,
  };
  let settings = 0;
  for (const row of rows) {
    const n = Number(row.n);
    if (row.type === "transaction" && row.deleted) {
      if (row.withBody) counts.deletedTransaction += n;
    } else if (!row.deleted) {
      if (row.type === "settings") settings += n;
      else if (row.type === "transaction") counts.transaction += n;
      else if (row.type === "category") counts.category += n;
      else if (row.type === "budget") counts.budget += n;
      else if (row.type === "recurrence") counts.recurrence += n;
      else if (row.type === "merchant") counts.merchant += n;
    }
  }
  return { counts, settings };
}

/** At most this many missing records are named in a `count_mismatch`. */
const MAX_MISSING = 20;

/** A soft-deleted month of a recurring payment the person dismissed. */
const isDismissal = (t: {
  deletedAt: Date | null;
  status: string;
  source: string;
  recurrenceId: string | null;
  occurrenceMonth: string | null;
}) =>
  t.deletedAt !== null &&
  t.status === "pending" &&
  t.source === "recurrence" &&
  t.recurrenceId !== null &&
  t.occurrenceMonth !== null;

/**
 * The plaintext rows that have no record of their own, by id: counts alone would let a missing
 * record hide behind a stray one of the same type. Every row must be a record of its type, under
 * the id `recordsFromSource` of `@wambito/vault` gives it (the server id; the derived id for a
 * dismissed month and a merchant rule), live, or deleted with a body for a soft-deleted
 * transaction. Inside `finish`'s transaction, under its locks.
 */
async function missingRecords(tx: Tx, userId: string): Promise<{ type: string; id: string }[]> {
  const held = new Map<string, { type: string; deleted: boolean; withBody: boolean }>();
  const rows = await tx
    .select({
      id: records.id,
      type: records.type,
      deleted: records.deleted,
      withBody: sql<boolean>`${records.body} is not null`,
    })
    .from(records)
    .where(eq(records.userId, userId));
  for (const row of rows) held.set(row.id, row);

  const missing: { type: string; id: string }[] = [];
  const expect = (type: string, id: string, deleted: boolean) => {
    const record = held.get(id);
    const ok =
      record !== undefined &&
      record.type === type &&
      record.deleted === deleted &&
      (!deleted || record.withBody);
    if (!ok) missing.push({ type, id });
  };

  for (const { id } of await tx
    .select({ id: categories.id })
    .from(categories)
    .where(eq(categories.userId, userId)))
    expect("category", id, false);
  for (const { id } of await tx
    .select({ id: categoryBudgets.id })
    .from(categoryBudgets)
    .where(eq(categoryBudgets.userId, userId)))
    expect("budget", id, false);
  for (const { id } of await tx
    .select({ id: recurrences.id })
    .from(recurrences)
    .where(eq(recurrences.userId, userId)))
    expect("recurrence", id, false);
  for (const { merchantKey } of await tx
    .select({ merchantKey: merchantCategories.merchantKey })
    .from(merchantCategories)
    .where(eq(merchantCategories.userId, userId)))
    expect("merchant", await merchantRecordId(userId, merchantKey), false);
  for (const t of await tx
    .select({
      id: transactions.id,
      deletedAt: transactions.deletedAt,
      status: transactions.status,
      source: transactions.source,
      recurrenceId: transactions.recurrenceId,
      occurrenceMonth: transactions.occurrenceMonth,
    })
    .from(transactions)
    .where(eq(transactions.userId, userId))) {
    const id =
      isDismissal(t) && t.recurrenceId && t.occurrenceMonth
        ? await uuidv5(t.recurrenceId, `${t.occurrenceMonth.slice(0, 7)}:0`)
        : t.id;
    expect("transaction", id, t.deletedAt !== null);
  }
  return missing;
}

/**
 * Starts the migration, or takes it over: a `plain` account with an email that the gate lets in
 * (`migrationOf` is `available`) becomes `migrating`, bound to `sessionId`; a `migrating` one is
 * bound to `sessionId` instead (a lost tab or a new sign-in resumes). Takes the records and wraps
 * locks, so a write of the session it takes over from is either committed before it or refused
 * after it. Answers the server's counts.
 */
export async function startMigration(
  db: Db,
  config: Pick<Config, "MIGRATION_OPEN" | "MIGRATION_OPEN_USER_IDS">,
  userId: string,
  sessionId: string | null,
): Promise<MigrationCounts> {
  if (sessionId === null) {
    throw new ApiError(403, "insufficient_scope", "Only the person's own session can do that");
  }
  return withUser(db, userId, async (tx) => {
    await lockRecords(tx, userId);
    await lockWraps(tx, userId);
    const state = await userState(tx, userId, { lock: true });
    const gate = migrationOf(config, { id: userId, ...state });
    if (gate !== "available" && gate !== "in_progress") {
      throw new ApiError(
        409,
        "not_migratable",
        "Only a plain account with an email, once the move is open to it, can start it",
      );
    }
    await tx
      .update(user)
      .set({ encryption: "migrating", migrationSessionId: sessionId })
      .where(eq(user.id, userId));
    return serverCounts(tx, userId);
  });
}

/** The JSON of `GET /v2/migration/source`: the `MigrationSource` of `@wambito/vault`. */
export async function migrationSource(db: Db, userId: string, sessionId: string | null) {
  return withUser(db, userId, async (tx) => {
    const state = await userState(tx, userId);
    requireBound(state, sessionId);
    const [account] = await tx
      .select({ currency: accounts.currency })
      .from(accounts)
      .where(and(eq(accounts.userId, userId), eq(accounts.isDefault, true)));
    const categoryRows = await tx
      .select()
      .from(categories)
      .where(eq(categories.userId, userId))
      .orderBy(asc(categories.sortOrder), asc(categories.id));
    const budgetRows = await tx
      .select()
      .from(categoryBudgets)
      .where(eq(categoryBudgets.userId, userId))
      .orderBy(asc(categoryBudgets.categoryId), asc(categoryBudgets.effectiveFrom));
    const recurrenceRows = await tx
      .select()
      .from(recurrences)
      .where(eq(recurrences.userId, userId))
      .orderBy(asc(recurrences.id));
    // Every soft-deleted row too: the server has no restore window, and a dismissed month left
    // out would be made again by the vault while `finish` deletes its only copy.
    const transactionRows = await tx
      .select()
      .from(transactions)
      .where(eq(transactions.userId, userId))
      .orderBy(asc(transactions.date), asc(transactions.id));
    const merchantRows = await tx
      .select()
      .from(merchantCategories)
      .where(eq(merchantCategories.userId, userId))
      .orderBy(asc(merchantCategories.merchantKey));
    return {
      profile: {
        timezone: state.timezone,
        locale: state.locale,
        onboardingCompletedAt: iso(state.onboardingCompletedAt),
        currency: account?.currency ?? "EUR",
      },
      categories: categoryRows.map((c) => ({
        id: c.id,
        name: c.name,
        kind: c.kind,
        icon: c.icon,
        color: c.color,
        sortOrder: c.sortOrder,
        archivedAt: iso(c.archivedAt),
        systemKey: c.systemKey,
        createdAt: c.createdAt.toISOString(),
        updatedAt: c.updatedAt.toISOString(),
      })),
      budgets: budgetRows.map((b) => ({
        id: b.id,
        categoryId: b.categoryId,
        amount: b.amount,
        effectiveFrom: b.effectiveFrom,
        createdAt: b.createdAt.toISOString(),
        updatedAt: b.updatedAt.toISOString(),
      })),
      recurrences: recurrenceRows.map((r) => ({
        id: r.id,
        accountId: r.accountId,
        categoryId: r.categoryId,
        name: r.name,
        amount: r.amount,
        frequency: r.frequency,
        dayOfMonth: r.dayOfMonth,
        monthOfYear: r.monthOfYear,
        startDate: r.startDate,
        endDate: r.endDate,
        createdAt: r.createdAt.toISOString(),
        updatedAt: r.updatedAt.toISOString(),
      })),
      transactions: transactionRows.map((t) => ({
        id: t.id,
        accountId: t.accountId,
        categoryId: t.categoryId,
        name: t.name,
        amount: t.amount,
        currency: t.currency,
        date: t.date,
        status: t.status,
        note: t.note,
        recurrenceId: t.recurrenceId,
        occurrenceMonth: t.occurrenceMonth,
        importId: t.importId,
        source: t.source,
        externalHash: t.externalHash,
        needsReview: t.needsReview,
        captureSource: t.captureSource,
        capturedAt: iso(t.capturedAt),
        captureMerchantKey: t.captureMerchantKey,
        deletedAt: iso(t.deletedAt),
        createdAt: t.createdAt.toISOString(),
        updatedAt: t.updatedAt.toISOString(),
      })),
      merchants: merchantRows.map((m) => ({
        id: m.id,
        merchantKey: m.merchantKey,
        categoryId: m.categoryId,
        createdAt: m.createdAt.toISOString(),
        updatedAt: m.updatedAt.toISOString(),
      })),
    };
  });
}

/**
 * Ends the migration. Under the records and wraps locks (so no push or key write lands between
 * the count and the delete), from the bound session only: the records must hold a recovery wrap's
 * data key (409 `keys_missing`), exactly one live `settings` record, and the same counts as the
 * server and as `client` (409 `count_mismatch` with all three, and nothing changes). Then it
 * deletes the plaintext rows, revokes the assistants and sets `encrypted`.
 */
export async function finishMigration(
  db: Db,
  userId: string,
  sessionId: string | null,
  client: MigrationCounts,
): Promise<void> {
  await withUser(db, userId, async (tx) => {
    await lockRecords(tx, userId);
    await lockWraps(tx, userId);
    requireBound(await userState(tx, userId, { lock: true }), sessionId);

    const [recovery] = await tx
      .select({ id: keyWraps.id })
      .from(keyWraps)
      .where(and(eq(keyWraps.userId, userId), eq(keyWraps.kind, "recovery")));
    if (!recovery) {
      throw new ApiError(409, "keys_missing", "The account has no data key to read its records");
    }
    // Every record with a body must open with the current data key: sealed under it, or under an
    // older one the key links reach (one link per rotation since). A push before the first wrap
    // takes any keyV, so this is the only place a record no wrap opens would show.
    const current = await currentKeyV(tx, userId);
    const [unreadable] = await tx
      .select({ n: sql<number>`count(*)::int` })
      .from(records)
      .where(
        and(
          eq(records.userId, userId),
          sql`${records.body} is not null`,
          sql`${records.keyV} <> ${current}`,
          sql`not (${records.keyV} < ${current} and (
            select count(*) from ${keyLinks}
            where ${keyLinks.userId} = ${userId} and ${keyLinks.keyV} > ${records.keyV}
              and ${keyLinks.keyV} <= ${current}
          ) = ${current} - ${records.keyV})`,
        ),
      );
    if ((unreadable?.n ?? 0) > 0) {
      throw new ApiError(
        409,
        "key_version_mismatch",
        "Some records are sealed under a key version the account's keys do not open",
      );
    }

    const server = await serverCounts(tx, userId);
    const { counts: stored, settings } = await recordCounts(tx, userId);
    const missing = await missingRecords(tx, userId);
    if (
      settings !== 1 ||
      missing.length > 0 ||
      !sameCounts(server, stored) ||
      !sameCounts(server, client)
    ) {
      throw new ApiError(
        409,
        "count_mismatch",
        settings !== 1
          ? `The records hold ${settings} settings records, not 1`
          : missing.length > 0
            ? "Some rows have no record of their own"
            : "The records do not hold the same as the server",
        { server, records: stored, client, missing: missing.slice(0, MAX_MISSING) },
      );
    }

    // Transactions first: they reference accounts, categories, recurrences and imports.
    await tx.delete(transactions).where(eq(transactions.userId, userId));
    await tx.delete(merchantCategories).where(eq(merchantCategories.userId, userId));
    await tx.delete(categoryBudgets).where(eq(categoryBudgets.userId, userId));
    await tx.delete(recurrences).where(eq(recurrences.userId, userId));
    await tx.delete(categories).where(eq(categories.userId, userId));
    await tx.delete(imports).where(eq(imports.userId, userId));
    await tx.delete(accounts).where(eq(accounts.userId, userId));
    await tx.delete(idempotencyKeys).where(eq(idempotencyKeys.userId, userId));
    await revokeAllAssistants(tx, userId);
    await tx
      .update(user)
      .set({ encryption: "encrypted", migrationSessionId: null })
      .where(eq(user.id, userId));
  });
}

/**
 * Gives up on the migration, from the bound session: deletes the account's records and its purge
 * mark, keeps its key wraps (the saved recovery key keeps working), and sets `plain` again.
 */
export async function cancelMigration(
  db: Db,
  userId: string,
  sessionId: string | null,
): Promise<void> {
  await withUser(db, userId, async (tx) => {
    await lockRecords(tx, userId);
    await lockWraps(tx, userId);
    requireBound(await userState(tx, userId, { lock: true }), sessionId);
    await tx.delete(records).where(eq(records.userId, userId));
    await tx.delete(recordPurges).where(eq(recordPurges.userId, userId));
    await tx
      .update(user)
      .set({ encryption: "plain", migrationSessionId: null })
      .where(eq(user.id, userId));
  });
}

/**
 * The write rule (spec 2026-11-19 §1): while the account is `migrating`, only the bound session
 * may write records or key material; `null` when the account may write, else the error.
 */
export async function migrationWriteRefusal(
  db: Db,
  userId: string,
  sessionId: string | null,
): Promise<ApiError | null> {
  const [row] = await db
    .select({ encryption: user.encryption, migrationSessionId: user.migrationSessionId })
    .from(user)
    .where(eq(user.id, userId));
  if (toEncryption(row?.encryption) !== "migrating") return null;
  return sessionId !== null && row?.migrationSessionId === sessionId ? null : migrationInProgress();
}
