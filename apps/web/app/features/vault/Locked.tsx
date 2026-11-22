import { useTranslations } from "use-intl";
import { PressButton } from "../../ui/PressButton.tsx";
import { ScreenTitle, SignInScreen } from "../sign-in/SignInScreen.tsx";
import type { LockedKind } from "./vault-gate.ts";

export interface LockedProps {
  /**
   * `offline`: no connection; `error`: anything else (both with a retry). `unsupported`: this
   * browser cannot keep the key safely (no retry).
   */
  kind?: LockedKind;
  onRetry(): void;
  retrying?: boolean;
  /** Signs out (and wipes this browser's vault): the way out of every vault screen. */
  onSignOut(): void;
}

const PREFIX: Record<LockedKind, string> = {
  error: "",
  offline: "offline_",
  unsupported: "unsupported_",
};

/**
 * The vault could not be opened: says why, offers a retry when one can help, and always a sign-out.
 */
export function Locked({ kind = "error", onRetry, retrying = false, onSignOut }: LockedProps) {
  const t = useTranslations("vault.locked");
  const tVault = useTranslations("vault");
  const prefix = PREFIX[kind];
  const canRetry = kind === "error" || kind === "offline";
  return (
    <SignInScreen mood="worried">
      <ScreenTitle>{t(`${prefix}title`)}</ScreenTitle>
      <p className="text-center text-ink-muted">{t(`${prefix}lead`)}</p>
      {canRetry && (
        <PressButton className="w-full" disabled={retrying} onClick={onRetry}>
          {retrying ? t("retrying") : t("retry")}
        </PressButton>
      )}
      <PressButton variant={canRetry ? "ghost" : "primary"} className="w-full" onClick={onSignOut}>
        {tVault("sign_out")}
      </PressButton>
    </SignInScreen>
  );
}
