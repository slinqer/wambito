import { createRoute, z } from "@hono/zod-openapi";
import { formatMinorAsDecimal } from "@wambito/core";
import {
  accounts,
  categories,
  categoryBudgets,
  recurrences,
  type Tx,
  transactions,
  user,
  withUser,
} from "@wambito/db";
import { and, asc, eq, isNull, sql } from "@wambito/db/orm";
import {
  type ClaimCodeResult,
  consumeClaimCode,
  dropClaimCodes,
  isSignInAllowed,
  issueClaimCode,
  overEmailLimit,
  sendClaimCode,
} from "../auth.ts";
import { isPreviewAccount } from "../config.ts";
import type { AppDeps } from "../deps.ts";
import { isUniqueViolation } from "../http/db-errors.ts";
import { jsonBody, jsonResponse, problems } from "../http/openapi.ts";
import { encryptedAccount } from "../http/preview.ts";
import { ApiError } from "../http/problem.ts";
import { router } from "../http/router.ts";
import { UpdateProfile } from "../http/schemas.ts";
import { deleteAccount } from "../services/account.ts";
import { userToday } from "../services/time.ts";
import { defaultAccount, toTransactionDto } from "../services/transactions.ts";

const profileDto = z
  .object({
    id: z.string(),
    email: z.string(),
    timezone: z.string(),
    locale: z.string(),
    onboardingCompletedAt: z.string().nullable(),
    currency: z.string(),
    /** A guest: signed up on the app without an email (its `email` is a placeholder until claimed). */
    isAnonymous: z.boolean(),
    /**
     * `preview`: the account keeps its finances only as end-to-end encrypted records (`/v2`), and
     * its `/v1` finance routes stay empty; `plain`: every other account.
     */
    encryption: z.enum(["plain", "preview"]),
  })
  .openapi("Profile");

/** An email as sign-in reads it: trimmed and lowercased. */
const emailField = z.string().trim().toLowerCase().pipe(z.email().max(254));

const claimSendBody = z.object({ email: emailField }).openapi("ClaimEmailSend");
const claimVerifyBody = z
  .object({ email: emailField, code: z.string().trim().min(1).max(32) })
  .openapi("ClaimEmailVerify");

const notAGuest = () => new ApiError(409, "not_a_guest", "This account already has an email");
const emailTaken = () => new ApiError(409, "email_taken", "That email already has an account");

/**
 * A claim code that did not work, with sign-in's codes and statuses (Better Auth's emailOTP:
 * INVALID_OTP 400, TOO_MANY_ATTEMPTS 403, OTP_EXPIRED 400), so the app shows the same messages.
 */
const CLAIM_CODE_PROBLEMS = {
  wrong: () => new ApiError(400, "invalid_code", "The code is wrong"),
  exhausted: () => new ApiError(403, "too_many_attempts", "Too many wrong tries with this code"),
  expired: () => new ApiError(400, "invalid_or_expired_code", "The code expired"),
  missing: () => new ApiError(400, "invalid_or_expired_code", "No such code, or already used"),
} satisfies Record<Exclude<ClaimCodeResult, "ok">, () => ApiError>;

/** The guest gate of the claim: only an anonymous user may claim an email. */
async function requireGuest(deps: AppDeps, userId: string) {
  const [row] = await deps.db
    .select({ isAnonymous: user.isAnonymous })
    .from(user)
    .where(eq(user.id, userId));
  if (!row?.isAnonymous) throw notAGuest();
}

/** The allowlist gate, the same as sign-in's (and a guest's `.invalid` placeholder never passes). */
function requireAllowed(deps: AppDeps, email: string) {
  if (!isSignInAllowed(deps.config, email)) {
    throw new ApiError(403, "sign_in_not_allowed", "Sign-in is not open to this address");
  }
}

const csvField = (value: string) =>
  /[",\n\r]/.test(value) ? `"${value.replaceAll('"', '""')}"` : value;

async function profile(deps: AppDeps, userId: string) {
  // Every profile the API answers with is the same one, so each read stamps (see the function).
  await stampOnboardedIfUsed(deps, userId);
  const [row] = await deps.db
    .select({
      id: user.id,
      email: user.email,
      timezone: user.timezone,
      locale: user.locale,
      onboardingCompletedAt: user.onboardingCompletedAt,
      isAnonymous: user.isAnonymous,
    })
    .from(user)
    .where(eq(user.id, userId));
  if (!row) throw new ApiError(401, "unauthenticated", "Sign in to continue");
  const [account] = await withUser(deps.db, userId, (tx) =>
    tx.select({ currency: accounts.currency }).from(accounts).where(eq(accounts.isDefault, true)),
  );
  return {
    ...row,
    onboardingCompletedAt: row.onboardingCompletedAt?.toISOString() ?? null,
    currency: account?.currency ?? "EUR",
    encryption: isPreviewAccount(deps.config, userId) ? ("preview" as const) : ("plain" as const),
  };
}

/**
 * Sets the default account's currency, only while it has no transactions (soft-deleted ones
 * count: they carry the old currency and can be restored) and no recurrences (they would later
 * materialize their old-currency amounts in the new one). The check is part of the UPDATE itself;
 * it runs in the caller's transaction, so a 409 rolls back the whole PATCH.
 */
async function setCurrency(tx: Tx, currency: string) {
  // Wait for any import or new transaction holding the account's lock. Taken in its own statement:
  // the UPDATE below then reads a fresh snapshot, so its `not exists` sees rows those writers just
  // committed. (Left to the UPDATE alone, Postgres would re-check the row after the wait but run
  // the subquery against the old snapshot, and switch an account that now has transactions.)
  await defaultAccount(tx, { lock: true });
  const changed = await tx
    .update(accounts)
    .set({ currency })
    .where(
      and(
        eq(accounts.isDefault, true),
        // Written out: Drizzle renders columns unqualified inside UPDATE, so `id` would be ambiguous.
        sql`not exists (select 1 from transactions t where t.account_id = accounts.id)`,
        sql`not exists (select 1 from recurrences r where r.account_id = accounts.id)`,
      ),
    )
    .returning({ id: accounts.id });
  if (changed.length > 0) return;
  // Nothing changed: fine if the account already has that currency, locked otherwise.
  const [account] = await tx
    .select({ currency: accounts.currency })
    .from(accounts)
    .where(eq(accounts.isDefault, true));
  if (account?.currency !== currency) {
    throw new ApiError(
      409,
      "currency_locked",
      "The currency cannot change once the account has transactions or recurrences",
    );
  }
}

/**
 * An account with at least one transaction that did not come from an import has been through
 * whatever the welcome is for, so reading its profile stamps `onboardingCompletedAt` when it is
 * still null. It covers the accounts made before the welcome reached the app (the app had none, and
 * its accounts have data): neither client sends them to it, and its "Entrar directo" never touches
 * their categories. Once: a stamped account is left as it is, and an empty one (the welcome's) is
 * not stamped. Imports do not count: the welcome's import step comes before its categories and
 * budgets, so an account with only imported rows is still in its welcome (before imports reached
 * the app, those accounts had manual or captured rows). Soft-deleted transactions count, as they
 * do for the currency's lock.
 */
async function stampOnboardedIfUsed(deps: AppDeps, userId: string) {
  await withUser(deps.db, userId, (tx) =>
    tx
      .update(user)
      .set({ onboardingCompletedAt: sql`now()` })
      .where(
        and(
          eq(user.id, userId),
          isNull(user.onboardingCompletedAt),
          // Row-level security limits `transactions` to this user's.
          sql`exists (select 1 from transactions where import_id is null)`,
        ),
      ),
  );
}

export function meRoutes(deps: AppDeps) {
  const app = router();

  app.openapi(
    createRoute({
      method: "get",
      path: "/v1/me",
      operationId: "getMe",
      responses: { 200: jsonResponse(profileDto, "Profile") },
    }),
    async (c) => c.json(await profile(deps, c.get("userId")), 200),
  );

  app.openapi(
    createRoute({
      method: "patch",
      path: "/v1/me",
      operationId: "updateMe",
      description:
        "Updates the profile. `currency` is the default account's; an end-to-end encrypted account (preview) keeps it in its records, so sending it is 403 `encrypted_account`.",
      request: { body: jsonBody(UpdateProfile) },
      responses: { 200: jsonResponse(profileDto, "Updated profile"), ...problems(403, 409, 422) },
    }),
    async (c) => {
      const { onboardingCompleted, currency, ...fields } = c.req.valid("json");
      const userId = c.get("userId");
      // A preview account's currency lives in its settings record.
      if (currency && isPreviewAccount(deps.config, userId)) throw encryptedAccount();
      const set = {
        ...fields,
        // Stamp completion once; later calls keep the first timestamp.
        ...(onboardingCompleted
          ? { onboardingCompletedAt: sql`coalesce(${user.onboardingCompletedAt}, now())` }
          : {}),
      };
      // One transaction: a locked currency (409) leaves every other field untouched.
      await withUser(deps.db, userId, async (tx) => {
        if (currency) await setCurrency(tx, currency);
        if (Object.keys(set).length > 0) {
          await tx.update(user).set(set).where(eq(user.id, userId));
        }
      });
      return c.json(await profile(deps, c.get("userId")), 200);
    },
  );

  // Saving a guest's progress (spec §4.2): the guest's own user receives the email, so its id,
  // sessions and every row stay; nothing is copied.
  app.openapi(
    createRoute({
      method: "post",
      path: "/v1/me/claim-email/send",
      operationId: "claimEmailSend",
      request: { body: jsonBody(claimSendBody) },
      responses: {
        204: { description: "A code is on its way to the email" },
        ...problems(403, 409, 422, 429),
      },
    }),
    async (c) => {
      const { email } = c.req.valid("json");
      const sessionUser = c.get("user");
      await requireGuest(deps, sessionUser.id);
      requireAllowed(deps, email);
      // The app then says to sign in with that email instead; the guest stays as it is.
      const [owner] = await deps.db.select({ id: user.id }).from(user).where(eq(user.email, email));
      if (owner) throw emailTaken();
      if (await overEmailLimit(deps, email)) {
        throw new ApiError(429, "too_many_requests", "Too many codes requested for this email");
      }
      const code = await issueClaimCode(deps, sessionUser.id, email);
      await sendClaimCode(deps, { email, code, locale: sessionUser.locale });
      return c.body(null, 204);
    },
  );

  app.openapi(
    createRoute({
      method: "post",
      path: "/v1/me/claim-email/verify",
      operationId: "claimEmailVerify",
      request: { body: jsonBody(claimVerifyBody) },
      responses: {
        200: jsonResponse(profileDto, "The profile, no longer a guest"),
        ...problems(400, 403, 409, 422),
      },
    }),
    async (c) => {
      const { email, code } = c.req.valid("json");
      const userId = c.get("userId");
      await requireGuest(deps, userId);
      requireAllowed(deps, email);
      const result = await consumeClaimCode(deps, userId, email, code);
      if (result !== "ok") throw CLAIM_CODE_PROBLEMS[result]();
      let claimed: { id: string }[];
      try {
        // One statement in one transaction. A concurrent claim of the same email by another guest
        // waits on the unique email index and then fails it: that one gets email_taken.
        claimed = await withUser(deps.db, userId, (tx) =>
          tx
            .update(user)
            .set({ email, emailVerified: true, isAnonymous: false })
            .where(and(eq(user.id, userId), eq(user.isAnonymous, true)))
            .returning({ id: user.id }),
        );
      } catch (error) {
        if (isUniqueViolation(error)) throw emailTaken();
        throw error;
      }
      if (claimed.length === 0) throw notAGuest();
      await dropClaimCodes(deps, userId);
      return c.json(await profile(deps, userId), 200);
    },
  );

  app.openapi(
    createRoute({
      method: "get",
      path: "/v1/me/export",
      operationId: "exportMe",
      request: { query: z.object({ format: z.enum(["json", "csv"]).default("json") }) },
      responses: {
        200: {
          description: "All of the user's data (JSON) or their transactions (CSV)",
          content: { "application/json": { schema: z.any() }, "text/csv": { schema: z.string() } },
        },
      },
    }),
    async (c) => {
      const { format } = c.req.valid("query");
      const userId = c.get("userId");
      const me = await profile(deps, userId);
      const data = await withUser(deps.db, userId, async (tx) => ({
        accounts: await tx.select().from(accounts),
        categories: await tx.select().from(categories).orderBy(asc(categories.createdAt)),
        budgets: await tx.select().from(categoryBudgets),
        transactions: await tx
          .select()
          .from(transactions)
          .where(isNull(transactions.deletedAt))
          .orderBy(asc(transactions.date), asc(transactions.id)),
        recurrences: await tx.select().from(recurrences),
      }));
      const stamp = userToday(deps, me);

      if (format === "csv") {
        const names = new Map(data.categories.map((cat) => [cat.id, cat.name]));
        const lines = data.transactions.map((t) =>
          [
            t.date,
            t.name,
            formatMinorAsDecimal(t.amount),
            t.currency,
            names.get(t.categoryId) ?? "",
            t.status,
            t.note ?? "",
          ]
            .map(csvField)
            .join(","),
        );
        return c.body(
          ["date,name,amount,currency,category,status,note", ...lines].join("\n"),
          200,
          {
            "content-type": "text/csv; charset=utf-8",
            "content-disposition": `attachment; filename="wambito-export-${stamp}.csv"`,
          },
        );
      }

      const body = {
        exportedAt: new Date().toISOString(),
        user: me,
        ...data,
        transactions: data.transactions.map(toTransactionDto),
      };
      return c.body(JSON.stringify(body), 200, {
        "content-type": "application/json",
        "content-disposition": `attachment; filename="wambito-export-${stamp}.json"`,
      });
    },
  );

  app.openapi(
    createRoute({
      method: "delete",
      path: "/v1/me",
      operationId: "deleteMe",
      responses: { 204: { description: "Account and all data permanently deleted" } },
    }),
    async (c) => {
      await deleteAccount(deps.db, c.get("userId"));
      return c.body(null, 204);
    },
  );

  return app;
}
