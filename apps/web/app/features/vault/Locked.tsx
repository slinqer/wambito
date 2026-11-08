import { useTranslations } from "use-intl";
import { PressButton } from "../../ui/PressButton.tsx";
import { ScreenTitle, SignInScreen } from "../sign-in/SignInScreen.tsx";

export interface LockedProps {
  /** `offline`: no connection; `error`: anything else. */
  kind?: "error" | "offline";
  onRetry(): void;
  retrying?: boolean;
}

/** The vault could not be opened (keys unreadable, no network): says so and offers a retry. */
export function Locked({ kind = "error", onRetry, retrying = false }: LockedProps) {
  const t = useTranslations("vault.locked");
  const prefix = kind === "offline" ? "offline_" : "";
  return (
    <SignInScreen mood="worried">
      <ScreenTitle>{t(`${prefix}title`)}</ScreenTitle>
      <p className="text-center text-ink-muted">{t(`${prefix}lead`)}</p>
      <PressButton className="w-full" disabled={retrying} onClick={onRetry}>
        {retrying ? t("retrying") : t("retry")}
      </PressButton>
    </SignInScreen>
  );
}
