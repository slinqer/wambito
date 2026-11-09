import { api } from "../api/client.ts";
import { ApiProblem } from "../api/errors.ts";
import type { VaultProfile } from "../local/vault-session.ts";

/**
 * Whether the signed-in account is in the end-to-end encryption preview (`GET /v1/me`
 * `encryption`): its profile for the vault, or null for a plain account. A loader helper (live
 * API); a failure throws to the route's error boundary.
 */
export async function previewProfile(): Promise<VaultProfile | null> {
  const { data, response } = await api.GET("/v1/me");
  if (!data) throw new ApiProblem({ status: response.status, code: "internal_error" });
  if (data.encryption !== "preview") return null;
  return {
    id: data.id,
    email: data.email,
    isAnonymous: data.isAnonymous,
    locale: data.locale,
    timezone: data.timezone,
  };
}
