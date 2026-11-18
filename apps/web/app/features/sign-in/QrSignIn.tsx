import { useEffect, useId, useRef, useSyncExternalStore } from "react";
import { renderSVG } from "uqr";
import { useTranslations } from "use-intl";
import { useLocale } from "../../i18n/IntlProvider.tsx";
import { PressButton } from "../../ui/PressButton.tsx";
import { formatTime } from "../vault/PairNewDevice.tsx";
import { FieldError } from "./SignInScreen.tsx";
import type { QrSignin } from "./signin-model.ts";

export interface QrSignInProps {
  /** `createQrSignin(...)`; the page makes it while the panel is on screen and stops it after. */
  model: QrSignin;
  /** `finish()` resolved: this browser holds the keys and the session; the page navigates. */
  onSignedIn(userId: string): void;
  /** The browser's time zone, for the time a `too_many` retries at. */
  timeZone: string;
}

const QR_PX = 208;

/**
 * The QR panel of `/sign-in` (web plan rulings 8–10): a QR and the 8-character code for the
 * phone, "Keep me signed in on this browser" (ticked; locked once a number is shown), the quiet
 * number line once the phone answered, "Opening your data…" while finishing, and the failures.
 */
export function QrSignIn({ model, onSignedIn, timeZone }: QrSignInProps) {
  const t = useTranslations("sign_in.qr");
  const { locale } = useLocale();
  const state = useSyncExternalStore(model.subscribe, model.state, model.state);
  const remember = useSyncExternalStore(model.subscribe, model.remember, model.remember);
  const titleId = useId();
  const boxNoteId = useId();
  const errorId = useId();
  const signedIn = useRef<string | null>(null);
  const onSignedInRef = useRef(onSignedIn);
  onSignedInRef.current = onSignedIn;

  useEffect(() => {
    if (state.status === "done" && signedIn.current !== state.userId) {
      signedIn.current = state.userId;
      onSignedInRef.current(state.userId);
    }
  }, [state]);

  const request = state.status === "showing" || state.status === "approved" ? state.request : null;
  const locked =
    state.status === "approved" || state.status === "finishing" || state.status === "done";
  const expired =
    state.status === "paused" || (state.status === "failed" && state.code === "expired");

  return (
    <section
      aria-labelledby={titleId}
      className="flex w-full flex-col items-center gap-(--space-3)"
    >
      <h2 id={titleId} className="m-0 text-center text-[20px] font-bold text-ink">
        {t("title")}
      </h2>

      {state.status === "opening" && (
        <div
          aria-busy="true"
          className="flex items-center justify-center rounded-(--radius-md) border-2 border-stroke text-center text-ink-muted"
          style={{ width: QR_PX, height: QR_PX }}
        >
          {t("opening")}
        </div>
      )}

      {request && (
        <>
          <p className="m-0 text-center text-ink-muted">{t("lead")}</p>
          <img
            src={`data:image/svg+xml,${encodeURIComponent(renderSVG(request.qr))}`}
            alt={request.code}
            width={QR_PX}
            height={QR_PX}
            className="rounded-(--radius-md) bg-white p-(--space-2)"
          />
          <div className="flex flex-col items-center gap-(--space-1)">
            <span className="text-sm text-ink-muted">{t("code_label")}</span>
            <p
              translate="no"
              className="m-0 font-mono text-[28px] font-bold tracking-[0.12em] text-ink"
            >
              {`${request.code.slice(0, 4)} ${request.code.slice(4)}`}
            </p>
          </div>
        </>
      )}

      {state.status === "approved" && (
        <p className="m-0 text-center text-[15px] text-ink-muted" role="status">
          {t("number", { number: `${state.number.slice(0, 3)} ${state.number.slice(3)}` })}
        </p>
      )}

      {(state.status === "finishing" || state.status === "done") && (
        <p className="m-0 text-center text-ink" role="status">
          {t("finishing")}
        </p>
      )}

      {expired && (
        <>
          <p className="m-0 text-center font-bold text-ink">{t("expired_title")}</p>
          <p className="m-0 text-center text-ink-muted">{t("expired_lead")}</p>
          <PressButton className="w-full" onClick={() => model.retry()}>
            {t("retry")}
          </PressButton>
        </>
      )}

      {state.status === "failed" && state.code !== "expired" && (
        <>
          <p className="m-0 text-center font-bold text-ink">{t("failed_title")}</p>
          <FieldError id={errorId}>
            {state.code === "too_many"
              ? t("too_many", {
                  time: formatTime(
                    new Date(state.retryAt ?? Date.now()).toISOString(),
                    locale,
                    timeZone,
                  ),
                })
              : t(
                  state.code === "tampered" ||
                    state.code === "offline" ||
                    state.code === "suspended"
                    ? state.code
                    : "server",
                )}
          </FieldError>
          {state.code !== "too_many" && state.code !== "suspended" && (
            <PressButton className="w-full" onClick={() => model.retry()}>
              {t("retry")}
            </PressButton>
          )}
        </>
      )}

      {state.status !== "finishing" && state.status !== "done" && (
        <div className="flex w-full flex-col gap-(--space-1)">
          <label className="flex min-h-11 items-center gap-(--space-2) text-[15px] font-bold text-ink">
            <input
              type="checkbox"
              className="size-5 accent-brand"
              checked={remember}
              disabled={locked}
              aria-describedby={remember ? undefined : boxNoteId}
              onChange={(event) => model.setRemember(event.target.checked)}
            />
            {t("remember")}
          </label>
          {!remember && (
            <p id={boxNoteId} className="m-0 text-[14px] text-ink-muted">
              {t("remember_off")}
            </p>
          )}
        </div>
      )}
    </section>
  );
}
