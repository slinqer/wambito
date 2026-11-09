import { redirect, type ShouldRevalidateFunctionArgs } from "react-router";
import { createTranslator } from "use-intl/core";
import { previewProfile } from "../auth/encryption.ts";
import { requireSession } from "../auth/session.ts";
import { Welcome } from "../features/onboarding/Welcome.tsx";
import { LocalOnboardingRoute, VaultGate } from "../features/vault/VaultGate.tsx";
import { CATALOGS } from "../i18n/catalog.ts";
import type { Route } from "./+types/welcome";

export const meta = () => {
  const t = createTranslator({ locale: "es", messages: CATALOGS.es, namespace: "onboarding" });
  return [{ title: t("meta_title") }, { name: "robots", content: "noindex" }];
};

/**
 * Signed in, and only until onboarding is done: afterwards `/welcome` goes to the app. A failed
 * session check (no connection, a server error) throws to the error boundary. A preview account
 * opens its vault first and is checked against the vault's flag (`LocalOnboardingRoute`).
 */
export async function clientLoader({ request }: Route.ClientLoaderArgs) {
  const user = await requireSession(new URL(request.url).pathname);
  const vault = await previewProfile();
  if (!vault && user.onboardingCompletedAt != null) throw redirect("/app");
  return { vault };
}

/** Moving between steps changes only the URL's step: the session was checked on the way in. */
export function shouldRevalidate({
  currentUrl,
  nextUrl,
  defaultShouldRevalidate,
}: ShouldRevalidateFunctionArgs) {
  const inWelcome = (url: URL) => url.pathname.startsWith("/welcome");
  return inWelcome(currentUrl) && inWelcome(nextUrl) ? false : defaultShouldRevalidate;
}

/** While the session is checked: the screen's background, nothing to read yet. */
export function HydrateFallback() {
  return <div className="lk-screen min-h-dvh" />;
}

/** `/welcome/:step?`: the optional onboarding (welcome, currency, categories, import, budgets). */
export default function WelcomeRoute({ loaderData }: Route.ComponentProps) {
  const welcome = (
    <Welcome languages={typeof navigator === "undefined" ? [] : navigator.languages} />
  );
  if (!loaderData.vault) return welcome;
  return (
    <VaultGate key={loaderData.vault.id} profile={loaderData.vault}>
      <LocalOnboardingRoute onboarded={false} to="/app">
        {welcome}
      </LocalOnboardingRoute>
    </VaultGate>
  );
}
