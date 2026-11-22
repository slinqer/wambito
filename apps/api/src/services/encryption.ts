import type { Db } from "@wambito/db";
import { user } from "@wambito/db";
import { eq } from "@wambito/db/orm";
import type { Config } from "../config.ts";

/**
 * How an account keeps its finances: `plain` (the server reads them, `/v1`), `encrypted` (only
 * end-to-end encrypted records, `/v2`), or `migrating` (the switch day, spec 2026-11-19 §1: the
 * web is moving a plain account's finances into records). A user born while `NEW_USERS_ENCRYPTED`
 * is on is `encrypted`; every other user is born `plain`. A `migrating` account behaves as a
 * `plain` one everywhere (session length, cleanup tiers, 401 codes, recovery sign-in) except for
 * the 426 on `/v1` finance routes and the migration's write rule.
 */
export type Encryption = "plain" | "migrating" | "encrypted";

/** A stored `user.encryption` as an `Encryption`; anything unknown is `plain`. */
export function toEncryption(value: string | null | undefined): Encryption {
  return value === "encrypted" || value === "migrating" ? value : "plain";
}

/** The account's `encryption`; `plain` for an id that does not exist (the caller then 401s). */
export async function accountEncryption(db: Db, userId: string): Promise<Encryption> {
  const [row] = await db
    .select({ encryption: user.encryption })
    .from(user)
    .where(eq(user.id, userId));
  return toEncryption(row?.encryption);
}

/**
 * The `migration` field of `GET /v1/me` (spec 2026-11-19 §1): `available` for a `plain` account
 * with an email while `MIGRATION_OPEN` is on or its id is in `MIGRATION_OPEN_USER_IDS`;
 * `in_progress` while `migrating`; none otherwise (a guest, an encrypted account, a closed gate).
 */
export function migrationOf(
  config: Pick<Config, "MIGRATION_OPEN" | "MIGRATION_OPEN_USER_IDS">,
  account: { id: string; encryption: Encryption; isAnonymous: boolean },
): "available" | "in_progress" | undefined {
  if (account.encryption === "migrating") return "in_progress";
  if (account.encryption !== "plain" || account.isAnonymous) return undefined;
  return config.MIGRATION_OPEN || config.MIGRATION_OPEN_USER_IDS.includes(account.id)
    ? "available"
    : undefined;
}
