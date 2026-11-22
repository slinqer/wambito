import { z } from "zod";
import { CAPTURE_SOURCES } from "./capture-sources.ts";
import { SUPPORTED_CURRENCIES } from "./currencies.ts";
import { isIsoDate, isMonth, isValidTimeZone } from "./dates.ts";

export const monthSchema = z.string().refine(isMonth, "Expected a month as YYYY-MM");
export const isoDateSchema = z.string().refine(isIsoDate, "Expected a date as YYYY-MM-DD");
export const amountSchema = z
  .number()
  .int()
  .refine(Number.isSafeInteger, "Amount is too large")
  .refine((n) => n !== 0, "Amount cannot be zero");
export const budgetAmountSchema = z.number().int().nonnegative().refine(Number.isSafeInteger);

const kindSchema = z.enum(["expense", "income"]);
const statusSchema = z.enum(["paid", "pending"]);
const frequencySchema = z.enum(["monthly", "yearly"]);
const nameSchema = z.string().trim().min(1).max(120);
const noteSchema = z.string().max(1000).nullable();

const atLeastOne = (value: object) => Object.keys(value).length > 0;
const AT_LEAST_ONE = "Provide at least one field";

/**
 * "Repetir" on a new transaction: it becomes the first occurrence of a recurrence made from it
 * (its name, amount and category; its date gives the day, the month of a yearly one and the start).
 */
export const repeatSchema = z.object({
  frequency: frequencySchema,
  endDate: isoDateSchema.nullable().optional(),
});
export type Repeat = z.infer<typeof repeatSchema>;

export const createTransactionSchema = z
  .object({
    name: nameSchema,
    amount: amountSchema,
    categoryId: z.uuid(),
    date: isoDateSchema,
    status: statusSchema.default("paid"),
    note: noteSchema.optional(),
    source: z.enum(["app", "web", "widget", "mcp"]).default("app"),
    repeat: repeatSchema.optional(),
  })
  .superRefine((value, ctx) => {
    if (value.repeat?.endDate && value.repeat.endDate < value.date) {
      ctx.addIssue({
        code: "custom",
        path: ["repeat", "endDate"],
        message: "endDate must be on or after date",
      });
    }
  });
export type CreateTransaction = z.infer<typeof createTransactionSchema>;

/** Several movements saved together (one tap in the app); at most 20, all or nothing. */
export const createTransactionsBatchSchema = z.object({
  items: z.array(createTransactionSchema).min(1).max(20),
});
export type CreateTransactionsBatch = z.infer<typeof createTransactionsBatchSchema>;

/** Undo of a batch: the ids to soft-delete. */
export const deleteTransactionsBatchSchema = z.object({
  ids: z.array(z.uuid()).min(1).max(20),
});
export type DeleteTransactionsBatch = z.infer<typeof deleteTransactionsBatchSchema>;

export const updateTransactionSchema = z
  .object({
    name: nameSchema,
    amount: amountSchema,
    categoryId: z.uuid(),
    date: isoDateSchema,
    status: statusSchema,
    note: noteSchema,
    needsReview: z.literal(false),
  })
  .partial()
  .refine(atLeastOne, AT_LEAST_ONE);
export type UpdateTransaction = z.infer<typeof updateTransactionSchema>;

const categoryFields = {
  name: z.string().trim().min(1).max(40),
  icon: z.string().min(1).max(40),
  color: z.string().min(1).max(40),
  sortOrder: z.number().int(),
};

export const createCategorySchema = z.object({
  ...categoryFields,
  kind: kindSchema,
  sortOrder: categoryFields.sortOrder.optional(),
});
export type CreateCategory = z.infer<typeof createCategorySchema>;

/** `kind` can change only while the category has no live transactions (the API checks). */
export const updateCategorySchema = z
  .object({ ...categoryFields, kind: kindSchema, archived: z.boolean() })
  .partial()
  .refine(atLeastOne, AT_LEAST_ONE);
export type UpdateCategory = z.infer<typeof updateCategorySchema>;

export const setBudgetSchema = z.object({
  amount: budgetAmountSchema,
  effectiveFrom: monthSchema,
});
export type SetBudget = z.infer<typeof setBudgetSchema>;

const recurrenceFields = z.object({
  name: nameSchema,
  amount: amountSchema,
  categoryId: z.uuid(),
  frequency: frequencySchema,
  dayOfMonth: z.number().int().min(1).max(31),
  monthOfYear: z.number().int().min(1).max(12).nullable().optional(),
  startDate: isoDateSchema,
  endDate: isoDateSchema.nullable().optional(),
});

type RecurrenceShape = Partial<z.infer<typeof recurrenceFields>>;

function checkRecurrence(value: RecurrenceShape, ctx: z.RefinementCtx) {
  if (value.frequency === "yearly" && value.monthOfYear == null) {
    ctx.addIssue({
      code: "custom",
      path: ["monthOfYear"],
      message: "Yearly recurrences need monthOfYear",
    });
  }
  if (value.startDate && value.endDate && value.endDate < value.startDate) {
    ctx.addIssue({
      code: "custom",
      path: ["endDate"],
      message: "endDate must be on or after startDate",
    });
  }
}

export const createRecurrenceSchema = recurrenceFields.superRefine(checkRecurrence);
export type CreateRecurrence = z.infer<typeof createRecurrenceSchema>;

// Cross-field rules are checked by the API on the merged recurrence, since a patch may rely on
// stored values (e.g. switching back to yearly with the monthOfYear already saved).
export const updateRecurrenceSchema = recurrenceFields.partial().refine(atLeastOne, AT_LEAST_ONE);
export type UpdateRecurrence = z.infer<typeof updateRecurrenceSchema>;

export const updateProfileSchema = z
  .object({
    timezone: z.string().refine(isValidTimeZone, "Unknown time zone"),
    locale: z.enum(["es", "en", "it", "pt"]),
    currency: z.enum(SUPPORTED_CURRENCIES),
    onboardingCompleted: z.literal(true),
  })
  .partial()
  .refine(atLeastOne, AT_LEAST_ONE);
export type UpdateProfile = z.infer<typeof updateProfileSchema>;

// Response DTOs (used to document the API in OpenAPI).

export const transactionDto = z.object({
  id: z.uuid(),
  name: z.string(),
  amount: z.number().int(),
  currency: z.string(),
  date: z.string(),
  status: statusSchema,
  note: z.string().nullable(),
  categoryId: z.uuid(),
  recurrenceId: z.uuid().nullable(),
  importId: z.uuid().nullable(),
  source: z.enum(["app", "web", "widget", "mcp", "import", "recurrence", "capture"]),
  needsReview: z.boolean(),
  // Plain text, not `CAPTURE_SOURCES`: the generated clients must decode a source they do not know.
  captureSource: z
    .string()
    .nullable()
    .describe(
      `Where a detected transaction came from: ${CAPTURE_SOURCES.join(", ")}, or a newer source`,
    ),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type TransactionDto = z.infer<typeof transactionDto>;

export const categoryDto = z.object({
  id: z.uuid(),
  name: z.string(),
  kind: kindSchema,
  icon: z.string(),
  color: z.string(),
  sortOrder: z.number().int(),
  archived: z.boolean(),
  currentBudget: z.number().int().nullable(),
});
export type CategoryDto = z.infer<typeof categoryDto>;

export const recurrenceDto = z.object({
  id: z.uuid(),
  name: z.string(),
  amount: z.number().int(),
  categoryId: z.uuid(),
  frequency: frequencySchema,
  dayOfMonth: z.number().int(),
  monthOfYear: z.number().int().nullable(),
  startDate: z.string(),
  endDate: z.string().nullable(),
});
export type RecurrenceDto = z.infer<typeof recurrenceDto>;

export const monthSummaryDto = z.object({
  month: z.string(),
  budgetTotal: z.number().int(),
  spent: z.number().int(),
  remaining: z.number().int(),
  income: z.number().int(),
  balance: z.number().int(),
  categories: z.array(
    z.object({
      categoryId: z.string(),
      budget: z.number().int().nullable(),
      spent: z.number().int(),
      remaining: z.number().int().nullable(),
      ratio: z.number().nullable(),
      state: z.enum(["ok", "near", "over"]),
    }),
  ),
});

export const problemDto = z.object({
  type: z.string(),
  title: z.string(),
  status: z.number().int(),
  code: z.string(),
  detail: z.string().optional(),
  errors: z.array(z.object({ path: z.string(), message: z.string() })).optional(),
});
