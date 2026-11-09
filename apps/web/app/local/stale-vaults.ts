import { deleteVault, vaultName } from "./db.ts";

const PREFIX = vaultName("");

export interface StaleVaultDeps {
  /** `indexedDB.databases()`; undefined where the browser has none (nothing is done then). */
  databases?: () => Promise<IDBDatabaseInfo[]>;
}

const browserDeps = (): StaleVaultDeps => ({
  databases:
    typeof indexedDB !== "undefined" && typeof indexedDB.databases === "function"
      ? () => indexedDB.databases()
      : undefined,
});

/**
 * A vault outlives a session that ended outside the sign-out (expired, revoked, the account
 * deleted elsewhere): this deletes every `wambito-vault-*` database in the browser but
 * `keepUserId`'s (all of them when signed out). Runs on sign-in and on every signed-out load of
 * the app's guards. Never throws: a database another tab holds open is deleted by the browser once
 * that tab lets go, or next time.
 */
export async function deleteStaleVaults(
  keepUserId: string | null,
  deps: StaleVaultDeps = browserDeps(),
): Promise<void> {
  if (!deps.databases) return;
  let infos: IDBDatabaseInfo[];
  try {
    infos = await deps.databases();
  } catch {
    return;
  }
  const keep = keepUserId === null ? null : vaultName(keepUserId);
  await Promise.all(
    infos
      .map((info) => info.name ?? "")
      .filter((name) => name.startsWith(PREFIX) && name !== keep)
      .map((name) => deleteVault(name.slice(PREFIX.length)).catch(() => {})),
  );
}
