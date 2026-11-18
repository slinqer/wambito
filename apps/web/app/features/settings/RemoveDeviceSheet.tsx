import { useEffect, useId, useRef, useState } from "react";
import { createPortal } from "react-dom";
import { useTranslations } from "use-intl";
import { cx } from "../../ui/cx.ts";
import { PressButton } from "../../ui/PressButton.tsx";
import { Sheet } from "../../ui/Sheet.tsx";
import { FieldError } from "../sign-in/SignInScreen.tsx";
import { codeOf, type SecurityApi } from "./security.ts";
import type { DeviceRow } from "./security-model.ts";

/**
 * A whole-screen step over Settings (the recovery key's setup, approving a device). Everything
 * else on the page is `inert` meanwhile: out of reach and out of the accessibility tree.
 */
export function Takeover({ label, children }: { label: string; children: React.ReactNode }) {
  const ref = useRef<HTMLDivElement>(null);
  useEffect(() => {
    const opener = document.activeElement instanceof HTMLElement ? document.activeElement : null;
    const { overflow } = document.body.style;
    document.body.style.overflow = "hidden";
    const outside = [...document.body.children].filter(
      (element): element is HTMLElement =>
        element instanceof HTMLElement && !element.contains(ref.current) && !element.inert,
    );
    for (const element of outside) element.inert = true;
    ref.current?.focus();
    return () => {
      for (const element of outside) element.inert = false;
      document.body.style.overflow = overflow;
      opener?.focus();
    };
  }, []);
  return createPortal(
    <div
      ref={ref}
      role="dialog"
      aria-modal="true"
      aria-label={label}
      tabIndex={-1}
      className="fixed inset-0 z-[45] overflow-y-auto outline-none"
    >
      {children}
    </div>,
    document.body,
  );
}

/** A typed recovery key's refusal, shown on the field. */
export type KeyError = "bad_recovery_key" | "wrong_recovery_key";
/** Anything else that stopped it, shown under the buttons. */
export type Problem = "rotated_elsewhere" | "offline" | "failed";

export const keyErrorOf = (error: unknown): KeyError | null => {
  const code = codeOf(error);
  return code === "bad_recovery_key" || code === "wrong_recovery_key" ? code : null;
};

export const problemOf = (error: unknown): Problem => {
  const code = codeOf(error);
  return code === "rotated_elsewhere" || code === "offline" ? code : "failed";
};

/** A recovery-key field: its label, the error on it. */
export function RecoveryKeyField({
  label,
  value,
  onChange,
  error,
}: {
  label: string;
  value: string;
  onChange(value: string): void;
  error: KeyError | null;
}) {
  const tUnlock = useTranslations("vault.unlock");
  const inputId = useId();
  const errorId = useId();
  return (
    <div className="flex flex-col gap-(--space-2)">
      <label htmlFor={inputId} className="text-[15px] font-bold text-ink">
        {label}
      </label>
      <div className={cx("lk-input min-h-11", error && "border-over")}>
        <input
          id={inputId}
          type="text"
          autoComplete="off"
          autoCapitalize="characters"
          autoCorrect="off"
          spellCheck={false}
          translate="no"
          placeholder={tUnlock("placeholder")}
          value={value}
          onChange={(event) => onChange(event.target.value)}
          aria-invalid={error !== null || undefined}
          aria-describedby={error ? errorId : undefined}
          className="min-h-9 min-w-0 flex-1 border-0 bg-transparent p-0 font-mono text-[16px] text-ink uppercase outline-none placeholder:font-normal placeholder:text-ink-muted"
        />
      </div>
      {error && <FieldError id={errorId}>{tUnlock(`error_${error}`)}</FieldError>}
    </div>
  );
}

/**
 * The account's passkeys, as far as Settings knows: a new recovery key is offered only once the
 * list is `ready` (Ruling 2's touch must not be skipped while it loads or after it failed).
 */
export type PasskeyList =
  | { status: "loading" }
  | { status: "failed"; retry(): void }
  | { status: "ready"; ids: readonly string[] };

/** The passkey list could not be read: the new key waits, with a retry. */
export function PasskeyListFailed({ retry }: { retry(): void }) {
  const t = useTranslations("settings.security");
  const tCommon = useTranslations("common");
  return (
    <div className="flex flex-col gap-(--space-2)">
      <p className="m-0 text-[14px] text-ink-muted">{t("passkeys_failed")}</p>
      <PressButton variant="ghost" size="sm" className="self-start" onClick={retry}>
        {tCommon("retry")}
      </PressButton>
    </div>
  );
}

export interface RemoveDeviceSheetProps {
  /** The device to remove; null: closed. Never this browser's own (the list does not offer it). */
  device: DeviceRow | null;
  security: SecurityApi;
  onClose(): void;
  /** The device lost its access (a wrap already gone counts): read the keys again. */
  onRemoved(device: DeviceRow): void;
}

/**
 * Removing a device is one tap: its wrap is deleted and its session ends (`removeDevice`). The data
 * key does not change and no recovery key is asked. Offline or any other failure keeps the row and
 * says so; nothing is half-done.
 */
export function RemoveDeviceSheet({
  device,
  security,
  onClose,
  onRemoved,
}: RemoveDeviceSheetProps) {
  const t = useTranslations("settings.security");
  const tSheet = useTranslations("settings.security.remove_sheet");
  const tUnlock = useTranslations("vault.unlock");
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);
  const problemId = useId();
  const name = device?.label ?? t("unnamed");

  const close = () => {
    setBusy(false);
    setProblem(null);
    onClose();
  };

  async function remove(event: React.FormEvent) {
    event.preventDefault();
    if (!device || busy) return;
    setBusy(true);
    setProblem(null);
    try {
      await security.removeDevice(device.id);
    } catch (error) {
      setBusy(false);
      setProblem(problemOf(error) === "offline" ? "offline" : "failed");
      return;
    }
    const removed = device;
    close();
    onRemoved(removed);
  }

  return (
    <Sheet open={device !== null} onClose={close} title={tSheet("title", { name })}>
      <form noValidate className="flex flex-col gap-(--space-4) pt-(--space-3)" onSubmit={remove}>
        <p className="m-0 text-[15px] text-ink">{tSheet("body")}</p>
        <PressButton
          type="submit"
          variant="secondary"
          className="w-full text-over"
          disabled={busy}
          aria-busy={busy || undefined}
          aria-describedby={problem ? problemId : undefined}
        >
          {busy ? tSheet("removing") : tSheet("confirm")}
        </PressButton>
        {problem && (
          <FieldError id={problemId}>
            {problem === "offline" ? tUnlock("error_offline") : tSheet("failed")}
          </FieldError>
        )}
      </form>
    </Sheet>
  );
}
