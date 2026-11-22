import { useId, useMemo } from "react";
import { useTranslations } from "use-intl";
import { useApiMode } from "../../api/ApiProvider.tsx";
import { useMe } from "../../api/queries.ts";
import { PageHeader } from "../../ui/PageHeader.tsx";
import { PressButton } from "../../ui/PressButton.tsx";
import { PressLink } from "../../ui/PressLink.tsx";
import { AgentsScreen, type CopyText } from "../assistants/AgentsScreen.tsx";
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
import { isSettingsCategory, type SettingsCategory } from "./settings-categories.ts";
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
  /**
   * Stands in for "Protect your data"'s step 3, "Create account (add an email)", which opens
   * `AddEmail` on the menu by default; stories use it to watch the tap.
   */
  onAddEmail?: () => void;
}

/**
 * An encrypted account's devices and keys (every one, an anonymous account made by the phone too):
 * the `security` prop (stories) or the open vault's, only in mode `local`; null elsewhere.
 */
export function useSettingsSecurity(securityProp?: SecurityApi): SecurityApi | null {
  const local = useApiMode() === "local";
  const session = useVaultSession();
  const vaultSecurity = useMemo(() => (session ? liveSecurity(session) : null), [session]);
  return local ? (securityProp ?? vaultSecurity) : null;
}

/** The cards of one category (what its page holds; later tasks redraw them one by one). */
export function SettingsCategoryBody({
  category,
  passkeys = livePasskeys,
  signOut = liveSignOut,
  save = saveToDisk,
  copy,
  security: securityProp,
}: SettingsProps & { category: SettingsCategory }) {
  const t = useTranslations("settings");
  const me = useMe().data;
  if (!me) throw new Error("Settings renders inside AppShell, which waits for the profile");
  const exporter = useExport(save);
  const appPath = useAppPath();
  const mode = useApiMode();
  const demo = mode === "demo";
  // A preview account's vault: no export or import yet (passkeys, the assistants and deleting
  // the account work: they are the account's, not its finances).
  const local = mode === "local";
  const security = useSettingsSecurity(securityProp);
  const dataOffId = useId();
  const dataOff = demo || local ? dataOffId : undefined;

  switch (category) {
    case "agents":
      return <AgentsScreen timeZone={me.timezone} {...(copy ? { copy } : {})} />;
    case "account":
      return (
        <>
          <PasskeysSection
            passkeys={passkeys}
            timeZone={me.timezone}
            off={demo}
            vaultUserId={local ? me.id : undefined}
            security={security ?? undefined}
          />
          {security && (
            <SecuritySection security={security} passkeys={passkeys} timeZone={me.timezone} />
          )}
          <DeleteAccount
            email={me.email}
            {...(demo ? {} : { userId: me.id })}
            signOut={signOut}
            onExport={(format) => void exporter.run(format)}
            exporting={exporter.busy !== null}
            off={demo}
            canExport={!local}
          />
        </>
      );
    case "preferences":
      return (
        <>
          <PreferencesSection />
          <TimeAndMoneySection me={me} />
        </>
      );
    case "data":
      return (
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
      );
    case "more":
      return <FeedbackSection />;
  }
}

/**
 * One category's page (`/app/settings/:category`, `/demo/settings/:category`): a back link to the
 * menu, the category's name and its cards. In the demo passkeys, import, export and deleting the
 * account are off, each with a note; a preview account (`local` mode) has import and export off.
 * An unknown category is the page's own "not found", with the way back to the menu.
 */
export function SettingsCategoryScreen({
  category,
  ...props
}: SettingsProps & { category: string }) {
  const t = useTranslations("settings");
  const appPath = useAppPath();
  const back = { to: appPath("/settings"), label: t("menu.back"), short: t("menu.back_short") };
  if (!isSettingsCategory(category)) {
    return (
      <ManageFrame>
        <PageHeader back={back} />
        <main className="lk-hero flex flex-col gap-(--space-2)">
          <h1 className="m-0 font-display text-[22px] font-bold text-ink">
            {t("menu.not_found_title")}
          </h1>
          <p className="m-0 text-[14px] font-bold text-ink-muted">{t("menu.not_found_lead")}</p>
        </main>
      </ManageFrame>
    );
  }
  return (
    <ManageFrame>
      <PageHeader back={back} />
      <main className="flex flex-col gap-(--space-4) pb-(--space-4)">
        <h1 className="m-0 font-display text-[28px] font-bold text-ink">
          {t(`menu.${category}.title`)}
        </h1>
        <SettingsCategoryBody category={category} {...props} />
      </main>
    </ManageFrame>
  );
}
