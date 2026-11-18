import type { CSSProperties, ReactNode } from "react";
import { useTranslations } from "use-intl";
import { useLocale } from "../../i18n/IntlProvider.tsx";
import { COMING_SOON } from "../../site/config.ts";
import { cx } from "../../ui/cx.ts";
import { PressLink } from "../../ui/PressLink.tsx";
import { BRAND_LOGOS, type BrandLogoName } from "./brand-logos.ts";
import { useDemoMoney } from "./demo-money.ts";
import { appLinkProps } from "./links.ts";
import { NewTabHint } from "./NewTabHint.tsx";
import { useRotatingPlay } from "./play-on-view.ts";

/**
 * Invented figures for the three examples, November 2026, in euro cents (`useDemoMoney` shows
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
const BUDGETS = {
  daysLeft: 14,
  rows: [
    { key: "restaurants", spent: 17000, limit: 20000 },
    { key: "leisure", spent: 6000, limit: 12000 },
    { key: "subscriptions", spent: 3800, limit: 4500 },
  ],
} as const;
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
const EXAMPLES = ["uber", "budgets", "top"] as const;
type Example = (typeof EXAMPLES)[number];

/**
 * Each example's steps, ms after it starts: the question pops in, Wambito reads the transactions,
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

/** A budget is near its limit from 80% spent: its bar and figure turn yellow, as in the app. */
const NEAR = 0.8;

function Logo({ name }: { name: BrandLogoName }) {
  return (
    <svg className="lk-landing-agent-logo" viewBox="0 0 24 24" data-logo={name} aria-hidden="true">
      <path d={BRAND_LOGOS[name]} />
    </svg>
  );
}

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

/** "How are my budgets doing?": a bar per budget filling up to what is spent, and a summary. */
function BudgetsAnswer() {
  const t = useTranslations("landing.agent.demo");
  const { money, percent } = useFormat();
  const [first] = BUDGETS.rows;
  return (
    <>
      <p>
        {t.rich("budgets.answer", {
          b: bold,
          percent: percent(first.spent / first.limit),
          days: BUDGETS.daysLeft,
          left: money(first.limit - first.spent),
        })}
      </p>
      <div className="lk-landing-chat-card">
        {BUDGETS.rows.map((row) => {
          const share = row.spent / row.limit;
          const near = share >= NEAR;
          return (
            <div key={row.key} className="lk-landing-budget">
              <div className="lk-rowtop">
                <span>{t(`categories.${row.key}`)}</span>
                <span className={cx("lk-status", near && "is-near")}>
                  {t("budgets.of", { spent: money(row.spent), limit: money(row.limit) })}
                </span>
              </div>
              <div className={cx("lk-bar", near && "is-near")}>
                <span style={{ width: `${Math.round(share * 100)}%` }} />
              </div>
            </div>
          );
        })}
      </div>
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
  budgets: BudgetsAnswer,
  top: TopAnswer,
};

/**
 * "Your agent analyzes your spending": on one side the heading, a line, the way in (the
 * app, where Settings → Assistants connects Claude or ChatGPT) and the two assistants' logos; on
 * the other a chat that plays three examples in turn while it is on screen (`useRotatingPlay`):
 * how much went on Uber this month, how the budgets are doing (bars filling up), and where most of
 * the money went (a column chart). The dots under it say which one is showing. The chat is an
 * illustration (hidden from assistive technology): the heading and the line say what it shows.
 * `pace` scales the timing (stories only).
 */
export function AgentDemo({ pace = 1 }: { pace?: number }) {
  const t = useTranslations("landing.agent");
  const { locale } = useLocale();
  const app = appLinkProps(locale, "create");
  const { ref, index, phase } = useRotatingPlay(EXAMPLES.length, STEPS, HOLD, { pace });
  const example = EXAMPLES[index] ?? "uber";
  const Answer = ANSWERS[example];
  const shown = (from: Phase) => ORDER.indexOf(phase) >= ORDER.indexOf(from);

  return (
    <section id="agent" className="lk-landing-section" aria-labelledby="agent-title">
      <div className="lk-landing-split">
        <div className="lk-landing-split-text">
          <h2 id="agent-title">{t("title")}</h2>
          <p>{t("body")}</p>
          {!COMING_SOON && (
            <div className="lk-landing-agent-cta">
              <PressLink {...app} variant="secondary" size="sm">
                {t("cta")}
                <NewTabHint target={app.target} />
              </PressLink>
              <span className="lk-landing-agent-note">{t("note")}</span>
            </div>
          )}
          <div className="lk-landing-agent-logos">
            <Logo name="claude" />
            <Logo name="openai" />
          </div>
        </div>
        <div
          ref={ref}
          className="lk-landing-panel lk-landing-chat"
          data-phase={phase}
          data-example={example}
          aria-hidden="true"
        >
          <div className="lk-landing-chat-log">
            {shown("ask") && (
              <p className="lk-landing-chat-ask">
                {t.rich(`demo.${example}.question`, { b: bold })}
              </p>
            )}
            {phase === "think" && (
              <p className="lk-landing-chat-status">
                <img src="/favicon.svg" alt="" width={20} height={20} />
                <span className="lk-landing-shimmer">{t("demo.thinking")}</span>
              </p>
            )}
            {shown("answer") && (
              <div className="lk-landing-chat-answer">
                <p className="lk-landing-chat-status is-done">
                  <img src="/favicon.svg" alt="" width={20} height={20} />
                  {t("demo.used")}
                </p>
                <Answer />
              </div>
            )}
          </div>
          <span className="lk-landing-chat-dots">
            {EXAMPLES.map((name) => (
              <span key={name} className={cx(name === example && "is-on")} />
            ))}
          </span>
        </div>
      </div>
    </section>
  );
}
