import { Outlet } from "react-router";
import { previewProfile } from "../auth/encryption.ts";
import { requireOnboarded, requireSession } from "../auth/session.ts";
import { AppShell } from "../features/home/AppShell.tsx";
import { LocalOnboardingRoute, VaultGate } from "../features/vault/VaultGate.tsx";
import type { Route } from "./+types/app";

/**
 * `/app/*`: signed in and onboarded (a signed-out visit goes to sign-in and comes back; one not
 * onboarded yet goes to /welcome). The shell holds the bottom bar or sidebar and the add sheet.
 * A preview account (`GET /v1/me` `encryption: "preview"`) opens its vault first; its onboarding
 * flag lives in the vault, so the redirect to /welcome happens after (`LocalOnboardingRoute`).
 */
export async function clientLoader({ request }: Route.ClientLoaderArgs) {
  const next = new URL(request.url).pathname;
  await requireSession(next);
  const vault = await previewProfile();
  if (!vault) await requireOnboarded(next);
  return { vault };
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
  if (!loaderData.vault) return shell;
  return (
    <VaultGate key={loaderData.vault.id} profile={loaderData.vault}>
      <LocalOnboardingRoute onboarded to="/welcome">
        {shell}
      </LocalOnboardingRoute>
    </VaultGate>
  );
}
