import { createMiddleware } from "hono/factory";
import { isPreviewAccount } from "../config.ts";
import type { AppDeps } from "../deps.ts";
import type { AppEnv } from "../env.ts";
import { accountEncryption } from "../services/encryption.ts";
import { ApiError } from "./problem.ts";

/**
 * The `/v1` finance routes: what a preview account (`migrating`, `encrypted` or listed in
 * `E2E_PREVIEW_USER_IDS`) keeps only as encrypted records under `/v2`. The account itself (`/v1/me` GET/PATCH/DELETE, the assistants,
 * claiming an email) is not here.
 */
const FINANCE_PATHS = [
  /^\/v1\/transactions(\/|$)/,
  /^\/v1\/categories(\/|$)/,
  /^\/v1\/recurrences(\/|$)/,
  /^\/v1\/summary$/,
  /^\/v1\/reports\//,
  /^\/v1\/captures(\/|$)/,
  /^\/v1\/imports(\/|$)/,
  /^\/v1\/me\/export$/,
];

/**
 * 426 `update_required`: the client predates the account's move to end-to-end encryption (its
 * finances are records under `/v2/sync` now). The web reloads; the MCP asks to connect again.
 */
export const updateRequired = () =>
  new ApiError(
    426,
    "update_required",
    "This account keeps its finances end-to-end encrypted; update the app",
  );

/**
 * A preview account uses `/v2` only: its `/v1` finance routes answer 426 `update_required`,
 * whether the request comes from a session or an assistant's token (after `requireUser`).
 */
export function previewOnlyV2(deps: Pick<AppDeps, "config" | "db">) {
  return createMiddleware<AppEnv>(async (c, next) => {
    const path = c.req.path.replace(/^.*?(?=\/v1\/)/, "");
    if (FINANCE_PATHS.some((p) => p.test(path))) {
      const userId = c.get("userId");
      const encryption = await accountEncryption(deps.db, userId);
      if (isPreviewAccount(deps.config, { id: userId, encryption })) throw updateRequired();
    }
    await next();
  });
}
