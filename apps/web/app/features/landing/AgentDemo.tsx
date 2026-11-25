import type { CSSProperties, ReactNode } from "react";
import { useTranslations } from "use-intl";
import { formatMoney } from "../../i18n/format.ts";
import { useLocale } from "../../i18n/IntlProvider.tsx";
import { COMING_SOON } from "../../site/config.ts";
import { BrandLogo, type BrandName } from "../../ui/BrandLogo.tsx";
import { cx } from "../../ui/cx.ts";
import { Icon } from "../../ui/Icon.tsx";
import { BRAND_LOGOS, type BrandLogoName } from "./brand-logos.ts";
import { DownloadLink } from "./DownloadLink.tsx";
import { DEMO_CURRENCY, demoCents, useDemoMoney } from "./demo-money.ts";
import { useRotatingPlay } from "./play-on-view.ts";

/**
 * Invented figures and names for the three examples, November 2026, in euro cents (`useDemoMoney` shows
 * them in the language's demo currency).
 */
const UBER = {
  total: 8640,
  more: 1210,
  count: 7,
  // Newest first.
  trips: [
    { day: 14, cents: 1290 },
    { day: 11, cents: 980 },
    { day: 6, cents: 1520 },
  ],
} as const;
/** What it finds in the email and adds as recurring payments, by the day each one is charged. */
const SUBSCRIPTIONS: readonly {
  name: string;
  logo: BrandLogoName;
  /** The brand's colour, the tile under its white mark. */
  color: string;
  day: number;
  cents: number;
}[] = [
  { name: "Netflix", logo: "netflix", color: "#e50914", day: 3, cents: 1299 },
  { name: "Spotify", logo: "spotify", color: "#1db954", day: 9, cents: 1099 },
  { name: "YouTube Premium", logo: "youtube", color: "#ff0000", day: 15, cents: 1199 },
  { name: "iCloud+", logo: "icloud", color: "#3693f3", day: 22, cents: 399 },
];
const TOP = {
  // Largest first; the chart's columns are sized against the first one.
  rows: [
    { key: "groceries", cents: 41200 },
    { key: "restaurants", cents: 17000 },
    { key: "transport", cents: 9600 },
    { key: "leisure", cents: 6000 },
  ],
} as const;
const DEMO_MONTH = { year: 2026, month: 10 } as const;

/** The examples, in the order they take turns. */
const EXAMPLES = ["uber", "subscriptions", "top"] as const;
type Example = (typeof EXAMPLES)[number];

/**
 * Each example's steps, ms after it starts: the question pops in, the agent reads (the transactions,
 * or the email),
 * then the answer, which stays `HOLD` ms before the next question. `idle` is empty; `done` is the
 * first example's still final state, which the page prerenders and keeps without JavaScript and
 * under reduced motion.
 */
const STEPS = [
  ["ask", 0],
  ["think", 900],
  ["answer", 2600],
] as const;
const HOLD = 6500;
type Phase = (typeof STEPS)[number][0] | "idle" | "done";
const ORDER: Phase[] = ["idle", "ask", "think", "answer", "done"];

/** The four agents "Mis agentes" connects, with the app's own logos (`brands.json`). */
const AGENT_LOGOS: readonly BrandName[] = ["claude", "chatgpt", "lumo", "grok"];

function useFormat() {
  const { locale } = useLocale();
  const money = useDemoMoney();
  const percent = (share: number) =>
    new Intl.NumberFormat(locale, { style: "percent", maximumFractionDigits: 0 }).format(share);
  const date = new Intl.DateTimeFormat(locale, { day: "numeric", month: "short", timeZone: "UTC" });
  const day = (n: number) => date.format(new Date(Date.UTC(DEMO_MONTH.year, DEMO_MONTH.month, n)));
  return { money, percent, day };
}

const bold = (chunks: ReactNode) => <b>{chunks}</b>;

/** "How much did I spend on Uber?": the total, the rides, and the latest three. */
function UberAnswer() {
  const t = useTranslations("landing.agent.demo.uber");
  const { money, day } = useFormat();
  return (
    <>
      <p>
        {t.rich("answer", {
          b: bold,
          amount: money(UBER.total),
          count: UBER.count,
          more: money(UBER.more),
        })}
      </p>
      <ul className="lk-landing-chat-card">
        {UBER.trips.map((trip) => (
          <li key={trip.day} className="lk-landing-demo-row">
            <span className="lk-tile">🚗</span>
            <span className="lk-landing-bill-name">
              Uber
              <span className="lk-landing-chat-date">{day(trip.day)}</span>
            </span>
            <span className="lk-amount">{money(-trip.cents)}</span>
          </li>
        ))}
      </ul>
    </>
  );
}

/**
 * "Read my emails and add the subscriptions I pay for": what it found, each one added as a
 * recurring payment on the day it is charged, and what they cost a month together.
 */
function SubscriptionsAnswer() {
  const t = useTranslations("landing.agent.demo.subscriptions");
  const { money } = useFormat();
  const { locale } = useLocale();
  // The sum of the amounts as shown (pesos round each one), so the rows add up to it.
  const total = formatMoney(
    SUBSCRIPTIONS.reduce((sum, row) => sum + demoCents(locale, row.cents), 0),
    DEMO_CURRENCY[locale].currency,
    locale,
  );
  return (
    <>
      <p>{t.rich("answer", { b: bold, count: SUBSCRIPTIONS.length, total })}</p>
      <ul className="lk-landing-chat-card">
        {SUBSCRIPTIONS.map((row) => (
          <li key={row.name} className="lk-landing-demo-row">
            <span className="lk-tile lk-landing-brand-tile" style={{ background: row.color }}>
              <svg viewBox="0 0 24 24" data-logo={row.logo} aria-hidden="true">
                <path d={BRAND_LOGOS[row.logo]} />
              </svg>
            </span>
            <span className="lk-landing-bill-name">
              {row.name}
              <span className="lk-landing-chat-date">{t("every", { day: row.day })}</span>
            </span>
            <span className="lk-landing-added">
              <span className="lk-amount">{money(-row.cents)}</span>
              <span className="lk-landing-added-tag">✓ {t("added")}</span>
            </span>
          </li>
        ))}
      </ul>
    </>
  );
}

/** "Where did most of my money go?": a column per category, the largest first, and a summary. */
function TopAnswer() {
  const t = useTranslations("landing.agent.demo");
  const { money, percent } = useFormat();
  const [first] = TOP.rows;
  const total = TOP.rows.reduce((sum, row) => sum + row.cents, 0);
  return (
    <>
      <p>
        {t.rich("top.answer", {
          b: bold,
          amount: money(first.cents),
          percent: percent(first.cents / total),
        })}
      </p>
      <ul className="lk-landing-chat-card lk-landing-columns">
        {TOP.rows.map((row) => (
          <li key={row.key} style={{ "--lk-col": row.cents / first.cents } as CSSProperties}>
            <span className="lk-landing-column-amount">{money(row.cents)}</span>
            <span className="lk-landing-column" />
            <span className="lk-landing-column-label">{t(`categories.${row.key}`)}</span>
          </li>
        ))}
      </ul>
    </>
  );
}

const ANSWERS: Record<Example, () => ReactNode> = {
  uber: UberAnswer,
  subscriptions: SubscriptionsAnswer,
  top: TopAnswer,
};

/**
 * "Your agent analyzes your spending": on one side the heading, a line, the way in ("Conecta
 * tu agente" leads to the downloads: the app, where "Mis agentes" connects Claude, ChatGPT, Lumo or Grok) and their logos; on the other
 * a chat that plays three examples in turn while it is on screen (`useRotatingPlay`): how much
 * went on Uber this month, the subscriptions it finds in your email and adds as recurring
 * payments (with the agent's own email access), and where most of the money went (a column chart). The dots under it say which one is showing. The chat is an
 * illustration (hidden from assistive technology): the heading and the line say what it shows.
 * `pace` scales the timing (stories only).
 */
export function AgentDemo({ pace = 1 }: { pace?: number }) {
  const t = useTranslations("landing.agent");
  const { locale } = useLocale();
  const { ref, index, phase, go } = useRotatingPlay(EXAMPLES.length, STEPS, HOLD, { pace });
  const example = EXAMPLES[index] ?? "uber";
  const Answer = ANSWERS[example];
  const shown = (from: Phase) => ORDER.indexOf(phase) >= ORDER.indexOf(from);
  // Reading the email says so; the others read the transactions.
  const reads = example === "subscriptions";
  const thinking = reads ? "demo.subscriptions.thinking" : "demo.thinking";
  const used = reads ? "demo.subscriptions.used" : "demo.used";

  return (
    <section id="agent" className="lk-landing-section" aria-labelledby="agent-title">
      <div className="lk-landing-split">
        <div className="lk-landing-split-text">
          <h2 id="agent-title">{t("title")}</h2>
          <p>{t("body")}</p>
          {!COMING_SOON && (
            <div className="lk-landing-agent-cta">
              <DownloadLink variant="secondary" size="sm">
                {t("cta")}
              </DownloadLink>
              <span className="lk-landing-agent-note">{t("note")}</span>
            </div>
          )}
          <div className="lk-landing-agent-logos">
            {AGENT_LOGOS.map((name) => (
              <BrandLogo key={name} name={name} size={34} className="lk-landing-agent-logo" />
            ))}
          </div>
        </div>
        <div
          ref={ref}
          className="lk-landing-panel lk-landing-chat"
          data-phase={phase}
          data-example={example}
        >
          <div className="lk-landing-chat-log" aria-hidden="true">
            {shown("ask") && (
              <p className="lk-landing-chat-ask">
                {t.rich(`demo.${example}.question`, { b: bold })}
              </p>
            )}
            {phase === "think" && (
              <p className="lk-landing-chat-status">
                <img src="/favicon.svg" alt="" width={20} height={20} />
                <span className="lk-landing-shimmer">{t(thinking)}</span>
              </p>
            )}
            {shown("answer") && (
              // `data-ph-mask`: session replays hide the answer's amounts (PostHog's
              // `maskTextSelector`); invented figures, but money is never recorded.
              <div className="lk-landing-chat-answer" data-ph-mask>
                <p className="lk-landing-chat-status is-done">
                  <img src="/favicon.svg" alt="" width={20} height={20} />
                  {t(used)}
                </p>
                <Answer />
              </div>
            )}
          </div>
          <div className="lk-landing-chat-nav">
            <button
              type="button"
              className="lk-landing-chat-arrow"
              aria-label={t("demo.previous")}
              onClick={() => go(index - 1)}
            >
              <Icon name="chevron-left" size={18} />
            </button>
            <span className="lk-landing-chat-dots" aria-hidden="true">
              {EXAMPLES.map((name) => (
                <span key={name} className={cx(name === example && "is-on")} />
              ))}
            </span>
            <button
              type="button"
              className="lk-landing-chat-arrow"
              aria-label={t("demo.next")}
              onClick={() => go(index + 1)}
            >
              <Icon name="chevron-right" size={18} />
            </button>
          </div>
        </div>
      </div>
    </section>
  );
}
