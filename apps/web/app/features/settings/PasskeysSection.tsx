import { useQuery, useQueryClient } from "@tanstack/react-query";
import { Fragment, useId, useRef, useState } from "react";
import { useTranslations } from "use-intl";
import { intlTag, type Locale } from "../../i18n/format.ts";
import { useLocale } from "../../i18n/IntlProvider.tsx";
import type { PasskeyPrf } from "../../local/prf.ts";
import { ConfirmSheet } from "../../ui/ConfirmSheet.tsx";
import { Icon } from "../../ui/Icon.tsx";
import { useToast } from "../../ui/Toast.tsx";
import { DemoOffNote, SettingsGroup, SettingsRow } from "./parts.tsx";
import type { PasskeyItem, PasskeysApi } from "./passkeys.ts";
import { codeOf, SECURITY_KEY, type SecurityApi } from "./security.ts";
import { deviceIconName, passkeyRows } from "./security-model.ts";

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
 * passkey wraps); "Turn on" touches that passkey (`evaluatePrf([id])`) and adds its wrap. A new
 * passkey whose provider gives no PRF is kept, and the section says so in text that stays
 * (`role="status"`), not a toast; one that gave a PRF whose wrap could not be saved is kept too, with
 * the generic failure (its row's "Turn on" tries again).
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
  /** The passkey just added gave no PRF: it signs in only; said until the next add or leaving. */
  const [addedWithoutWrap, setAddedWithoutWrap] = useState(false);
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
    setAddedWithoutWrap(false);
    // With the open vault's keys: whether the new passkey gave a PRF, and whether it wrapped the
    // data key. Only a passkey that gave none (told by `onNoPrf`) gets the password-manager notice;
    // a second touch that was cancelled or failed is not the password manager's doing.
    let gavePrf = false;
    let wrapped = false;
    let noPrf = false;
    try {
      const outcome = await passkeys.add(
        vaultUserId
          ? {
              userId: vaultUserId,
              explainSecondTouch: () => toast.show({ message: tVault("passkey_second_touch") }),
              onNoPrf: () => {
                noPrf = true;
              },
              ...(security
                ? {
                    keep: async (passkey: PasskeyPrf) => {
                      gavePrf = true;
                      await security.addPasskeyWrap(passkey);
                      wrapped = true;
                    },
                  }
                : {}),
            }
          : undefined,
      );
      if (outcome === "added") {
        // An encrypted account's passkey that opens nothing: said at once, as text that stays.
        if (security && vaultUserId && gavePrf && !wrapped) {
          toast.show({ tone: "error", message: t("turn_on_failed") });
        } else if (security && vaultUserId && noPrf) setAddedWithoutWrap(true);
        else toast.show({ message: t("added") });
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

  const head = {
    icon: <Icon name="fingerprint" size={22} />,
    title: t("title"),
    line: t("line"),
  };
  const note = "m-0 px-(--space-1) py-(--space-2) text-[14px] text-ink-muted";

  if (off) {
    return (
      <SettingsGroup head={head}>
        <SettingsRow
          icon={<Icon name="plus" size={20} />}
          title={t("add")}
          trailing={{ kind: "none" }}
        />
        <DemoOffNote id={offId} />
      </SettingsGroup>
    );
  }

  return (
    <>
      <SettingsGroup head={head}>
        {list.isError && <p className={note}>{t("list_failed")}</p>}
        {list.data?.length === 0 && (
          <p className={note}>
            {t("empty")} {t("lead")}
          </p>
        )}
        {rows.map((item) => {
          const date = day(item);
          return (
            <Fragment key={item.id}>
              <SettingsRow
                icon={<Icon name={deviceIconName(item.name)} size={20} />}
                title={item.name ?? t("default_name")}
                line={`${t("created", { date })}${item.synced ? ` · ${t("synced")}` : ""}`}
                trailing={{
                  kind: "trash",
                  label: item.name
                    ? t("remove_named_label", { name: item.name })
                    : t("remove_label", { date }),
                  onPress: () => {
                    setRemoving(item);
                    setConfirmOpen(true);
                  },
                }}
              />
              {item.unlocks === false && (
                <SettingsRow
                  icon={<Icon name="key" size={20} />}
                  title={
                    item.name
                      ? t("turn_on_named_label", { name: item.name })
                      : t("turn_on_label", { date })
                  }
                  line={t("locked")}
                  trailing={{ kind: "chevron" }}
                  {...(turningOn === null ? { onPress: () => void turnOn(item) } : {})}
                />
              )}
              {noPrf === item.id && (
                <p id={noPrfId} role="alert" className="m-0 w-full text-[14px] text-over">
                  {t("turn_on_no_prf")}
                </p>
              )}
            </Fragment>
          );
        })}
        {supported ? (
          <SettingsRow
            icon={<Icon name="plus" size={20} />}
            title={adding ? t("adding") : t("add")}
            trailing={{ kind: "none" }}
            {...(adding ? {} : { onPress: () => void add() })}
          />
        ) : (
          <p className={note}>{t("unsupported")}</p>
        )}
        {addedWithoutWrap && (
          <p role="status" className={`${note} text-ink`}>
            {t("add_no_prf")}
          </p>
        )}
      </SettingsGroup>
      <ConfirmSheet
        open={confirmOpen}
        onClose={() => setConfirmOpen(false)}
        title={t("remove_title")}
        body={t("remove_body")}
        confirmLabel={t("remove_confirm")}
        onConfirm={remove}
      />
    </>
  );
}
