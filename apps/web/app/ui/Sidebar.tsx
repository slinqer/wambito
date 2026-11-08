import { Link } from "react-router";
import { useTranslations } from "use-intl";
import { PressButton } from "./PressButton.tsx";

export interface SidebarProps {
  /** The current section: `home`, `search`, `insights`, `recurring`, `categories` or `settings`. */
  current: string;
  /** Opens the add sheet. */
  onAdd(): void;
  /** Sections whose screen does not exist yet: listed, marked "pronto", and not links. */
  soon?: readonly string[];
  /** Where the app lives: `/app`, or `/demo` in the demo. */
  base?: string;
}

const LINKS = [
  { key: "home", to: "" },
  { key: "search", to: "/search" },
  { key: "insights", to: "/insights" },
  { key: "recurring", to: "/recurring" },
  // Categories are managed in home's Categorías tab: the link opens home on it.
  { key: "categories", to: "", state: { view: "budgets" } },
  { key: "settings", to: "/settings" },
] as const;

/**
 * Desktop navigation, in place of the bottom bar: the wordmark, the six sections (the current
 * one raised) and a primary "Agregar" that opens the add sheet.
 */
export function Sidebar({ current, onAdd, soon = [], base = "/app" }: SidebarProps) {
  const t = useTranslations();
  return (
    <nav
      aria-label={t("nav.label")}
      className="flex w-56 flex-none flex-col gap-(--space-2) border-stroke border-r-2 bg-surface-sunken p-(--space-4)"
    >
      <span className="lk-logo px-(--space-3) pb-(--space-4)">{t("app.name")}</span>
      {LINKS.map((link) =>
        soon.includes(link.key) ? (
          <span key={link.key} className="lk-side-link is-soon">
            {t(`nav.${link.key}`)}
            <span className="lk-soon ml-auto">{t("nav.soon")}</span>
          </span>
        ) : (
          <Link
            key={link.key}
            to={`${base}${link.to}`}
            state={"state" in link ? link.state : undefined}
            className="lk-side-link"
            aria-current={current === link.key ? "page" : undefined}
          >
            {t(`nav.${link.key}`)}
          </Link>
        ),
      )}
      <PressButton className="mt-(--space-4)" onClick={onAdd}>
        {t("nav.add")}
      </PressButton>
      {/* Free space under Agregar, where Wambi lands when something is celebrated. */}
      <span aria-hidden="true" className="mt-(--space-4) block h-24" data-celebration-anchor="96" />
    </nav>
  );
}
