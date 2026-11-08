import { sql } from "drizzle-orm";
import {
  bigint,
  boolean,
  char,
  check,
  customType,
  date,
  index,
  integer,
  jsonb,
  pgEnum,
  pgTable,
  primaryKey,
  smallint,
  text,
  timestamp,
  uniqueIndex,
  uuid,
} from "drizzle-orm/pg-core";
import { v7 as uuidv7 } from "uuid";
import { session, user } from "./auth.ts";

/** Postgres `bytea` as a plain `Uint8Array` (the driver hands back a Buffer; it is copied out). */
const bytea = customType<{ data: Uint8Array; driverData: Uint8Array }>({
  dataType: () => "bytea",
  fromDriver: (value) => new Uint8Array(value),
  toDriver: (value) => value,
});

const id = () =>
  uuid("id")
    .primaryKey()
    .$defaultFn(() => uuidv7());
const userId = () =>
  text("user_id")
    .notNull()
    .references(() => user.id, { onDelete: "cascade" });
const money = (name: string) => bigint(name, { mode: "number" });
const timestamps = {
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  updatedAt: timestamp("updated_at", { withTimezone: true })
    .notNull()
    .defaultNow()
    .$onUpdate(() => new Date()),
};

export const categoryKind = pgEnum("category_kind", ["expense", "income"]);
export const transactionStatus = pgEnum("transaction_status", ["paid", "pending"]);
export const transactionSource = pgEnum("transaction_source", [
  "app",
  "web",
  "widget",
  "mcp",
  "import",
  "recurrence",
  "capture",
]);
export const recurrenceFrequency = pgEnum("recurrence_frequency", ["monthly", "yearly"]);
export const importSource = pgEnum("import_source", ["budge"]);
export const importStatus = pgEnum("import_status", ["preview", "confirmed", "reverted"]);

export const accounts = pgTable(
  "accounts",
  {
    id: id(),
    userId: userId(),
    name: text("name").notNull(),
    currency: char("currency", { length: 3 }).notNull(),
    isDefault: boolean("is_default").notNull().default(false),
    ...timestamps,
  },
  (t) => [uniqueIndex("accounts_one_default").on(t.userId).where(sql`${t.isDefault}`)],
);

export const categories = pgTable(
  "categories",
  {
    id: id(),
    userId: userId(),
    name: text("name").notNull(),
    kind: categoryKind("kind").notNull(),
    icon: text("icon").notNull(),
    color: text("color").notNull(),
    sortOrder: integer("sort_order").notNull().default(0),
    archivedAt: timestamp("archived_at", { withTimezone: true }),
    /** Marks a built-in category the app looks up by key (e.g. the `other` fallback of a capture). */
    systemKey: text("system_key"),
    ...timestamps,
  },
  (t) => [
    uniqueIndex("categories_active_name")
      .on(t.userId, sql`lower(${t.name})`)
      .where(sql`${t.archivedAt} is null`),
    uniqueIndex("categories_system_key")
      .on(t.userId, t.kind, t.systemKey)
      .where(sql`${t.systemKey} is not null and ${t.archivedAt} is null`),
  ],
);

export const categoryBudgets = pgTable(
  "category_budgets",
  {
    id: id(),
    userId: userId(),
    categoryId: uuid("category_id")
      .notNull()
      .references(() => categories.id, { onDelete: "cascade" }),
    amount: money("amount").notNull(),
    effectiveFrom: date("effective_from").notNull(),
    ...timestamps,
  },
  (t) => [uniqueIndex("category_budgets_month").on(t.categoryId, t.effectiveFrom)],
);

export const recurrences = pgTable("recurrences", {
  id: id(),
  userId: userId(),
  accountId: uuid("account_id")
    .notNull()
    .references(() => accounts.id, { onDelete: "cascade" }),
  categoryId: uuid("category_id")
    .notNull()
    .references(() => categories.id, { onDelete: "cascade" }),
  name: text("name").notNull(),
  amount: money("amount").notNull(),
  frequency: recurrenceFrequency("frequency").notNull(),
  dayOfMonth: integer("day_of_month").notNull(),
  monthOfYear: integer("month_of_year"),
  startDate: date("start_date").notNull(),
  endDate: date("end_date"),
  ...timestamps,
});

export const imports = pgTable("imports", {
  id: id(),
  userId: userId(),
  source: importSource("source").notNull(),
  fileHash: text("file_hash").notNull(),
  status: importStatus("status").notNull().default("preview"),
  stats: jsonb("stats").notNull(),
  payload: jsonb("payload"),
  ...timestamps,
});

export const transactions = pgTable(
  "transactions",
  {
    id: id(),
    userId: userId(),
    accountId: uuid("account_id")
      .notNull()
      .references(() => accounts.id, { onDelete: "cascade" }),
    categoryId: uuid("category_id")
      .notNull()
      .references(() => categories.id, { onDelete: "cascade" }),
    name: text("name").notNull(),
    amount: money("amount").notNull(),
    currency: char("currency", { length: 3 }).notNull(),
    date: date("date").notNull(),
    status: transactionStatus("status").notNull().default("paid"),
    note: text("note"),
    recurrenceId: uuid("recurrence_id").references(() => recurrences.id, { onDelete: "set null" }),
    /** First day of the month a recurrence occurrence belongs to; stays put if the user moves its date. */
    occurrenceMonth: date("occurrence_month"),
    importId: uuid("import_id").references(() => imports.id, { onDelete: "set null" }),
    source: transactionSource("source").notNull(),
    externalHash: text("external_hash"),
    /** A captured bank notification waiting for the user to confirm it. */
    needsReview: boolean("needs_review").notNull().default(false),
    captureSource: text("capture_source"),
    /** When the notification was posted on the phone; the duplicate window runs on it. */
    capturedAt: timestamp("captured_at", { withTimezone: true }),
    /** `merchantKey` of the merchant as notified, so renaming the row still teaches that merchant. */
    captureMerchantKey: text("capture_merchant_key"),
    deletedAt: timestamp("deleted_at", { withTimezone: true }),
    ...timestamps,
  },
  (t) => [
    index("transactions_user_date").on(t.userId, t.date),
    index("transactions_user_category_date").on(t.userId, t.categoryId, t.date),
    uniqueIndex("transactions_recurrence_month")
      .on(t.recurrenceId, t.occurrenceMonth)
      .where(sql`${t.recurrenceId} is not null`),
    uniqueIndex("transactions_external_hash").on(t.userId, t.externalHash),
    index("transactions_user_capture")
      .on(t.userId, t.capturedAt)
      .where(sql`${t.capturedAt} is not null`),
  ],
);

/** The category the user last chose for a merchant, so the next capture from it lands there. */
export const merchantCategories = pgTable(
  "merchant_categories",
  {
    id: id(),
    userId: userId(),
    merchantKey: text("merchant_key").notNull(),
    categoryId: uuid("category_id")
      .notNull()
      .references(() => categories.id, { onDelete: "cascade" }),
    ...timestamps,
  },
  (t) => [uniqueIndex("merchant_categories_key").on(t.userId, t.merchantKey)],
);

export const idempotencyKeys = pgTable(
  "idempotency_keys",
  {
    userId: userId(),
    key: text("key").notNull(),
    requestHash: text("request_hash").notNull(),
    status: integer("status").notNull(),
    body: jsonb("body").notNull(),
    createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  },
  (t) => [primaryKey({ columns: [t.userId, t.key] })],
);

/** Per-email throttle for sign-in emails. Not user-scoped, so no RLS. */
export const emailThrottle = pgTable("email_throttle", {
  email: text("email").primaryKey(),
  windowStart: timestamp("window_start", { withTimezone: true }).notNull(),
  count: integer("count").notNull(),
});

/**
 * Admin actions, append-only: the app role has no UPDATE/DELETE (see `grantAppRole`). No foreign
 * keys, so a row outlives the user it names. Not user-scoped.
 */
export const adminAudit = pgTable(
  "admin_audit",
  {
    id: text("id")
      .primaryKey()
      .$defaultFn(() => uuidv7()),
    at: timestamp("at", { withTimezone: true }).notNull().defaultNow(),
    adminUserId: text("admin_user_id"),
    action: text("action").notNull(),
    targetUserId: text("target_user_id"),
    emailHash: text("email_hash"),
    reason: text("reason"),
    detail: jsonb("detail"),
  },
  (t) => [
    index("admin_audit_at_idx").on(t.at.desc()),
    index("admin_audit_target_idx").on(t.targetUserId),
  ],
);

/** When an admin session last re-verified. Goes with the session. */
export const adminVerification = pgTable("admin_verification", {
  sessionId: text("session_id")
    .primaryKey()
    .references(() => session.id, { onDelete: "cascade" }),
  verifiedAt: timestamp("verified_at", { withTimezone: true }).notNull(),
});

/** A pending email change an admin started; only the token's hash is stored. */
export const emailChange = pgTable("email_change", {
  id: text("id")
    .primaryKey()
    .$defaultFn(() => uuidv7()),
  userId: text("user_id")
    .notNull()
    .unique()
    .references(() => user.id, { onDelete: "cascade" }),
  newEmail: text("new_email").notNull(),
  tokenHash: text("token_hash").notNull().unique(),
  expiresAt: timestamp("expires_at", { withTimezone: true }).notNull(),
  createdBy: text("created_by").notNull(),
  createdAt: timestamp("created_at", { withTimezone: true }).defaultNow(),
});

/**
 * End-to-end encrypted records (spec 2026-11-08 section 5.1). The server stores `body` as opaque
 * bytes. `id` is made by the client; `version` comes from `records_version_seq` and is raised on
 * every write with `set version = nextval('records_version_seq')`.
 */
export const records = pgTable(
  "records",
  {
    id: uuid("id").primaryKey(),
    userId: userId(),
    type: text("type").notNull(),
    version: bigint("version", { mode: "number" })
      .notNull()
      .default(sql`nextval('records_version_seq')`),
    deleted: boolean("deleted").notNull().default(false),
    keyV: smallint("key_v").notNull(),
    encV: smallint("enc_v").notNull(),
    body: bytea("body"),
    updatedAt: timestamp("updated_at", { withTimezone: true }).notNull().defaultNow(),
  },
  (t) => [
    index("records_user_version").on(t.userId, t.version),
    check("records_deleted_body", sql`${t.deleted} = (${t.body} is null)`),
  ],
);

/** Copies of the data key wrapped by a passkey, the recovery key, a device or an assistant. */
export const keyWraps = pgTable(
  "key_wraps",
  {
    id: id(),
    userId: userId(),
    kind: text("kind").notNull(),
    ref: text("ref"),
    keyV: smallint("key_v").notNull(),
    wrapped: bytea("wrapped").notNull(),
    publicKey: bytea("public_key"),
    label: text("label"),
    createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
    lastUsedAt: timestamp("last_used_at", { withTimezone: true }),
  },
  (t) => [
    check("key_wraps_kind", sql`${t.kind} in ('passkey', 'recovery', 'device', 'assistant')`),
    uniqueIndex("key_wraps_one_recovery").on(t.userId).where(sql`${t.kind} = 'recovery'`),
    uniqueIndex("key_wraps_ref").on(t.userId, t.kind, t.ref).where(sql`${t.ref} is not null`),
  ],
);

/** A new device waiting to be approved by a signed-in one. */
export const pairingRequests = pgTable(
  "pairing_requests",
  {
    id: id(),
    userId: userId(),
    code: text("code").notNull(),
    publicKey: bytea("public_key").notNull(),
    sealed: bytea("sealed"),
    expiresAt: timestamp("expires_at", { withTimezone: true }).notNull(),
  },
  (t) => [uniqueIndex("pairing_requests_code").on(t.userId, t.code)],
);

/** Tables protected by row-level security on `user_id`. */
export const RLS_TABLES = [
  "accounts",
  "categories",
  "category_budgets",
  "recurrences",
  "imports",
  "transactions",
  "merchant_categories",
  "idempotency_keys",
  "records",
  "key_wraps",
  "pairing_requests",
] as const;
