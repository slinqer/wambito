import { useId } from "react";
import { useLocale, useTranslations } from "use-intl";
import type { components } from "../api/schema";

export type AdminMetrics = components["schemas"]["AdminMetrics"];

function Card({
  label,
  value,
  note,
  wide = false,
}: {
  label: string;
  value: string;
  note?: string | undefined;
  wide?: boolean;
}) {
  const id = useId();
  return (
    <div
      role="group"
      aria-labelledby={id}
      className={`lk-hero flex flex-col gap-(--space-1) ${wide ? "col-span-2" : ""}`}
    >
      <span id={id} className="lk-hero-label">
        {label}
      </span>
      <span className="font-display text-[34px] leading-none font-bold text-ink tabular-nums">
        {value}
      </span>
      {note && <span className="text-[13px] font-bold text-ink-muted">{note}</span>}
    </div>
  );
}

/**
 * The user counts that lead the home (spec §6): accounts, with email, without email, active in the last
 * 30 days, and the sign-ups of the last 7 days with the 7 before them beside.
 */
export function MetricCards({ metrics }: { metrics: AdminMetrics }) {
  const t = useTranslations("admin.home.cards");
  const number = new Intl.NumberFormat(useLocale());
  const n = (value: number) => number.format(value);
  return (
    <div className="grid grid-cols-2 gap-(--space-3)">
      <Card wide label={t("total")} value={n(metrics.total)} />
      <Card label={t("with_email")} value={n(metrics.withEmail)} />
      <Card label={t("guests")} value={n(metrics.guests)} />
      <Card label={t("active")} value={n(metrics.active30d)} />
      <Card
        label={t("signups")}
        value={n(metrics.signups7d)}
        note={t("previous", { count: n(metrics.signupsPrev7d) })}
      />
    </div>
  );
}
