import { Fragment, useId, useState } from "react";
import { useTranslations } from "use-intl";
import { passkeysSupported as browserPasskeys } from "../../auth/passkey.ts";
import { FingerprintIcon } from "../../ui/FingerprintIcon.tsx";
import { PressButton } from "../../ui/PressButton.tsx";
import { FieldError, ScreenTitle, SignInScreen } from "../sign-in/SignInScreen.tsx";
import { RecoveryKeyField } from "./RecoveryKeyField.tsx";
import { isFullRecoveryKey } from "./recovery-key-input.ts";
import { unlockLayout } from "./unlock-layout.ts";
import type { UnlockMeans } from "./vault-gate.ts";

/** Why unlocking failed; `null` from `onUnlock` means it worked. Mirrors `KeysError.code`. */
export type UnlockError =
  | "bad_recovery_key"
  | "wrong_recovery_key"
  | "no_prf"
  | "no_passkey_wrap"
  | "offline"
  | "server";

/** No hint and a passkey wrap: the passkey leads, as for most accounts. */
const DEFAULT_MEANS: UnlockMeans = { noPrfHere: false, passkeyWrap: true };

export interface UnlockProps {
  /**
   * `removed`: another device removed this browser; its vault (and unsynced edits) are gone.
   * `unverified`: a new key version did not verify; the vault is kept, unlocking resumes the sync.
   */
  notice?: "removed" | "unverified" | undefined;
  /** Tries the typed text (any case, spaces or dashes). Resolves to the error, or `null`. */
  onUnlock(text: string): Promise<UnlockError | null>;
  /**
   * "Open with my passkey": a touch of one of the person's passkeys for its PRF. Resolves to the
   * error, or `null` (it worked, or the person closed the prompt). Without it there is no button.
   */
  onPasskey?(): Promise<UnlockError | null>;
  /** Whether this browser can use passkeys (WebAuthn); stories stand in for it. */
  passkeysSupported?(): boolean;
  /** "From another device": the pairing screen, where a device that has the data approves this one. */
  onPair?(): void;
  /** Signs out (and wipes this browser's vault): the way out. */
  onSignOut(): void;
  /** Another screen's title (the consent page's); "Open your data here" by default. */
  title?: string;
  /** Another lead, or null for none; by default one that fits the layout. */
  lead?: string | null;
  /** The way out's label when it is not signing out (the consent page goes back). */
  exitLabel?: string;
  /** What can open the data here; by default a passkey wrap and no hint (passkey first). */
  means?: UnlockMeans;
}

/**
 * A new browser on an account that has keys: a passkey whose PRF opens its wrap, another device
 * that approves this one, or the recovery key, to open the data here. One of three layouts
 * (`unlockLayout`, spec 2026-11-20 section 1): the recovery key first (the last passkey touched
 * here gave no PRF, with a line saying so), the passkey first, or the pairing first; the rest under
 * "More options", closed until tapped or until a passkey above it fails with `no_prf` or
 * `no_passkey_wrap`. With nothing else to offer the recovery key leads alone. No passkey prompt
 * without a tap.
 */
export function Unlock({
  notice,
  onUnlock,
  onPasskey,
  passkeysSupported = browserPasskeys,
  onPair,
  onSignOut,
  title,
  lead,
  exitLabel,
  means = DEFAULT_MEANS,
}: UnlockProps) {
  const t = useTranslations("vault.unlock");
  const tVault = useTranslations("vault");
  const [text, setText] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<UnlockError | null>(null);
  const [passkeyError, setPasskeyError] = useState<UnlockError | null>(null);
  const [withPasskey] = useState(() => Boolean(onPasskey) && passkeysSupported());
  const [moreOpen, setMoreOpen] = useState(false);
  const inputId = useId();
  const errorId = useId();
  const passkeyErrorId = useId();
  const moreId = useId();
  const layout = unlockLayout({
    noPrfHere: means.noPrfHere,
    passkeyWrap: means.passkeyWrap,
    passkeysSupported: withPasskey,
    canPair: Boolean(onPair),
  });

  async function passkey() {
    if (busy || !onPasskey) return;
    setBusy(true);
    setError(null);
    setPasskeyError(null);
    try {
      const failed = await onPasskey();
      setPasskeyError(failed);
      // The passkey above "More options" cannot open the data: the recovery key comes into sight.
      if (layout.main === "passkey" && (failed === "no_prf" || failed === "no_passkey_wrap")) {
        setMoreOpen(true);
      }
    } finally {
      setBusy(false);
    }
  }

  async function submit(event: React.FormEvent) {
    event.preventDefault();
    if (busy || !isFullRecoveryKey(text)) return;
    setBusy(true);
    setError(null);
    setPasskeyError(null);
    try {
      setError(await onUnlock(text));
    } finally {
      setBusy(false);
    }
  }

  const keyForm = (primary: boolean) => (
    <form noValidate className="flex w-full flex-col gap-(--space-3)" onSubmit={submit}>
      <label htmlFor={inputId} className="text-sm text-ink-muted">
        {t("label")}
      </label>
      <RecoveryKeyField
        id={inputId}
        value={text}
        onChange={(next) => {
          setText(next);
          if (error) setError(null);
        }}
        invalid={error !== null}
        describedBy={error ? errorId : undefined}
      />
      {error && <FieldError id={errorId}>{t(`error_${error}`)}</FieldError>}
      <PressButton
        type="submit"
        variant={primary ? "primary" : "secondary"}
        className="w-full"
        disabled={busy || !isFullRecoveryKey(text)}
      >
        {busy ? t("busy") : t("submit")}
      </PressButton>
    </form>
  );

  const passkeyButton = (primary: boolean) => (
    <div className="flex w-full flex-col gap-(--space-2)">
      <PressButton
        variant={primary ? "primary" : "secondary"}
        className="w-full"
        disabled={busy}
        aria-describedby={passkeyError ? passkeyErrorId : undefined}
        onClick={() => void passkey()}
      >
        <FingerprintIcon />
        {primary ? t("passkey") : t("other_passkey")}
      </PressButton>
      {passkeyError && <FieldError id={passkeyErrorId}>{t(`error_${passkeyError}`)}</FieldError>}
    </div>
  );

  const pairButton = (primary: boolean) => (
    <PressButton
      variant={primary ? "primary" : "secondary"}
      className="w-full"
      disabled={busy}
      onClick={onPair}
    >
      {t("pair")}
    </PressButton>
  );

  const place = (what: "key" | "passkey" | "pair", primary: boolean) =>
    what === "key"
      ? keyForm(primary)
      : what === "passkey"
        ? passkeyButton(primary)
        : pairButton(primary);

  const defaultLead = layout.main === "key" ? t("lead") : t("lead_other");

  return (
    <SignInScreen>
      <ScreenTitle>{title ?? t("title")}</ScreenTitle>
      {notice && (
        <p role="status" className="lk-rowcard m-0 text-[15px] text-ink">
          {tVault(notice)}
        </p>
      )}
      {lead !== null && <p className="text-center text-ink-muted">{lead ?? defaultLead}</p>}
      {layout.main === "key" && means.noPrfHere && (
        <p className="m-0 text-center text-[15px] text-ink">{t("no_prf_line")}</p>
      )}
      {place(layout.main, true)}
      {layout.below.map((what) => (
        <Fragment key={what}>{place(what, false)}</Fragment>
      ))}
      {layout.more.length > 0 && (
        <div className="flex w-full flex-col gap-(--space-3)">
          <PressButton
            variant="ghost"
            className="w-full"
            aria-expanded={moreOpen}
            aria-controls={moreOpen ? moreId : undefined}
            onClick={() => setMoreOpen((was) => !was)}
          >
            {t("more")}
          </PressButton>
          {moreOpen && (
            <div id={moreId} className="flex w-full flex-col gap-(--space-3)">
              {layout.more.map((what) => (
                <Fragment key={what}>{place(what, false)}</Fragment>
              ))}
            </div>
          )}
        </div>
      )}
      <PressButton variant="ghost" className="w-full" disabled={busy} onClick={onSignOut}>
        {exitLabel ?? tVault("sign_out")}
      </PressButton>
    </SignInScreen>
  );
}
