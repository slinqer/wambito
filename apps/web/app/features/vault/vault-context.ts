import { createContext, useContext } from "react";
import type { VaultSession } from "../../local/vault-session.ts";

/**
 * The open vault, for the screens that act on its keys (Settings → Security): the gate provides it
 * beside `<ApiProvider mode="local">`; null everywhere else (live, demo, stories without one).
 */
export const VaultSessionContext = createContext<VaultSession | null>(null);

export function useVaultSession(): VaultSession | null {
  return useContext(VaultSessionContext);
}
