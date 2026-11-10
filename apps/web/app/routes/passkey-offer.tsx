import { useQueryClient } from "@tanstack/react-query";
import { createTranslator } from "use-intl/core";
import { queryKeys } from "../api/queries.ts";
import { DEFAULT_NEXT } from "../auth/next.ts";
import { requireSession } from "../auth/session.ts";
import type { Profile } from "../features/onboarding/onboarding-api.ts";
import { livePasskeyOffer, PasskeyOffer } from "../features/sign-in/PasskeyOffer.tsx";
import { CATALOGS } from "../i18n/catalog.ts";
import type { Route } from "./+types/passkey-offer";

export const meta = () => {
  const t = createTranslator({ locale: "es", messages: CATALOGS.es, namespace: "passkey_offer" });
  return [{ title: t("meta_title") }, { name: "robots", content: "noindex" }];
};

/**
 * Signed in only: the offer is for someone who just signed in with their email. (A visitor who
 * is not goes to sign-in and, afterwards, to the app.) A failed session check throws to the
 * error boundary.
 */
export async function clientLoader() {
  const user = await requireSession(DEFAULT_NEXT);
  return { userId: user.id };
}

/** While the session is checked: the screen's background, nothing to read yet. */
export function HydrateFallback() {
  return <div className="lk-screen min-h-dvh" />;
}

/** `/passkey-offer?next=…`: "¿Entrar con tu huella la próxima vez?" (after an email sign-in). */
export default function PasskeyOfferRoute({ loaderData }: Route.ComponentProps) {
  // The profile the sign-in just read (`useFinishSignIn`): no request of its own. Without it (a
  // reload), the account counts as plain and a new passkey gets no second touch.
  const profile = useQueryClient().getQueryData<Profile>(queryKeys.me());
  return (
    <PasskeyOffer
      offer={livePasskeyOffer}
      userId={loaderData.userId}
      encrypted={profile?.id === loaderData.userId && profile.encryption === "preview"}
    />
  );
}
