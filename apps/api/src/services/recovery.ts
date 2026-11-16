import { createHash, timingSafeEqual } from "node:crypto";
import { type Db, keyWraps, recoveryVerifiers, withUser } from "@wambito/db";
import { and, eq, ne } from "@wambito/db/orm";
import { isUniqueViolation } from "../http/db-errors.ts";
import { ApiError } from "../http/problem.ts";
import { lockWraps } from "./keys.ts";

const sha256 = (bytes: Uint8Array) => new Uint8Array(createHash("sha256").update(bytes).digest());

/** Compared with when the lookup finds nothing, so a miss costs what a wrong auth costs. */
const NO_HASH = new Uint8Array(32);

const verifierTaken = () =>
  new ApiError(409, "verifier_taken", "This recovery key is already another account's");

/**
 * Stores the person's recovery verifier (SHA-256 of the key's lookup and auth bytes), replacing
 * any earlier one: only the newest recovery key signs in. Needs a recovery wrap (409
 * `recovery_required`): a key that opens no wrap would sign in to an account it cannot read. A
 * lookup hash another user holds is 409 `verifier_taken`. Under the person's wrap lock, so a
 * recovery wrap replaced at the same time (which deletes the verifier, `putKeyWrap`) cannot
 * interleave with it.
 */
export async function putVerifier(
  db: Db,
  userId: string,
  lookupHash: Uint8Array,
  authHash: Uint8Array,
): Promise<void> {
  try {
    await withUser(db, userId, async (tx) => {
      await lockWraps(tx, userId);
      const [wrap] = await tx
        .select({ id: keyWraps.id })
        .from(keyWraps)
        .where(and(eq(keyWraps.userId, userId), eq(keyWraps.kind, "recovery")))
        .limit(1);
      if (!wrap) {
        throw new ApiError(
          409,
          "recovery_required",
          "Store the recovery wrap before the recovery key's verifier",
        );
      }
      const [held] = await tx
        .select({ userId: recoveryVerifiers.userId })
        .from(recoveryVerifiers)
        .where(
          and(eq(recoveryVerifiers.lookupHash, lookupHash), ne(recoveryVerifiers.userId, userId)),
        )
        .limit(1);
      if (held) throw verifierTaken();
      await tx
        .insert(recoveryVerifiers)
        .values({ userId, lookupHash, authHash })
        .onConflictDoUpdate({
          target: recoveryVerifiers.userId,
          set: { lookupHash, authHash, createdAt: new Date() },
        });
    });
  } catch (error) {
    // Two people storing the same lookup at once: the unique index refuses the second.
    if (!(error instanceof ApiError) && isUniqueViolation(error)) throw verifierTaken();
    throw error;
  }
}

/**
 * The user whose verifier `lookup` and `auth` (the raw bytes a recovery key derives) match; null
 * otherwise, the same way for an unknown lookup and a wrong auth. Both are hashed as stored; the
 * auth hash is compared in constant time.
 */
export async function findVerifiedUser(
  db: Db,
  lookup: Uint8Array,
  auth: Uint8Array,
): Promise<string | null> {
  const [row] = await db
    .select({ userId: recoveryVerifiers.userId, authHash: recoveryVerifiers.authHash })
    .from(recoveryVerifiers)
    .where(eq(recoveryVerifiers.lookupHash, sha256(lookup)))
    .limit(1);
  const given = sha256(auth);
  const stored = row?.authHash.length === given.length ? row.authHash : NO_HASH;
  const match = timingSafeEqual(given, stored);
  return row && match && stored !== NO_HASH ? row.userId : null;
}
