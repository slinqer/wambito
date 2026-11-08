/**
 * The shared schemas, named for the OpenAPI document: each becomes a component
 * (`#/components/schemas/<Name>`) that operations reference, so generated clients get these names
 * instead of ones derived from paths. The schemas themselves live in @wambito/core and are built
 * with plain zod, possibly before @hono/zod-openapi has added `.openapi()` to zod, so they are
 * named with zod's own `.meta({ id })`, which the document generator reads the same way. It
 * returns a named copy and leaves the core schemas unchanged. Schemas declared in the routes, with
 * @hono/zod-openapi's `z`, use `.openapi(name)`.
 */
import { z } from "@hono/zod-openapi";
import {
  captureResultDto,
  categoryDto,
  createCaptureSchema,
  createCategorySchema,
  createRecurrenceSchema,
  createTransactionSchema,
  createTransactionsBatchSchema,
  deleteTransactionsBatchSchema,
  monthSummaryDto,
  problemDto,
  recurrenceDto,
  reviewTransactionsSchema,
  setBudgetSchema,
  transactionDto,
  updateCategorySchema,
  updateProfileSchema,
  updateRecurrenceSchema,
  updateTransactionSchema,
} from "@wambito/core";

export const Problem = problemDto.meta({ id: "Problem" });

export const Transaction = transactionDto.meta({ id: "Transaction" });
export const CreateTransaction = createTransactionSchema.meta({ id: "CreateTransaction" });
export const UpdateTransaction = updateTransactionSchema.meta({ id: "UpdateTransaction" });
/**
 * Core's batch holds core's unnamed create schema, so its items are swapped for the named one
 * above (keeping core's limits, 1 to 20): otherwise generated clients get an unnamed duplicate of
 * CreateTransaction for them.
 */
const batchItems = createTransactionsBatchSchema.shape.items;
export const CreateTransactionsBatch = createTransactionsBatchSchema
  .extend({ items: batchItems.clone({ ...batchItems.def, element: CreateTransaction }) })
  .meta({ id: "CreateTransactionsBatch" });
export const DeleteTransactionsBatch = deleteTransactionsBatchSchema.meta({
  id: "DeleteTransactionsBatch",
});

export const ReviewTransactions = reviewTransactionsSchema.meta({ id: "ReviewTransactions" });
export const CreateCapture = createCaptureSchema.meta({ id: "CreateCapture" });
export const CaptureResult = captureResultDto.meta({ id: "CaptureResult" });

export const Category = categoryDto.meta({ id: "Category" });
export const CreateCategory = createCategorySchema.meta({ id: "CreateCategory" });
export const UpdateCategory = updateCategorySchema.meta({ id: "UpdateCategory" });
export const SetBudget = setBudgetSchema.meta({ id: "SetBudget" });

export const Recurrence = recurrenceDto.meta({ id: "Recurrence" });
export const CreateRecurrence = createRecurrenceSchema.meta({ id: "CreateRecurrence" });
export const UpdateRecurrence = updateRecurrenceSchema.meta({ id: "UpdateRecurrence" });

export const Summary = monthSummaryDto.meta({ id: "Summary" });
export const UpdateProfile = updateProfileSchema.meta({ id: "UpdateProfile" });

/**
 * The `Idempotency-Key` request header (src/http/idempotency.ts): a retry with the same key and
 * body replays the first response. Header names are matched without regard to case.
 */
export const idempotencyKeyHeader = ({ required }: { required: boolean }) =>
  z.object({
    "Idempotency-Key": (required ? z.string().min(1) : z.string().optional()).openapi({
      description:
        "A key that stays the same across retries of the same request (a UUID, say): a retry with the same key and body returns the first response instead of saving twice.",
    }),
  });

/** The kinds of encrypted record (spec 2026-11-08 section 5.1); `type` travels in clear. */
export const RECORD_TYPES = [
  "transaction",
  "category",
  "budget",
  "recurrence",
  "merchant",
  "settings",
  "account",
] as const;

/** Largest record body, in decoded bytes. */
export const MAX_RECORD_BODY = 64 * 1024;
/** Changes per `POST /v2/sync`. */
export const MAX_SYNC_CHANGES = 500;

const BASE64URL = /^[A-Za-z0-9_-]*$/;
/** Decoded size of an unpadded base64url string, without decoding it. */
const decodedLength = (text: string) => Math.floor((text.length * 3) / 4);

const recordFields = {
  id: z.uuid(),
  type: z.enum(RECORD_TYPES),
  deleted: z.boolean(),
  keyV: z.int().min(0).max(32767).openapi({ description: "The data key version of `body`" }),
  encV: z.int().min(0).max(32767).openapi({ description: "The record format version" }),
};

export const SyncRecord = z
  .object({
    ...recordFields,
    version: z.int().min(1),
    body: z.string().nullable().openapi({
      description: "The encrypted record, base64url without padding; null when deleted",
    }),
  })
  .openapi("SyncRecord");

export const SyncChange = z
  .object({
    ...recordFields,
    baseVersion: z.int().min(1).nullable().openapi({
      description: "The version this change was made on; null creates the record",
    }),
    body: z
      .string()
      .regex(BASE64URL, "Not base64url")
      .refine((body) => body.length % 4 !== 1, { message: "Not base64url" })
      .refine((body) => decodedLength(body) <= MAX_RECORD_BODY, {
        message: `Over ${MAX_RECORD_BODY} bytes`,
      })
      .nullable()
      .openapi({
        description: `The encrypted record, base64url without padding, at most ${MAX_RECORD_BODY} bytes decoded; null exactly when deleted`,
      }),
  })
  .refine((change) => change.deleted === (change.body === null), {
    message: "A deleted record has no body, and a live one has one",
    path: ["body"],
  })
  .openapi("SyncChange");

export const PushRecords = z
  .object({ changes: z.array(SyncChange).min(1).max(MAX_SYNC_CHANGES) })
  .openapi("PushRecords");

export const PushResult = z
  .union([
    z.object({ id: z.uuid(), version: z.int() }).openapi("PushApplied"),
    z.object({ id: z.uuid(), conflict: SyncRecord }).openapi("PushConflict"),
    z.object({ id: z.uuid(), error: z.literal("id_taken") }).openapi("PushRejected"),
  ])
  .openapi("PushResult");

export const PushResults = z.object({ results: z.array(PushResult) }).openapi("PushResults");

export const PulledRecords = z
  .object({
    records: z.array(SyncRecord),
    next: z.int().nullable().openapi({
      description: "The `since` of the next page; null when this page reaches `latest`",
    }),
    latest: z.int().openapi({ description: "The newest version on the server; 0 when none" }),
  })
  .openapi("PulledRecords");
