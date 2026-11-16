import type { Db } from "@wambito/db";
import { user } from "@wambito/db";
import { eq } from "@wambito/db/orm";

/**
 * How an account keeps its finances: `plain` (the server reads them, `/v1`) or `encrypted` (only
 * end-to-end encrypted records, `/v2`). Fixed at sign-up: a user born while `NEW_USERS_ENCRYPTED`
 * is on is `encrypted`; every other user is `plain`.
 */
export type Encryption = "plain" | "encrypted";

/** The account's `encryption`; `plain` for an id that does not exist (the caller then 401s). */
export async function accountEncryption(db: Db, userId: string): Promise<Encryption> {
  const [row] = await db
    .select({ encryption: user.encryption })
    .from(user)
    .where(eq(user.id, userId));
  return row?.encryption === "encrypted" ? "encrypted" : "plain";
}
