import { useId, useState } from "react";
import { useTranslations } from "use-intl";
import { PressButton } from "../../ui/PressButton.tsx";
import { FieldError, ScreenTitle, SignInScreen } from "../sign-in/SignInScreen.tsx";
import type { LockedKind } from "./vault-gate.ts";

export interface LockedProps {
  /**
   * `offline`: no connection; `error`: anything else (both with a retry). `unsupported`: this
   * browser cannot keep the key safely; `guest`: a guest's data was set up elsewhere and cannot be
   * opened here (neither has a retry).
   */
  kind?: LockedKind;
  onRetry(): void;
  retrying?: boolean;
  /** Signs out (and wipes this browser's vault): the way out of every vault screen. */
  onSignOut(): void;
  /** A guest's way out for good: deletes the account. Resolves to whether it worked. */
  onDeleteAccount?(): Promise<boolean>;
}

const PREFIX: Record<LockedKind, string> = {
  error: "",
  offline: "offline_",
  unsupported: "unsupported_",
  guest: "guest_",
};

/**
 * The vault could not be opened: says why, offers a retry when one can help, and always a sign-out.
 * A guest locked out of its data can also delete the account (two taps: ask, then confirm).
 */
export function Locked({
  kind = "error",
  onRetry,
  retrying = false,
  onSignOut,
  onDeleteAccount,
}: LockedProps) {
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
      {kind === "guest" && onDeleteAccount && <DeleteGuest onDelete={onDeleteAccount} />}
    </SignInScreen>
  );
}

function DeleteGuest({ onDelete }: { onDelete(): Promise<boolean> }) {
  const t = useTranslations("vault.locked");
  const [step, setStep] = useState<"idle" | "confirm" | "busy" | "failed">("idle");
  const errorId = useId();
  if (step === "idle") {
    return (
      <PressButton variant="ghost" className="w-full text-over" onClick={() => setStep("confirm")}>
        {t("delete_account")}
      </PressButton>
    );
  }
  return (
    <div className="flex w-full flex-col gap-(--space-2)">
      <p className="m-0 text-center text-[15px] text-ink">{t("delete_lead")}</p>
      {step === "failed" && <FieldError id={errorId}>{t("delete_failed")}</FieldError>}
      <PressButton
        variant="secondary"
        className="w-full text-over"
        disabled={step === "busy"}
        aria-busy={step === "busy" || undefined}
        aria-describedby={step === "failed" ? errorId : undefined}
        onClick={async () => {
          setStep("busy");
          setStep((await onDelete().catch(() => false)) ? "busy" : "failed");
        }}
      >
        {step === "busy" ? t("deleting") : t("delete_confirm")}
      </PressButton>
      <PressButton
        variant="ghost"
        className="w-full"
        disabled={step === "busy"}
        onClick={() => setStep("idle")}
      >
        {t("delete_cancel")}
      </PressButton>
    </div>
  );
}
