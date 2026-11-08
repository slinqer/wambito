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
/** Smallest live record body, in decoded bytes: a sealed record's nonce (12) and tag (16). */
export const MIN_RECORD_BODY = 12 + 16;
/** Changes per `POST /v2/sync`. */
export const MAX_SYNC_CHANGES = 500;

const BASE64URL = /^[A-Za-z0-9_-]*$/;
/** Decoded size of an unpadded base64url string, without decoding it. */
const decodedLength = (text: string) => Math.floor((text.length * 3) / 4);

/**
 * Only lower-case canonical UUIDs, the same rule as `@wambito/crypto`: record and key-wrap ids
 * enter the associated data byte for byte, so the server never changes their case.
 */
const LOWER_CASE_UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
/** A record or key-wrap id: a lower-case UUID; anything else (upper case included) is 422. */
export const lowerCaseUuid = () =>
  z
    .string()
    .regex(LOWER_CASE_UUID, "Not a lower-case UUID")
    .openapi({ format: "uuid", description: "A UUID in lower case" });

const recordFields = {
  id: lowerCaseUuid(),
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
      .refine((body) => decodedLength(body) >= MIN_RECORD_BODY, {
        message: `Under ${MIN_RECORD_BODY} bytes`,
      })
      .nullable()
      .openapi({
        description: `The encrypted record, base64url without padding, ${MIN_RECORD_BODY}–${MAX_RECORD_BODY} bytes decoded (at least a nonce and a tag); null exactly when deleted`,
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
    z
      .object({
        id: z.uuid(),
        error: z.enum(["id_taken", "not_found"]).openapi({
          description:
            "`id_taken`: the id is someone else's. `not_found`: an update for a record the server does not have (never uploaded, or a purged tombstone); resync in full.",
        }),
      })
      .openapi("PushRejected"),
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

/** Ways into an account's data key (spec 2026-11-08 section 5.2). */
export const KEY_WRAP_KINDS = ["passkey", "recovery", "device", "assistant"] as const;
/** Largest wrapped key, in decoded bytes. */
export const MAX_WRAPPED = 1024;
/** A device's X25519 public key, in bytes. */
export const DEVICE_PUBLIC_KEY_BYTES = 32;

/** Unpadded base64url whose decoded length is within `min`..`max` bytes. */
const base64urlBytes = (min: number, max: number) =>
  z
    .string()
    .regex(BASE64URL, "Not base64url")
    .refine((text) => text.length % 4 !== 1, { message: "Not base64url" })
    .refine(
      (text) => {
        const length = decodedLength(text);
        return length >= min && length <= max;
      },
      { message: min === max ? `Not ${min} bytes` : `Not ${min}–${max} bytes` },
    );

const keyWrapFields = {
  kind: z.enum(KEY_WRAP_KINDS),
  ref: z.string().min(1).max(512).nullable().optional().openapi({
    description:
      "The passkey's credential id (base64url), the device id, or the assistant's OAuth client id; none for `recovery`",
  }),
  keyV: z.int().min(0).max(32767).openapi({ description: "The data key version this wraps" }),
  wrapped: base64urlBytes(1, MAX_WRAPPED).openapi({
    description: `The wrapped data key, base64url without padding, 1–${MAX_WRAPPED} bytes decoded`,
  }),
  publicKey: base64urlBytes(DEVICE_PUBLIC_KEY_BYTES, DEVICE_PUBLIC_KEY_BYTES)
    .nullable()
    .optional()
    .openapi({
      description: `\`device\` only, and required there: its X25519 public key, ${DEVICE_PUBLIC_KEY_BYTES} bytes, base64url`,
    }),
  label: z.string().max(100).nullable().optional().openapi({
    description: 'Shown in Settings ("Pixel 9", "Firefox on Mac")',
  }),
};

type KeyWrapShape = { kind: string; ref?: string | null; publicKey?: string | null };
const refByKind = (wrap: KeyWrapShape) => (wrap.kind === "recovery") === (wrap.ref == null);
const publicKeyByKind = (wrap: KeyWrapShape) =>
  (wrap.kind === "device") === (wrap.publicKey != null);
const REF_RULE = { message: "`recovery` has no ref; every other kind has one", path: ["ref"] };
const PUBLIC_KEY_RULE = {
  message: "`device` has a public key; no other kind has one",
  path: ["publicKey"],
};

export const PutKeyWrap = z
  .object(keyWrapFields)
  .refine(refByKind, REF_RULE)
  .refine(publicKeyByKind, PUBLIC_KEY_RULE)
  .openapi("PutKeyWrap");

export const KeyWrap = z
  .object({
    id: z.uuid(),
    kind: z.enum(KEY_WRAP_KINDS),
    ref: z.string().nullable(),
    keyV: z.int(),
    wrapped: z.string().openapi({ description: "base64url without padding" }),
    publicKey: z.string().nullable().openapi({ description: "base64url without padding" }),
    label: z.string().nullable(),
    createdAt: z.string(),
    lastUsedAt: z.string().nullable(),
  })
  .openapi("KeyWrap");

export const KeyWraps = z.object({ wraps: z.array(KeyWrap) }).openapi("KeyWraps");

export const RotateKeys = z
  .object({
    keyV: z.int().min(0).max(32767).openapi({ description: "The new key version: current + 1" }),
    wraps: z
      .array(
        z
          .object({ id: lowerCaseUuid(), ...keyWrapFields })
          .refine(refByKind, REF_RULE)
          .refine(publicKeyByKind, PUBLIC_KEY_RULE)
          .openapi("RotatedKeyWrap"),
      )
      .min(1)
      .max(200),
  })
  .refine((body) => body.wraps.every((wrap) => wrap.keyV === body.keyV), {
    message: "Every wrap carries the new keyV",
    path: ["wraps"],
  })
  .refine((body) => new Set(body.wraps.map((wrap) => wrap.id)).size === body.wraps.length, {
    message: "Wrap ids repeat",
    path: ["wraps"],
  })
  .refine(
    (body) => {
      const refs = body.wraps.filter((w) => w.ref != null).map((w) => `${w.kind}\n${w.ref}`);
      return new Set(refs).size === refs.length;
    },
    { message: "A kind and ref repeat", path: ["wraps"] },
  )
  .openapi("RotateKeys");

/** The longest a sealed data key may be, in bytes (a sealed 32-byte key is far smaller). */
export const MAX_SEALED_PAIRING = 1024;

const pairingKey = (description: string) =>
  base64urlBytes(DEVICE_PUBLIC_KEY_BYTES, DEVICE_PUBLIC_KEY_BYTES).openapi({ description });

export const StartPairing = z
  .object({
    commitment: pairingKey(
      'SHA-256("wambito/v1/pairing-commit" || the new device\'s X25519 public key), 32 bytes, base64url',
    ),
  })
  .openapi("StartPairing");

export const PairingStarted = z
  .object({
    id: z.uuid(),
    code: z
      .string()
      .openapi({ description: "8 Crockford base32 characters for the person to type" }),
    expiresAt: z.string(),
  })
  .openapi("PairingStarted");

export const PairingFound = z
  .object({
    id: z.uuid(),
    commitment: z.string().openapi({ description: "base64url without padding" }),
    expiresAt: z.string(),
  })
  .openapi("PairingFound");

export const PairingApprover = z
  .object({
    publicKey: pairingKey(
      "The approving device's ephemeral X25519 public key, 32 bytes, base64url",
    ),
  })
  .openapi("PairingApprover");

export const PairingReveal = z
  .object({
    publicKey: pairingKey(
      "The new device's X25519 public key, 32 bytes, base64url; must match the commitment",
    ),
  })
  .openapi("PairingReveal");

export const SealPairing = z
  .object({
    sealed: base64urlBytes(1, MAX_SEALED_PAIRING).openapi({
      description: `The data key sealed to the new device's public key, base64url, 1–${MAX_SEALED_PAIRING} bytes decoded; its first 32 bytes are the approver key`,
    }),
    keyV: z
      .int()
      .min(0)
      .max(32767)
      .openapi({ description: "The data key version the seal is bound to" }),
  })
  .openapi("SealPairing");

const nullableB64 = z.string().nullable().openapi({ description: "base64url; null until set" });

export const PairingState = z
  .object({
    commitment: z.string().openapi({ description: "base64url" }),
    approverKey: nullableB64,
    publicKey: nullableB64,
    sealed: nullableB64,
    keyV: z.int().nullable().openapi({ description: "null until sealed" }),
    expiresAt: z.string(),
  })
  .openapi("PairingState");
