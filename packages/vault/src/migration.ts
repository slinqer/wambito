import { parseRecord, type RecordBodies, type RecordType } from "@wambito/core";
import { uuidv5 } from "./ids.ts";

/**
 * The switch day (E2E stage 5): a plain account's server rows, as `GET /v2/migration/source`
 * answers them, become sealed-record bodies with the same ids (but for a dismissed month and a
 * merchant, which take the ids the vault derives). Design:
 * `docs/superpowers/specs/2026-11-19-e2e-stage-5-switch-design.md` section 3.
 */

/**
 * The namespace of the seeded records' ids; the account's own namespace is UUID v5 of it and the
 * user id. The settings record is `uuidv5(<account namespace>, "settings")`, the same id the web's
 * first open writes, so a migrated account and a new one have one settings record each. Fixed
 * forever.
 */
export const SETTINGS_SEED_NAMESPACE = "6f1f7a4e-0c5b-5e0a-9a3e-2b1d6c8f4a10";

/** ISO timestamp string as JSON carries it. */
type Instant = string;

/** The server's rows, as the database holds them: ids, ISO timestamps, `YYYY-MM-DD` dates, cents. */
export interface MigrationSource {
  profile: {
    timezone: string;
    locale: string;
    onboardingCompletedAt: Instant | null;
    /** The default account's currency. */
    currency: string;
  };
  categories: Array<{
    id: string;
    name: string;
    kind: "expense" | "income";
    icon: string;
    color: string;
    sortOrder: number;
    archivedAt: Instant | null;
    systemKey: string | null;
    createdAt: Instant;
    updatedAt?: Instant;
  }>;
  budgets: Array<{
    id: string;
    categoryId: string;
    amount: number;
    /** `YYYY-MM-DD`, the first day of the month. */
    effectiveFrom: string;
    createdAt?: Instant;
    updatedAt?: Instant;
  }>;
  recurrences: Array<{
    id: string;
    accountId?: string;
    categoryId: string;
    name: string;
    amount: number;
    frequency: "monthly" | "yearly";
    dayOfMonth: number;
    monthOfYear: number | null;
    startDate: string;
    endDate: string | null;
    createdAt: Instant;
    updatedAt?: Instant;
  }>;
  /** Live rows and every soft-deleted one, whatever its age (dismissed months among them). */
  transactions: Array<{
    id: string;
    accountId?: string;
    categoryId: string;
    name: string;
    amount: number;
    currency: string;
    date: string;
    status: "paid" | "pending";
    note: string | null;
    recurrenceId: string | null;
    /** `YYYY-MM-01`. */
    occurrenceMonth: string | null;
    importId?: string | null;
    source: RecordBodies["transaction"]["source"];
    externalHash?: string | null;
    needsReview: boolean;
    captureSource: string | null;
    capturedAt: Instant | null;
    captureMerchantKey: string | null;
    deletedAt: Instant | null;
    createdAt: Instant;
    updatedAt: Instant;
  }>;
  merchants: Array<{
    id: string;
    merchantKey: string;
    categoryId: string;
    createdAt?: Instant;
    updatedAt?: Instant;
  }>;
}

/**
 * Per type, what `POST /v2/migration/start` and `finish` count: live records, and the deleted
 * transactions with a body (dismissed months among them) apart. The one `settings` record is
 * checked apart.
 */
export interface MigrationCounts {
  transaction: number;
  deletedTransaction: number;
  category: number;
  budget: number;
  recurrence: number;
  merchant: number;
}

/** One record to write: a deleted one is a tombstone that keeps its body. */
export interface MigrationRecord {
  type: RecordType;
  id: string;
  body: unknown;
  deleted: boolean;
}

const LOCALES = ["es", "en", "it", "pt"] as const;
/** `YYYY-MM-DD` to the vault's `YYYY-MM`. */
const monthOf = (date: string) => date.slice(0, 7);

/**
 * The vault's id of a dismissed month: the vault re-ids a dismissal as
 * `uuidv5(rule, "<month>:<rev>")` (`materialize` and `dropPending` in `backend.ts`), and a server
 * rule is at revision 0. With its server id, a dismissed payment would be made again.
 */
const isDismissal = (t: MigrationSource["transactions"][number]) =>
  t.deletedAt !== null &&
  t.status === "pending" &&
  t.source === "recurrence" &&
  t.recurrenceId !== null &&
  t.occurrenceMonth !== null;

/** The settings record's id for an account, as the web's first open derives it. */
export async function settingsRecordId(userId: string): Promise<string> {
  return uuidv5(await uuidv5(SETTINGS_SEED_NAMESPACE, userId), "settings");
}

/**
 * The id of the `merchant` record that remembers `merchantKey`, as the phone makes it
 * (`merchantRecordId` in apps/mobile/lib/local/captures.dart): every device converges on one record
 * per merchant, so a migrated memory is the one the phone's capture learning updates. The server's
 * unique `(userId, merchantKey)` means two rows never share an id.
 */
export async function merchantRecordId(userId: string, merchantKey: string): Promise<string> {
  return uuidv5(await uuidv5(SETTINGS_SEED_NAMESPACE, userId), `merchant:${merchantKey}`);
}

/**
 * Every record the vault needs for this source, each body checked by `parseRecord` (and stored as
 * it parses, defaults filled). Throws on a row that would not make a valid record; the error names
 * the type and id, never a value.
 */
export async function recordsFromSource(
  source: MigrationSource,
  userId: string,
): Promise<MigrationRecord[]> {
  const out: MigrationRecord[] = [];
  const add = <T extends RecordType>(
    type: T,
    id: string,
    body: RecordBodies[T],
    deleted = false,
  ) => {
    const parsed = parseRecord(type, body);
    if (!parsed.ok)
      throw new Error(`Migration: ${type} ${id} is not a valid record: ${parsed.error}`);
    out.push({ type, id, body: parsed.value, deleted });
  };

  const { profile } = source;
  add("settings", await settingsRecordId(userId), {
    s: 1,
    name: null,
    currency: profile.currency as RecordBodies["settings"]["currency"],
    locale: (LOCALES as readonly string[]).includes(profile.locale)
      ? (profile.locale as RecordBodies["settings"]["locale"])
      : "es",
    timezone: profile.timezone,
    onboardingCompletedAt: profile.onboardingCompletedAt,
    revokedDevices: [],
    recoveryKeySavedAt: null,
  });

  for (const c of source.categories) {
    add("category", c.id, {
      s: 1,
      name: c.name,
      kind: c.kind,
      icon: c.icon,
      color: c.color,
      sortOrder: c.sortOrder,
      archivedAt: c.archivedAt,
      systemKey: c.systemKey,
      createdAt: c.createdAt,
    });
  }

  for (const b of source.budgets) {
    add("budget", b.id, {
      s: 1,
      categoryId: b.categoryId,
      amount: b.amount,
      effectiveFrom: monthOf(b.effectiveFrom),
    });
  }

  for (const r of source.recurrences) {
    add("recurrence", r.id, {
      s: 1,
      name: r.name,
      amount: r.amount,
      categoryId: r.categoryId,
      frequency: r.frequency,
      dayOfMonth: r.dayOfMonth,
      monthOfYear: r.monthOfYear,
      startDate: r.startDate,
      endDate: r.endDate,
      rev: 0,
      createdAt: r.createdAt,
    });
  }

  for (const m of source.merchants) {
    add("merchant", await merchantRecordId(userId, m.merchantKey), {
      s: 1,
      merchantKey: m.merchantKey,
      categoryId: m.categoryId,
    });
  }

  for (const t of source.transactions) {
    const occurrenceMonth = t.occurrenceMonth === null ? null : monthOf(t.occurrenceMonth);
    const id =
      isDismissal(t) && t.recurrenceId && occurrenceMonth
        ? await uuidv5(t.recurrenceId, `${occurrenceMonth}:0`)
        : t.id;
    add(
      "transaction",
      id,
      {
        s: 1,
        name: t.name,
        amount: t.amount,
        currency: t.currency,
        date: t.date,
        status: t.status,
        note: t.note,
        categoryId: t.categoryId,
        accountId: null,
        recurrenceId: t.recurrenceId,
        occurrenceMonth,
        source: t.source,
        needsReview: t.needsReview,
        captureSource: t.captureSource as RecordBodies["transaction"]["captureSource"],
        capturedAt: t.capturedAt,
        captureMerchantKey: t.captureMerchantKey,
        createdAt: t.createdAt,
        updatedAt: t.updatedAt,
      },
      t.deletedAt !== null,
    );
  }
  return out;
}

/** The counts `finish` compares, by the server's rule (see `MigrationCounts`). */
export function countsOf(records: MigrationRecord[]): MigrationCounts {
  const counts: MigrationCounts = {
    transaction: 0,
    deletedTransaction: 0,
    category: 0,
    budget: 0,
    recurrence: 0,
    merchant: 0,
  };
  for (const r of records) {
    if (r.type === "transaction") {
      if (r.deleted) counts.deletedTransaction += 1;
      else counts.transaction += 1;
    } else if (!r.deleted && r.type in counts) {
      counts[r.type as Exclude<keyof MigrationCounts, "deletedTransaction">] += 1;
    }
  }
  return counts;
}
