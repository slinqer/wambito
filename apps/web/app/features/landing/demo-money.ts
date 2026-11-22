import type { Locale } from "../../i18n/format.ts";
import { formatMoney } from "../../i18n/format.ts";
import { useLocale } from "../../i18n/IntlProvider.tsx";

/**
 * The currency the landing's invented figures show in, per language: Colombian pesos in Spanish,
 * dollars in English, euros in Italian and Portuguese. The figures are written once, in euro
 * cents, and scaled by `rate` so they stay believable (a 12.50 € pastry is $50.000 COP); pesos are
 * rounded to whole hundreds, as prices there are.
 */
export const DEMO_CURRENCY: Record<Locale, { currency: string; rate: number; round: number }> = {
  es: { currency: "COP", rate: 4000, round: 10_000 },
  en: { currency: "USD", rate: 1, round: 1 },
  it: { currency: "EUR", rate: 1, round: 1 },
  pt: { currency: "EUR", rate: 1, round: 1 },
};

/** Euro cents → this currency's cents, scaled and rounded. */
export function demoCents(locale: Locale, euroCents: number): number {
  const { rate, round } = DEMO_CURRENCY[locale];
  return Math.round((euroCents * rate) / round) * round;
}

/** Formats a demo figure (given in euro cents) in the page language's demo currency. */
export function useDemoMoney() {
  const { locale } = useLocale();
  const { currency } = DEMO_CURRENCY[locale];
  return (euroCents: number, opts?: { sign?: "always" }) =>
    formatMoney(demoCents(locale, euroCents), currency, locale, opts);
}
