import type { Month } from "@wambito/core";
import { lazy, Suspense, useState } from "react";
import { useTranslations } from "use-intl";
import type { TrendReport } from "../../api/queries.ts";
import { formatMoney } from "../../i18n/format.ts";
import { useLocale } from "../../i18n/IntlProvider.tsx";
import { Icon } from "../../ui/Icon.tsx";
import { durationToken, useReducedMotionPreference } from "../../ui/motion-tokens.ts";
import { TREND_MARGIN, X_AXIS_HEIGHT, Y_AXIS_WIDTH } from "./chart-geometry.ts";
import type { TrendPoint } from "./charts.tsx";
import { compactAmount, monthLabel, type Period, shortMonth } from "./insights-model.ts";
import { capitalize, InsightCard, Loading, SrTable, usePeriodPhrase } from "./parts.tsx";

const TrendBars = lazy(() => import("./charts.tsx").then((m) => ({ default: m.TrendBars })));

/** The chart's height, in px. */
const HEIGHT = 190;

export interface TrendChartProps {
  /** One entry per month, oldest first, with the range it answers; undefined while loading. */
  data: TrendReport | undefined;
  /** An older answer is on screen while the new one loads. */
  stale: boolean;
  /** The months asked for: the subtitle until the first answer lands. */
  period: Period;
  current: Month;
  currency: string;
  order: number;
}

/**
 * Month by month (spec §2.7): income and spending as bars that rise from the axis, the budget as
 * a dashed line (with gaps where there was none), on a compact y-axis (`6 mil`), over the last six
 * months up to the one on screen (a year for a year). One month is selected (the latest by
 * default) and its figures are written under the chart: tapping a month selects it, and the
 * arrows beside the figures step through them from the keyboard. Screen readers also get every
 * month as a table. With no transactions in those months it says so instead of drawing.
 */
export function TrendChart({ data, stale, period, current, currency, order }: TrendChartProps) {
  const t = useTranslations("insights.trend");
  const { locale } = useLocale();
  const reduce = useReducedMotionPreference();
  const [picked, setPicked] = useState<Month | null>(null);
  // Labels come from the answer's own range, like its figures.
  const phrase = usePeriodPhrase(locale, current)(data?.range ?? period);
  const money = (cents: number) => formatMoney(cents, currency, locale);
  const months = data?.months ?? [];
  const empty = months.every((m) => m.income === 0 && m.expenses === 0);
  const name = (month: Month) => capitalize(monthLabel(month, current, locale), locale);
  const found = months.findIndex((m) => m.month === picked);
  const selected = found === -1 ? months.length - 1 : found;
  const shown = months[selected];

  const points: TrendPoint[] = months.map((m) => ({
    ...m,
    budget: m.budget > 0 ? m.budget : null,
    label: shortMonth(m.month, locale),
  }));
  const select = (index: number) => {
    const month = months[index]?.month;
    if (month) setPicked(month);
  };
  const budgetText = (budget: number) => (budget > 0 ? money(budget) : t("no_budget"));

  return (
    <InsightCard
      title={t("title")}
      subtitle={capitalize(phrase, locale)}
      order={order}
      busy={stale}
    >
      {!data ? (
        <Loading height={HEIGHT + 64} />
      ) : empty || !shown ? (
        <p className="m-0 py-(--space-4) text-center text-[15px] font-bold text-ink-muted">
          {t("empty", { period: phrase })}
        </p>
      ) : (
        <>
          <div
            aria-hidden="true"
            data-animated={String(!reduce)}
            className="relative -mx-(--space-1)"
            style={{ height: HEIGHT }}
          >
            {/* The selected month's band, behind the bars. */}
            <span
              data-testid="trend-selected"
              className="lk-trend-band"
              style={{
                left: `calc(${Y_AXIS_WIDTH}px + (100% - ${Y_AXIS_WIDTH + TREND_MARGIN.right}px) * ${selected / months.length})`,
                width: `calc((100% - ${Y_AXIS_WIDTH + TREND_MARGIN.right}px) / ${months.length})`,
                top: TREND_MARGIN.top,
                bottom: X_AXIS_HEIGHT,
              }}
            />
            <Suspense fallback={<Loading height={HEIGHT} />}>
              <TrendBars
                points={points}
                height={HEIGHT}
                animate={!reduce}
                durationMs={Math.round(durationToken("--hop") * 1000)}
                formatTick={(value) => compactAmount(value, locale)}
              />
            </Suspense>
            {/* A tap target per month over the plot: tapping one selects it. Pointer only (the
                arrows below are the keyboard's way), so out of the tab order. */}
            <div
              className="absolute flex"
              style={{
                left: Y_AXIS_WIDTH,
                right: TREND_MARGIN.right,
                top: TREND_MARGIN.top,
                bottom: X_AXIS_HEIGHT,
              }}
            >
              {months.map((m, index) => (
                <button
                  key={m.month}
                  type="button"
                  tabIndex={-1}
                  className="lk-trend-hit"
                  onClick={() => select(index)}
                />
              ))}
            </div>
          </div>

          <div className="flex items-center gap-(--space-2)">
            <button
              type="button"
              className="lk-step flex-none"
              aria-label={t("previous")}
              disabled={selected <= 0}
              onClick={() => select(selected - 1)}
            >
              <Icon name="chevron-left" size={16} />
            </button>
            <div
              data-testid="trend-readout"
              className="min-w-0 flex-1"
              aria-live="polite"
              aria-atomic="true"
            >
              <p className="m-0 font-display text-[16px] font-semibold text-ink">
                {name(shown.month)}
              </p>
              <ul className="m-0 flex list-none flex-wrap gap-x-(--space-3) gap-y-0.5 p-0 text-[12px] font-extrabold text-ink-muted">
                <li className="flex items-center gap-(--space-1)">
                  <span className="lk-swatch lk-swatch-income" aria-hidden="true" />
                  {t("income")} <span className="lk-num text-ink">{money(shown.income)}</span>
                </li>
                <li className="flex items-center gap-(--space-1)">
                  <span className="lk-swatch lk-swatch-expense" aria-hidden="true" />
                  {t("expenses")} <span className="lk-num text-ink">{money(shown.expenses)}</span>
                </li>
                <li className="flex items-center gap-(--space-1)">
                  <span className="lk-swatch-line" aria-hidden="true" />
                  {t("budget")} <span className="lk-num text-ink">{budgetText(shown.budget)}</span>
                </li>
              </ul>
            </div>
            <button
              type="button"
              className="lk-step flex-none"
              aria-label={t("next")}
              disabled={selected >= months.length - 1}
              onClick={() => select(selected + 1)}
            >
              <Icon name="chevron-right" size={16} />
            </button>
          </div>

          <SrTable
            caption={t("caption", { period: phrase })}
            head={[t("col_month"), t("income"), t("expenses"), t("budget")]}
            rows={months.map((m) => ({
              key: m.month,
              cells: [name(m.month), money(m.income), money(m.expenses), budgetText(m.budget)],
            }))}
          />
        </>
      )}
    </InsightCard>
  );
}
