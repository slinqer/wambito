import { useQuery, useQueryClient } from "@tanstack/react-query";
import { useId, useRef, useState } from "react";
import { useTranslations } from "use-intl";
import { intlTag, type Locale } from "../../i18n/format.ts";
import { useLocale } from "../../i18n/IntlProvider.tsx";
import { ConfirmSheet } from "../../ui/ConfirmSheet.tsx";
import { FingerprintIcon } from "../../ui/FingerprintIcon.tsx";
import { PressButton } from "../../ui/PressButton.tsx";
import { useToast } from "../../ui/Toast.tsx";
import { DemoOffNote, SettingsSection } from "./parts.tsx";
import type { PasskeyItem, PasskeysApi } from "./passkeys.ts";
import { codeOf, SECURITY_KEY, type SecurityApi } from "./security.ts";
import { passkeyRows } from "./security-model.ts";

export const PASSKEYS_KEY = ["passkeys"] as const;

/** A day as `2 oct 2026` (es) or `Oct 2, 2026` (en), in the person's time zone. */
export function formatDay(iso: string, locale: Locale, timeZone: string): string {
  try {
    return new Intl.DateTimeFormat(intlTag(locale), { dateStyle: "medium", timeZone })
      .format(new Date(iso))
      .replace(/\./g, "");
  } catch {
    return iso.slice(0, 10);
  }
}

/**
 * The person's passkeys (spec §2.4: "Settings also offers it"): each with when it was made and
 * whether it syncs, and its own "Eliminar" after asking; "Agregar una huella" where the browser
 * can make one. Closing the browser's prompt is silent, as on sign-in. With `security` (an
 * encrypted account), each says whether it opens the data ("Unlocks" / "Does not unlock", from the
 * passkey wraps); "Turn on" touches that passkey (`evaluatePrf([id])`) and adds its wrap.
 */
export function PasskeysSection({
  passkeys,
  timeZone,
  off = false,
  vaultUserId,
  security,
}: {
  passkeys: PasskeysApi;
  timeZone: string;
  /** The demo: nothing is listed or asked of the browser; "Agregar" is off, with a note. */
  off?: boolean;
  /** An encrypted account's open vault: a new passkey unlocks it too (its PRF wraps the data key). */
  vaultUserId?: string | undefined;
  /** The open vault's keys: which passkeys open the data, and "Turn on" for the others. */
  security?: SecurityApi | undefined;
}) {
  const t = useTranslations("settings.passkeys");
  const tVault = useTranslations("vault");
  const { locale } = useLocale();
  const qc = useQueryClient();
  const toast = useToast();
  const offId = useId();
  const list = useQuery({ queryKey: PASSKEYS_KEY, queryFn: () => passkeys.list(), enabled: !off });
  const [supported] = useState(() => passkeys.supported());
  const [adding, setAdding] = useState(false);
  const inFlight = useRef(false);
  const [removing, setRemoving] = useState<PasskeyItem | null>(null);
  const [confirmOpen, setConfirmOpen] = useState(false);
  const wraps = useQuery({
    queryKey: SECURITY_KEY,
    queryFn: () => (security as SecurityApi).load(),
    enabled: !off && security !== undefined,
  });
  const rows = passkeyRows(list.data ?? [], security ? wraps.data?.wraps : undefined);
  const [turningOn, setTurningOn] = useState<string | null>(null);
  /** A passkey whose provider gives no PRF: it cannot open the data, say so under it. */
  const [noPrf, setNoPrf] = useState<string | null>(null);
  const noPrfId = useId();

  const turnOn = async (item: PasskeyItem) => {
    if (!security || turningOn) return;
    setTurningOn(item.id);
    setNoPrf(null);
    try {
      let touched: Awaited<ReturnType<SecurityApi["evaluatePrf"]>>;
      try {
        touched = await security.evaluatePrf([item.credentialId]);
      } catch (problem) {
        if (codeOf(problem) === "no_prf") setNoPrf(item.id);
        else toast.show({ tone: "error", message: t("turn_on_failed") });
        return;
      }
      if (!touched) return;
      try {
        await security.addPasskeyWrap(touched);
      } catch {
        toast.show({ tone: "error", message: t("turn_on_failed") });
        return;
      } finally {
        touched.prf.fill(0);
      }
      toast.show({ message: t("turned_on") });
      await qc.invalidateQueries({ queryKey: SECURITY_KEY });
    } finally {
      setTurningOn(null);
    }
  };

  const day = (item: PasskeyItem) => formatDay(item.createdAt, locale, timeZone);

  const add = async () => {
    if (inFlight.current) return;
    inFlight.current = true;
    setAdding(true);
    try {
      const outcome = await passkeys.add(
        vaultUserId
          ? {
              userId: vaultUserId,
              explainSecondTouch: () => toast.show({ message: tVault("passkey_second_touch") }),
            }
          : undefined,
      );
      if (outcome === "added") {
        toast.show({ message: t("added") });
        await qc.invalidateQueries({ queryKey: PASSKEYS_KEY });
        if (security) await qc.invalidateQueries({ queryKey: SECURITY_KEY });
      } else if (outcome === "failed") {
        toast.show({ tone: "error", message: t("add_failed") });
      }
    } finally {
      inFlight.current = false;
      setAdding(false);
    }
  };

  const remove = async () => {
    if (!removing) return;
    try {
      await passkeys.remove(removing.id, { last: (list.data?.length ?? 0) <= 1 });
    } catch (problem) {
      toast.show({ tone: "error", message: t("remove_failed") });
      throw problem;
    }
    toast.show({ message: t("removed") });
    await qc.invalidateQueries({ queryKey: PASSKEYS_KEY });
  };

  if (off) {
    return (
      <SettingsSection title={t("title")} lead={t("lead")}>
        <PressButton variant="secondary" className="self-start" disabled aria-describedby={offId}>
          <FingerprintIcon />
          {t("add")}
        </PressButton>
        <DemoOffNote id={offId} />
      </SettingsSection>
    );
  }

  return (
    <SettingsSection title={t("title")} lead={t("lead")}>
      <div className="flex flex-col gap-(--space-2)" aria-busy={list.isPending || undefined}>
        {list.isError && <p className="m-0 text-[14px] text-ink-muted">{t("list_failed")}</p>}
        {list.data?.length === 0 && <p className="m-0 text-[14px] text-ink">{t("empty")}</p>}
        {list.data && list.data.length > 0 && (
          <ul className="m-0 flex list-none flex-col gap-(--space-2) p-0">
            {rows.map((item) => (
              <li key={item.id} className="lk-rowcard flex-wrap justify-between">
                <span className="flex min-w-0 items-center gap-(--space-3)">
                  <span className="flex-none text-brand-glow" aria-hidden="true">
                    <FingerprintIcon />
                  </span>
                  <span className="flex min-w-0 flex-col">
                    <span className="truncate text-[15px] font-bold text-ink">
                      {item.name ?? t("default_name")}
                    </span>
                    <span className="flex flex-wrap gap-x-(--space-2) text-[13px] text-ink-muted">
                      <span>{t("created", { date: day(item) })}</span>
                      {item.synced && <span>{t("synced")}</span>}
                      {item.unlocks === true && <span>{t("unlocks")}</span>}
                      {item.unlocks === false && (
                        <span className="font-bold text-ink">{t("locked")}</span>
                      )}
                    </span>
                  </span>
                </span>
                {item.unlocks === false && (
                  <PressButton
                    variant="secondary"
                    size="sm"
                    className="flex-none"
                    disabled={turningOn !== null}
                    aria-busy={turningOn === item.id || undefined}
                    aria-describedby={noPrf === item.id ? noPrfId : undefined}
                    aria-label={
                      item.name
                        ? t("turn_on_named_label", { name: item.name })
                        : t("turn_on_label", { date: day(item) })
                    }
                    onClick={() => void turnOn(item)}
                  >
                    {t("turn_on")}
                  </PressButton>
                )}
                <PressButton
                  variant="ghost"
                  size="sm"
                  className="flex-none"
                  aria-label={
                    item.name
                      ? t("remove_named_label", { name: item.name, date: day(item) })
                      : t("remove_label", { date: day(item) })
                  }
                  onClick={() => {
                    setRemoving(item);
                    setConfirmOpen(true);
                  }}
                >
                  {t("remove")}
                </PressButton>
                {noPrf === item.id && (
                  <p id={noPrfId} role="alert" className="m-0 w-full text-[14px] text-over">
                    {t("turn_on_no_prf")}
                  </p>
                )}
              </li>
            ))}
          </ul>
        )}
      </div>
      {supported ? (
        <PressButton
          variant="secondary"
          className="self-start"
          disabled={adding}
          aria-busy={adding || undefined}
          onClick={() => void add()}
        >
          <FingerprintIcon />
          {adding ? t("adding") : t("add")}
        </PressButton>
      ) : (
        <p className="m-0 text-[14px] text-ink-muted">{t("unsupported")}</p>
      )}
      <ConfirmSheet
        open={confirmOpen}
        onClose={() => setConfirmOpen(false)}
        title={t("remove_title")}
        body={t("remove_body")}
        confirmLabel={t("remove_confirm")}
        onConfirm={remove}
      />
    </SettingsSection>
  );
}
