import { Outlet } from "react-router";
import { accountGate } from "../auth/encryption.ts";
import { markSeenToday } from "../auth/seen.ts";
import { requireOnboarded, requireSession } from "../auth/session.ts";
import { AppShell } from "../features/home/AppShell.tsx";
import { MigrationGate } from "../features/migration/MigrationScreen.tsx";
import { LocalOnboardingRoute, VaultGate } from "../features/vault/VaultGate.tsx";
import { clearSignInPrf } from "../local/prf.ts";
import type { Route } from "./+types/app";

/**
 * `/app/*`: signed in and onboarded (a signed-out visit goes to sign-in and comes back; one not
 * onboarded yet goes to /welcome). The shell holds the bottom bar or sidebar and the add sheet.
 * A preview account (`GET /v1/me` `encryption: "preview"`) opens its vault first; its onboarding
 * flag lives in the vault, so the redirect to /welcome happens after (`LocalOnboardingRoute`).
 * An account whose move to end-to-end encryption is open or running (`migration`) runs that flow
 * first (`MigrationGate`); its done reloads into the vault gate.
 */
export async function clientLoader({ request }: Route.ClientLoaderArgs) {
  const next = new URL(request.url).pathname;
  await requireSession(next);
  // The daily "app opened" call, for every account (plain too); never awaited, never throws.
  const { vault, migration } = await accountGate((me) => void markSeenToday(me.id, me.timezone));
  // A plain account has no vault: a passkey PRF kept at sign-in is not needed.
  if (!vault) clearSignInPrf();
  if (!vault && !migration) await requireOnboarded(next);
  return { vault, migration };
}

/** While the session is checked: the screen's background, nothing to read yet. */
export function HydrateFallback() {
  return <div className="lk-screen min-h-dvh" />;
}

export default function AppRoute({ loaderData }: Route.ComponentProps) {
  const shell = (
    <AppShell>
      <Outlet />
    </AppShell>
  );
  if (loaderData.migration) {
    return <MigrationGate key={loaderData.migration.profile.id} gate={loaderData.migration} />;
  }
  if (!loaderData.vault) return shell;
  return (
    <VaultGate key={loaderData.vault.id} profile={loaderData.vault}>
      <LocalOnboardingRoute onboarded to="/welcome">
        {shell}
      </LocalOnboardingRoute>
    </VaultGate>
  );
}
