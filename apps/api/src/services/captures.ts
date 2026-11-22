import {
  type CaptureResult,
  type CreateCapture,
  FALLBACK_CATEGORY_NAMES,
  merchantKey,
  merchantKeyPrefixes,
  todayIn,
} from "@wambito/core";
import { categories, merchantCategories, type Tx, transactions } from "@wambito/db";
import { and, desc, eq, gte, inArray, isNull, lte, sql } from "@wambito/db/orm";
import { defaultAccount, type TransactionRow, toTransactionDto } from "./transactions.ts";

type Locale = keyof typeof FALLBACK_CATEGORY_NAMES;
type Kind = CreateCapture["kind"];

/** Two captures this close in time, with the same kind, amount and currency, are one purchase. */
const DUPLICATE_WINDOW_MS = 10 * 60 * 1000;

const asLocale = (value: string): Locale =>
  value in FALLBACK_CATEGORY_NAMES ? (value as Locale) : "es";

/**
 * The person's `other` category of this kind: the one marked by `system_key`, else an active
 * category with the localized name (which gets the key), else a new one. Returns its id.
 */
export async function fallbackCategory(
  tx: Tx,
  userId: string,
  kind: Kind,
  locale: string,
): Promise<string> {
  const [keyed] = await tx
    .select({ id: categories.id })
    .from(categories)
    .where(
      and(
        eq(categories.kind, kind),
        eq(categories.systemKey, "other"),
        isNull(categories.archivedAt),
      ),
    );
  if (keyed) return keyed.id;
  const name = FALLBACK_CATEGORY_NAMES[asLocale(locale)][kind];
  const [named] = await tx
    .select({ id: categories.id })
    .from(categories)
    .where(
      and(
        eq(categories.kind, kind),
        isNull(categories.archivedAt),
        sql`lower(${categories.name}) = lower(${name})`,
      ),
    );
  if (named) {
    await tx.update(categories).set({ systemKey: "other" }).where(eq(categories.id, named.id));
    return named.id;
  }
  const [created] = await tx
    .insert(categories)
    .values({
      userId,
      name,
      kind,
      icon: "📦",
      color: "#8e8e9a",
      systemKey: "other",
    })
    .returning({ id: categories.id });
  if (!created) throw new Error("Could not create the fallback category");
  return created.id;
}

/** `merchantKey`, or null for a merchant with no letters or digits worth remembering (R5). */
function keyOf(merchant: string): string | null {
  try {
    return merchantKey(merchant);
  } catch {
    return null;
  }
}

/**
 * The category remembered for this merchant key, when it is still active. The key itself wins;
 * otherwise the longest learned key made of its leading words, so "lidl casal ribeiro" (a branch,
 * as Google Wallet names it) gets what "lidl" taught (`merchantKeyPrefixes`).
 */
async function rememberedCategory(tx: Tx, key: string | null, kind: Kind): Promise<string | null> {
  if (key === null) return null; // nothing to look up: use the fallback
  const candidates = [key, ...merchantKeyPrefixes(key)];
  const [row] = await tx
    .select({ id: categories.id })
    .from(merchantCategories)
    .innerJoin(categories, eq(categories.id, merchantCategories.categoryId))
    .where(
      and(
        inArray(merchantCategories.merchantKey, candidates),
        eq(categories.kind, kind),
        isNull(categories.archivedAt),
      ),
    )
    // Every candidate starts the key, so the longest is the closest one.
    .orderBy(desc(sql`length(${merchantCategories.merchantKey})`))
    .limit(1);
  return row?.id ?? null;
}

/**
 * Saves a capture, or answers that it is already saved. Runs in the caller's transaction (RLS
 * scopes every query to the person); the default account's lock serializes concurrent captures,
 * so two notifications of one purchase cannot both pass the duplicate check.
 */
export async function saveCapture(
  tx: Tx,
  user: { id: string; timezone: string; locale: string },
  input: CreateCapture,
): Promise<{ status: 200 | 201; body: CaptureResult }> {
  const account = await defaultAccount(tx, { lock: true });
  const signed = input.kind === "expense" ? -input.amount : input.amount;
  const capturedAt = new Date(input.capturedAt);
  const from = new Date(capturedAt.getTime() - DUPLICATE_WINDOW_MS);
  const to = new Date(capturedAt.getTime() + DUPLICATE_WINDOW_MS);

  const [existing] = await tx
    .select({ row: transactions, categoryName: categories.name, systemKey: categories.systemKey })
    .from(transactions)
    .innerJoin(categories, eq(categories.id, transactions.categoryId))
    .where(
      and(
        isNull(transactions.deletedAt),
        eq(transactions.source, "capture"),
        eq(transactions.amount, signed),
        eq(transactions.currency, account.currency),
        // The notified currency lives only in the note, so editing the note of a capture within
        // the window stops it merging.
        sql`${transactions.note} is not distinct from ${noteFor(input, account.currency)}`,
        gte(transactions.capturedAt, from),
        lte(transactions.capturedAt, to),
      ),
    )
    .orderBy(
      sql`abs(extract(epoch from (${transactions.capturedAt} - ${capturedAt.toISOString()}::timestamptz)))`,
    )
    .limit(1);
  if (existing) {
    return {
      status: 200,
      body: {
        result: "merged",
        transaction: toTransactionDto(existing.row),
        category: { name: existing.categoryName, fallback: existing.systemKey === "other" },
      },
    };
  }

  const key = keyOf(input.merchant);
  const remembered = await rememberedCategory(tx, key, input.kind);
  const categoryId = remembered ?? (await fallbackCategory(tx, user.id, input.kind, user.locale));
  const [category] = await tx.select().from(categories).where(eq(categories.id, categoryId));
  const [row] = await tx
    .insert(transactions)
    .values({
      userId: user.id,
      accountId: account.id,
      categoryId,
      name: input.merchant,
      amount: signed,
      currency: account.currency,
      date: todayIn(user.timezone, capturedAt),
      note: noteFor(input, account.currency),
      source: "capture",
      captureSource: input.source,
      capturedAt,
      captureMerchantKey: key,
      needsReview: true,
    })
    .returning();
  if (!row || !category) throw new Error("Could not save the capture");
  return {
    status: 201,
    body: {
      result: "created",
      transaction: toTransactionDto(row),
      category: { name: category.name, fallback: category.systemKey === "other" },
    },
  };
}

/** The notified amount and currency, kept in the note when the account's currency differs. */
function noteFor(input: CreateCapture, accountCurrency: string): string | null {
  return input.currency === accountCurrency
    ? null
    : `${(input.amount / 100).toFixed(2)} ${input.currency}`;
}

/**
 * Remembers the category a person confirmed for a capture's merchant. Called when, in this
 * request, a `capture` row goes from needing review to confirmed; `row` is the updated row. Only
 * a category that is active, of the transaction's kind and not a fallback is remembered (RLS
 * scopes the lookup to this person), and a merchant with nothing alphanumeric is skipped. The key
 * is the merchant as notified (`capture_merchant_key`), so a row renamed before or while it is
 * confirmed still teaches the merchant the next notification names; the row's name is used only
 * when the key was never stored.
 */
export async function learn(tx: Tx, userId: string, row: TransactionRow): Promise<void> {
  const key = row.captureMerchantKey ?? keyOf(row.name);
  if (key === null) return;
  const [category] = await tx
    .select({ id: categories.id })
    .from(categories)
    .where(
      and(
        eq(categories.id, row.categoryId),
        eq(categories.kind, row.amount < 0 ? "expense" : "income"),
        isNull(categories.archivedAt),
        isNull(categories.systemKey),
      ),
    );
  if (!category) return;
  await tx
    .insert(merchantCategories)
    .values({ userId, merchantKey: key, categoryId: category.id })
    .onConflictDoUpdate({
      target: [merchantCategories.userId, merchantCategories.merchantKey],
      set: { categoryId: category.id },
    });
}
