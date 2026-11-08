import { z } from "zod";
import { CAPTURE_SOURCES } from "./capture-sources.ts";
import { SUPPORTED_CURRENCIES } from "./currencies.ts";
import { isValidTimeZone } from "./dates.ts";
import { amountSchema, budgetAmountSchema, isoDateSchema, monthSchema } from "./schemas.ts";

/**
 * The plaintext bodies of the encrypted records (spec 4.2, 5.1): what gets sealed is
 * `{ s: 1, ...fields }`. `id`, `version` and `deleted` live in the record envelope, never here.
 * The objects are loose: unknown keys are kept, so a newer client's extra fields do not break an
 * older one and survive its edits and conflict merges (the merge copies every key it does not
 * know from the server's copy). `s` is the schema version and is required.
 */
const text = z.string();
const timestamp = z.string();
const frequency = z.enum(["monthly", "yearly"]);

export const transactionRecord = z.object({
  s: z.literal(1),
  name: text,
  amount: amountSchema,
  currency: text,
  date: isoDateSchema,
  status: z.enum(["paid", "pending"]),
  note: text.nullable().default(null),
  categoryId: z.uuid(),
  accountId: z.uuid().nullable().default(null),
  recurrenceId: z.uuid().nullable().default(null),
  /** The month a recurrence generated it for; one per rule and month, deleted or not. */
  occurrenceMonth: monthSchema.nullable().default(null),
  source: z.enum(["app", "web", "widget", "mcp", "import", "recurrence", "capture"]),
  needsReview: z.boolean().default(false),
  captureSource: z.enum(CAPTURE_SOURCES).nullable().default(null),
  capturedAt: timestamp.nullable().default(null),
  captureMerchantKey: text.nullable().default(null),
  createdAt: timestamp.optional(),
  /** Set on create and on every edit; an older record has none (read `createdAt`). */
  updatedAt: timestamp.optional(),
}).loose();

export const categoryRecord = z.object({
  s: z.literal(1),
  name: text,
  kind: z.enum(["expense", "income"]),
  icon: text,
  color: text,
  sortOrder: z.number().int(),
  archivedAt: timestamp.nullable().default(null),
  systemKey: text.nullable().default(null),
  createdAt: timestamp.optional(),
}).loose();

/** One entry of the budget history: the amount applies from `effectiveFrom` until a later entry. */
export const budgetRecord = z.object({
  s: z.literal(1),
  categoryId: z.uuid(),
  amount: budgetAmountSchema,
  effectiveFrom: monthSchema,
}).loose();

export const recurrenceRecord = z.object({
  s: z.literal(1),
  name: text,
  amount: amountSchema,
  categoryId: z.uuid(),
  frequency,
  dayOfMonth: z.number().int().min(1).max(31),
  monthOfYear: z.number().int().min(1).max(12).nullable().default(null),
  startDate: isoDateSchema,
  endDate: isoDateSchema.nullable().default(null),
  /**
   * The rule's revision. An occurrence's id is the UUID v5 of the rule id and `<month>:<rev>`;
   * dropping the pending occurrences (an edit, an archive) bumps it so they come back under new ids.
   */
  rev: z.number().int().min(0).default(0),
  createdAt: timestamp.optional(),
}).loose();

/** The merchant memory: the category last chosen for a merchant (`merchantKey` of its name). */
export const merchantRecord = z.object({
  s: z.literal(1),
  merchantKey: text.min(1),
  categoryId: z.uuid(),
}).loose();

/** The profile preferences (one per account). */
export const settingsRecord = z.object({
  s: z.literal(1),
  name: text.nullable().default(null),
  currency: z.enum(SUPPORTED_CURRENCIES),
  locale: z.enum(["es", "en", "it", "pt"]),
  timezone: z.string().refine(isValidTimeZone, "Unknown time zone"),
  onboardingCompletedAt: timestamp.nullable().default(null),
}).loose();

export const accountRecord = z.object({
  s: z.literal(1),
  name: text,
  currency: text,
  isDefault: z.boolean().default(false),
}).loose();

export const RECORD_SCHEMAS = {
  transaction: transactionRecord,
  category: categoryRecord,
  budget: budgetRecord,
  recurrence: recurrenceRecord,
  merchant: merchantRecord,
  settings: settingsRecord,
  account: accountRecord,
} as const;

export type RecordType = keyof typeof RECORD_SCHEMAS;
export const RECORD_TYPES = Object.keys(RECORD_SCHEMAS) as RecordType[];

export type RecordBodies = { [K in RecordType]: z.infer<(typeof RECORD_SCHEMAS)[K]> };
export type TransactionRecord = RecordBodies["transaction"];
export type CategoryRecord = RecordBodies["category"];
export type BudgetRecord = RecordBodies["budget"];
export type RecurrenceRecord = RecordBodies["recurrence"];
export type MerchantRecord = RecordBodies["merchant"];
export type SettingsRecord = RecordBodies["settings"];
export type AccountRecord = RecordBodies["account"];

export type ParsedRecord<T extends RecordType> =
  | { ok: true; value: RecordBodies[T] }
  | { ok: false; error: string };

/** Validates a decrypted body. Never throws: a bad record is an `{ ok: false }`. */
export function parseRecord<T extends RecordType>(type: T, json: unknown): ParsedRecord<T> {
  const schema = (RECORD_SCHEMAS as Record<RecordType, z.ZodType>)[type];
  if (!schema) return { ok: false, error: `Unknown record type: ${String(type)}` };
  try {
    const result = schema.safeParse(json);
    if (result.success) return { ok: true, value: result.data as RecordBodies[T] };
    return {
      ok: false,
      error: result.error.issues
        .map((i) => `${i.path.join(".") || "(body)"}: ${i.message}`)
        .join("; "),
    };
  } catch (error) {
    return { ok: false, error: error instanceof Error ? error.message : "Invalid record" };
  }
}
