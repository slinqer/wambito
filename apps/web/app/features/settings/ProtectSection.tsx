import { useQuery, useQueryClient } from "@tanstack/react-query";
import { useId, useRef, useState } from "react";
import { useTranslations } from "use-intl";
import { FingerprintIcon } from "../../ui/FingerprintIcon.tsx";
import { Icon } from "../../ui/Icon.tsx";
import { PressButton } from "../../ui/PressButton.tsx";
import { useToast } from "../../ui/Toast.tsx";
import { FieldError } from "../sign-in/SignInScreen.tsx";
import { RecoveryKeySetup } from "../vault/RecoveryKeySetup.tsx";
import { PASSKEYS_KEY } from "./PasskeysSection.tsx";
import { SettingLabel, SettingsSection } from "./parts.tsx";
import type { PasskeysApi } from "./passkeys.ts";
import { protectStatus } from "./protect-model.ts";
import { Takeover } from "./RemoveDeviceSheet.tsx";
import { useRecoveryKeyStep } from "./recovery-key-step.ts";
import {
  protectSettingsKey,
  SECURITY_KEY,
  type SecurityApi,
  type SecuritySnapshot,
} from "./security.ts";
import { passkeyRows } from "./security-model.ts";

/**
 * "Protect your data" (spec 2026-11-15 section 5.2, Proton's recovery checklist): for an account
 * without an email (`isAnonymous`) at the top of Settings → Security. "N of 2" until the recovery
 * key or a passkey that opens the data is there, then a quiet list.
 * 1. "Save a recovery key": `newRecoveryKey()` with no check (web ruling 16: the open vault and the
 *    session are the proof), `RecoveryKeySetup`, `commit()` after the four characters (a failed
 *    commit may be saved: the setup stays, as in Security), then `markRecoveryKeySaved()`.
 * 2. "Add a passkey" (only where this browser can make one): the new passkey's PRF wraps the data
 *    key (`SecurityApi.addPasskeyWrap`). Done only when a passkey wrap exists; a passkey without one
 *    stays (it signs in) and the no-PRF line says so; a wrap that could not be saved says to try
 *    again with Turn on in Passkeys instead.
 * 3. "Create account (add an email)": `onAddEmail`; hidden without it.
 */
export function ProtectSection({
  security,
  passkeys,
  profile,
  onAddEmail,
}: {
  security: SecurityApi;
  passkeys: PasskeysApi;
  profile: { id: string; isAnonymous: boolean };
  onAddEmail?: (() => void) | undefined;
}) {
  const t = useTranslations("settings.protect");
  const tSecurity = useTranslations("settings.security");
  const tUnlock = useTranslations("vault.unlock");
  const tVault = useTranslations("vault");
  const qc = useQueryClient();
  const toast = useToast();
  const problemId = useId();
  const noPrfId = useId();
  const anonymous = profile.isAnonymous;
  const snapshot = useQuery({
    queryKey: SECURITY_KEY,
    queryFn: () => security.load(),
    enabled: anonymous,
  });
  const settings = useQuery({
    queryKey: protectSettingsKey(profile.id),
    queryFn: () => security.settings(),
    enabled: anonymous,
  });
  const list = useQuery({
    queryKey: PASSKEYS_KEY,
    queryFn: () => passkeys.list(),
    enabled: anonymous,
  });
  const [supported] = useState(() => passkeys.supported());
  const {
    key,
    start: makeKey,
    save: saveKey,
    cancel,
  } = useRecoveryKeyStep(security, async () => {
    toast.show({ message: t("recovery_saved") });
    void qc.invalidateQueries({ queryKey: SECURITY_KEY });
  });
  const [adding, setAdding] = useState(false);
  /** The last new passkey was made, but its wrap could not be saved (not a missing PRF). */
  const [linkFailed, setLinkFailed] = useState(false);
  const inFlight = useRef(false);

  const wraps = snapshot.data?.wraps;
  const status =
    snapshot.isSuccess && settings.isSuccess
      ? protectStatus({
          anonymous,
          recoveryKeySavedAt: settings.data?.recoveryKeySavedAt ?? null,
          passkeyWrap: (wraps ?? []).some((w) => w.kind === "passkey"),
          passkeyWithoutWrap: passkeyRows(list.data ?? [], wraps).some((p) => p.unlocks === false),
          passkeysSupported: supported,
        })
      : null;
  if (!anonymous || !status) return null;

  async function addPasskey() {
    if (inFlight.current) return;
    inFlight.current = true;
    setAdding(true);
    setLinkFailed(false);
    let keepFailed = false;
    try {
      const outcome = await passkeys.add({
        userId: profile.id,
        explainSecondTouch: () => toast.show({ message: tVault("passkey_second_touch") }),
        keep: async (passkey) => {
          try {
            await security.addPasskeyWrap(passkey);
          } catch (error) {
            keepFailed = true;
            throw error;
          }
        },
      });
      if (outcome === "failed") {
        toast.show({ tone: "error", message: t("passkey_failed") });
        return;
      }
      if (outcome !== "added") return;
      setLinkFailed(keepFailed);
      await Promise.all([
        qc.invalidateQueries({ queryKey: PASSKEYS_KEY }),
        qc.invalidateQueries({ queryKey: SECURITY_KEY }),
      ]);
      // Without PRF the passkey stays (it signs in) and the step's no-PRF line shows instead.
      const fresh = qc.getQueryData<SecuritySnapshot>(SECURITY_KEY);
      if (fresh?.wraps.some((w) => w.kind === "passkey")) {
        toast.show({ message: t("passkey_added") });
      }
    } finally {
      inFlight.current = false;
      setAdding(false);
    }
  }

  const doneMark = (
    <span className="flex flex-none items-center gap-(--space-1) text-[14px] font-bold text-ink">
      <Icon name="check" size={20} className="text-brand-glow" />
      {t("done")}
    </span>
  );
  const keyIdle = key.step === "idle" ? key : null;

  return (
    <SettingsSection title={t("title")} {...(status.show ? { lead: t("lead") } : {})}>
      {status.show && (
        <p className="m-0 text-[15px] font-bold text-ink">{t("count", { done: status.done })}</p>
      )}
      <ol aria-label={t("steps_label")} className="m-0 flex list-none flex-col gap-(--space-3) p-0">
        <li className="flex flex-col gap-(--space-2)">
          <div className="flex items-start justify-between gap-(--space-3)">
            <SettingLabel label={t("recovery_title")} hint={t("recovery_lead")} />
            {status.recoveryKey && doneMark}
          </div>
          {!status.recoveryKey && (
            <PressButton
              variant="secondary"
              className="self-start"
              disabled={keyIdle?.busy}
              aria-busy={keyIdle?.busy || undefined}
              aria-describedby={keyIdle?.problem ? problemId : undefined}
              onClick={() => void makeKey()}
            >
              {t("recovery_action")}
            </PressButton>
          )}
          {keyIdle?.problem && (
            <FieldError id={problemId}>
              {keyIdle.problem === "offline"
                ? tUnlock("error_offline")
                : t(
                    keyIdle.problem === "rotated_elsewhere"
                      ? "recovery_rotated"
                      : "recovery_failed",
                  )}
            </FieldError>
          )}
        </li>
        {status.passkeyOffered && (
          <li className="flex flex-col gap-(--space-2)">
            <div className="flex items-start justify-between gap-(--space-3)">
              <SettingLabel label={t("passkey_title")} hint={t("passkey_lead")} />
              {status.passkey && doneMark}
            </div>
            {!status.passkey && (
              <PressButton
                variant="secondary"
                className="self-start"
                disabled={adding}
                aria-busy={adding || undefined}
                aria-describedby={linkFailed || status.passkeyWithoutPrf ? noPrfId : undefined}
                onClick={() => void addPasskey()}
              >
                <FingerprintIcon />
                {adding ? t("passkey_adding") : t("passkey_action")}
              </PressButton>
            )}
            {!status.passkey && (linkFailed || status.passkeyWithoutPrf) && (
              <p id={noPrfId} className="m-0 text-[14px] text-over">
                {t(linkFailed ? "link_failed" : "no_prf")}
              </p>
            )}
          </li>
        )}
        {onAddEmail && (
          <li className="flex flex-col gap-(--space-2)">
            <SettingLabel label={t("email_title")} hint={t("email_lead")} />
            <PressButton variant="secondary" className="self-start" onClick={onAddEmail}>
              {t("email_action")}
            </PressButton>
          </li>
        )}
      </ol>
      {key.step === "setup" && (
        <Takeover label={t("recovery_action")}>
          <RecoveryKeySetup
            recoveryKey={key.recoveryKey}
            busy={key.saving}
            problem={key.failed ? tSecurity("maybe_saved") : null}
            onContinue={() => void saveKey(key)}
            {...(key.failed ? {} : { onCancel: cancel })}
          />
        </Takeover>
      )}
    </SettingsSection>
  );
}
