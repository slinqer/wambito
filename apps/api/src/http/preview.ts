import { createMiddleware } from "hono/factory";
import { type Config, isPreviewAccount } from "../config.ts";
import type { AppEnv } from "../env.ts";
import { ApiError } from "./problem.ts";

/**
 * The `/v1` finance routes: what a preview account (`E2E_PREVIEW_USER_IDS`) keeps only as
 * encrypted records under `/v2`. The account itself (`/v1/me` GET/PATCH/DELETE, the assistants,
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

export const encryptedAccount = () =>
  new ApiError(
    403,
    "encrypted_account",
    "This account keeps its finances end-to-end encrypted; use /v2/sync",
  );

/**
 * A preview account uses `/v2` only: its `/v1` finance routes answer 403 `encrypted_account`,
 * whether the request comes from a session or an assistant's token (after `requireUser`).
 */
export function previewOnlyV2(config: Pick<Config, "E2E_PREVIEW_USER_IDS">) {
  return createMiddleware<AppEnv>(async (c, next) => {
    if (isPreviewAccount(config, c.get("userId"))) {
      const path = c.req.path.replace(/^.*?(?=\/v1\/)/, "");
      if (FINANCE_PATHS.some((p) => p.test(path))) throw encryptedAccount();
    }
    await next();
  });
}
