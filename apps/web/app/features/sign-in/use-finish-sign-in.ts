import { useQueryClient } from "@tanstack/react-query";
import { useCallback } from "react";
import { useNavigate } from "react-router";
import { useApi, useClearSession } from "../../api/ApiProvider.tsx";
import { queryKeys } from "../../api/queries.ts";
import type { paths } from "../../api/schema";
import { isLocale, type Locale } from "../../i18n/format.ts";
import { useLocale } from "../../i18n/IntlProvider.tsx";
import { deleteStaleVaults } from "../../local/stale-vaults.ts";
import {
  type AuthUser,
  destinationAfterSignIn,
  offersPasskey,
  type SignInAuth,
  type SignInMethod,
} from "./auth.ts";

type Profile = paths["/v1/me"]["get"]["responses"][200]["content"]["application/json"];

export interface FinishSignIn {
  /**
   * Who signed in, from the sign-in response (used when the profile can't be read). A QR or
   * recovery-key sign-in knows only the id.
   */
  user: Pick<AuthUser, "id" | "onboardingCompletedAt">;
  /** `?next=` as given; only a same-origin path is honoured. */
  next: string | null;
  /** `?lang=` from the landing: the language a new user's profile starts in. */
  lang: Locale | null;
  /**
   * How they signed in. Only after an email sign-in (code or magic link) may Wambito offer a
   * passkey (`offersPasskey`): someone who just used one needs no offer, and a QR or recovery-key
   * sign-in (web plan ruling 13) never gets one. Email unless said otherwise.
   */
  method?: SignInMethod;
}

/** The passkey offer's screen: it takes the page the person was heading to as `?next=`. */
export const PASSKEY_OFFER_PATH = "/passkey-offer";

/**
 * What happens right after any sign-in (code, magic link, passkey, QR, recovery key): forget the previous person's
 * cached data and any vault of someone else left in this browser, give a new user the language of
 * the page they came from (`PATCH /v1/me`), switch the app to the profile's language, and go to onboarding, `next` or the app. After an email
 * sign-in that is due the passkey offer, it goes first and then leads on to that page.
 */
export function useFinishSignIn(auth: Pick<SignInAuth, "shouldOfferPasskey">) {
  const api = useApi();
  const clearSession = useClearSession();
  const queryClient = useQueryClient();
  const navigate = useNavigate();
  const { setLocale } = useLocale();

  return useCallback(
    async ({ user, next, lang, method = "email" }: FinishSignIn) => {
      clearSession();
      // Another person's vault left in this browser (a session that ended outside the sign-out).
      await deleteStaleVaults(user.id);
      let profile: Profile | null = null;
      try {
        profile = (await api.GET("/v1/me")).data ?? null;
        // Not onboarded yet means new here: the landing's language becomes theirs.
        if (profile && lang && profile.onboardingCompletedAt == null && profile.locale !== lang) {
          const { data } = await api.PATCH("/v1/me", { body: { locale: lang } });
          profile = data ?? profile;
        }
        if (profile) queryClient.setQueryData(queryKeys.me(), profile);
      } catch {
        // The profile is a nicety here: the person is signed in either way.
      }
      if (isLocale(profile?.locale)) setLocale(profile.locale);
      const destination = destinationAfterSignIn(profile ?? user, next);
      // Asking is a nicety too: a failure just means no offer. Not on the way to an assistant's
      // consent, whose link expires in minutes; the offer comes at the next sign-in.
      const offer =
        offersPasskey(method, destination) &&
        (await auth.shouldOfferPasskey(user.id).catch(() => false));
      if (offer) {
        const search = new URLSearchParams({ next: destination });
        navigate({ pathname: PASSKEY_OFFER_PATH, search: `?${search}` }, { replace: true });
      } else {
        navigate(destination, { replace: true });
      }
    },
    [api, auth, clearSession, queryClient, navigate, setLocale],
  );
}
