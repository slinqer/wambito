import { type ReactNode, useEffect } from "react";
import { useLocation } from "react-router";
import { useMe } from "../../api/queries.ts";
import { isLocale } from "../../i18n/format.ts";
import { useLocale } from "../../i18n/IntlProvider.tsx";
import { BottomBar } from "../../ui/BottomBar.tsx";
import { Sidebar } from "../../ui/Sidebar.tsx";
import {
  TransactionSheetProvider,
  useTransactionSheet,
} from "../add-transaction/TransactionSheetProvider.tsx";
import { useAppPath } from "./app-path.ts";

const SECTIONS = new Set(["search", "insights", "recurring", "categories", "settings"]);

/**
 * The navigation's section for a path: `/app/categories/…` is Categorías, and so on. The demo's
 * copy of the screens (`/demo/…`) has the same sections.
 */
export function sectionOf(pathname: string): string {
  const [, app, section = ""] = pathname.split("/");
  return (app === "app" || app === "demo") && SECTIONS.has(section) ? section : "home";
}

function Frame({ banner, children }: { banner?: ReactNode; children: ReactNode }) {
  const { openAdd } = useTransactionSheet();
  const current = sectionOf(useLocation().pathname);
  const base = useAppPath()();
  return (
    <div className="lk-screen lk-app-shell flex min-h-dvh">
      <div className="sticky top-0 hidden h-dvh flex-none lg:flex">
        <Sidebar current={current} onAdd={() => openAdd()} base={base} />
      </div>
      <div className="min-w-0 flex-1 pb-[calc(112px+env(safe-area-inset-bottom))] lg:pb-(--space-6)">
        {banner}
        {children}
      </div>
      <div className="fixed inset-x-0 bottom-0 z-30 pb-[env(safe-area-inset-bottom)] lg:hidden">
        <BottomBar current={current} onAdd={() => openAdd()} base={base} />
      </div>
    </div>
  );
}

/**
 * The frame of the signed-in app (`/app/*`, and the demo's `/demo/*`): the bottom bar on phones
 * (Inicio · ＋ · Análisis), the sidebar on wide screens, and the add/edit sheet both open. It
 * waits for the profile (its currency and time zone drive every screen) and speaks the profile's
 * language. `banner` sits above every screen, beside the sidebar (the demo's notice).
 */
export function AppShell({ banner, children }: { banner?: ReactNode; children: ReactNode }) {
  const me = useMe();
  const { locale, setLocale } = useLocale();
  const profileLocale = me.data?.locale;
  useEffect(() => {
    if (isLocale(profileLocale) && profileLocale !== locale) {
      setLocale(profileLocale);
    }
  }, [profileLocale, locale, setLocale]);

  if (me.error && !me.data) throw me.error;
  if (!me.data) return <div className="lk-screen min-h-dvh" aria-busy="true" />;
  return (
    <TransactionSheetProvider currency={me.data.currency} timezone={me.data.timezone}>
      <Frame banner={banner}>{children}</Frame>
    </TransactionSheetProvider>
  );
}
