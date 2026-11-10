import { useId, useMemo } from "react";
import { useTranslations } from "use-intl";
import { useApiMode } from "../../api/ApiProvider.tsx";
import { useMe } from "../../api/queries.ts";
import { PageHeader } from "../../ui/PageHeader.tsx";
import { PressButton } from "../../ui/PressButton.tsx";
import { PressLink } from "../../ui/PressLink.tsx";
import { AssistantsSection, type CopyText } from "../assistants/AssistantsSection.tsx";
import { ManageFrame } from "../categories/CategoryDetail.tsx";
import { useAppPath } from "../home/app-path.ts";
import { liveSignOut, type SignOutRequest } from "../home/use-sign-out.ts";
import { useVaultSession } from "../vault/vault-context.ts";
import { DeleteAccount } from "./DeleteAccount.tsx";
import { FeedbackSection } from "./FeedbackSection.tsx";
import { PasskeysSection } from "./PasskeysSection.tsx";
import { PreferencesSection } from "./PreferencesSection.tsx";
import { DemoOffNote, SettingLabel, SettingsSection } from "./parts.tsx";
import { livePasskeys, type PasskeysApi } from "./passkeys.ts";
import { SecuritySection } from "./SecuritySection.tsx";
import { liveSecurity, type SecurityApi } from "./security.ts";
import { TimeAndMoneySection } from "./TimeAndMoneySection.tsx";
import { type SaveFile, saveToDisk, useExport } from "./use-export.ts";

export type { SaveFile } from "./use-export.ts";

export interface SettingsProps {
  /** Better Auth's passkeys by default; stories stand in for them. */
  passkeys?: PasskeysApi;
  /** Ends the session after the account is deleted; Better Auth's by default. */
  signOut?: SignOutRequest;
  /** Where downloads go; the browser's by default. */
  save?: SaveFile;
  /** Copies the assistants' address; the browser's clipboard by default. */
  copy?: CopyText;
  /** An encrypted account's keys (Security); the open vault's by default, stories stand in. */
  security?: SecurityApi;
}

/**
 * Settings (`/app/settings`, spec §2.7): language, theme and sound; time zone, and the currency
 * while it can still change; passkeys; import from Budge and the export; "Conecta tu asistente"
 * (the MCP's address, and the assistants let in); comments and ideas (an
 * email to the founder); and deleting the account. Reached from the avatar menu (phones) and the sidebar (wide screens). In the demo
 * (`/demo/settings`, spec §2.6b) passkeys, import, export and deleting the account are off, each
 * with a note: there is no account behind them. "Conecta tu asistente" keeps its address and
 * steps there, and lists nothing. A preview account (`local` mode) has import, export and the
 * assistants' list off with a "not available yet" note; passkeys and deleting the account work,
 * and Security lists the devices that open the data (not for a guest, who has no recovery key).
 */
export function Settings({
  passkeys = livePasskeys,
  signOut = liveSignOut,
  save = saveToDisk,
  copy,
  security: securityProp,
}: SettingsProps) {
  const t = useTranslations("settings");
  const tManage = useTranslations("manage");
  const me = useMe().data;
  if (!me) throw new Error("Settings renders inside AppShell, which waits for the profile");
  const exporter = useExport(save);
  const appPath = useAppPath();
  const mode = useApiMode();
  const demo = mode === "demo";
  // A preview account's vault: no export, import or assistants yet (passkeys and deleting the
  // account work: they are the account's, not its finances).
  const local = mode === "local";
  const session = useVaultSession();
  const vaultSecurity = useMemo(() => (session ? liveSecurity(session) : null), [session]);
  // An encrypted account's devices and keys. A guest (Ruling 8: no recovery key) gets only
  // "Approve a new device", so its other device has somewhere to approve a pairing.
  const vaultKeys = local ? (securityProp ?? vaultSecurity) : null;
  const security = me.isAnonymous ? null : vaultKeys;
  const dataOffId = useId();
  const assistantsOffId = useId();
  const dataOff = demo || local ? dataOffId : undefined;

  return (
    <ManageFrame>
      <PageHeader back={{ to: appPath(), label: tManage("back"), short: tManage("back_short") }} />
      <main className="flex flex-col gap-(--space-4) pb-(--space-4)">
        <div className="flex flex-col gap-(--space-1)">
          <h1 className="m-0 font-display text-[28px] font-bold text-ink">{t("title")}</h1>
          <p className="m-0 break-all text-[14px] text-ink-muted">
            {/* The demo has no sign-in: say whose made-up account this is. */}
            {demo ? t("demo_viewing") : t("signed_in_as", { email: me.email })}
          </p>
        </div>
        <PreferencesSection />
        <TimeAndMoneySection me={me} />
        <PasskeysSection
          passkeys={passkeys}
          timeZone={me.timezone}
          off={demo}
          vaultUserId={local ? me.id : undefined}
          security={security ?? undefined}
        />
        {vaultKeys && (
          <SecuritySection
            security={vaultKeys}
            passkeys={passkeys}
            timeZone={me.timezone}
            guest={me.isAnonymous}
          />
        )}
        <SettingsSection title={t("data.title")}>
          <div className="flex flex-col gap-(--space-2)">
            <SettingLabel label={t("data.import_title")} hint={t("data.import_lead")} />
            {demo || local ? (
              <PressButton
                variant="secondary"
                className="self-start"
                disabled
                aria-describedby={dataOff}
              >
                {t("data.import_action")}
              </PressButton>
            ) : (
              <PressLink to={appPath("/import")} variant="secondary" className="self-start">
                {t("data.import_action")}
              </PressLink>
            )}
          </div>
          <div className="flex flex-col gap-(--space-2)">
            <SettingLabel label={t("data.export_title")} hint={t("data.export_lead")} />
            <div className="flex flex-wrap gap-(--space-2)">
              {(["json", "csv"] as const).map((format) => (
                <PressButton
                  key={format}
                  variant="secondary"
                  disabled={demo || local || exporter.busy !== null}
                  aria-describedby={dataOff}
                  aria-busy={exporter.busy === format || undefined}
                  onClick={() => void exporter.run(format)}
                >
                  {t(format === "json" ? "data.export_json" : "data.export_csv")}
                </PressButton>
              ))}
            </div>
          </div>
          {(demo || local) && <DemoOffNote id={dataOffId} local={local} />}
        </SettingsSection>
        <AssistantsSection
          timeZone={me.timezone}
          off={demo || local}
          offNote={local ? <DemoOffNote id={assistantsOffId} local /> : undefined}
          {...(copy ? { copy } : {})}
        />
        <FeedbackSection />
        <DeleteAccount
          email={me.email}
          signOut={signOut}
          onExport={(format) => void exporter.run(format)}
          exporting={exporter.busy !== null}
          off={demo}
          canExport={!local}
        />
      </main>
    </ManageFrame>
  );
}
