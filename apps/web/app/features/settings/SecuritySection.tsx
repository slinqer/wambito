import { useQuery, useQueryClient } from "@tanstack/react-query";
import { useId, useState } from "react";
import { useTranslations } from "use-intl";
import { useLocale } from "../../i18n/IntlProvider.tsx";
import { PressButton } from "../../ui/PressButton.tsx";
import { Sheet } from "../../ui/Sheet.tsx";
import { useToast } from "../../ui/Toast.tsx";
import { FieldError } from "../sign-in/SignInScreen.tsx";
import { ApproveDevice } from "../vault/ApproveDevice.tsx";
import { RecoveryKeySetup } from "../vault/RecoveryKeySetup.tsx";
import { formatDay, PASSKEYS_KEY } from "./PasskeysSection.tsx";
import { SettingLabel, SettingsSection } from "./parts.tsx";
import type { PasskeysApi } from "./passkeys.ts";
import {
  type KeyError,
  keyErrorOf,
  type PasskeyList,
  PasskeyListFailed,
  type Problem,
  problemOf,
  RecoveryKeyField,
  RemoveDeviceSheet,
  Takeover,
} from "./RemoveDeviceSheet.tsx";
import { codeOf, SECURITY_KEY, type SecurityApi } from "./security.ts";
import { type DeviceRow, deviceRows } from "./security-model.ts";

/**
 * Settings → Security for an encrypted account (stage 2b Task 8; mode `local`, never a guest):
 * this browser and the other devices that open the data (label, added date; "Not verified" when
 * an attestation fails), each other one with "Remove" (a key rotation, `RemoveDeviceSheet`);
 * "Approve a new device" (`ApproveDevice`); "New recovery key" (confirmed by the current key or a
 * passkey touch, then `RecoveryKeySetup`); and how many records could not be read, when any.
 */
export function SecuritySection({
  security,
  passkeys,
  timeZone,
}: {
  security: SecurityApi;
  passkeys: PasskeysApi;
  timeZone: string;
}) {
  const t = useTranslations("settings.security");
  const { locale } = useLocale();
  const qc = useQueryClient();
  const snapshot = useQuery({ queryKey: SECURITY_KEY, queryFn: () => security.load() });
  const passkeyList = useQuery({ queryKey: PASSKEYS_KEY, queryFn: () => passkeys.list() });
  const [canTouch] = useState(() => passkeys.supported());
  const [removing, setRemoving] = useState<DeviceRow | null>(null);
  const [approving, setApproving] = useState(false);
  const [newKey, setNewKey] = useState(false);

  const known: PasskeyList = passkeyList.isSuccess
    ? { status: "ready", ids: passkeyList.data.map((p) => p.credentialId) }
    : passkeyList.isError
      ? { status: "failed", retry: () => void passkeyList.refetch() }
      : { status: "loading" };
  const rows = snapshot.data ? deviceRows(snapshot.data) : null;
  const changed = () => void qc.invalidateQueries({ queryKey: SECURITY_KEY });
  const day = (iso: string | null) => (iso ? formatDay(iso, locale, timeZone) : null);
  const unreadable = snapshot.data?.unreadable ?? 0;

  const deviceItem = (row: DeviceRow) => {
    const name = row.label ?? t("unnamed");
    const added = day(row.createdAt);
    return (
      <li key={row.id} className="lk-rowcard justify-between">
        <span className="flex min-w-0 flex-col">
          <span className="truncate text-[15px] font-bold text-ink">{name}</span>
          <span className="flex flex-wrap gap-x-(--space-2) text-[13px] text-ink-muted">
            {row.thisBrowser && <span className="font-bold text-ink">{t("this_browser")}</span>}
            {added && <span>{t("added", { date: added })}</span>}
            {!row.verified && <span className="font-bold text-over">{t("not_verified")}</span>}
          </span>
        </span>
        {row.removable && (
          <PressButton
            variant="ghost"
            size="sm"
            className="flex-none"
            aria-label={t("remove_label", { name })}
            onClick={() => setRemoving(row)}
          >
            {t("remove")}
          </PressButton>
        )}
      </li>
    );
  };

  return (
    <SettingsSection title={t("title")} lead={t("lead")}>
      <div className="flex flex-col gap-(--space-2)" aria-busy={snapshot.isPending || undefined}>
        {snapshot.isError && <p className="m-0 text-[14px] text-ink-muted">{t("load_failed")}</p>}
        {rows && (
          <ul className="m-0 flex list-none flex-col gap-(--space-2) p-0">
            {rows.thisBrowser && deviceItem(rows.thisBrowser)}
            {rows.others.map(deviceItem)}
          </ul>
        )}
      </div>
      <div className="flex flex-col gap-(--space-2)">
        <SettingLabel label={t("approve")} hint={t("approve_lead")} />
        <PressButton variant="secondary" className="self-start" onClick={() => setApproving(true)}>
          {t("approve")}
        </PressButton>
      </div>
      <div className="flex flex-col gap-(--space-2)">
        <SettingLabel label={t("recovery_title")} hint={t("recovery_lead")} />
        <PressButton variant="secondary" className="self-start" onClick={() => setNewKey(true)}>
          {t("new_recovery")}
        </PressButton>
      </div>
      {unreadable > 0 && (
        <SettingLabel label={t("unreadable", { count: unreadable })} hint={t("unreadable_lead")} />
      )}
      <RemoveDeviceSheet
        device={removing}
        security={security}
        passkeyList={known}
        canTouch={canTouch}
        onClose={() => setRemoving(null)}
        onChanged={changed}
      />
      <NewRecoveryKeySheet
        open={newKey}
        security={security}
        passkeyList={known}
        canTouch={canTouch}
        onClose={() => setNewKey(false)}
      />
      {approving && (
        <Takeover label={t("approve")}>
          <ApproveDevice
            keys={security.pairing}
            {...(security.findPairing ? { findPairing: security.findPairing } : {})}
            {...(security.scanSupported ? { scanSupported: security.scanSupported } : {})}
            onDone={() => {
              setApproving(false);
              changed();
            }}
          />
        </Takeover>
      )}
    </SettingsSection>
  );
}

type NewKeyStep =
  | { step: "confirm"; busy: boolean; keyError: KeyError | null; problem: Problem | null }
  | { step: "setup"; recoveryKey: string; commit(): Promise<void> }
  | { step: "saving" };

/**
 * "New recovery key" (spec 7.4's "ask again", stage 2b Ruling 1): the current recovery key, typed,
 * or a touch of one of the person's passkeys confirms it (a touch without PRF counts; a cancel does
 * not); then `RecoveryKeySetup` shows the new key, and `commit()` runs only after its four
 * characters are typed back.
 */
function NewRecoveryKeySheet({
  open,
  security,
  passkeyList,
  canTouch,
  onClose,
}: {
  open: boolean;
  security: SecurityApi;
  /** The touch is offered only once the list has loaded, and only when there are passkeys. */
  passkeyList: PasskeyList;
  canTouch: boolean;
  onClose(): void;
}) {
  const t = useTranslations("settings.security.new_key");
  const tUnlock = useTranslations("vault.unlock");
  const toast = useToast();
  const problemId = useId();
  const [text, setText] = useState("");
  const [step, setStep] = useState<NewKeyStep>({
    step: "confirm",
    busy: false,
    keyError: null,
    problem: null,
  });
  const passkeyIds = passkeyList.status === "ready" ? passkeyList.ids : null;
  const confirm = (patch: Partial<Extract<NewKeyStep, { step: "confirm" }>> = {}) =>
    setStep({ step: "confirm", busy: false, keyError: null, problem: null, ...patch });

  const close = () => {
    setText("");
    confirm();
    onClose();
  };

  async function make() {
    try {
      const prepared = await security.newRecoveryKey();
      setStep({ step: "setup", ...prepared });
    } catch (error) {
      confirm({ problem: problemOf(error) });
    }
  }

  async function withKey(event: React.FormEvent) {
    event.preventDefault();
    if (step.step !== "confirm" || step.busy || text.trim() === "") return;
    confirm({ busy: true });
    try {
      await security.checkRecoveryKey(text);
    } catch (error) {
      const keyError = keyErrorOf(error);
      confirm(keyError ? { keyError } : { problem: problemOf(error) });
      return;
    }
    await make();
  }

  async function withPasskey() {
    if (step.step !== "confirm" || step.busy || !passkeyIds?.length || !canTouch) return;
    confirm({ busy: true });
    try {
      const touched = await security.evaluatePrf([...passkeyIds]);
      if (!touched) {
        confirm();
        return;
      }
      // Only the touch confirms: the PRF itself is not needed here.
      touched.prf.fill(0);
    } catch (error) {
      // A completed touch without PRF confirms too (Ruling 2).
      if (codeOf(error) !== "no_prf") {
        confirm({ problem: problemOf(error) });
        return;
      }
    }
    await make();
  }

  async function save(commit: () => Promise<void>) {
    setStep({ step: "saving" });
    try {
      await commit();
    } catch (error) {
      confirm({ problem: problemOf(error) });
      return;
    }
    toast.show({ message: t("saved") });
    close();
  }

  if (step.step === "setup") {
    return (
      <Takeover label={t("title")}>
        <RecoveryKeySetup
          recoveryKey={step.recoveryKey}
          onContinue={() => void save(step.commit)}
          onCancel={close}
        />
      </Takeover>
    );
  }

  const busy = step.step === "saving" || step.busy;
  const asking = step.step === "confirm" ? step : null;
  return (
    <Sheet open={open} onClose={close} title={t("title")}>
      <form noValidate className="flex flex-col gap-(--space-4) pt-(--space-3)" onSubmit={withKey}>
        <p className="m-0 text-[15px] text-ink">{t("body")}</p>
        <RecoveryKeyField
          label={t("key_label")}
          value={text}
          onChange={(value) => {
            setText(value);
            if (asking?.keyError) confirm();
          }}
          error={asking?.keyError ?? null}
        />
        <PressButton
          type="submit"
          className="w-full"
          disabled={busy || text.trim() === ""}
          aria-busy={busy || undefined}
          aria-describedby={asking?.problem ? problemId : undefined}
        >
          {busy ? t("checking") : t("continue")}
        </PressButton>
        {canTouch && (passkeyList.status === "loading" || (passkeyIds?.length ?? 0) > 0) && (
          <PressButton
            variant="secondary"
            className="w-full"
            disabled={busy || passkeyIds === null}
            aria-busy={passkeyIds === null || undefined}
            onClick={() => void withPasskey()}
          >
            {t("passkey")}
          </PressButton>
        )}
        {passkeyList.status === "failed" && <PasskeyListFailed retry={passkeyList.retry} />}
        {asking?.problem && (
          <FieldError id={problemId}>
            {asking.problem === "offline"
              ? tUnlock("error_offline")
              : t(asking.problem === "rotated_elsewhere" ? "rotated_elsewhere" : "failed")}
          </FieldError>
        )}
      </form>
    </Sheet>
  );
}
