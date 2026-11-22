import { useMemo, useState } from "react";
import { Link } from "react-router";
import { useTranslations } from "use-intl";
import { useApi, useApiMode } from "../../api/ApiProvider.tsx";
import { useMe } from "../../api/queries.ts";
import { useLocale } from "../../i18n/IntlProvider.tsx";
import { useTheme } from "../../theme/ThemeProvider.tsx";
import { BrandLogo } from "../../ui/BrandLogo.tsx";
import { Icon } from "../../ui/Icon.tsx";
import { PageHeader } from "../../ui/PageHeader.tsx";
import { ManageFrame } from "../categories/CategoryDetail.tsx";
import { useAppPath } from "../home/app-path.ts";
import { AddEmail } from "./AddEmail.tsx";
import { claimEmail } from "./add-email.ts";
import { ProtectSection } from "./ProtectSection.tsx";
import { livePasskeys, type PasskeysApi } from "./passkeys.ts";
import { Takeover } from "./RemoveDeviceSheet.tsx";
import { useSettingsSecurity } from "./Settings.tsx";
import type { SecurityApi } from "./security.ts";
import { type SettingsCategory, settingsCategories } from "./settings-categories.ts";

/** The four apps Wambito works with, in the "Mis agentes" tile (two by two). */
function AgentsTile() {
  return (
    <span className="lk-menutile-quad" aria-hidden="true">
      {(["chatgpt", "claude", "lumo", "grok"] as const).map((name) => (
        <BrandLogo key={name} name={name} size={13} />
      ))}
    </span>
  );
}

function CategoryIcon({ category }: { category: SettingsCategory }) {
  switch (category) {
    case "agents":
      return <AgentsTile />;
    case "account":
      return <Icon name="shield" size={22} />;
    case "preferences":
      return <Icon name="sliders" size={22} />;
    case "data":
      return <Icon name="folder" size={22} />;
    case "more":
      return <Icon name="info" size={22} />;
  }
}

/** One row of the menu: a 40 px icon tile, the category's name and line, a chevron. */
function SettingsMenuRow({
  to,
  icon,
  title,
  line,
}: {
  to: string;
  icon: React.ReactNode;
  title: string;
  line: string;
}) {
  return (
    <Link to={to} className="lk-rowcard lk-menurow">
      <span className="lk-menutile" aria-hidden="true">
        {icon}
      </span>
      <span className="lk-rowmain">
        <span className="lk-menurow-title">{title}</span>
        <span className="lk-menurow-line">{line}</span>
      </span>
      <span className="lk-menurow-chevron" aria-hidden="true">
        <Icon name="chevron-right" size={16} />
      </span>
    </Link>
  );
}

export interface SettingsMenuProps {
  /** Better Auth's passkeys by default; stories stand in for them. */
  passkeys?: PasskeysApi;
  /** An encrypted account's keys (Protect); the open vault's by default, stories stand in. */
  security?: SecurityApi;
  /** Stands in for "Protect your data"'s "Create account (add an email)"; opens `AddEmail` by default. */
  onAddEmail?: () => void;
}

/**
 * The settings menu (`/app/settings`, `/demo/settings`): "Protect your data" (an account without an
 * email) above one row per category, each on its own URL. Preferences' line is live: the language,
 * the theme and the currency now in use.
 */
export function SettingsMenu({
  passkeys = livePasskeys,
  security: securityProp,
  onAddEmail,
}: SettingsMenuProps) {
  const t = useTranslations("settings");
  const tRoot = useTranslations();
  const tManage = useTranslations("manage");
  const me = useMe().data;
  if (!me) throw new Error("Settings renders inside AppShell, which waits for the profile");
  const appPath = useAppPath();
  const demo = useApiMode() === "demo";
  const { locale } = useLocale();
  const { pref } = useTheme();
  const security = useSettingsSecurity(securityProp);
  const api = useApi();
  const claim = useMemo(() => claimEmail(api), [api]);
  const [addingEmail, setAddingEmail] = useState(false);

  const lineOf = (category: SettingsCategory) =>
    category === "preferences"
      ? t("menu.preferences.line", {
          language: tRoot(`language.${locale}`),
          theme: tRoot(`theme.${pref}`),
          currency: me.currency,
        })
      : t(`menu.${category}.line`);

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
        {security && me.isAnonymous && (
          // An account without an email: its checklist first (spec 2026-11-15 section 5.2).
          <ProtectSection
            security={security}
            passkeys={passkeys}
            profile={me}
            onAddEmail={onAddEmail ?? (() => setAddingEmail(true))}
          />
        )}
        <nav aria-label={t("title")} className="flex flex-col gap-(--space-2)">
          {settingsCategories().map((category) => (
            <SettingsMenuRow
              key={category}
              to={appPath(`/settings/${category}`)}
              icon={<CategoryIcon category={category} />}
              title={t(`menu.${category}.title`)}
              line={lineOf(category)}
            />
          ))}
        </nav>
        {addingEmail && (
          <Takeover label={t("add_email.title")}>
            <AddEmail
              claim={claim}
              security={security ?? undefined}
              onDone={() => setAddingEmail(false)}
            />
          </Takeover>
        )}
      </main>
    </ManageFrame>
  );
}
