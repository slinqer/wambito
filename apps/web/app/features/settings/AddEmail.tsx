import { useQueryClient } from "@tanstack/react-query";
import { type FormEvent, useId, useRef, useState } from "react";
import { useTranslations } from "use-intl";
import { queryKeys } from "../../api/queries.ts";
import { PressButton } from "../../ui/PressButton.tsx";
import { useToast } from "../../ui/Toast.tsx";
import { CODE_ERRORS, EMAIL } from "../sign-in/auth.ts";
import { CODE_LENGTH, CodeInput, type CodeInputHandle } from "../sign-in/CodeInput.tsx";
import { FieldError, ScreenTitle, SignInScreen } from "../sign-in/SignInScreen.tsx";
import { RecoveryKeySetup } from "../vault/RecoveryKeySetup.tsx";
import { type ClaimEmail, ClaimError, type ClaimErrorKey, EMAIL_TAKEN } from "./add-email.ts";
import { useRecoveryKeyStep } from "./recovery-key-step.ts";
import type { SecurityApi } from "./security.ts";

type Busy = "send" | "verify" | null;

/**
 * Step 3 of "Protect your data" (spec 2026-11-15 section 5.2): an account without an email adds
 * one. The email, then the 6-digit code it receives (`CodeInput`, sign-in's error copy), then done:
 * the profile is read again (the email shows, the Protect block goes) and `onDone` closes. The user
 * id and the keys do not change. An email that already has an account is refused with the words to
 * bring this data into it from the phone: the web never merges (web ruling 5).
 */
export function AddEmail({
  claim,
  onDone,
  onCancel,
  security,
}: {
  claim: ClaimEmail;
  /**
   * The open vault's keys. With them, an account that has not saved a recovery key sees its setup
   * right after the email (spec section 7.1), with no way out until it is saved.
   */
  security?: SecurityApi | undefined;
  onDone(): void;
  /** Closes without adding; defaults to `onDone`. */
  onCancel?: () => void;
}) {
  const t = useTranslations("settings.add_email");
  const tRoot = useTranslations();
  const qc = useQueryClient();
  const toast = useToast();
  const [step, setStep] = useState<"email" | "code" | "key">("email");
  const tProtect = useTranslations("settings.protect");
  const tSecurity = useTranslations("settings.security");
  const finish = () => {
    toast.show({ message: t("done") });
    onDone();
  };
  const recovery = useRecoveryKeyStep(security as SecurityApi, finish);
  const [email, setEmail] = useState("");
  const [code, setCode] = useState("");
  const [error, setError] = useState<ClaimErrorKey | null>(null);
  const [busy, setBusy] = useState<Busy>(null);
  // A ref, not state: Enter and the 6th digit can both submit within one render.
  const inFlight = useRef(false);
  const codeInput = useRef<CodeInputHandle>(null);
  const emailId = useId();
  const errorId = useId();

  /** Runs one call at a time; false when it failed (the error is shown) or another is running. */
  async function run(kind: Exclude<Busy, null>, call: () => Promise<void>): Promise<boolean> {
    if (inFlight.current) return false;
    inFlight.current = true;
    setBusy(kind);
    setError(null);
    try {
      await call();
      return true;
    } catch (failure) {
      setError(failure instanceof ClaimError ? failure.key : "errors.generic");
      return false;
    } finally {
      inFlight.current = false;
      setBusy(null);
    }
  }

  async function send(event?: FormEvent) {
    event?.preventDefault();
    const address = email.trim().toLowerCase();
    if (!EMAIL.test(address)) {
      setError("errors.invalid_email");
      return;
    }
    if (await run("send", () => claim.send(address))) {
      setEmail(address);
      setCode("");
      setStep("code");
    }
  }

  /** Whether the settings record says no recovery key was saved (a record we cannot read: assume it was). */
  async function keyUnsaved(): Promise<boolean> {
    if (!security) return false;
    try {
      return ((await security.settings())?.recoveryKeySavedAt ?? null) === null;
    } catch {
      return false;
    }
  }

  async function verify(candidate: string) {
    if (candidate.length !== CODE_LENGTH) return;
    const ok = await run("verify", () => claim.verify(email, candidate));
    if (ok) {
      void qc.invalidateQueries({ queryKey: queryKeys.me() });
      if (await keyUnsaved()) {
        setStep("key");
        void recovery.start();
      } else finish();
    } else {
      setCode("");
      codeInput.current?.focus(0);
    }
  }

  const errorText = error ? (error === EMAIL_TAKEN ? t("taken") : tRoot(error)) : null;
  const cancel = (
    <PressButton
      variant="ghost"
      className="w-full"
      disabled={busy !== null}
      onClick={onCancel ?? onDone}
    >
      {t("cancel")}
    </PressButton>
  );

  if (step === "key") {
    const { key } = recovery;
    // Nothing to cancel: the email is claimed, and the key is the way back in.
    if (key.step === "setup") {
      return (
        <RecoveryKeySetup
          recoveryKey={key.recoveryKey}
          busy={key.saving}
          problem={key.failed ? tSecurity("maybe_saved") : null}
          onContinue={() => void recovery.save(key)}
        />
      );
    }
    return (
      <SignInScreen>
        <ScreenTitle>{tProtect("recovery_title")}</ScreenTitle>
        <p className="text-center text-ink-muted">{tProtect("recovery_lead")}</p>
        {key.problem && (
          <FieldError id={errorId}>
            {tProtect(key.problem === "rotated_elsewhere" ? "recovery_rotated" : "recovery_failed")}
          </FieldError>
        )}
        <PressButton
          className="w-full"
          disabled={key.busy}
          aria-busy={key.busy || undefined}
          onClick={() => void recovery.start()}
        >
          {tProtect("recovery_action")}
        </PressButton>
      </SignInScreen>
    );
  }

  if (step === "code") {
    return (
      <SignInScreen>
        <ScreenTitle>{t("code_title")}</ScreenTitle>
        <p className="text-center text-ink-muted">
          {t.rich("code_lead", {
            email,
            strong: (chunks) => <strong className="wrap-anywhere text-ink">{chunks}</strong>,
          })}
        </p>
        <form
          noValidate
          className="flex w-full flex-col gap-(--space-3)"
          onSubmit={(event) => {
            event.preventDefault();
            void verify(code);
          }}
        >
          <CodeInput
            ref={codeInput}
            value={code}
            onChange={(value) => {
              setCode(value);
              if (error) setError(null);
            }}
            onComplete={(value) => void verify(value)}
            invalid={error !== null && (CODE_ERRORS as ReadonlySet<string>).has(error)}
            readOnly={busy === "verify"}
            describedBy={errorText ? errorId : undefined}
            autoFocus
          />
          {errorText && <FieldError id={errorId}>{errorText}</FieldError>}
          <PressButton
            type="submit"
            className="w-full"
            disabled={busy !== null || code.length !== CODE_LENGTH}
          >
            {busy === "verify" ? t("confirming") : t("confirm")}
          </PressButton>
        </form>
        <div className="flex w-full flex-col items-center">
          <PressButton
            variant="ghost"
            disabled={busy !== null}
            onClick={async () => {
              if (!(await run("send", () => claim.send(email)))) return;
              setCode("");
              toast.show({ message: t("resent") });
              codeInput.current?.focus(0);
            }}
          >
            {t("resend")}
          </PressButton>
          <PressButton
            variant="ghost"
            disabled={busy !== null}
            onClick={() => {
              setStep("email");
              setCode("");
              setError(null);
            }}
          >
            {t("change_email")}
          </PressButton>
        </div>
        {cancel}
      </SignInScreen>
    );
  }

  return (
    <SignInScreen>
      <ScreenTitle>{t("title")}</ScreenTitle>
      <p className="text-center text-ink-muted">{t("lead")}</p>
      <form noValidate className="flex w-full flex-col gap-(--space-3)" onSubmit={send}>
        <label htmlFor={emailId} className="text-sm text-ink-muted">
          {t("email_label")}
        </label>
        <div className="lk-input min-h-11">
          <input
            id={emailId}
            type="email"
            name="email"
            autoComplete="email"
            autoCapitalize="none"
            spellCheck={false}
            enterKeyHint="send"
            autoFocus
            placeholder={t("email_placeholder")}
            value={email}
            onChange={(event) => {
              setEmail(event.target.value);
              if (error) setError(null);
            }}
            aria-invalid={error !== null || undefined}
            aria-describedby={errorText ? errorId : undefined}
            className="min-h-9 min-w-0 flex-1 border-0 bg-transparent p-0 font-text text-[16px] text-ink outline-none placeholder:font-normal placeholder:text-ink-muted"
          />
        </div>
        {errorText && <FieldError id={errorId}>{errorText}</FieldError>}
        <PressButton type="submit" className="w-full" disabled={busy !== null}>
          {busy === "send" ? t("sending") : t("send")}
        </PressButton>
      </form>
      {cancel}
    </SignInScreen>
  );
}
