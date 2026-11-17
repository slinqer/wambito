import type { Month } from "@wambito/core";
import { useEffect, useId, useRef, useState } from "react";
import { Link } from "react-router";
import { useTranslations } from "use-intl";
import { useApiMode } from "../../api/ApiProvider.tsx";
import { useLocale } from "../../i18n/IntlProvider.tsx";
import { LANDING_PATH } from "../../site/paths.ts";
import { Icon } from "../../ui/Icon.tsx";
import { MonthPicker } from "../../ui/MonthPicker.tsx";
import { PressButton } from "../../ui/PressButton.tsx";
import { PressLink } from "../../ui/PressLink.tsx";
import { ThemeToggle } from "../../ui/ThemeToggle.tsx";
import { useAppPath } from "./app-path.ts";
import { SHOW_CATEGORIES } from "./home-storage.ts";
import { type SignOutRequest, useSignOut } from "./use-sign-out.ts";

export interface HomeHeaderProps {
  month: Month;
  onMonth(month: Month): void;
  /** The current month in the person's time zone: the latest one to show. */
  max: Month;
  /** Ends the session (stories pass a stand-in); Better Auth's by default. */
  signOut?: SignOutRequest | undefined;
}

/** Sections that live in the avatar menu (on phones, the only way there). */
const SECTIONS = [
  { key: "recurring", to: "/recurring" },
  // Categories are managed in home's Categorías tab: the link opens home on it.
  { key: "categories", to: "", state: SHOW_CATEGORIES },
  { key: "settings", to: "/settings" },
] as const;

/**
 * Home's header, one row: the month (previous months browsable) on the left; the magnifier and the
 * account button on the right, which opens the avatar menu with
 * the day/night switch, Recurrentes, Categorías and Ajustes, and sign-out (in the demo, "Salir del
 * demo", back to the landing: there is no session to end). The menu is a disclosure: its
 * button says whether it is open, Escape or a tap outside closes it and gives focus back.
 */
export function HomeHeader({ month, onMonth, max, signOut: request }: HomeHeaderProps) {
  const t = useTranslations();
  const [open, setOpen] = useState(false);
  const menuId = useId();
  const button = useRef<HTMLButtonElement>(null);
  const panel = useRef<HTMLDivElement>(null);
  const signOut = useSignOut(request);
  const appPath = useAppPath();
  const demo = useApiMode() === "demo";
  const { locale } = useLocale();

  useEffect(() => {
    if (!open) return;
    const onKey = (event: KeyboardEvent) => {
      if (event.key !== "Escape") return;
      setOpen(false);
      button.current?.focus();
    };
    const onPointer = (event: PointerEvent) => {
      const target = event.target as Node;
      if (!panel.current?.contains(target) && !button.current?.contains(target)) setOpen(false);
    };
    document.addEventListener("keydown", onKey);
    document.addEventListener("pointerdown", onPointer);
    return () => {
      document.removeEventListener("keydown", onKey);
      document.removeEventListener("pointerdown", onPointer);
    };
  }, [open]);

  return (
    // No wordmark: the app's icon already says where you are, and without it the month and the two
    // buttons fit one row down to 320px.
    <header className="relative flex items-center justify-between gap-x-(--space-2)">
      <MonthPicker month={month} onChange={onMonth} max={max} />
      <div className="flex flex-none items-center gap-(--space-2)">
        <Link to={appPath("/search")} className="lk-avatar" aria-label={t("nav.search")}>
          <Icon name="search" size={22} />
        </Link>
        <button
          ref={button}
          type="button"
          className="lk-avatar"
          aria-label={t("home.account")}
          aria-expanded={open}
          aria-controls={menuId}
          onClick={() => setOpen((current) => !current)}
        >
          <Icon name="user" size={22} />
        </button>
      </div>
      {/* Above home's sticky tabs (z-20, later in the page), which once hid its lower half. */}
      <div
        ref={panel}
        id={menuId}
        hidden={!open}
        className="lk-menu absolute top-full right-0 z-30 mt-(--space-2) w-60"
      >
        <div className="flex items-center justify-between gap-(--space-2)">
          <span className="text-[14px] font-bold text-ink">{t("theme.label")}</span>
          <ThemeToggle />
        </div>
        <ul className="m-0 flex list-none flex-col gap-(--space-1) p-0">
          {SECTIONS.map((section) => (
            <li key={section.key}>
              <Link
                to={appPath(section.to)}
                state={"state" in section ? section.state : undefined}
                onClick={() => setOpen(false)}
                className="flex min-h-11 items-center justify-between rounded-sm text-[14px] font-bold text-ink no-underline hover:underline focus-visible:outline-3 focus-visible:outline-focus focus-visible:outline-offset-2"
              >
                {t(`nav.${section.key}`)}
                <span aria-hidden="true">›</span>
              </Link>
            </li>
          ))}
        </ul>
        {demo ? (
          <PressLink to={LANDING_PATH[locale]} variant="secondary" size="sm">
            {t("demo.leave")}
          </PressLink>
        ) : (
          <PressButton variant="secondary" size="sm" onClick={() => void signOut()}>
            {t("home.sign_out")}
          </PressButton>
        )}
      </div>
    </header>
  );
}
