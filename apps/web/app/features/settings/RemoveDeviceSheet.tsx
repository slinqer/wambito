import { useEffect, useId, useRef, useState } from "react";
import { createPortal } from "react-dom";
import { useTranslations } from "use-intl";
import type { PasskeyPrf } from "../../local/prf.ts";
import type { RotateResult } from "../../local/rotate.ts";
import { cx } from "../../ui/cx.ts";
import { PressButton } from "../../ui/PressButton.tsx";
import { Sheet } from "../../ui/Sheet.tsx";
import { FieldError } from "../sign-in/SignInScreen.tsx";
import { RecoveryKeySetup } from "../vault/RecoveryKeySetup.tsx";
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

type Step =
  | { step: "ask"; busy: boolean; keyError: KeyError | null; problem: Problem | null }
  | {
      step: "setup";
      recoveryKey: string;
      commit(): Promise<RotateResult>;
      saving: boolean;
      /** A commit failed: the new key may be saved, so it stays on screen (no Cancel) until done. */
      failed: boolean;
    }
  | { step: "committing" }
  | { step: "done"; result: RotateResult };

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
  /** The device to remove; null: closed. Never this browser's own (rotate.ts refuses it). */
  device: DeviceRow | null;
  security: SecurityApi;
  /** The account's passkeys: a touch of one confirms "make a new recovery key". */
  passkeyList: PasskeyList;
  /** Whether this browser can touch a passkey (WebAuthn). */
  canTouch: boolean;
  onClose(): void;
  /** The account's keys changed (or may have): read them again. */
  onChanged(): void;
}

/**
 * Removing a device rotates the data key (stage 2b Ruling 2): the person types the recovery key
 * (re-wrapped, nothing new to write down), or makes a new one (a passkey touch confirms it when
 * the account has passkeys; that passkey keeps its wrap), shown through `RecoveryKeySetup`, and
 * committed only after its four characters are typed back. Then the sync takes the new keys and the
 * sheet lists what was left out.
 */
export function RemoveDeviceSheet({
  device,
  security,
  passkeyList,
  canTouch,
  onClose,
  onChanged,
}: RemoveDeviceSheetProps) {
  const passkeyIds = passkeyList.status === "ready" ? passkeyList.ids : null;
  /**
   * "Make a new recovery key": only with the list loaded, and, when the account has passkeys,
   * only where this browser can touch one (else only the typed key confirms).
   */
  const newKeyOffer: "wait" | "failed" | "no" | "touch" | "plain" =
    passkeyIds === null
      ? passkeyList.status === "failed"
        ? "failed"
        : "wait"
      : passkeyIds.length === 0
        ? "plain"
        : canTouch
          ? "touch"
          : "no";
  const t = useTranslations("settings.security");
  const tSheet = useTranslations("settings.security.remove_sheet");
  const tUnlock = useTranslations("vault.unlock");
  const [step, setStep] = useState<Step>({
    step: "ask",
    busy: false,
    keyError: null,
    problem: null,
  });
  const [text, setText] = useState("");
  const problemId = useId();
  /** The passkey touched for "make a new key": kept until done, each try gets a copy (rotate zeroes it). */
  const touched = useRef<PasskeyPrf | null>(null);
  /** A passkey touch confirmed it (with or without PRF): a retry asks for no second touch. */
  const confirmed = useRef(false);
  const [usedPasskey, setUsedPasskey] = useState(false);

  const forget = () => {
    touched.current?.prf.fill(0);
    touched.current = null;
    confirmed.current = false;
  };
  useEffect(() => forget, []);

  const name = device?.label ?? t("unnamed");
  const ask = (patch: Partial<Extract<Step, { step: "ask" }>> = {}) =>
    setStep({ step: "ask", busy: false, keyError: null, problem: null, ...patch });

  const close = () => {
    forget();
    setText("");
    setUsedPasskey(false);
    ask();
    onClose();
  };

  const failed = (error: unknown) => {
    const keyError = keyErrorOf(error);
    if (keyError) {
      ask({ keyError });
      return;
    }
    const problem = problemOf(error);
    if (problem === "rotated_elsewhere") {
      // The sync picks up the other device's keys; the list follows.
      void security.reloadKeys().catch(() => {});
      onChanged();
    }
    ask({ problem });
  };

  /**
   * Commits the rotation. From the new key's setup, a failure other than `rotated_elsewhere` (refused
   * for sure) may have been saved: the setup stays with the same key, and Continue retries the
   * same `commit()` (retry-safe; `landed()` recognises a rotation whose answer was lost).
   */
  async function commit(
    run: () => Promise<RotateResult>,
    setup?: Extract<Step, { step: "setup" }>,
  ) {
    if (setup?.saving) return;
    setStep(setup ? { ...setup, saving: true } : { step: "committing" });
    let result: RotateResult;
    try {
      result = await run();
    } catch (error) {
      if (setup && problemOf(error) !== "rotated_elsewhere") {
        setStep({ ...setup, saving: false, failed: true });
        return;
      }
      failed(error);
      return;
    }
    forget();
    try {
      await security.reloadKeys();
    } catch {
      // The sync tries again on its own; the rotation is kept.
    }
    onChanged();
    setStep({ step: "done", result });
  }

  async function withKey(event: React.FormEvent) {
    event.preventDefault();
    if (!device || step.step !== "ask" || step.busy || text.trim() === "") return;
    ask({ busy: true });
    let prepared: Awaited<ReturnType<SecurityApi["rotate"]>>;
    try {
      prepared = await security.rotate({ remove: [device.id], recovery: { text } });
    } catch (error) {
      failed(error);
      return;
    }
    await commit(prepared.commit);
  }

  async function withNewKey() {
    if (!device || step.step !== "ask" || step.busy || passkeyIds === null) return;
    if (newKeyOffer !== "touch" && newKeyOffer !== "plain") return;
    ask({ busy: true });
    if (!confirmed.current && newKeyOffer === "touch") {
      let passkey: PasskeyPrf | null = null;
      try {
        passkey = await security.evaluatePrf([...passkeyIds]);
        if (!passkey) {
          ask();
          return;
        }
      } catch (error) {
        // A touch without PRF still confirms (Ruling 2): that passkey just keeps no wrap.
        if (codeOf(error) !== "no_prf") {
          ask({ problem: problemOf(error) });
          return;
        }
      }
      confirmed.current = true;
      touched.current = passkey;
    }
    const kept = touched.current;
    setUsedPasskey(kept !== null);
    let prepared: Awaited<ReturnType<SecurityApi["rotate"]>>;
    try {
      prepared = await security.rotate({
        remove: [device.id],
        recovery: { fresh: true },
        ...(kept ? { passkey: { credentialId: kept.credentialId, prf: kept.prf.slice() } } : {}),
      });
    } catch (error) {
      failed(error);
      return;
    }
    setStep({
      step: "setup",
      recoveryKey: prepared.recoveryKey as string,
      commit: prepared.commit,
      saving: false,
      failed: false,
    });
  }

  if (step.step === "setup") {
    return (
      <Takeover label={tSheet("title", { name })}>
        <RecoveryKeySetup
          recoveryKey={step.recoveryKey}
          busy={step.saving}
          problem={step.failed ? t("maybe_saved") : null}
          onContinue={() => void commit(step.commit, step)}
          {...(step.failed ? {} : { onCancel: () => ask() })}
        />
      </Takeover>
    );
  }

  const done = step.step === "done" ? step.result : null;
  const dropped = done ? done.dropped.filter((d) => d.id !== device?.id) : [];
  const lostPasskeys = (passkeyIds?.length ?? 0) > (usedPasskey ? 1 : 0);
  const busy = step.step === "committing" || (step.step === "ask" && step.busy);
  const asking = step.step === "ask" ? step : null;

  return (
    <Sheet
      open={device !== null}
      onClose={close}
      title={done ? tSheet("done_title") : tSheet("title", { name })}
    >
      {done ? (
        <div className="flex flex-col gap-(--space-4) pt-(--space-3)">
          <p className="m-0 text-[15px] text-ink">{tSheet("done_lead", { name })}</p>
          {dropped.length > 0 && (
            <div className="flex flex-col gap-(--space-1)">
              <p className="m-0 text-[15px] text-ink">{tSheet("dropped_lead")}</p>
              <ul className="m-0 flex flex-col gap-(--space-1) pl-(--space-4) text-[15px] text-ink">
                {dropped.map((d) => (
                  <li key={d.id}>
                    {tSheet("dropped_item", { name: d.label ?? t("unnamed"), reason: d.reason })}
                  </li>
                ))}
              </ul>
            </div>
          )}
          {lostPasskeys && (
            <p className="m-0 text-[14px] text-ink-muted">{tSheet("passkeys_note")}</p>
          )}
        </div>
      ) : (
        <form
          noValidate
          className="flex flex-col gap-(--space-4) pt-(--space-3)"
          onSubmit={withKey}
        >
          <p className="m-0 text-[15px] text-ink">{tSheet("body")}</p>
          <RecoveryKeyField
            label={tSheet("key_label")}
            value={text}
            onChange={(value) => {
              setText(value);
              if (asking?.keyError) ask();
            }}
            error={asking?.keyError ?? null}
          />
          <PressButton
            type="submit"
            variant="secondary"
            className="w-full text-over"
            disabled={busy || text.trim() === ""}
            aria-busy={busy || undefined}
            aria-describedby={asking?.problem ? problemId : undefined}
          >
            {busy ? tSheet("removing") : tSheet("confirm")}
          </PressButton>
          {(newKeyOffer === "wait" || newKeyOffer === "touch" || newKeyOffer === "plain") && (
            <PressButton
              variant="ghost"
              className="w-full"
              disabled={busy || newKeyOffer === "wait"}
              aria-busy={newKeyOffer === "wait" || undefined}
              onClick={() => void withNewKey()}
            >
              {tSheet("or_new")}
            </PressButton>
          )}
          {passkeyList.status === "failed" && <PasskeyListFailed retry={passkeyList.retry} />}
          {asking?.problem && (
            <FieldError id={problemId}>
              {asking.problem === "offline"
                ? tUnlock("error_offline")
                : tSheet(asking.problem === "rotated_elsewhere" ? "rotated_elsewhere" : "failed")}
            </FieldError>
          )}
        </form>
      )}
    </Sheet>
  );
}
