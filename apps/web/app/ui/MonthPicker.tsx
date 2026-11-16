import { addMonths, type Month } from "@wambito/core";
import { useTranslations } from "use-intl";
import { formatMonth } from "../i18n/format.ts";
import { useLocale } from "../i18n/IntlProvider.tsx";
import { Icon } from "./Icon.tsx";

export interface MonthPickerProps {
  month: Month;
  onChange(month: Month): void;
  /** The latest month that can be shown (the current month in the person's time zone). */
  max: Month;
}

/**
 * The month shown on home: previous and next arrows around the month's name (`Octubre`, with the
 * year when it differs from `max`'s: `Diciembre 2025`). "Next" stops at `max`. The name is a
 * polite live region, so stepping announces the new month.
 */
export function MonthPicker({ month, onChange, max }: MonthPickerProps) {
  const t = useTranslations("month_picker");
  const { locale } = useLocale();
  const name = formatMonth(month, locale);
  const year = month.slice(0, 4);
  const label = year === max.slice(0, 4) ? name : `${name} ${year}`;
  const atMax = month >= max;

  return (
    <div
      role="group"
      aria-label={t("label")}
      className="inline-flex min-w-0 items-center gap-(--space-1) min-[400px]:gap-(--space-2)"
    >
      <button
        type="button"
        className="lk-step flex-none"
        aria-label={t("previous")}
        onClick={() => onChange(addMonths(month, -1))}
      >
        <Icon name="chevron-left" size={16} />
      </button>
      <span
        aria-live="polite"
        className="min-w-0 truncate text-center font-display text-lg font-semibold text-ink min-[400px]:min-w-[7.5em]"
      >
        {label}
      </span>
      <button
        type="button"
        className="lk-step flex-none"
        aria-label={t("next")}
        disabled={atMax}
        onClick={() => {
          if (!atMax) onChange(addMonths(month, 1));
        }}
      >
        <Icon name="chevron-right" size={16} />
      </button>
    </div>
  );
}
