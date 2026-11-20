import { createRoute, z } from "@hono/zod-openapi";
import type { AppDeps } from "../deps.ts";
import type { Grant } from "../env.ts";
import { jsonBody, jsonResponse, problems } from "../http/openapi.ts";
import { router } from "../http/router.ts";
import {
  cancelMigration,
  finishMigration,
  migrationSource,
  startMigration,
} from "../services/migration.ts";
import { profile, profileDto } from "./me.ts";

const count = z.number().int().min(0);
const MigrationCounts = z
  .object({
    transaction: count,
    deletedTransaction: count.openapi({
      description:
        "Soft-deleted transactions (dismissed months among them): records deleted with a body",
    }),
    category: count,
    budget: count,
    recurrence: count,
    merchant: count,
  })
  .openapi("MigrationCounts", {
    description:
      "Per type, the live rows (records), and the soft-deleted transactions apart. The one `settings` record is checked apart.",
  });

const instant = z.string().openapi({ description: "ISO 8601 timestamp" });
const day = z.string().openapi({ description: "`YYYY-MM-DD`" });

const MigrationSource = z
  .object({
    profile: z.object({
      timezone: z.string(),
      locale: z.string(),
      onboardingCompletedAt: instant.nullable(),
      currency: z.string().openapi({ description: "The default account's currency" }),
    }),
    categories: z.array(
      z.object({
        id: z.string(),
        name: z.string(),
        kind: z.enum(["expense", "income"]),
        icon: z.string(),
        color: z.string(),
        sortOrder: z.number().int(),
        archivedAt: instant.nullable(),
        systemKey: z.string().nullable(),
        createdAt: instant,
        updatedAt: instant,
      }),
    ),
    budgets: z.array(
      z.object({
        id: z.string(),
        categoryId: z.string(),
        amount: z.number().int(),
        effectiveFrom: day.openapi({ description: "`YYYY-MM-DD`, the first day of the month" }),
        createdAt: instant,
        updatedAt: instant,
      }),
    ),
    recurrences: z.array(
      z.object({
        id: z.string(),
        accountId: z.string(),
        categoryId: z.string(),
        name: z.string(),
        amount: z.number().int(),
        frequency: z.enum(["monthly", "yearly"]),
        dayOfMonth: z.number().int(),
        monthOfYear: z.number().int().nullable(),
        startDate: day,
        endDate: day.nullable(),
        createdAt: instant,
        updatedAt: instant,
      }),
    ),
    transactions: z
      .array(
        z.object({
          id: z.string(),
          accountId: z.string(),
          categoryId: z.string(),
          name: z.string(),
          amount: z.number().int(),
          currency: z.string(),
          date: day,
          status: z.enum(["paid", "pending"]),
          note: z.string().nullable(),
          recurrenceId: z.string().nullable(),
          occurrenceMonth: day.nullable(),
          importId: z.string().nullable(),
          source: z.enum(["app", "web", "widget", "mcp", "import", "recurrence", "capture"]),
          externalHash: z.string().nullable(),
          needsReview: z.boolean(),
          captureSource: z.string().nullable(),
          capturedAt: instant.nullable(),
          captureMerchantKey: z.string().nullable(),
          deletedAt: instant.nullable(),
          createdAt: instant,
          updatedAt: instant,
        }),
      )
      .openapi({ description: "Live rows and every soft-deleted one the server still has" }),
    merchants: z.array(
      z.object({
        id: z.string(),
        merchantKey: z.string(),
        categoryId: z.string(),
        createdAt: instant,
        updatedAt: instant,
      }),
    ),
  })
  .openapi("MigrationSource");

const FinishMigration = z.object({ counts: MigrationCounts }).openapi("FinishMigration");

/** The 409 of `finish`: `count_mismatch` carries the three sets of counts in `errors`. */
const MigrationProblem = z
  .object({
    type: z.string(),
    title: z.string(),
    status: z.number().int(),
    code: z.string(),
    detail: z.string().optional(),
    errors: z
      .object({
        server: MigrationCounts,
        records: MigrationCounts,
        client: MigrationCounts,
        missing: z
          .array(z.object({ type: z.string(), id: z.string() }))
          .max(20)
          .openapi({
            description:
              "Rows with no record of their own type, id and state (at most 20): the record type and the id the record should have",
          }),
      })
      .optional(),
  })
  .openapi("MigrationProblem");

const sessionIdOf = (grant: Grant) => (grant.kind === "session" ? grant.sessionId : null);

/**
 * The switch day (spec 2026-11-19 §2): a plain account moves to end-to-end encryption from the
 * web. Sessions only (assistants get 403 from the scopes). The source answer is never logged.
 */
export function migrationRoutes(deps: AppDeps) {
  const app = router();

  app.openapi(
    createRoute({
      method: "post",
      path: "/v2/migration/start",
      operationId: "startMigration",
      description:
        "Starts moving a plain account with an email to end-to-end encryption (once the move is open to it) and binds it to this session: while it runs, only this session may push records or write key material (others get 409 `migration_in_progress`). On a migrating account it takes the move over for this session. Answers the server's counts; a retry answers the same. 409 `not_migratable` otherwise.",
      responses: {
        200: jsonResponse(MigrationCounts, "The server's counts"),
        ...problems(403, 409),
      },
    }),
    async (c) =>
      c.json(
        await startMigration(deps.db, deps.config, c.get("userId"), sessionIdOf(c.get("grant"))),
        200,
      ),
  );

  app.openapi(
    createRoute({
      method: "get",
      path: "/v2/migration/source",
      operationId: "migrationSource",
      description:
        "Every finance row of the migrating account, with the server's ids, for the bound session. 409 `not_migrating`, or `migration_in_progress` for another session.",
      responses: {
        200: jsonResponse(MigrationSource, "The plaintext rows"),
        ...problems(403, 409),
      },
    }),
    async (c) =>
      c.json(await migrationSource(deps.db, c.get("userId"), sessionIdOf(c.get("grant"))), 200),
  );

  app.openapi(
    createRoute({
      method: "post",
      path: "/v2/migration/finish",
      operationId: "finishMigration",
      description:
        "Ends the move, from the bound session. Only when the records hold exactly one live `settings` record, a record for every row (its type, its id: the server's, or the derived one of a dismissed month or a merchant rule, and its state), and the same counts as the server and as `counts` does it delete the plaintext rows, revoke the assistants and make the account encrypted; else 409 `count_mismatch` (with `errors.server`, `errors.records`, `errors.client` and `errors.missing`) and nothing changes. 409 `keys_missing` without a recovery wrap; 409 `key_version_mismatch` when a record is sealed under a key version the current key does not reach (neither the current one nor an older one its key links lead to).",
      request: { body: jsonBody(FinishMigration) },
      responses: {
        200: jsonResponse(profileDto, "The profile, now encrypted"),
        409: {
          content: { "application/problem+json": { schema: MigrationProblem } },
          description: "Problem",
        },
        ...problems(403, 422),
      },
    }),
    async (c) => {
      const userId = c.get("userId");
      await finishMigration(
        deps.db,
        userId,
        sessionIdOf(c.get("grant")),
        c.req.valid("json").counts,
      );
      return c.json(await profile(deps, userId), 200);
    },
  );

  app.openapi(
    createRoute({
      method: "post",
      path: "/v2/migration/cancel",
      operationId: "cancelMigration",
      description:
        "Gives up on the move, from the bound session: deletes the account's records, keeps its key wraps and makes it plain again.",
      responses: { 204: { description: "Cancelled" }, ...problems(403, 409) },
    }),
    async (c) => {
      await cancelMigration(deps.db, c.get("userId"), sessionIdOf(c.get("grant")));
      return c.body(null, 204);
    },
  );

  return app;
}
