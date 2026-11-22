import { useMemo } from "react";
import { useTranslations } from "use-intl";
import { useApiMode } from "../../api/ApiProvider.tsx";
import { useMe } from "../../api/queries.ts";
import { PageHeader } from "../../ui/PageHeader.tsx";
import { AgentsScreen, type CopyText } from "../assistants/AgentsScreen.tsx";
import { ManageFrame } from "../categories/CategoryDetail.tsx";
import { useAppPath } from "../home/app-path.ts";
import { liveSignOut, type SignOutRequest } from "../home/use-sign-out.ts";
import { useVaultSession } from "../vault/vault-context.ts";
import { AccountScreen } from "./AccountScreen.tsx";
import { DataScreen } from "./DataScreen.tsx";
import { MoreScreen } from "./MoreScreen.tsx";
import { PreferencesScreen } from "./PreferencesScreen.tsx";
import { livePasskeys, type PasskeysApi } from "./passkeys.ts";
import { liveSecurity, type SecurityApi } from "./security.ts";
import { isSettingsCategory, type SettingsCategory } from "./settings-categories.ts";
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
  /** Where "Mis agentes" says the web is served; the page's own origin by default (stories pin it). */
  agentsOrigin?: string;
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

/** The body of one category's page: the screen that category owns (agents, account, preferences, data, more). */
export function SettingsCategoryBody({
  category,
  passkeys = livePasskeys,
  signOut = liveSignOut,
  save = saveToDisk,
  copy,
  security: securityProp,
  agentsOrigin,
}: SettingsProps & { category: SettingsCategory }) {
  const me = useMe().data;
  if (!me) throw new Error("Settings renders inside AppShell, which waits for the profile");
  const exporter = useExport(save);
  const security = useSettingsSecurity(securityProp);

  switch (category) {
    case "agents":
      return (
        <AgentsScreen
          timeZone={me.timezone}
          {...(copy ? { copy } : {})}
          {...(agentsOrigin ? { origin: agentsOrigin } : {})}
        />
      );
    case "account":
      return (
        <AccountScreen
          passkeys={passkeys}
          security={security}
          signOut={signOut}
          onExport={(format) => void exporter.run(format)}
          exporting={exporter.busy !== null}
        />
      );
    case "preferences":
      return <PreferencesScreen me={me} />;
    case "data":
      return <DataScreen onExport={(format) => exporter.run(format)} exporting={exporter.busy} />;
    case "more":
      return <MoreScreen />;
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
