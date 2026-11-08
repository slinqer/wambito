import type { ClientMetadataResourceFetch } from "@better-auth/oauth-provider";
import type { Db } from "@wambito/db";
import type { Config } from "./config.ts";
import type { Mailer } from "./mailer.ts";

/** Test-only seams in `POST /v2/sync` (services/sync.ts). Production passes none. */
export interface SyncHooks {
  /**
   * Awaited after a push has written its changes and before its transaction commits, while it
   * still holds the person's records lock: tests delay it to check that versions become visible in
   * commit order. Read on every push, so a test may set it after the app is built.
   */
  beforeCommit?: () => Promise<void>;
}

export interface AppDeps {
  config: Config;
  db: Db;
  mailer: Mailer;
  /**
   * The clock the API reads "today" and "this month" from. Unset: the real one. The e2e stack pins
   * it with E2E_NOW (server.ts), and tests can pass their own.
   */
  now?: () => Date;
  /**
   * Fetches an assistant's Client ID Metadata Document. Unset: `@better-auth/cimd/node`'s, which
   * resolves DNS once, refuses private and special-use addresses, pins the address and never
   * follows a redirect. Tests pass their own.
   */
  fetchClientMetadata?: ClientMetadataResourceFetch;
  /** Test-only hooks into `POST /v2/sync`; see SyncHooks. */
  syncHooks?: SyncHooks;
}
