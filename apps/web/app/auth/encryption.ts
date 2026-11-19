import { api } from "../api/client.ts";
import { ApiProblem } from "../api/errors.ts";
import type { VaultProfile } from "../local/vault-session.ts";

/** `GET /v1/me` `migration`: the switch day's move to end-to-end encryption (E2E stage 5). */
export type Migration = "available" | "in_progress";

/** A plain account's move: the flow runs before the app (`features/migration`). */
export interface MigrationGate {
  profile: VaultProfile;
  migration: Migration;
}

/** The profile's move, or null when there is none for it. */
export function migrationOf(me: { migration?: Migration | undefined }): Migration | null {
  return me.migration ?? null;
}

/**
 * What the signed-in account opens (`GET /v1/me`): its vault (`encryption: "preview"`), the
 * migration flow (`migration` set; a migrating account answers preview too, but it is the flow's
 * until `finish`), or neither (a plain account). A loader helper (live API); `onMe` gets the id
 * and time zone of any account, plain too; a failure throws to the route's error boundary.
 */
export async function accountGate(
  onMe?: (me: { id: string; timezone: string }) => void,
): Promise<{ vault: VaultProfile | null; migration: MigrationGate | null }> {
  const { data, response } = await api.GET("/v1/me");
  if (!data) throw new ApiProblem({ status: response.status, code: "internal_error" });
  onMe?.({ id: data.id, timezone: data.timezone });
  const profile: VaultProfile = {
    id: data.id,
    email: data.email,
    isAnonymous: data.isAnonymous,
    locale: data.locale,
    timezone: data.timezone,
  };
  const migration = migrationOf(data);
  if (migration) return { vault: null, migration: { profile, migration } };
  return { vault: data.encryption === "preview" ? profile : null, migration: null };
}

/**
 * Whether the signed-in account is in the end-to-end encryption preview: its profile for the
 * vault, or null for a plain account and for one whose move is available or running (the flow's).
 */
export async function previewProfile(
  onMe?: (me: { id: string; timezone: string }) => void,
): Promise<VaultProfile | null> {
  return (await accountGate(onMe)).vault;
}
