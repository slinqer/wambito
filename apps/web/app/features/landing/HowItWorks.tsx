import { type CSSProperties, type ReactNode, useEffect, useState } from "react";
import { useTranslations } from "use-intl";
import { LANDING_ART, Wambi } from "../../wambi/Wambi.tsx";
import { useDemoMoney } from "./demo-money.ts";
import { useReplayOnView } from "./play-on-view.ts";

/** Sample figures for the illustrations, in euro cents (`useDemoMoney` shows them in the language's demo currency). */
const DEMO = {
  groceries: { remaining: 4633, filled: "62%" },
  goingOut: { remaining: 800, filled: "91%" },
  importedRows: 1248,
  recurring: [
    { key: "rent", emoji: "🏠", cents: -65000, days: 3 },
    { key: "streaming", emoji: "🎬", cents: -1299, days: 9 },
    { key: "gym", emoji: "🏋️", cents: -3500, days: 16 },
  ],
  // An expense as the phone shows it, and the same record as the server keeps it: noise.
  coffee: { emoji: "☕", cents: -450, sealed: "x9Fq·2LmK·v0Zt·R7cA" },
  code: "482 913",
} as const;

/** How long the imported count takes to run from 0 to its total, in ms. */
const COUNT_MS = 1600;

/** How often a card on screen plays its illustration again, in ms. */
const REPLAY_MS = 6000;

/**
 * "1248 transactions ready". With `play` (each time its card plays, a fresh one) it counts up from
 * 0, then a check pops to confirm. Without it (before the card plays, without JavaScript, under
 * reduced motion) it shows the final count, confirmed. No motion library: this is the landing.
 */
function ImportedCount({ total, play, pace }: { total: number; play: boolean; pace: number }) {
  const t = useTranslations("landing.how");
  const [shown, setShown] = useState(play ? 0 : total);
  const [counting, setCounting] = useState(play);

  useEffect(() => {
    if (!play) return;
    let frame = 0;
    const start = performance.now();
    const tick = (now: number) => {
      const progress = Math.min(1, (now - start) / (COUNT_MS * pace));
      // Ease out: fast at first, settling on the total.
      setShown(Math.round(total * (1 - (1 - progress) ** 3)));
      if (progress < 1) {
        frame = requestAnimationFrame(tick);
        return;
      }
      setCounting(false);
    };
    frame = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(frame);
  }, [play, pace, total]);

  return (
    <span
      className="lk-landing-imported"
      data-state={counting ? "counting" : "done"}
      data-counted={play ? "" : undefined}
    >
      {t("import.demo_rows", { count: shown })}
      <span className="lk-landing-imported-check">
        <svg viewBox="0 0 24 24">
          <path d="m5.5 12.5 4 4 9-9" />
        </svg>
      </span>
    </span>
  );
}

/** His celebration, held on frame 4 (jumping, fists up): on the landing he reacts to nothing. */
const STILL_CELEBRATE = { ...LANDING_ART.celebrate, play: false };

/**
 * A card: its name, one line and the illustration, which plays by itself
 * once the card is on screen and again every few seconds while it stays (`useReplayOnView`):
 * `data-play` carries the round, which CSS animates, and the illustration is remounted each round
 * so its animations start over. Before it plays it is the still, final picture.
 */
function Feature({
  demo,
  title,
  body,
  pace,
}: {
  demo: (play: boolean) => ReactNode;
  title: string;
  body: string;
  pace: number;
}) {
  const { ref, round } = useReplayOnView<HTMLLIElement>(REPLAY_MS, { pace });
  return (
    <li ref={ref} className="lk-landing-card" data-play={round > 0 ? round : undefined}>
      <h3>{title}</h3>
      <p>{body}</p>
      {/* The illustration repeats what the text says, so it is hidden from assistive technology. */}
      <div key={round} className="lk-landing-demo" aria-hidden="true">
        {demo(round > 0)}
      </div>
    </li>
  );
}

/**
 * What Wambito does, as a grid of six cards (three across on desktop, two on tablets, one on
 * phones), each with its name, one line and a small illustration built from the app's own pieces
 * that fills the card's foot: where the money goes, budgets that warn you, fixed payments with
 * their due dates, end-to-end encryption (an expense on the phone, noise on the server), importing your history (Budge today) and signing in without a password, under a big title with Wambi jumping for joy at its end. Automatic capture has
 * its own section above (`AutomaticCapture.tsx`). `pace` scales the timing (stories only).
 */
export function HowItWorks({ pace = 1 }: { pace?: number }) {
  const t = useTranslations("landing.how");
  const money = useDemoMoney();
  const dot = (color: string) => ({ "--dot": color }) as CSSProperties;

  return (
    <section id="how" className="lk-landing-section" aria-labelledby="how-title">
      <div className="lk-landing-section-head is-center">
        <h2 id="how-title">
          {t("title")}
          {/* Wambi jumping for joy after the title: a still frame, decorative. */}
          <span
            className="lk-landing-title-wambi"
            data-wambi-spot="how"
            data-wambi-pose="celebrate"
            aria-hidden="true"
          >
            <Wambi mood="celebrating" size="100%" decorative art={STILL_CELEBRATE} />
          </span>
        </h2>
      </div>
      <ul className="lk-landing-cards is-how">
        <Feature
          pace={pace}
          title={t("spend.title")}
          body={t("spend.body")}
          demo={() => (
            <div className="lk-landing-demo-row">
              <span className="lk-landing-donut" />
              <div className="grid gap-(--space-2)">
                <span className="lk-overline">{t("spend.demo_label")}</span>
                <ul className="lk-landing-legend">
                  <li style={dot("var(--candy)")}>{t("demo_categories.groceries")}</li>
                  <li style={dot("var(--brand-glow)")}>{t("demo_categories.home")}</li>
                  <li style={dot("var(--near)")}>{t("demo_categories.going_out")}</li>
                  <li style={dot("var(--good)")}>{t("demo_categories.transport")}</li>
                </ul>
              </div>
            </div>
          )}
        />
        <Feature
          pace={pace}
          title={t("budgets.title")}
          body={t("budgets.body")}
          demo={() => (
            <>
              <div className="lk-landing-budget">
                <div className="lk-rowtop">
                  <span>{t("demo_categories.groceries")}</span>
                  <span className="lk-status">
                    {t("budgets.demo_remaining", { amount: money(DEMO.groceries.remaining) })}
                  </span>
                </div>
                <div className="lk-bar">
                  <span style={{ width: DEMO.groceries.filled }} />
                </div>
              </div>
              <div className="lk-landing-budget">
                <div className="lk-rowtop">
                  <span>{t("demo_categories.going_out")}</span>
                  <span className="lk-status is-near">
                    {t("budgets.demo_remaining", { amount: money(DEMO.goingOut.remaining) })}
                  </span>
                </div>
                <div className="lk-bar is-near">
                  <span style={{ width: DEMO.goingOut.filled }} />
                </div>
              </div>
            </>
          )}
        />
        <Feature
          pace={pace}
          title={t("recurring.title")}
          body={t("recurring.body")}
          demo={() => (
            <ul className="lk-landing-bills">
              {DEMO.recurring.map((bill) => (
                <li key={bill.key} className="lk-landing-demo-row">
                  <span className="lk-tile">{bill.emoji}</span>
                  <span className="lk-landing-bill-name">
                    {t(`recurring.demo.${bill.key}`)}
                    <span className="lk-landing-bill-due">
                      {t("recurring.demo_due", { days: bill.days })}
                    </span>
                  </span>
                  <span className="lk-amount">{money(bill.cents)}</span>
                </li>
              ))}
            </ul>
          )}
        />
        <Feature
          pace={pace}
          title={t("encryption.title")}
          body={t("encryption.body")}
          demo={() => (
            <div className="lk-landing-vault">
              <div className="lk-landing-demo-row lk-landing-vault-plain">
                <span className="lk-tile">{DEMO.coffee.emoji}</span>
                <span className="lk-landing-bill-name">
                  {t("encryption.demo_item")}
                  <span className="lk-landing-vault-where">{t("encryption.demo_device")}</span>
                </span>
                <span className="lk-amount">{money(DEMO.coffee.cents)}</span>
              </div>
              <span className="lk-landing-lock">
                <svg viewBox="0 0 24 24">
                  <rect x="5" y="10.5" width="14" height="10" rx="2.5" />
                  <path d="M8.5 10.5V8a3.5 3.5 0 0 1 7 0v2.5" />
                </svg>
              </span>
              <div className="lk-landing-sealed">
                <span className="lk-landing-sealed-text">{DEMO.coffee.sealed}</span>
                <span className="lk-landing-vault-where">{t("encryption.demo_server")}</span>
              </div>
            </div>
          )}
        />
        <Feature
          pace={pace}
          title={t("import.title")}
          body={t("import.body")}
          demo={(play) => (
            <div className="lk-landing-demo-row flex-wrap">
              <span className="lk-landing-file">{t("import.demo_file")}</span>
              <svg className="lk-landing-arrow" viewBox="0 0 24 24">
                <path d="M4 12h15M13 6l6 6-6 6" />
              </svg>
              <ImportedCount total={DEMO.importedRows} play={play} pace={pace} />
            </div>
          )}
        />
        <Feature
          pace={pace}
          title={t("passwords.title")}
          body={t("passwords.body")}
          demo={() => (
            <div className="lk-landing-demo-row lk-landing-signin">
              <span className="lk-landing-fingerprint">
                <svg viewBox="0 0 24 24">
                  <path d="M6.5 18.5c1-1.6 1.5-3.6 1.5-6.5a4 4 0 0 1 8 0c0 2 0 4-.6 6" />
                  <path d="M12 12c0 3.5-.6 6.4-2 8.5M4.6 15.5c.3-1.1.4-2.3.4-3.5a7 7 0 0 1 12.2-4.7" />
                  <path d="M19 11c.2 2.6 0 5.2-.8 7.5" />
                </svg>
              </span>
              <span className="lk-landing-or">{t("passwords.demo_or")}</span>
              <span className="lk-landing-code">{DEMO.code}</span>
            </div>
          )}
        />
      </ul>
    </section>
  );
}
