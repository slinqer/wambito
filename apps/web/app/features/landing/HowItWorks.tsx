import { type ReactNode, useEffect, useState } from "react";
import { useTranslations } from "use-intl";
import { useLocale } from "../../i18n/IntlProvider.tsx";
import { DONUT_ON_SCREEN } from "./app-screen.gen.ts";
import { useDemoMoney } from "./demo-money.ts";
import { useReplayOnView } from "./play-on-view.ts";

/** Sample figures for the illustrations, in euro cents (`useDemoMoney` shows them in the language's demo currency). */
const DEMO = {
  importedRows: 1248,
  // Subscriptions: name (a brand, the same in every language), its mark in public/landing/logos/.
  subscriptions: [
    { name: "Netflix", logo: "netflix.svg", cents: -1299, days: 3 },
    { name: "Spotify", logo: "spotify.svg", cents: -1199, days: 9 },
    { name: "YouTube Premium", logo: "youtube.svg", cents: -1399, days: 16 },
  ],
  // An expense as the phone shows it, and the same record as the server keeps it: noise.
  coffee: { emoji: "☕", cents: -450, sealed: "x9Fq·2LmK·v0Zt·R7cA" },
} as const;

/** How long the imported count takes to run from 0 to its total, in ms. */
const COUNT_MS = 1600;

/** How long the count waits, hidden, while the file is pushed and the arrow points, in ms. */
const COUNT_WAIT_MS = 1100;

/** How often a card on screen plays its illustration again, in ms. */
const REPLAY_MS = 6000;

/**
 * "1248 transactions ready". With `play` (each time its card plays, a fresh one) it waits, hidden,
 * while the file is pushed and the arrow points (`waiting`), pops in and counts up from 0, then a
 * check pops to confirm. Without it (before the card plays, without JavaScript, under
 * reduced motion) it shows the final count, confirmed. No motion library: this is the landing.
 */
function ImportedCount({ total, play, pace }: { total: number; play: boolean; pace: number }) {
  const t = useTranslations("landing.how");
  const [shown, setShown] = useState(play ? 0 : total);
  const [state, setState] = useState<"waiting" | "counting" | "done">(play ? "waiting" : "done");

  useEffect(() => {
    if (!play) return;
    let frame = 0;
    let start = 0;
    const tick = (now: number) => {
      const progress = Math.min(1, (now - start) / (COUNT_MS * pace));
      // Ease out: fast at first, settling on the total.
      setShown(Math.round(total * (1 - (1 - progress) ** 3)));
      if (progress < 1) {
        frame = requestAnimationFrame(tick);
        return;
      }
      setState("done");
    };
    const wait = window.setTimeout(() => {
      setState("counting");
      start = performance.now();
      frame = requestAnimationFrame(tick);
    }, COUNT_WAIT_MS * pace);
    return () => {
      window.clearTimeout(wait);
      cancelAnimationFrame(frame);
    };
  }, [play, pace, total]);

  return (
    <span className="lk-landing-imported" data-state={state} data-counted={play ? "" : undefined}>
      {t("import.demo_rows", { count: shown })}
      <span className="lk-landing-imported-check">
        <svg viewBox="0 0 24 24">
          <path d="m5.5 12.5 4 4 9-9" />
        </svg>
      </span>
    </span>
  );
}

/**
 * The apps a history comes from, `logo` being the mark in public/landing/logos/: all marked as
 * coming soon, since encrypted accounts cannot import yet (a later stage brings Budge back first,
 * then the others). Brand names stay as they are in every language;
 * the marks stay their owners' trademarks and only say where a file comes from.
 */
const SOURCES = [
  { name: "Budge", logo: "budge.png", soon: true },
  { name: "Buddy", logo: "buddy.png", soon: true },
  { name: "Excel", logo: "microsoft-excel.svg", soon: true },
  { name: "Sheets", logo: "google-sheets.svg", soon: true },
] as const;

/** The apps in a row, each with its mark; the ones still to come carry the "Soon" tag. */
function Sources({ soon }: { soon: string }) {
  return (
    <ul className="lk-landing-sources">
      {SOURCES.map((source) => (
        <li key={source.name} className={source.soon ? "is-soon" : undefined}>
          <img src={`/landing/logos/${source.logo}`} alt="" width={18} height={18} />
          {source.name}
          {source.soon && <span className="lk-landing-soon">{soon}</span>}
        </li>
      ))}
    </ul>
  );
}

/**
 * A real app screen in a phone (the demo, made-up data, rendered by
 * `pnpm --filter @wambito/web landing-screens`), in the page's language: the screen without what
 * moves, and what moves laid over it, which CSS animates as the app does each time the card plays.
 * - `insights`: the "By category" card; the donut's ring (at `DONUT_ON_SCREEN`) sweeps in.
 * - `budgets`: home's Categories tab; the bars' fills (over the whole screen) grow from the left.
 * Both themes are here and CSS shows the one in use; lazy, so the hidden ones are never fetched.
 * Decorative: the card's text says what it shows.
 */
function AppScreen({ screen, locale }: { screen: "insights" | "budgets"; locale: string }) {
  return (
    <div className="lk-landing-phone">
      {(["night", "day"] as const).map((theme) => (
        <div key={theme} className={`lk-landing-screen is-${theme}`}>
          <img
            className="lk-landing-screen-shot"
            src={`/landing/${screen}-${locale}-${theme}.webp`}
            alt=""
            width={390}
            height={844}
            loading="lazy"
            decoding="async"
          />
          {screen === "insights" ? (
            <img
              className="lk-landing-screen-ring"
              src={`/landing/donut-${locale}-${theme}.webp`}
              alt=""
              width={200}
              height={200}
              loading="lazy"
              decoding="async"
              style={DONUT_ON_SCREEN}
            />
          ) : (
            <img
              className="lk-landing-screen-bars"
              src={`/landing/budget-bars-${locale}-${theme}.webp`}
              alt=""
              width={390}
              height={844}
              loading="lazy"
              decoding="async"
            />
          )}
        </div>
      ))}
    </div>
  );
}

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
 * What Wambito does, as a grid of five cards (three then two, centred, on desktop; two on tablets,
 * the last centred; one on phones), each with its name, one line and a small illustration that fills the card's foot:
 * importing your history first (the apps it comes from, all coming soon, all pointing down to the transactions ready; where people start), then where the money goes and
 * budgets that warn you (the app's real screens, in phones), subscriptions with their due dates and what they cost a month,
 * end-to-end encryption (an expense on the phone, noise on the server), under a big title (signing in without a password is in the FAQ). Automatic capture has
 * its own section above (`AutomaticCapture.tsx`). `pace` scales the timing (stories only).
 */
export function HowItWorks({ pace = 1 }: { pace?: number }) {
  const t = useTranslations("landing.how");
  const { locale } = useLocale();
  const money = useDemoMoney();

  return (
    <section id="how" className="lk-landing-section" aria-labelledby="how-title">
      <div className="lk-landing-section-head is-center">
        <h2 id="how-title">{t("title")}</h2>
      </div>
      <ul className="lk-landing-cards is-how">
        <Feature
          pace={pace}
          title={t("import.title")}
          body={t("import.body")}
          demo={(play) => (
            <div className="lk-landing-demo-row lk-landing-import">
              <Sources soon={t("import.soon")} />
              <svg className="lk-landing-arrow" viewBox="0 0 24 24">
                <path d="M4 12h15M13 6l6 6-6 6" />
              </svg>
              <ImportedCount total={DEMO.importedRows} play={play} pace={pace} />
            </div>
          )}
        />
        <Feature
          pace={pace}
          title={t("spend.title")}
          body={t("spend.body")}
          demo={() => <AppScreen screen="insights" locale={locale} />}
        />
        <Feature
          pace={pace}
          title={t("budgets.title")}
          body={t("budgets.body")}
          demo={() => <AppScreen screen="budgets" locale={locale} />}
        />
        <Feature
          pace={pace}
          title={t("subscriptions.title")}
          body={t("subscriptions.body")}
          demo={() => (
            <div className="lk-landing-subs">
              <div className="lk-landing-subs-total">
                <span>{t("subscriptions.demo_label")}</span>
                <strong>
                  {t("subscriptions.demo_total", {
                    amount: money(-DEMO.subscriptions.reduce((total, sub) => total + sub.cents, 0)),
                  })}
                </strong>
              </div>
              <ul className="lk-landing-bills">
                {DEMO.subscriptions.map((sub) => (
                  <li key={sub.name} className="lk-landing-demo-row">
                    <span className="lk-tile lk-landing-sub-logo">
                      <img src={`/landing/logos/${sub.logo}`} alt="" width={20} height={20} />
                    </span>
                    <span className="lk-landing-bill-name">
                      {sub.name}
                      <span className="lk-landing-bill-due">
                        {t("subscriptions.demo_due", { days: sub.days })}
                      </span>
                    </span>
                    <span className="lk-amount">{money(sub.cents)}</span>
                  </li>
                ))}
              </ul>
            </div>
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
      </ul>
    </section>
  );
}
