import { useEffect, useId, useRef, useState } from "react";
import { renderSVG } from "uqr";
import { useTranslations } from "use-intl";
import { intlTag, type Locale } from "../../i18n/format.ts";
import { useLocale } from "../../i18n/IntlProvider.tsx";
import { PressButton } from "../../ui/PressButton.tsx";
import { FieldError, ScreenTitle, SignInScreen } from "../sign-in/SignInScreen.tsx";

/** What the screen needs of a new device's request (`local/pairing.ts` `NewDevicePairing`). */
export interface PairNewDeviceRequest {
  code: string;
  qr: string;
  expiresAt: string;
  number(): Promise<string>;
  /** Resolves once this browser holds the keys; the gate then opens the vault. */
  finish(): Promise<unknown>;
  cancel(): void;
}

/** What a pairing can end in, as shown; `cancelled` shows nothing. */
export type PairingProblem = "expired" | "tampered" | "offline" | "server";

/** A thrown pairing error's code as a problem to show; null for a cancel (nothing to say). */
export function pairingProblem(error: unknown): PairingProblem | "bad_code" | null {
  const code =
    error && typeof error === "object" && "code" in error && typeof error.code === "string"
      ? error.code
      : undefined;
  if (code === "cancelled") return null;
  if (code === "expired" || code === "tampered" || code === "offline" || code === "bad_code") {
    return code;
  }
  return "server";
}

/** The six digits in two groups of three, the same on both screens. */
export function PairingNumber({ value }: { value: string }) {
  return (
    <p
      translate="no"
      className="m-0 text-center font-mono text-[40px] leading-none font-bold tracking-[0.12em] text-ink"
    >
      {`${value.slice(0, 3)} ${value.slice(3)}`}
    </p>
  );
}

/** A time as `14:05` (es) or `02:05 PM` (en), in the person's time zone. */
export function formatTime(iso: string, locale: Locale, timeZone: string): string {
  const at = new Date(iso);
  try {
    return new Intl.DateTimeFormat(intlTag(locale), {
      hour: "2-digit",
      minute: "2-digit",
      timeZone,
    }).format(at);
  } catch {
    // An unknown zone: the browser's own.
    return new Intl.DateTimeFormat(intlTag(locale), { hour: "2-digit", minute: "2-digit" }).format(
      at,
    );
  }
}

export interface PairNewDeviceProps {
  /** Asks for a request (again on "Start again"; the gate cancels the previous one). */
  start(): Promise<PairNewDeviceRequest>;
  /** Back to where the person came from (Unlock, or a guest's Locked); cancels the request. */
  onBack(): void;
  /** The account's time zone (`VaultProfile.timezone`), for the expiry. */
  timeZone: string;
}

type View =
  | { step: "starting" }
  | { step: "waiting"; request: PairNewDeviceRequest; number: string | null }
  | { step: "done" }
  | { step: "failed"; problem: PairingProblem };

/**
 * A new browser opens the data from a device that has it: shows a QR and the 8-character code
 * (two groups of four), how long it works, then the number to compare once the other device
 * answered. The other device approves; this one only waits.
 */
export function PairNewDevice({ start, onBack, timeZone }: PairNewDeviceProps) {
  const t = useTranslations("vault.pair");
  const { locale } = useLocale();
  const [view, setView] = useState<View>({ step: "starting" });
  const [attempt, setAttempt] = useState(0);
  const errorId = useId();
  const startRef = useRef(start);
  startRef.current = start;

  useEffect(() => {
    // `attempt` starts a new request ("Start again"); each one is cancelled when it is left.
    void attempt;
    let alive = true;
    let request: PairNewDeviceRequest | null = null;
    const fail = (error: unknown) => {
      if (!alive) return;
      const problem = pairingProblem(error);
      if (problem && problem !== "bad_code") setView({ step: "failed", problem });
    };
    setView({ step: "starting" });
    startRef.current().then((started) => {
      if (!alive) {
        started.cancel();
        return;
      }
      request = started;
      setView({ step: "waiting", request: started, number: null });
      started.number().then((number) => {
        if (alive) setView({ step: "waiting", request: started, number });
      }, fail);
      started.finish().then(() => {
        if (alive) setView({ step: "done" });
      }, fail);
    }, fail);
    return () => {
      alive = false;
      request?.cancel();
    };
  }, [attempt]);

  const restart = () => setAttempt((n) => n + 1);

  if (view.step === "failed") {
    const { problem } = view;
    return (
      <SignInScreen mood="worried">
        <ScreenTitle>{t(problem === "expired" ? "expired_title" : "failed_title")}</ScreenTitle>
        {problem === "expired" ? (
          <p className="text-center text-ink-muted">{t("expired_lead")}</p>
        ) : (
          <FieldError id={errorId}>{t(problem)}</FieldError>
        )}
        {problem !== "tampered" && (
          <PressButton className="w-full" onClick={restart}>
            {t("restart")}
          </PressButton>
        )}
        <PressButton
          variant={problem === "tampered" ? "primary" : "ghost"}
          className="w-full"
          onClick={onBack}
        >
          {t("back")}
        </PressButton>
      </SignInScreen>
    );
  }

  return (
    <SignInScreen>
      <ScreenTitle>{t("title")}</ScreenTitle>
      {view.step === "starting" && (
        <p className="text-center text-ink-muted" aria-busy="true">
          {t("starting")}
        </p>
      )}
      {view.step === "done" && (
        <p className="text-center text-ink" role="status">
          {t("done")}
        </p>
      )}
      {view.step === "waiting" && view.number === null && (
        <>
          <p className="text-center text-ink-muted">{t("lead")}</p>
          <img
            src={`data:image/svg+xml,${encodeURIComponent(renderSVG(view.request.qr))}`}
            alt={view.request.code}
            width={208}
            height={208}
            className="rounded-(--radius-md) bg-white p-(--space-2)"
          />
          <div className="flex flex-col items-center gap-(--space-1)">
            <span className="text-sm text-ink-muted">{t("code_label")}</span>
            <p
              translate="no"
              className="m-0 font-mono text-[28px] font-bold tracking-[0.12em] text-ink"
            >
              {`${view.request.code.slice(0, 4)} ${view.request.code.slice(4)}`}
            </p>
          </div>
          <p className="text-center text-[14px] text-ink-muted">
            {t("expires", {
              time: formatTime(view.request.expiresAt, locale, timeZone),
            })}
          </p>
          <p className="text-center text-ink-muted" role="status">
            {t("waiting")}
          </p>
        </>
      )}
      {view.step === "waiting" && view.number !== null && (
        <>
          <h2 className="m-0 text-center text-[18px] font-bold text-ink">{t("number_title")}</h2>
          <PairingNumber value={view.number} />
          <p className="text-center text-ink-muted">{t("number_lead")}</p>
        </>
      )}
      {view.step !== "done" && (
        <PressButton variant="ghost" className="w-full" onClick={onBack}>
          {t("back")}
        </PressButton>
      )}
    </SignInScreen>
  );
}
