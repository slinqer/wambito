import { Bar, BarChart, CartesianGrid, ResponsiveContainer, XAxis, YAxis } from "recharts";
import { useLocale, useTranslations } from "use-intl";
import { SrTable } from "../features/insights/parts.tsx";
import type { AdminMetrics } from "./MetricCards.tsx";

const HEIGHT = 200;

const Block = ({
  id,
  title,
  note,
  children,
}: {
  id: string;
  title: string;
  note?: string;
  children: React.ReactNode;
}) => (
  <section aria-labelledby={id} className="lk-hero flex min-w-0 flex-col gap-(--space-3)">
    <div className="flex flex-col gap-(--space-1)">
      <h2 id={id} className="m-0 font-display text-[20px] leading-tight font-bold text-ink">
        {title}
      </h2>
      {note && <p className="m-0 text-[13px] font-bold text-ink-muted">{note}</p>}
    </div>
    {children}
  </section>
);

const th = "py-(--space-1) pr-(--space-3) text-left text-[13px] font-bold text-ink-muted";
const td = "py-(--space-1) pr-(--space-3) tabular-nums text-ink";

/** Daily actives: one bar per day (the last 90), the drawing decorative and a table for readers. */
function DailyActive({ days }: { days: AdminMetrics["dailyActive"] }) {
  const t = useTranslations("admin.home.activity.daily");
  const locale = useLocale();
  const day = new Intl.DateTimeFormat(locale, { day: "numeric", month: "short", timeZone: "UTC" });
  const points = days.map((d) => ({ ...d, label: day.format(new Date(`${d.day}T00:00:00Z`)) }));
  return (
    <Block id="admin-daily-title" title={t("title")} note={t("subtitle")}>
      <div aria-hidden="true">
        <ResponsiveContainer
          width="100%"
          height={HEIGHT}
          initialDimension={{ width: 320, height: HEIGHT }}
        >
          <BarChart
            data={points}
            accessibilityLayer={false}
            margin={{ top: 8, right: 4, bottom: 0, left: 0 }}
            barCategoryGap="10%"
            className="lk-admin-bars"
          >
            <CartesianGrid vertical={false} />
            <XAxis
              dataKey="label"
              axisLine={false}
              tickLine={false}
              interval="preserveStartEnd"
              minTickGap={24}
              height={24}
            />
            <YAxis
              width={32}
              axisLine={false}
              tickLine={false}
              tickCount={4}
              allowDecimals={false}
              domain={[0, "auto"]}
              tick={{ className: "lk-admin-bars-tick" }}
            />
            <Bar
              dataKey="count"
              className="lk-admin-bars-email"
              radius={[3, 3, 0, 0]}
              isAnimationActive={false}
            />
          </BarChart>
        </ResponsiveContainer>
      </div>
      <SrTable
        caption={t("title")}
        head={[t("day"), t("count")]}
        rows={points.map((p) => ({ key: p.day, cells: [p.label, String(p.count)] }))}
      />
    </Block>
  );
}

/** Cohorts by sign-up week: the weeks 1, 4 and 12 are "at least N"; "—" while the week is not there yet. */
function Cohorts({ cohorts }: { cohorts: AdminMetrics["cohorts"] }) {
  const t = useTranslations("admin.home.activity.cohorts");
  const locale = useLocale();
  const day = new Intl.DateTimeFormat(locale, { day: "numeric", month: "short", timeZone: "UTC" });
  const cell = (value: number | null) =>
    value === null ? t("none") : t("at_least", { count: value });
  return (
    <Block id="admin-cohorts-title" title={t("title")} note={t("subtitle")}>
      {cohorts.length === 0 ? (
        <p className="m-0 text-ink-muted">{t("empty")}</p>
      ) : (
        <div className="overflow-x-auto">
          <table className="w-full border-collapse">
            <caption className="sr-only">{t("title")}</caption>
            <thead>
              <tr>
                <th scope="col" className={th}>
                  {t("week")}
                </th>
                <th scope="col" className={th}>
                  {t("size")}
                </th>
                <th scope="col" className={th}>
                  {t("week1")}
                </th>
                <th scope="col" className={th}>
                  {t("week4")}
                </th>
                <th scope="col" className={th}>
                  {t("week12")}
                </th>
              </tr>
            </thead>
            <tbody>
              {cohorts.map((c) => (
                <tr key={c.weekStart}>
                  <th scope="row" className={`${td} text-left font-bold`}>
                    {day.format(new Date(`${c.weekStart}T00:00:00Z`))}
                  </th>
                  <td className={td}>{c.size}</td>
                  <td className={td}>{cell(c.week1)}</td>
                  <td className={td}>{cell(c.week4)}</td>
                  <td className={td}>{cell(c.week12)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </Block>
  );
}

function Installs({ installs }: { installs: AdminMetrics["installsByPlatform"] }) {
  const t = useTranslations("admin.home.activity.installs");
  const number = new Intl.NumberFormat(useLocale());
  return (
    <Block id="admin-installs-title" title={t("title")}>
      <ul
        aria-labelledby="admin-installs-title"
        className="m-0 flex list-none flex-col gap-(--space-1) p-0"
      >
        {installs.map((i) => (
          <li key={i.platform} className="flex justify-between gap-(--space-3)">
            <span className="font-bold text-ink">{t(`platforms.${i.platform}`)}</span>
            <span className="tabular-nums text-ink">{number.format(i.count)}</span>
          </li>
        ))}
      </ul>
    </Block>
  );
}

function Versions({ versions }: { versions: AdminMetrics["versions"] }) {
  const t = useTranslations("admin.home.activity.versions");
  return (
    <Block id="admin-versions-title" title={t("title")}>
      {versions.length === 0 ? (
        <p className="m-0 text-ink-muted">{t("empty")}</p>
      ) : (
        <div className="overflow-x-auto">
          <table className="w-full border-collapse">
            <caption className="sr-only">{t("title")}</caption>
            <thead>
              <tr>
                <th scope="col" className={th}>
                  {t("platform")}
                </th>
                <th scope="col" className={th}>
                  {t("version")}
                </th>
                <th scope="col" className={th}>
                  {t("users")}
                </th>
              </tr>
            </thead>
            <tbody>
              {versions.map((v) => (
                <tr key={`${v.platform}/${v.appVersion}`}>
                  <td className={td}>{v.platform}</td>
                  <td className={td}>{v.appVersion}</td>
                  <td className={td}>{v.users}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </Block>
  );
}

/** The four activity blocks under the sign-ups chart: daily actives, cohorts, installs, versions. */
export function ActivityBlocks({ metrics }: { metrics: AdminMetrics }) {
  return (
    <>
      <DailyActive days={metrics.dailyActive} />
      <Cohorts cohorts={metrics.cohorts} />
      <Installs installs={metrics.installsByPlatform} />
      <Versions versions={metrics.versions} />
    </>
  );
}
