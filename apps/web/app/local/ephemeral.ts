import { deleteVault, META, request, vaultName } from "./db.ts";

const PREFIX = vaultName("");

export interface EphemeralDeps {
  /** `indexedDB.databases()`; undefined where the browser has none (nothing is done then). */
  databases?: (() => Promise<IDBDatabaseInfo[]>) | undefined;
}

const browserDeps = (): EphemeralDeps => ({
  databases:
    typeof indexedDB !== "undefined" && typeof indexedDB.databases === "function"
      ? () => indexedDB.databases()
      : undefined,
});

/** Whether the vault database `name` has the meta `ephemeral` (an unticked sign-in). Never throws. */
function isEphemeral(name: string): Promise<boolean> {
  return new Promise((resolve) => {
    let open: IDBOpenDBRequest;
    try {
      // no version: the database as it is, never upgraded from here
      open = indexedDB.open(name);
    } catch {
      resolve(false);
      return;
    }
    // Gone since it was listed (another sweep deleted it): never make it again, empty and at
    // version 1, which a later `openVault` could not upgrade. Aborting ends in `onerror`.
    open.onupgradeneeded = () => open.transaction?.abort();
    open.onerror = () => resolve(false);
    open.onblocked = () => resolve(false);
    open.onsuccess = () => {
      const db = open.result;
      if (!db.objectStoreNames.contains(META)) {
        db.close();
        resolve(false);
        return;
      }
      const read = request(db.transaction(META, "readonly").objectStore(META).get("ephemeral"));
      read.then(
        (value) => {
          db.close();
          resolve(value === true);
        },
        () => {
          db.close();
          resolve(false);
        },
      );
    };
  });
}

/**
 * An unticked sign-in ("Keep me signed in" off; web plan ruling 11) marks its vault `ephemeral`.
 * Its session cookie ends with the browser, and the signed-out sweep (`deleteStaleVaults(null)`)
 * then wipes it; this covers the other case, a browser where someone else signed in since: every
 * `ephemeral` vault whose user is not `signedInUserId` (all of them when null) is deleted. The
 * signed-in person's own ephemeral vault stays (a reload keeps the session). Runs on every
 * signed-in load of the live guards. Never throws: a vault another tab holds open is deleted once
 * it lets go, or next time.
 */
export async function wipeForeignEphemeralVaults(
  signedInUserId: string | null,
  deps: EphemeralDeps = browserDeps(),
): Promise<void> {
  if (!deps.databases) return;
  let infos: IDBDatabaseInfo[];
  try {
    infos = await deps.databases();
  } catch {
    return;
  }
  const keep = signedInUserId === null ? null : vaultName(signedInUserId);
  const others = infos
    .map((info) => info.name ?? "")
    .filter((name) => name.startsWith(PREFIX) && name !== keep);
  await Promise.all(
    others.map(async (name) => {
      if (await isEphemeral(name)) {
        await deleteVault(name.slice(PREFIX.length)).catch(() => {});
      }
    }),
  );
}
