import { useEffect, useRef } from "react";
import { useTranslations } from "use-intl";
import { FieldError, ScreenTitle, SignInScreen } from "../features/sign-in/SignInScreen.tsx";
import { FingerprintIcon } from "../ui/FingerprintIcon.tsx";
import { PressButton } from "../ui/PressButton.tsx";
import { PressLink } from "../ui/PressLink.tsx";
import type { VerificationStatus } from "./use-admin.ts";

const ERROR_ID = "admin-verify-error";

/**
 * The panel's entry screen (spec §4.3): why it asks, and one button, "Confirmar con tu passkey",
 * which opens the browser's prompt (PIN, fingerprint or face). A refused passkey says so and keeps
 * the button; an admin with no passkey cannot use the panel, so the screen says that instead and
 * links to the settings where one is added. The heading takes the focus on arrival, since the
 * screen also appears mid-task, when a verification runs out.
 */
export function VerifyScreen({
  verification,
  onVerify,
}: {
  verification: VerificationStatus;
  onVerify: () => void;
}) {
  const t = useTranslations("admin.verify");
  const heading = useRef<HTMLHeadingElement>(null);
  const noPasskey = verification === "no_passkey";

  useEffect(() => {
    heading.current?.focus();
  }, [noPasskey]);

  if (noPasskey) {
    return (
      <SignInScreen mood="worried">
        <ScreenTitle ref={heading} focusable>
          {t("no_passkey.title")}
        </ScreenTitle>
        <p className="text-center text-ink-muted">{t("no_passkey.body")}</p>
        <PressLink to="/app/settings/account" className="w-full">
          {t("no_passkey.link")}
        </PressLink>
      </SignInScreen>
    );
  }

  const busy = verification === "busy";
  const failed = verification === "failed";
  return (
    <SignInScreen>
      <ScreenTitle ref={heading} focusable>
        {t("title")}
      </ScreenTitle>
      <p className="text-center text-ink-muted">{t("lead")}</p>
      {failed && <FieldError id={ERROR_ID}>{t("failed")}</FieldError>}
      <PressButton
        className="w-full"
        disabled={busy}
        aria-describedby={failed ? ERROR_ID : undefined}
        onClick={onVerify}
      >
        <FingerprintIcon />
        {busy ? t("busy") : t("button")}
      </PressButton>
    </SignInScreen>
  );
}
