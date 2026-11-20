import { type RefObject, useEffect, useRef } from "react";
import { useTranslations } from "use-intl";
import { PressButton } from "../../ui/PressButton.tsx";
import type { ConsentChoice } from "./consent.ts";
import type { AnalyticsConsent } from "./use-analytics-consent.ts";

/**
 * The cookie banner: a card fixed at the bottom of the page, not a modal (no focus trap, the page
 * stays usable). It asks with two equal buttons, decline first; opened again from the footer it
 * also says the current choice; with GPC/DNT on it is only a note with "Close". Nothing renders
 * before the hook is `ready`, so the prerendered HTML has no banner. Opened from the footer it
 * takes the focus, and gives it back to `returnFocus` when it closes.
 */
export function ConsentBanner({
  consent,
  returnFocus,
}: {
  consent: AnalyticsConsent;
  returnFocus?: RefObject<HTMLElement | null>;
}) {
  const t = useTranslations("landing.consent");
  const box = useRef<HTMLElement>(null);
  const asked = consent.state !== "ask" || consent.browserSaysNo;
  const shown = consent.ready && consent.open;

  // Opened on request (not the first visit's question): move the focus into it.
  useEffect(() => {
    if (shown && asked) box.current?.focus();
  }, [shown, asked]);

  // While open, it reserves what it covers at the bottom of the viewport (`--lk-consent-h` on
  // `<html>`), so the footer can scroll clear of it and a focused link is never hidden behind it
  // (WCAG 2.2 SC 2.4.11). The reserve goes when it closes or unmounts.
  useEffect(() => {
    const el = box.current;
    if (!shown || !el) return;
    const root = document.documentElement;
    const measure = () => {
      const covered = Math.max(0, Math.ceil(window.innerHeight - el.getBoundingClientRect().top));
      root.style.setProperty("--lk-consent-h", `${covered}px`);
    };
    measure();
    const observer = typeof ResizeObserver === "undefined" ? null : new ResizeObserver(measure);
    observer?.observe(el);
    window.addEventListener("resize", measure);
    return () => {
      observer?.disconnect();
      window.removeEventListener("resize", measure);
      root.style.removeProperty("--lk-consent-h");
    };
  }, [shown]);

  if (!shown) return null;

  const done = (act: () => void) => () => {
    const hadFocus = box.current?.contains(document.activeElement) ?? false;
    act();
    if (hadFocus) returnFocus?.current?.focus();
  };
  const choose = (choice: ConsentChoice) => done(() => consent.choose(choice));

  return (
    <section ref={box} className="lk-consent" aria-label={t("label")} tabIndex={-1}>
      {consent.browserSaysNo ? (
        <>
          <p className="lk-consent-text">{t("browser_no")}</p>
          <div className="lk-consent-actions">
            <PressButton variant="secondary" onClick={done(consent.close)}>
              {t("close")}
            </PressButton>
          </div>
        </>
      ) : (
        <>
          <div className="lk-consent-text">
            <h2 className="lk-consent-title">{t("title")}</h2>
            <p>{t("body")}</p>
            {consent.state !== "ask" && (
              <p className="lk-consent-current">
                {t(consent.state === "granted" ? "current_granted" : "current_denied")}
              </p>
            )}
          </div>
          <div className="lk-consent-actions">
            <PressButton variant="secondary" onClick={choose("denied")}>
              {t("decline")}
            </PressButton>
            <PressButton variant="primary" onClick={choose("granted")}>
              {t("accept")}
            </PressButton>
          </div>
        </>
      )}
    </section>
  );
}
