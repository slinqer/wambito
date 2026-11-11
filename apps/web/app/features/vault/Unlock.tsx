import { useId, useState } from "react";
import { useTranslations } from "use-intl";
import { passkeysSupported as browserPasskeys } from "../../auth/passkey.ts";
import { cx } from "../../ui/cx.ts";
import { FingerprintIcon } from "../../ui/FingerprintIcon.tsx";
import { PressButton } from "../../ui/PressButton.tsx";
import { FieldError, ScreenTitle, SignInScreen } from "../sign-in/SignInScreen.tsx";

/** Why unlocking failed; `null` from `onUnlock` means it worked. Mirrors `KeysError.code`. */
export type UnlockError =
  | "bad_recovery_key"
  | "wrong_recovery_key"
  | "no_prf"
  | "no_passkey_wrap"
  | "offline"
  | "server";

export interface UnlockProps {
  /**
   * `removed`: another device removed this browser; its vault (and unsynced edits) are gone.
   * `unverified`: a new key version did not verify; the vault is kept, unlocking resumes the sync.
   */
  notice?: "removed" | "unverified" | undefined;
  /** Tries the typed text (any case, spaces or dashes). Resolves to the error, or `null`. */
  onUnlock(text: string): Promise<UnlockError | null>;
  /**
   * "Use a passkey": a touch of one of the person's passkeys for its PRF. Resolves to the error, or
   * `null` (it worked, or the person closed the prompt). Without it there is no button.
   */
  onPasskey?(): Promise<UnlockError | null>;
  /** Whether this browser can use passkeys (WebAuthn); stories stand in for it. */
  passkeysSupported?(): boolean;
  /** "From another device": the pairing screen, where a device that has the data approves this one. */
  onPair?(): void;
  /** Signs out (and wipes this browser's vault): the way out. */
  onSignOut(): void;
}

/**
 * A new browser on an account that has keys: type the recovery key, touch a passkey whose PRF
 * opens its wrap, or have another device approve this one, to open the data here.
 */
export function Unlock({
  notice,
  onUnlock,
  onPasskey,
  passkeysSupported = browserPasskeys,
  onPair,
  onSignOut,
}: UnlockProps) {
  const t = useTranslations("vault.unlock");
  const tVault = useTranslations("vault");
  const [text, setText] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<UnlockError | null>(null);
  const [passkeyError, setPasskeyError] = useState<UnlockError | null>(null);
  const [withPasskey] = useState(() => Boolean(onPasskey) && passkeysSupported());
  const inputId = useId();
  const errorId = useId();
  const passkeyErrorId = useId();

  async function passkey() {
    if (busy || !onPasskey) return;
    setBusy(true);
    setError(null);
    setPasskeyError(null);
    try {
      setPasskeyError(await onPasskey());
    } finally {
      setBusy(false);
    }
  }

  async function submit(event: React.FormEvent) {
    event.preventDefault();
    if (busy || text.trim() === "") return;
    setBusy(true);
    setError(null);
    setPasskeyError(null);
    try {
      setError(await onUnlock(text));
    } finally {
      setBusy(false);
    }
  }

  return (
    <SignInScreen>
      <ScreenTitle>{t("title")}</ScreenTitle>
      {notice && (
        <p role="status" className="lk-rowcard m-0 text-[15px] text-ink">
          {tVault(notice)}
        </p>
      )}
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
      {withPasskey && (
        <div className="flex w-full flex-col gap-(--space-2)">
          <PressButton
            variant="secondary"
            className="w-full"
            disabled={busy}
            aria-describedby={passkeyError ? passkeyErrorId : undefined}
            onClick={() => void passkey()}
          >
            <FingerprintIcon />
            {t("passkey")}
          </PressButton>
          {passkeyError && (
            <FieldError id={passkeyErrorId}>{t(`error_${passkeyError}`)}</FieldError>
          )}
        </div>
      )}
      {onPair && (
        <PressButton variant="secondary" className="w-full" disabled={busy} onClick={onPair}>
          {t("pair")}
        </PressButton>
      )}
      <PressButton variant="ghost" className="w-full" disabled={busy} onClick={onSignOut}>
        {tVault("sign_out")}
      </PressButton>
    </SignInScreen>
  );
}
