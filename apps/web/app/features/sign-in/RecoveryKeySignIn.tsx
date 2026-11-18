import { type FormEvent, useEffect, useId, useRef, useState } from "react";
import { useTranslations } from "use-intl";
import { cx } from "../../ui/cx.ts";
import { PressButton } from "../../ui/PressButton.tsx";
import type { RecoveryErrorCode, RecoveryResult } from "./auth.ts";
import { FieldError } from "./SignInScreen.tsx";
import { useSecondsUntil } from "./use-seconds-until.ts";

/** When a 429 names no `retry-after`. */
const DEFAULT_WAIT_S = 30;

/** The catalog key for each failure (`vault.unlock.*` where the unlock already says it). */
const ERROR_KEYS: Record<RecoveryErrorCode, string> = {
  bad_recovery_key: "vault.unlock.error_bad_recovery_key",
  wrong_recovery_key: "vault.unlock.error_wrong_recovery_key",
  recovery_key_invalid: "errors.recovery_key_invalid",
  account_suspended: "errors.account_suspended",
  too_many_requests: "sign_in.recovery.too_many",
  offline: "vault.unlock.error_offline",
  server: "vault.unlock.error_server",
};

export interface RecoveryKeySignInProps {
  /** `SignInAuth.signInWithRecoveryKey`: signs in and opens the data with the same text. */
  signIn(text: string): Promise<RecoveryResult>;
  /** Signed in and opened: the page finishes the sign-in (web plan ruling 13). */
  onSignedIn(userId: string): Promise<void> | void;
  /** Another way in is busy: the button and the field wait. */
  disabled?: boolean;
  /** Tells the page while this one is busy, so no other way starts meanwhile. */
  onBusy?(busy: boolean): void;
}

/**
 * "Recovery key" on `/sign-in` (web plan ruling 14): a button that opens the field; the typed key
 * (any case, spaces or dashes) signs in and opens the data in this browser. The text lives in this
 * component's state only: never logged or stored.
 */
export function RecoveryKeySignIn({
  signIn,
  onSignedIn,
  disabled,
  onBusy,
}: RecoveryKeySignInProps) {
  const t = useTranslations("sign_in.recovery");
  const tRoot = useTranslations();
  const [open, setOpen] = useState(false);
  const [text, setText] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<RecoveryErrorCode | null>(null);
  const [retryAt, setRetryAt] = useState(0);
  const retryIn = useSecondsUntil(retryAt);
  const input = useRef<HTMLInputElement>(null);
  const inFlight = useRef(false);
  const fieldId = useId();
  const errorId = useId();
  const panelId = useId();

  useEffect(() => {
    if (open) input.current?.focus();
  }, [open]);

  async function submit(event: FormEvent) {
    event.preventDefault();
    if (inFlight.current || disabled || text.trim() === "" || retryIn > 0) return;
    inFlight.current = true;
    setBusy(true);
    onBusy?.(true);
    setError(null);
    let signedIn = false;
    try {
      const result = await signIn(text);
      if ("userId" in result) {
        signedIn = true;
        setText("");
        // stays busy while the profile is read and the next page loads
        await onSignedIn(result.userId);
        return;
      }
      setError(result.error);
      if (result.error === "too_many_requests") {
        setRetryAt(Date.now() + (result.retryAfterS ?? DEFAULT_WAIT_S) * 1000);
      }
      input.current?.focus();
    } finally {
      if (!signedIn) {
        inFlight.current = false;
        setBusy(false);
        onBusy?.(false);
      }
    }
  }

  const errorText = error ? tRoot(ERROR_KEYS[error]) : null;
  return (
    <div className="flex w-full flex-col gap-(--space-3)">
      <PressButton
        variant="secondary"
        className="w-full"
        aria-expanded={open}
        aria-controls={open ? panelId : undefined}
        disabled={disabled && !open}
        onClick={() => setOpen((was) => !was)}
      >
        {t("open")}
      </PressButton>
      {open && (
        <form
          id={panelId}
          noValidate
          className="flex w-full flex-col gap-(--space-3)"
          onSubmit={submit}
        >
          <label htmlFor={fieldId} className="text-sm text-ink-muted">
            {t("label")}
          </label>
          <div className={cx("lk-input min-h-11", error && "border-over")}>
            <input
              ref={input}
              id={fieldId}
              name="recovery-key"
              type="text"
              autoComplete="off"
              autoCapitalize="characters"
              autoCorrect="off"
              spellCheck={false}
              translate="no"
              placeholder={tRoot("vault.unlock.placeholder")}
              value={text}
              readOnly={busy}
              onChange={(event) => {
                setText(event.target.value);
                if (error) setError(null);
              }}
              aria-invalid={error !== null || undefined}
              aria-describedby={error ? errorId : undefined}
              className="min-h-9 min-w-0 flex-1 border-0 bg-transparent p-0 font-mono text-[16px] text-ink uppercase outline-none placeholder:font-normal placeholder:text-ink-muted"
            />
          </div>
          {errorText && <FieldError id={errorId}>{errorText}</FieldError>}
          <PressButton
            type="submit"
            className="w-full"
            disabled={busy || disabled || text.trim() === "" || retryIn > 0}
          >
            {busy
              ? t("busy")
              : retryIn > 0
                ? tRoot("sign_in.wait", { seconds: retryIn })
                : t("submit")}
          </PressButton>
        </form>
      )}
    </div>
  );
}
