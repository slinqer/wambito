import { useQuery, useQueryClient } from "@tanstack/react-query";
import { useId, useState } from "react";
import { useTranslations } from "use-intl";
import { useLocale } from "../../i18n/IntlProvider.tsx";
import { Icon } from "../../ui/Icon.tsx";
import { PressButton } from "../../ui/PressButton.tsx";
import { Sheet } from "../../ui/Sheet.tsx";
import { useToast } from "../../ui/Toast.tsx";
import { FieldError } from "../sign-in/SignInScreen.tsx";
import { ApproveDevice } from "../vault/ApproveDevice.tsx";
import { RecoveryKeySetup } from "../vault/RecoveryKeySetup.tsx";
import { formatDay, PASSKEYS_KEY } from "./PasskeysSection.tsx";
import { SettingsGroup, SettingsRow } from "./parts.tsx";
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
import { changeKeys, codeOf, SECURITY_KEY, type SecurityApi } from "./security.ts";
import { type DeviceRow, deviceIconName, deviceRows } from "./security-model.ts";

/**
 * Cuenta y seguridad's encrypted part (mode `local`), as light rows: a "Tus dispositivos" group
 * (this browser with the "Este" chip, the others with a trash button that opens `RemoveDeviceSheet`:
 * the wrap goes, the keys stay; "Conectar otro dispositivo" opens `ApproveDevice`; the unreadable
 * count when above 0) and a group with "Clave de recuperación" (confirmed by the current key or a
 * passkey touch, then `RecoveryKeySetup`) and "Cambiar claves" (a rotation that removes no device,
 * typed recovery key; it disconnects assistants).
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
  const toast = useToast();
  const snapshot = useQuery({
    queryKey: SECURITY_KEY,
    queryFn: () => security.load(),
  });
  const passkeyList = useQuery({
    queryKey: PASSKEYS_KEY,
    queryFn: () => passkeys.list(),
  });
  const [canTouch] = useState(() => passkeys.supported());
  const [removing, setRemoving] = useState<DeviceRow | null>(null);
  const [approving, setApproving] = useState(false);
  const [newKey, setNewKey] = useState(false);
  const [changing, setChanging] = useState(false);

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
    const line = [
      added ? t("added", { date: added }) : null,
      row.verified ? null : t("not_verified"),
    ]
      .filter(Boolean)
      .join(" · ");
    return (
      <SettingsRow
        key={row.id}
        icon={<Icon name={deviceIconName(row.label)} size={20} />}
        title={name}
        {...(line ? { line } : {})}
        trailing={
          row.thisBrowser
            ? { kind: "chip", text: t("this_browser") }
            : row.removable
              ? {
                  kind: "trash",
                  label: t("remove_label", { name }),
                  onPress: () => setRemoving(row),
                }
              : { kind: "none" }
        }
      />
    );
  };

  return (
    <>
      <SettingsGroup
        head={{ icon: <Icon name="phone" size={22} />, title: t("title"), line: t("lead") }}
      >
        {snapshot.isError && (
          <p className="m-0 px-(--space-1) py-(--space-2) text-[14px] text-ink-muted">
            {t("load_failed")}
          </p>
        )}
        {rows?.thisBrowser && deviceItem(rows.thisBrowser)}
        {rows?.others.map(deviceItem)}
        <SettingsRow
          icon={<Icon name="plus" size={20} />}
          title={t("connect")}
          trailing={{ kind: "none" }}
          onPress={() => setApproving(true)}
        />
        {unreadable > 0 && (
          <p className="m-0 px-(--space-1) py-(--space-2) text-[13px] text-ink-muted">
            {t("unreadable", { count: unreadable })}. {t("unreadable_lead")}
          </p>
        )}
      </SettingsGroup>
      <SettingsGroup>
        <SettingsRow
          icon={<Icon name="key" size={20} />}
          title={t("recovery_title")}
          line={t("recovery_line")}
          trailing={{ kind: "chevron" }}
          onPress={() => setNewKey(true)}
        />
        <SettingsRow
          icon={<Icon name="key" size={20} />}
          title={t("change_keys")}
          line={t("change_keys_line")}
          trailing={{ kind: "chevron" }}
          onPress={() => setChanging(true)}
        />
      </SettingsGroup>
      {approving && (
        <Takeover label={t("connect")}>
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
      <RemoveDeviceSheet
        device={removing}
        security={security}
        onClose={() => setRemoving(null)}
        onRemoved={(row) => {
          changed();
          toast.show({ message: t("removed_done", { name: row.label ?? t("unnamed") }) });
        }}
      />
      <ChangeKeysSheet
        open={changing}
        security={security}
        onClose={() => setChanging(false)}
        onChanged={changed}
      />
      <NewRecoveryKeySheet
        open={newKey}
        security={security}
        passkeyList={known}
        canTouch={canTouch}
        onClose={() => setNewKey(false)}
        onChanged={changed}
      />
    </>
  );
}

type NewKeyStep =
  | { step: "confirm"; busy: boolean; keyError: KeyError | null; problem: Problem | null }
  | {
      step: "setup";
      recoveryKey: string;
      commit(): Promise<void>;
      saving: boolean;
      /** A commit failed: the key may be saved, so it stays on screen (no Cancel) until done. */
      failed: boolean;
    };

/**
 * "New recovery key" (spec 7.4's "ask again", stage 2b Ruling 1): the current recovery key, typed,
 * or a touch of one of the person's passkeys confirms it (a touch without PRF counts; a cancel does
 * not); an account with no passkeys can also make one without the old key (the four characters
 * typed back are the confirmation), while one with passkeys this browser cannot touch needs the
 * typed key. Then `RecoveryKeySetup` shows the new key, and `commit()` runs only after its four
 * characters are typed back. A failed commit may have been saved: the setup stays, says so, and
 * Continue commits the same key again; only `rotated_elsewhere` (refused for sure) starts over,
 * with the keys and the list read again.
 */
function NewRecoveryKeySheet({
  open,
  security,
  passkeyList,
  canTouch,
  onClose,
  onChanged,
}: {
  open: boolean;
  security: SecurityApi;
  /** The touch is offered only once the list has loaded, and only when there are passkeys. */
  passkeyList: PasskeyList;
  canTouch: boolean;
  onClose(): void;
  /** The account's keys changed (or may have): read them again. */
  onChanged(): void;
}) {
  const t = useTranslations("settings.security.new_key");
  const tSecurity = useTranslations("settings.security");
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
  /** No passkeys at all: nothing else could confirm it, so the type-back does. */
  const plain = passkeyIds !== null && passkeyIds.length === 0;
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
      setStep({ step: "setup", ...prepared, saving: false, failed: false });
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

  async function withoutKey() {
    if (step.step !== "confirm" || step.busy || !plain) return;
    confirm({ busy: true });
    await make();
  }

  async function save(setup: Extract<NewKeyStep, { step: "setup" }>) {
    if (setup.saving) return;
    setStep({ ...setup, saving: true });
    try {
      await setup.commit();
    } catch (error) {
      if (problemOf(error) === "rotated_elsewhere") {
        // Refused for sure: the sync picks up the other device's keys, the list follows.
        void security.reloadKeys().catch(() => {});
        onChanged();
        confirm({ problem: "rotated_elsewhere" });
      } else {
        setStep({ ...setup, saving: false, failed: true });
      }
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
          busy={step.saving}
          problem={step.failed ? tSecurity("maybe_saved") : null}
          onContinue={() => void save(step)}
          {...(step.failed ? {} : { onCancel: close })}
        />
      </Takeover>
    );
  }

  const busy = step.busy;
  const asking = step.step === "confirm" ? step : null;
  return (
    <Sheet open={open} onClose={close} title={t("title")}>
      <form noValidate className="flex flex-col gap-(--space-4) pt-(--space-3)" onSubmit={withKey}>
        <p className="m-0 text-[15px] text-ink">{tSecurity("recovery_lead")}</p>
        <p className="m-0 text-[15px] text-ink">
          {t(plain ? "body_no_passkeys" : canTouch ? "body" : "body_no_touch")}
        </p>
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
        {plain && (
          <PressButton
            variant="ghost"
            className="w-full"
            disabled={busy}
            onClick={() => void withoutKey()}
          >
            {t("plain")}
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

/**
 * "Change keys": a rotation that removes no device. The typed recovery key confirms it (nothing
 * new to write down); the person's devices keep working and every connected assistant is
 * disconnected. A key the sheet cannot trust, or another device rotating first, is said on the
 * sheet, as when removing a device.
 */
function ChangeKeysSheet({
  open,
  security,
  onClose,
  onChanged,
}: {
  open: boolean;
  security: SecurityApi;
  onClose(): void;
  /** The account's keys changed (or may have): read them again. */
  onChanged(): void;
}) {
  const t = useTranslations("settings.security");
  const tSheet = useTranslations("settings.security.remove_sheet");
  const tUnlock = useTranslations("vault.unlock");
  const toast = useToast();
  const problemId = useId();
  const [text, setText] = useState("");
  const [busy, setBusy] = useState(false);
  const [keyError, setKeyError] = useState<KeyError | null>(null);
  const [problem, setProblem] = useState<Problem | null>(null);

  const close = () => {
    setText("");
    setBusy(false);
    setKeyError(null);
    setProblem(null);
    onClose();
  };

  async function submit(event: React.FormEvent) {
    event.preventDefault();
    if (busy || text.trim() === "") return;
    setBusy(true);
    setKeyError(null);
    setProblem(null);
    try {
      await changeKeys(security, text);
    } catch (error) {
      setBusy(false);
      const typed = keyErrorOf(error);
      if (typed) {
        setKeyError(typed);
        return;
      }
      const found = problemOf(error);
      if (found === "rotated_elsewhere") {
        // The sync picks up the other device's keys; the list follows.
        void security.reloadKeys().catch(() => {});
        onChanged();
      }
      setProblem(found);
      return;
    }
    onChanged();
    toast.show({ message: t("change_keys_done") });
    close();
  }

  return (
    <Sheet open={open} onClose={close} title={t("change_keys")}>
      <form noValidate className="flex flex-col gap-(--space-4) pt-(--space-3)" onSubmit={submit}>
        <p className="m-0 text-[15px] text-ink">{t("change_keys_body")}</p>
        <RecoveryKeyField
          label={tSheet("key_label")}
          value={text}
          onChange={(value) => {
            setText(value);
            if (keyError) setKeyError(null);
          }}
          error={keyError}
        />
        <PressButton
          type="submit"
          className="w-full"
          disabled={busy || text.trim() === ""}
          aria-busy={busy || undefined}
          aria-describedby={problem ? problemId : undefined}
        >
          {busy ? t("changing") : t("change_keys")}
        </PressButton>
        {problem && (
          <FieldError id={problemId}>
            {problem === "offline"
              ? tUnlock("error_offline")
              : problem === "rotated_elsewhere"
                ? tSheet("rotated_elsewhere")
                : t("change_keys_failed")}
          </FieldError>
        )}
      </form>
    </Sheet>
  );
}
