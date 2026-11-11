import { LINK_BYTES } from "@wambito/crypto";
import {
  type Db,
  keyLinks,
  keyWraps,
  oauthConsent,
  passkey,
  session,
  type Tx,
  withUser,
} from "@wambito/db";
import { and, asc, eq, inArray, ne, type SQL, sql } from "@wambito/db/orm";
import { ApiError } from "../http/problem.ts";
import type { KEY_WRAP_KINDS } from "../http/schemas.ts";

type KeyWrapKind = (typeof KEY_WRAP_KINDS)[number];
type KeyWrapRow = typeof keyWraps.$inferSelect;

/** A wrap as it travels: bytes are base64url, dates ISO 8601. */
export interface KeyWrapDto {
  id: string;
  kind: KeyWrapKind;
  ref: string | null;
  keyV: number;
  wrapped: string;
  publicKey: string | null;
  attestation: string | null;
  label: string | null;
  createdAt: string;
  lastUsedAt: string | null;
}

/** A wrap to store; bytes base64url, already checked by the route's schema. */
export interface KeyWrapInput {
  kind: KeyWrapKind;
  ref?: string | null;
  keyV: number;
  wrapped: string;
  publicKey?: string | null;
  attestation?: string | null;
  label?: string | null;
}

const b64 = (bytes: Uint8Array) => Buffer.from(bytes).toString("base64url");
const bytes = (text: string) => new Uint8Array(Buffer.from(text, "base64url"));

export function toKeyWrap(row: KeyWrapRow): KeyWrapDto {
  return {
    id: row.id,
    // Only ever written from a validated wrap, and the table checks it.
    kind: row.kind as KeyWrapKind,
    ref: row.ref,
    keyV: row.keyV,
    wrapped: b64(row.wrapped),
    publicKey: row.publicKey === null ? null : b64(row.publicKey),
    attestation: row.attestation === null ? null : b64(row.attestation),
    label: row.label,
    createdAt: row.createdAt.toISOString(),
    lastUsedAt: row.lastUsedAt?.toISOString() ?? null,
  };
}

/**
 * Takes the transaction-level lock on one person's wraps. Every write to `key_wraps` takes it
 * first, so the current keyV a write checks cannot change before it commits.
 */
async function lockWraps(tx: Tx, userId: string): Promise<void> {
  await tx.execute(
    sql`select pg_advisory_xact_lock(hashtextextended(${`key_wraps:${userId}`}, 0))`,
  );
}

/** The account's current key version: the highest over its wraps; null when it has none. */
export async function currentKeyV(tx: Tx, userId: string): Promise<number | null> {
  const [row] = await tx
    .select({ keyV: sql<number | null>`max(${keyWraps.keyV})` })
    .from(keyWraps)
    .where(eq(keyWraps.userId, userId));
  return row?.keyV == null ? null : Number(row.keyV);
}

/** One of `userId`'s wraps: every statement names the person too, on top of row-level security. */
const own = (userId: string, ...conditions: (SQL | undefined)[]) =>
  and(eq(keyWraps.userId, userId), ...conditions);

/**
 * A passkey wrap's ref must be one of the person's passkey credential ids; an assistant wrap's, an
 * OAuth client the person consented to. Devices are not registered anywhere else, so any ref goes.
 */
async function checkRef(tx: Tx, userId: string, wrap: KeyWrapInput): Promise<void> {
  const ref = wrap.ref ?? "";
  if (wrap.kind === "passkey") {
    const [found] = await tx
      .select({ id: passkey.id })
      .from(passkey)
      .where(and(eq(passkey.userId, userId), eq(passkey.credentialID, ref)))
      .limit(1);
    if (!found) throw new ApiError(422, "unknown_passkey", "No passkey of yours has this id");
  }
  if (wrap.kind === "assistant") {
    const [found] = await tx
      .select({ id: oauthConsent.id })
      .from(oauthConsent)
      .where(and(eq(oauthConsent.userId, userId), eq(oauthConsent.clientId, ref)))
      .limit(1);
    if (!found)
      throw new ApiError(422, "unknown_assistant", "You have not connected this assistant");
  }
}

/**
 * The caller's session id, or null for an OAuth grant. A device wrap remembers the session that
 * registered it; removing the wrap ends that session, except the caller's own.
 */
export interface SessionOption {
  sessionId: string | null;
}

/**
 * Ends `sessionIds` (the removed devices'), in the caller's transaction, after the wraps were
 * deleted or replaced: never the caller's own, and never one a remaining device wrap of the person
 * still uses (a browser that enrolled again under the same session keeps its old wrap when the
 * delete of it failed; removing that stale wrap must not sign the good one out).
 */
async function endSessions(
  tx: Tx,
  userId: string,
  sessionIds: (string | null)[],
  callerSessionId: string | null,
): Promise<void> {
  const ids = sessionIds.filter((id): id is string => id !== null && id !== callerSessionId);
  if (ids.length === 0) return;
  const inUse = await tx
    .select({ sessionId: keyWraps.sessionId })
    .from(keyWraps)
    .where(own(userId, inArray(keyWraps.sessionId, ids)));
  const used = new Set(inUse.map((row) => row.sessionId));
  const ended = ids.filter((id) => !used.has(id));
  if (ended.length === 0) return;
  await tx.delete(session).where(and(eq(session.userId, userId), inArray(session.id, ended)));
}

const values = (
  userId: string,
  id: string,
  wrap: KeyWrapInput,
  sessionId: string | null = null,
) => ({
  id,
  userId,
  kind: wrap.kind,
  ref: wrap.kind === "recovery" ? null : (wrap.ref ?? null),
  keyV: wrap.keyV,
  wrapped: bytes(wrap.wrapped),
  publicKey: wrap.publicKey == null ? null : bytes(wrap.publicKey),
  attestation: wrap.attestation == null ? null : bytes(wrap.attestation),
  label: wrap.label ?? null,
  sessionId: wrap.kind === "device" ? sessionId : null,
});

/** A device wrap carries its public key and the attestation of it; the server cannot check it. */
function checkAttestation(wrap: KeyWrapInput): void {
  if (wrap.kind === "device" && (wrap.publicKey == null || wrap.attestation == null)) {
    throw new ApiError(
      422,
      "attestation_required",
      "A device wrap needs its public key and an attestation",
    );
  }
}

const keyVersionMismatch = (current: number, expected: number) =>
  new ApiError(
    409,
    "key_version_mismatch",
    `The account's key version is ${current}; this needs ${expected}`,
  );

const recoveryRequired = () =>
  new ApiError(
    409,
    "recovery_required",
    "An account always keeps its recovery wrap; make a new recovery key to replace it",
  );

/** A key link as it travels: the version it leads to and its 60 bytes, base64url. */
export interface KeyLinkDto {
  keyV: number;
  link: string;
}

async function listLinks(tx: Tx, userId: string): Promise<KeyLinkDto[]> {
  const rows = await tx
    .select({ keyV: keyLinks.keyV, link: keyLinks.link })
    .from(keyLinks)
    .where(eq(keyLinks.userId, userId))
    .orderBy(asc(keyLinks.keyV));
  return rows.map((row) => ({ keyV: row.keyV, link: b64(row.link) }));
}

/** Every wrap of the account's data key, and the links between its versions, by keyV. */
export async function listKeys(
  db: Db,
  userId: string,
): Promise<{ wraps: KeyWrapDto[]; links: KeyLinkDto[] }> {
  return withUser(db, userId, async (tx) => {
    const rows = await tx
      .select()
      .from(keyWraps)
      .where(own(userId))
      .orderBy(asc(keyWraps.createdAt), asc(keyWraps.id));
    return { wraps: rows.map(toKeyWrap), links: await listLinks(tx, userId) };
  });
}

/**
 * Adds wrap `id`, or replaces it when it is already the person's. The wrap must carry the
 * account's current keyV (any keyV for the first wrap), and an account's first wrap is its
 * recovery wrap (422 `recovery_required`). It also replaces the wrap it would
 * otherwise duplicate: the recovery wrap (one per account), or the wrap of the same kind and ref.
 * The recovery wrap's id cannot take another kind (409 `recovery_required`). An id that is someone
 * else's is 409 `id_taken`. `onlyFirst` (`If-None-Match: *`): only while the account has no wrap
 * but `id` itself (a retry of the same PUT), else 409 `already_set_up`; checked under the lock, so
 * of two setups at once exactly one makes the account's data key.
 */
export async function putKeyWrap(
  db: Db,
  userId: string,
  id: string,
  wrap: KeyWrapInput,
  { onlyFirst = false, sessionId }: { onlyFirst?: boolean } & SessionOption,
): Promise<KeyWrapDto> {
  checkAttestation(wrap);
  return withUser(db, userId, async (tx) => {
    await lockWraps(tx, userId);
    if (onlyFirst) {
      const [other] = await tx
        .select({ id: keyWraps.id })
        .from(keyWraps)
        .where(own(userId, ne(keyWraps.id, id)))
        .limit(1);
      if (other) {
        throw new ApiError(409, "already_set_up", "This account already has its keys");
      }
    }
    const current = await currentKeyV(tx, userId);
    if (current !== null && wrap.keyV !== current) throw keyVersionMismatch(current, current);
    if (current === null && wrap.kind !== "recovery") {
      throw new ApiError(
        422,
        "recovery_required",
        "An account's first wrap is its recovery wrap; make the recovery key first",
      );
    }
    await checkRef(tx, userId, wrap);

    const row = values(userId, id, wrap, sessionId);
    const duplicate =
      wrap.kind === "recovery"
        ? eq(keyWraps.kind, "recovery")
        : and(eq(keyWraps.kind, wrap.kind), eq(keyWraps.ref, row.ref ?? ""));
    await tx.delete(keyWraps).where(own(userId, ne(keyWraps.id, id), duplicate));

    const [existing] = await tx
      .select({ id: keyWraps.id, kind: keyWraps.kind })
      .from(keyWraps)
      .where(own(userId, eq(keyWraps.id, id)));
    if (existing?.kind === "recovery" && wrap.kind !== "recovery") throw recoveryRequired();
    if (existing) {
      const { id: _id, userId: _userId, ...fields } = row;
      const [updated] = await tx
        .update(keyWraps)
        .set(fields)
        .where(own(userId, eq(keyWraps.id, id)))
        .returning();
      return toKeyWrap(updated as KeyWrapRow);
    }
    const [inserted] = await tx
      .insert(keyWraps)
      .values(row)
      .onConflictDoNothing({ target: keyWraps.id })
      .returning();
    // The id exists, but row-level security hides it: it is someone else's.
    if (!inserted) throw new ApiError(409, "id_taken", "This id is taken");
    return toKeyWrap(inserted);
  });
}

/**
 * Deletes wrap `id`; 404 when the person has none with that id, 409 for the recovery wrap. A device
 * wrap's session ends with it (never the caller's own, nor one another device wrap still uses).
 */
export async function deleteKeyWrap(
  db: Db,
  userId: string,
  id: string,
  { sessionId }: SessionOption,
): Promise<void> {
  await withUser(db, userId, async (tx) => {
    await lockWraps(tx, userId);
    const [found] = await tx
      .select({ kind: keyWraps.kind, sessionId: keyWraps.sessionId })
      .from(keyWraps)
      .where(own(userId, eq(keyWraps.id, id)));
    if (!found) throw new ApiError(404, "not_found");
    if (found.kind === "recovery") throw recoveryRequired();
    await tx.delete(keyWraps).where(own(userId, eq(keyWraps.id, id)));
    await endSessions(tx, userId, [found.sessionId], sessionId);
  });
}

/**
 * Replaces every wrap of the account with `wraps`, all at `keyV`, in one transaction. `keyV` must
 * be the current keyV + 1 (any keyV when the account has no wrap yet), and `wraps` must hold
 * exactly one recovery wrap. Each wrap passes the same ref checks as a PUT. An id that is someone
 * else's fails the whole rotation with 409 `id_taken`. `link` (the previous data key sealed under the
 * new one, which the server cannot open) is required once the account has a version (422
 * `link_required`) and refused for its first (422 `link_unexpected`); it must be 60 bytes (422
 * `invalid_link`). It is stored in the same transaction, and the answer lists every link. A device
 * wrap is the same device across the rotation when its `ref` is: it keeps the old row's session;
 * the sessions of devices left out end (never the caller's own, nor one a kept wrap still uses).
 */
export async function rotateKeys(
  db: Db,
  userId: string,
  keyV: number,
  wraps: (KeyWrapInput & { id: string })[],
  link: Uint8Array | null,
  { sessionId }: SessionOption,
): Promise<{ wraps: KeyWrapDto[]; links: KeyLinkDto[] }> {
  if (wraps.filter((wrap) => wrap.kind === "recovery").length !== 1) {
    throw new ApiError(422, "recovery_required", "A rotation carries exactly one recovery wrap");
  }
  for (const wrap of wraps) checkAttestation(wrap);
  return withUser(db, userId, async (tx) => {
    await lockWraps(tx, userId);
    const current = await currentKeyV(tx, userId);
    if (current !== null && keyV !== current + 1) throw keyVersionMismatch(current, current + 1);
    if (current === null && link !== null) {
      throw new ApiError(422, "link_unexpected", "The first version has no link");
    }
    if (current !== null && link === null) {
      throw new ApiError(422, "link_required", "A rotation carries the link to the previous key");
    }
    if (link !== null && link.length !== LINK_BYTES) {
      throw new ApiError(422, "invalid_link", `A link is ${LINK_BYTES} bytes`);
    }
    for (const wrap of wraps) await checkRef(tx, userId, wrap);

    const oldDevices = await tx
      .select({ ref: keyWraps.ref, sessionId: keyWraps.sessionId })
      .from(keyWraps)
      .where(own(userId, eq(keyWraps.kind, "device")));
    const sessionOfRef = new Map(oldDevices.map((row) => [row.ref, row.sessionId]));
    const keptRefs = new Set(wraps.filter((w) => w.kind === "device").map((w) => w.ref ?? null));
    const removed = oldDevices.filter((row) => !keptRefs.has(row.ref)).map((row) => row.sessionId);

    await tx.delete(keyWraps).where(own(userId));
    const rows = wraps.map((wrap) =>
      values(userId, wrap.id, wrap, sessionOfRef.get(wrap.ref ?? null) ?? null),
    );
    const inserted = await tx
      .insert(keyWraps)
      .values(rows)
      .onConflictDoNothing({ target: keyWraps.id })
      .returning();
    // Some id exists, hidden by row-level security: the whole rotation rolls back.
    if (inserted.length !== rows.length) throw new ApiError(409, "id_taken", "An id is taken");
    if (link !== null) await tx.insert(keyLinks).values({ userId, keyV, link });
    await endSessions(tx, userId, removed, sessionId);
    return { wraps: inserted.map(toKeyWrap), links: await listLinks(tx, userId) };
  });
}

/**
 * The wrap of the assistant `clientId`, with `last_used_at` set to now; null when the person has
 * none for it.
 */
export async function useAssistantWrap(
  db: Db,
  userId: string,
  clientId: string,
): Promise<KeyWrapDto | null> {
  return withUser(db, userId, async (tx) => {
    const [row] = await tx
      .update(keyWraps)
      .set({ lastUsedAt: sql`now()` })
      .where(own(userId, eq(keyWraps.kind, "assistant"), eq(keyWraps.ref, clientId)))
      .returning();
    return row ? toKeyWrap(row) : null;
  });
}

/**
 * Deletes the wraps of passkeys `credentialIds` of `userId`. Called by the Better Auth hook on
 * `/passkey/delete-passkey` once the passkey is gone (auth.ts).
 */
export async function deletePasskeyWraps(
  db: Db,
  userId: string,
  credentialIds: string[],
): Promise<void> {
  if (credentialIds.length === 0) return;
  await withUser(db, userId, async (tx) => {
    await lockWraps(tx, userId);
    await tx
      .delete(keyWraps)
      .where(own(userId, eq(keyWraps.kind, "passkey"), inArray(keyWraps.ref, credentialIds)));
  });
}
