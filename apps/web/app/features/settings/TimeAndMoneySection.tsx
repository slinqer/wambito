import { useQueryClient } from "@tanstack/react-query";
import { SUPPORTED_CURRENCIES, type SupportedCurrency } from "@wambito/core";
import { useId, useMemo, useState } from "react";
import { useTranslations } from "use-intl";
import { ApiProblem, type Translator } from "../../api/errors.ts";
import { useRecurrences } from "../../api/queries.ts";
import { formatMoney, lukasHint } from "../../i18n/format.ts";
import { useLocale } from "../../i18n/IntlProvider.tsx";
import { Icon } from "../../ui/Icon.tsx";
import { PressButton } from "../../ui/PressButton.tsx";
import { Sheet } from "../../ui/Sheet.tsx";
import { useToast } from "../../ui/Toast.tsx";
import { currencyName } from "../onboarding/CurrencyStep.tsx";
import { isSupportedCurrency } from "../onboarding/currency.ts";
import { type Profile, useHasTransactions } from "../onboarding/onboarding-api.ts";
import { browserTimeZone } from "../onboarding/timezone.ts";
import { SettingLabel, SettingsGroup, SettingsRow } from "./parts.tsx";
import {
  searchZones,
  zoneCity,
  zoneOffset,
  zoneRegion,
  zoneSearchIndex,
} from "./settings-model.ts";
import { failureMessage, refreshAllButProfile, useSaveProfile } from "./use-profile.ts";

/**
 * "Hora y moneda": the time zone and the currency as two value rows; each opens a sheet with its
 * picker (the currency's while it can still change, else the line that says why it stays).
 */
export function TimeAndMoneySection({ me }: { me: Profile }) {
  const t = useTranslations("settings");
  return (
    <SettingsGroup label={t("time_and_money")}>
      <TimeZoneSetting zone={me.timezone} />
      <CurrencySetting currency={me.currency} />
    </SettingsGroup>
  );
}

/** How many zones a search lists at once; typing narrows it. */
const ZONES_SHOWN = 40;

/**
 * The profile's time zone (`America/Bogota` shown as "Bogota", with its region and offset) and
 * "Cambiar", which opens a sheet to search the zones the browser knows by city. Picking one saves
 * it and refetches everything, since "today" and the months' edges move with it.
 */
function TimeZoneSetting({ zone }: { zone: string }) {
  const t = useTranslations("settings.timezone");
  const tRoot = useTranslations() as unknown as Translator;
  const { locale } = useLocale();
  const qc = useQueryClient();
  const save = useSaveProfile();
  const toast = useToast();
  const [open, setOpen] = useState(false);
  const [query, setQuery] = useState("");
  const [busy, setBusy] = useState(false);
  const { zone: deviceZone, supported } = useMemo(browserTimeZone, []);
  const zones = useMemo(
    () => (supported.includes(zone) ? supported : [zone, ...supported]),
    [supported, zone],
  );
  // Countries' names for every zone, built the first time the sheet opens (then kept).
  const index = useMemo(() => (open ? zoneSearchIndex(zones) : undefined), [open, zones]);
  const found = useMemo(() => searchZones(zones, query, ZONES_SHOWN, index), [zones, query, index]);
  const offset = zoneOffset(zone, locale);

  const choose = async (next: string) => {
    if (busy) return;
    if (next === zone) {
      setOpen(false);
      return;
    }
    setBusy(true);
    try {
      await save({ timezone: next });
    } catch (problem) {
      toast.show({ tone: "error", message: failureMessage(problem, tRoot) });
      return;
    } finally {
      setBusy(false);
    }
    setOpen(false);
    setQuery("");
    void refreshAllButProfile(qc);
    toast.show({ message: t("saved", { city: zoneCity(next) }) });
  };

  const offerDevice =
    deviceZone && deviceZone !== zone && supported.includes(deviceZone) ? deviceZone : null;

  return (
    <>
      <SettingsRow
        icon={<Icon name="clock" size={20} />}
        title={t("label")}
        trailing={{ kind: "chevron", value: zoneCity(zone) }}
        onPress={() => setOpen(true)}
      />
      <Sheet open={open} onClose={() => setOpen(false)} title={t("sheet_title")}>
        <div className="flex flex-col gap-(--space-3) pt-(--space-3)" aria-busy={busy || undefined}>
          <p className="m-0 text-[14px] text-ink-muted">{t("hint")}</p>
          <p className="m-0 text-[13px] text-ink-muted">
            {[zoneCity(zone), zoneRegion(zone), offset].filter(Boolean).join(" · ")}
          </p>
          <label className="flex flex-col gap-(--space-1)">
            <span className="text-[14px] font-bold text-ink">{t("search")}</span>
            <span className="lk-input min-h-11">
              <input
                type="search"
                value={query}
                autoComplete="off"
                spellCheck={false}
                placeholder={t("placeholder")}
                onChange={(event) => setQuery(event.target.value)}
                className="min-h-9 min-w-0 flex-1 border-0 bg-transparent p-0 font-text text-[16px] text-ink outline-none placeholder:font-normal placeholder:text-ink-muted"
              />
            </span>
          </label>
          {offerDevice && !query && (
            <PressButton
              variant="secondary"
              disabled={busy}
              onClick={() => void choose(offerDevice)}
            >
              {t("use_device", { city: zoneCity(offerDevice) })}
            </PressButton>
          )}
          {found.matches.length === 0 ? (
            <p className="m-0 text-[15px] text-ink-muted" role="status">
              {t("no_results", { query: query.trim() })}
            </p>
          ) : (
            <ul className="m-0 flex list-none flex-col gap-(--space-2) p-0">
              {found.matches.map((candidate) => (
                <li key={candidate}>
                  <ZoneOption
                    zone={candidate}
                    current={candidate === zone}
                    disabled={busy}
                    onPick={() => void choose(candidate)}
                  />
                </li>
              ))}
            </ul>
          )}
          {found.more > 0 && (
            <p className="m-0 text-[13px] text-ink-muted">{t("more", { count: found.more })}</p>
          )}
        </div>
      </Sheet>
    </>
  );
}

function ZoneOption({
  zone,
  current,
  disabled,
  onPick,
}: {
  zone: string;
  current: boolean;
  disabled: boolean;
  onPick(): void;
}) {
  const t = useTranslations("settings.timezone");
  const { locale } = useLocale();
  return (
    <button
      type="button"
      aria-pressed={current}
      disabled={disabled}
      onClick={onPick}
      className="lk-rowcard lk-zone flex min-h-11 w-full cursor-pointer items-center justify-between gap-(--space-2) text-left focus-visible:outline-3 focus-visible:outline-focus focus-visible:outline-offset-2 disabled:cursor-wait"
    >
      <span className="flex min-w-0 flex-col">
        <span className="truncate text-[15px] font-bold text-ink">{zoneCity(zone)}</span>
        <span className="truncate text-[13px] text-ink-muted">
          {[zoneRegion(zone), zoneOffset(zone, locale)].filter(Boolean).join(" · ")}
        </span>
      </span>
      {current && <span className="lk-soon flex-none">{t("current")}</span>}
    </button>
  );
}

/** What 50 lukas (or 50 dollars, 50 euros) look like in each currency, as amounts are shown. */
const EXAMPLE: Record<SupportedCurrency, number> = { COP: 5_000_000, USD: 5_000, EUR: 5_000 };

/**
 * The account's currency, while it can still change: one radio per supported currency with an
 * example amount, shown while this screen sees no transactions and no recurrences. The server has
 * the last word, since it also counts deleted transactions, which the list here never returns: a
 * 409 `currency_locked` turns the choice into the same short line as an account that visibly has
 * transactions. While a choice saves the radios stay enabled (marked busy), so the keyboard's
 * focus stays where it is; `choose` ignores another pick until the first one is answered.
 */
function CurrencySetting({ currency }: { currency: string }) {
  const t = useTranslations("settings.currency");
  const tRoot = useTranslations() as unknown as Translator;
  const { locale } = useLocale();
  const qc = useQueryClient();
  const save = useSaveProfile();
  const toast = useToast();
  const hasTransactions = useHasTransactions();
  const recurrences = useRecurrences();
  const [lockedByServer, setLockedByServer] = useState(false);
  const [busy, setBusy] = useState(false);
  const [open, setOpen] = useState(false);
  const hintId = useId();

  const known =
    (hasTransactions.data !== undefined || hasTransactions.isError) &&
    (recurrences.data !== undefined || recurrences.isError);
  const locked =
    lockedByServer ||
    hasTransactions.data === true ||
    (recurrences.data?.length ?? 0) > 0 ||
    !isSupportedCurrency(currency);

  const choose = async (next: SupportedCurrency) => {
    if (busy || next === currency) return;
    setBusy(true);
    try {
      await save({ currency: next });
    } catch (problem) {
      if (problem instanceof ApiProblem && problem.code === "currency_locked") {
        setLockedByServer(true);
      } else {
        toast.show({ tone: "error", message: failureMessage(problem, tRoot) });
      }
      return;
    } finally {
      setBusy(false);
    }
    setOpen(false);
    void refreshAllButProfile(qc);
    toast.show({ message: t("saved", { currency: next }) });
  };

  const choices = (
    <fieldset
      className="m-0 flex min-w-0 flex-col gap-(--space-2) border-0 p-0"
      disabled={!known}
      aria-busy={!known || busy || undefined}
      aria-describedby={hintId}
    >
      <legend className="contents">
        <SettingLabel label={t("label")} hint={t("hint")} hintId={hintId} />
      </legend>
      {SUPPORTED_CURRENCIES.map((code) => {
        const example = formatMoney(EXAMPLE[code], code, locale);
        const hint = lukasHint(EXAMPLE[code], code, locale);
        return (
          <label
            key={code}
            className="flex min-h-11 cursor-pointer items-center gap-(--space-3) rounded-lg border-2 border-stroke bg-surface-row px-(--space-4) py-(--space-2) shadow-edge-sm has-checked:border-brand-glow has-disabled:cursor-not-allowed has-disabled:opacity-60 has-focus-visible:outline-3 has-focus-visible:outline-focus has-focus-visible:outline-offset-2"
          >
            <input
              type="radio"
              name="currency"
              value={code}
              checked={currency === code}
              onChange={() => void choose(code)}
              className="size-5 shrink-0 accent-brand outline-none"
            />
            <span className="flex min-w-0 flex-1 flex-col">
              <span className="text-ink">{currencyName(code, locale)}</span>
              <span className="lk-num text-[13px] text-ink-muted">
                {example}
                {hint && ` (${hint})`}
              </span>
            </span>
            <span className="lk-num text-ink-muted">{code}</span>
          </label>
        );
      })}
    </fieldset>
  );

  return (
    <>
      <SettingsRow
        icon={<Icon name="coin" size={20} />}
        title={t("label")}
        trailing={{ kind: "chevron", value: currency }}
        onPress={() => setOpen(true)}
      />
      <Sheet open={open} onClose={() => setOpen(false)} title={t("label")}>
        <div className="pt-(--space-3)">
          {known && locked ? (
            <p className="m-0 text-[14px] text-ink-muted">{t("locked", { currency })}</p>
          ) : (
            choices
          )}
        </div>
      </Sheet>
    </>
  );
}
