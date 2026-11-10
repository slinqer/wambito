import { useId, useState } from "react";
import { useLocale, useTranslations } from "use-intl";
import { cx } from "../../ui/cx.ts";
import { PressButton } from "../../ui/PressButton.tsx";
import { FieldError, ScreenTitle, SignInScreen } from "../sign-in/SignInScreen.tsx";
import {
  confirmationMatches,
  groupPosition,
  pickPositions,
  recoveryFileText,
} from "./vault-model.ts";

/** Hands the recovery file to the browser's download. */
export type SaveTextFile = (file: { name: string; content: string }) => void;

export const RECOVERY_FILE_NAME = "wambito-recovery-key.txt";

/** The browser's download of a small text file. */
export const saveTextFile: SaveTextFile = ({ name, content }) => {
  const url = URL.createObjectURL(new Blob([content], { type: "text/plain;charset=utf-8" }));
  const link = document.createElement("a");
  link.href = url;
  link.download = name;
  link.rel = "noopener";
  link.hidden = true;
  document.body.append(link);
  link.click();
  link.remove();
  setTimeout(() => URL.revokeObjectURL(url), 60_000);
};

export interface RecoveryKeySetupProps {
  /** The formatted key (`XXXX-XXXX-…`). Shown here and nowhere else. */
  recoveryKey: string;
  /** The person confirmed they kept it: the app goes on. */
  onContinue(): void;
  /** Signs out (and wipes this browser's vault): nothing was sent yet, so nothing is kept. */
  onSignOut?(): void;
  /**
   * Settings' new key (an open vault): "Cancel" instead of signing out; nothing was sent, the old
   * key keeps working.
   */
  onCancel?(): void;
  onCopy?(text: string): Promise<void> | void;
  onSave?: SaveTextFile;
  /** For the file's date; defaults to now. */
  now?: Date;
  /** The 1-based positions to type back (4). Random unless a story pins them. */
  positions?: number[];
}

/**
 * First run: shows the recovery key once, lets the person copy or download it, then asks for four
 * of its characters back before "Continue" enables (spec 7.1). Pure UI: the key comes in, the
 * caller decides what happens next.
 */
export function RecoveryKeySetup({
  recoveryKey,
  onContinue,
  onSignOut,
  onCancel,
  onCopy = (text) => navigator.clipboard.writeText(text),
  onSave = saveTextFile,
  now,
  positions: given,
}: RecoveryKeySetupProps) {
  const t = useTranslations("vault.setup");
  const tVault = useTranslations("vault");
  const locale = useLocale();
  const [positions] = useState(() => given ?? pickPositions());
  const [step, setStep] = useState<"show" | "confirm">("show");
  const [copied, setCopied] = useState(false);
  const [typed, setTyped] = useState<string[]>(() => positions.map(() => ""));
  const errorId = useId();
  const tCommon = useTranslations("common");

  async function copy() {
    try {
      await onCopy(recoveryKey);
      setCopied(true);
      setTimeout(() => setCopied(false), 2500);
    } catch {
      // The clipboard can be blocked; the key is on screen and in the file.
    }
  }

  function download() {
    const date = new Intl.DateTimeFormat(locale, { dateStyle: "long" }).format(now ?? new Date());
    onSave({
      name: RECOVERY_FILE_NAME,
      content: recoveryFileText({
        title: t("file_title"),
        key: recoveryKey,
        line: t("file_line"),
        date: t("file_date", { date }),
      }),
    });
  }

  if (step === "show") {
    return (
      <SignInScreen>
        <ScreenTitle>{t("title")}</ScreenTitle>
        <p className="text-center text-ink-muted">{t("lead")}</p>
        <div
          role="group"
          aria-label={t("key_label")}
          translate="no"
          className="flex w-full flex-wrap justify-center gap-x-(--space-3) gap-y-(--space-2) rounded-md border-2 border-stroke bg-surface-row p-(--space-3) font-mono text-[20px] font-bold tracking-wider text-ink select-all"
        >
          {recoveryKey.split("-").map((group, i) => (
            <span key={i}>{group}</span>
          ))}
        </div>
        <div className="flex w-full gap-(--space-2)">
          <PressButton variant="secondary" className="flex-1" onClick={copy}>
            <span aria-live="polite">{copied ? t("copied") : t("copy")}</span>
          </PressButton>
          <PressButton variant="secondary" className="flex-1" onClick={download}>
            {t("download")}
          </PressButton>
        </div>
        <PressButton className="w-full" onClick={() => setStep("confirm")}>
          {t("saved")}
        </PressButton>
        {onCancel ? (
          <PressButton variant="ghost" className="w-full" onClick={onCancel}>
            {tCommon("cancel")}
          </PressButton>
        ) : (
          onSignOut && (
            <PressButton variant="ghost" className="w-full" onClick={onSignOut}>
              {tVault("sign_out")}
            </PressButton>
          )
        )}
      </SignInScreen>
    );
  }

  const filled = typed.every((c) => c.trim() !== "");
  const matches = confirmationMatches(recoveryKey, positions, typed);
  const mismatch = filled && !matches;
  return (
    <SignInScreen>
      <ScreenTitle>{t("confirm_title")}</ScreenTitle>
      <p className="text-center text-ink-muted">{t("confirm_lead")}</p>
      <form
        className="flex w-full flex-col gap-(--space-3)"
        onSubmit={(event) => {
          event.preventDefault();
          if (matches) onContinue();
        }}
      >
        <fieldset className="m-0 flex min-w-0 justify-center gap-(--space-2) border-0 p-0">
          <legend className="sr-only">{t("chars_group")}</legend>
          {positions.map((n, i) => {
            const at = groupPosition(n);
            return (
              <label key={n} className="flex min-w-0 flex-1 flex-col items-center gap-(--space-1)">
                <span
                  aria-hidden="true"
                  className="text-center text-[12px] leading-tight text-ink-muted"
                >
                  <span className="block font-bold text-ink">{t("group", at)}</span>
                  {t("char_in_group", at)}
                </span>
                <span className={cx("lk-input min-h-11 w-full", mismatch && "border-over")}>
                  <input
                    aria-label={t("char_label", at)}
                    aria-invalid={mismatch || undefined}
                    aria-describedby={mismatch ? errorId : undefined}
                    value={typed[i]}
                    maxLength={1}
                    autoComplete="off"
                    autoCapitalize="characters"
                    spellCheck={false}
                    onChange={(event) =>
                      setTyped((now) => now.map((c, j) => (j === i ? event.target.value : c)))
                    }
                    className="min-h-9 w-full min-w-0 border-0 bg-transparent p-0 text-center font-mono text-[20px] font-bold text-ink uppercase outline-none"
                  />
                </span>
              </label>
            );
          })}
        </fieldset>
        {mismatch && (
          <div className="text-center">
            <FieldError id={errorId}>{t("mismatch")}</FieldError>
          </div>
        )}
        <PressButton type="submit" className="w-full" disabled={!matches}>
          {t("continue")}
        </PressButton>
        <PressButton variant="ghost" className="w-full" onClick={() => setStep("show")}>
          {t("show_again")}
        </PressButton>
      </form>
    </SignInScreen>
  );
}
