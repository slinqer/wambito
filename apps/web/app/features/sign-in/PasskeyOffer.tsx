import { useEffect, useRef, useState } from "react";
import { useNavigate, useSearchParams } from "react-router";
import { useTranslations } from "use-intl";
import { previewProfile } from "../../auth/encryption.ts";
import { DEFAULT_NEXT, safeNext } from "../../auth/next.ts";
import {
  addPasskey,
  type PasskeyOutcome,
  passkeysSupported,
  rememberOfferDecided,
} from "../../auth/passkey.ts";
import { keepSignInPrf } from "../../local/prf.ts";
import { PressButton } from "../../ui/PressButton.tsx";
import { useToast } from "../../ui/Toast.tsx";
import { FingerprintIcon } from "./SignIn.tsx";
import { FieldError, ScreenTitle, SignInScreen } from "./SignInScreen.tsx";

/** The offer's browser side, as a prop so stories can stand in for WebAuthn and storage. */
export interface PasskeyOfferApi {
  /** Whether this browser can use passkeys at all (WebAuthn). */
  supported(): boolean;
  /**
   * Creates a passkey for the signed-in user; the browser asks for the fingerprint or face. An
   * encrypted account may need a second touch for the passkey's PRF: `explainSecondTouch` says why
   * first.
   */
  add(hooks?: { explainSecondTouch(): void }): Promise<PasskeyOutcome>;
  /** Remembers that this user answered, so the offer is not shown to them again on this device. */
  decide(userId: string): void;
}

export const livePasskeyOffer: PasskeyOfferApi = {
  supported: passkeysSupported,
  // The offer comes right after sign-in, before the vault opens: the new passkey's PRF waits for
  // the vault gate, which adds its wrap once the data is open (a plain account drops it).
  add: (hooks) =>
    addPasskey({
      wantsPrf: async () => (await previewProfile()) !== null,
      explainSecondTouch: () => hooks?.explainSecondTouch(),
      keep: keepSignInPrf,
    }),
  decide: (userId) => rememberOfferDecided(userId),
};

/**
 * `/passkey-offer?next=…`: right after an email sign-in, "¿Entrar con tu huella la próxima vez?".
 * A passkey in plain words, then two ways out: create it (the browser asks for the fingerprint or
 * face) or "Ahora no". Either answer is remembered for this user on this device, and leads on to
 * `next` (same origin only), which is where sign-in was heading: onboarding or the app. Cancelling
 * the browser's prompt is silent and the offer stays; where WebAuthn is missing there is nothing
 * to offer and it goes straight on. The heading takes the focus on arrival, since the screen
 * appears without a tap on a link.
 */
export function PasskeyOffer({ offer, userId }: { offer: PasskeyOfferApi; userId: string }) {
  const t = useTranslations("passkey_offer");
  const tVault = useTranslations("vault");
  const toast = useToast();
  const navigate = useNavigate();
  const [params] = useSearchParams();
  const next = safeNext(params.get("next"), DEFAULT_NEXT);
  const supported = useState(() => offer.supported())[0];
  const [busy, setBusy] = useState(false);
  const [failed, setFailed] = useState(false);
  // A ref, not state: two quick taps must not open two prompts.
  const inFlight = useRef(false);
  const heading = useRef<HTMLHeadingElement>(null);

  useEffect(() => {
    if (supported) heading.current?.focus();
    else navigate(next, { replace: true });
  }, [supported, navigate, next]);

  if (!supported) return null;

  async function create() {
    if (inFlight.current) return;
    inFlight.current = true;
    setBusy(true);
    setFailed(false);
    try {
      const outcome = await offer.add({
        explainSecondTouch: () => toast.show({ message: tVault("passkey_second_touch") }),
      });
      if (outcome === "failed") {
        setFailed(true);
        return;
      }
      if (outcome === "cancelled") return;
      offer.decide(userId);
      toast.show({ message: t("added") });
      navigate(next, { replace: true });
    } finally {
      inFlight.current = false;
      setBusy(false);
    }
  }

  function notNow() {
    if (inFlight.current) return;
    offer.decide(userId);
    navigate(next, { replace: true });
  }

  return (
    <SignInScreen>
      <ScreenTitle ref={heading} focusable>
        {t("title")}
      </ScreenTitle>
      <p className="text-center text-ink-muted">{t("lead")}</p>
      <ul className="flex w-full list-disc flex-col gap-(--space-2) pl-(--space-5) text-ink marker:text-ink-muted">
        <li>{t("points.key")}</li>
        <li>{t("points.unlock")}</li>
        <li>{t("points.sync")}</li>
        <li>{t("points.backup")}</li>
      </ul>
      {failed && <FieldError id="passkey-offer-error">{t("failed")}</FieldError>}
      <div className="flex w-full flex-col gap-(--space-2)">
        <PressButton
          className="w-full"
          disabled={busy}
          aria-describedby={failed ? "passkey-offer-error" : undefined}
          onClick={create}
        >
          <FingerprintIcon />
          {busy ? t("adding") : t("add")}
        </PressButton>
        <PressButton variant="ghost" className="w-full" disabled={busy} onClick={notNow}>
          {t("not_now")}
        </PressButton>
      </div>
    </SignInScreen>
  );
}
