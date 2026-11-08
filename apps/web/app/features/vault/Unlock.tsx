import { useId, useState } from "react";
import { useTranslations } from "use-intl";
import { cx } from "../../ui/cx.ts";
import { PressButton } from "../../ui/PressButton.tsx";
import { FieldError, ScreenTitle, SignInScreen } from "../sign-in/SignInScreen.tsx";

/** Why unlocking failed; `null` from `onUnlock` means it worked. Mirrors `KeysError.code`. */
export type UnlockError = "bad_recovery_key" | "wrong_recovery_key" | "offline" | "server";

export interface UnlockProps {
  /** Tries the typed text (any case, spaces or dashes). Resolves to the error, or `null`. */
  onUnlock(text: string): Promise<UnlockError | null>;
  /** Signs out (and wipes this browser's vault): the way out. */
  onSignOut(): void;
}

/** A new browser on an account that has keys: type the recovery key to open the data here. */
export function Unlock({ onUnlock, onSignOut }: UnlockProps) {
  const t = useTranslations("vault.unlock");
  const tVault = useTranslations("vault");
  const [text, setText] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<UnlockError | null>(null);
  const inputId = useId();
  const errorId = useId();

  async function submit(event: React.FormEvent) {
    event.preventDefault();
    if (busy || text.trim() === "") return;
    setBusy(true);
    setError(null);
    try {
      setError(await onUnlock(text));
    } finally {
      setBusy(false);
    }
  }

  return (
    <SignInScreen>
      <ScreenTitle>{t("title")}</ScreenTitle>
      <p className="text-center text-ink-muted">{t("lead")}</p>
      <form noValidate className="flex w-full flex-col gap-(--space-3)" onSubmit={submit}>
        <label htmlFor={inputId} className="text-sm text-ink-muted">
          {t("label")}
        </label>
        <div className={cx("lk-input min-h-11", error && "border-over")}>
          <input
            id={inputId}
            name="recovery-key"
            type="text"
            autoComplete="off"
            autoCapitalize="characters"
            autoCorrect="off"
            spellCheck={false}
            translate="no"
            placeholder={t("placeholder")}
            value={text}
            onChange={(event) => {
              setText(event.target.value);
              if (error) setError(null);
            }}
            aria-invalid={error !== null || undefined}
            aria-describedby={error ? errorId : undefined}
            className="min-h-9 min-w-0 flex-1 border-0 bg-transparent p-0 font-mono text-[16px] text-ink uppercase outline-none placeholder:font-normal placeholder:text-ink-muted"
          />
        </div>
        {error && <FieldError id={errorId}>{t(`error_${error}`)}</FieldError>}
        <PressButton type="submit" className="w-full" disabled={busy || text.trim() === ""}>
          {busy ? t("busy") : t("submit")}
        </PressButton>
      </form>
      <p className="text-center text-[14px] text-ink-muted">{t("soon")}</p>
      <PressButton variant="ghost" className="w-full" disabled={busy} onClick={onSignOut}>
        {tVault("sign_out")}
      </PressButton>
    </SignInScreen>
  );
}
