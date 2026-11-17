import { Link } from "react-router";
import { useTranslations } from "use-intl";
import { Icon } from "./Icon.tsx";

export interface BottomBarProps {
  /** The current section; one the bar has no tab for (categories, say) marks none. */
  current: string;
  /** Opens the add sheet. */
  onAdd(): void;
  /** Tabs whose screen does not exist yet: shown, marked "pronto", and not a link. */
  soon?: readonly ("home" | "insights")[];
  /** Where the app lives: `/app`, or `/demo` in the demo. */
  base?: string;
}

const TABS = [
  { key: "home", to: "", icon: "home" },
  { key: "insights", to: "/insights", icon: "chart" },
] as const;

/**
 * Phone navigation: Inicio · ＋ · Análisis. The current tab's icon is filled, the other's outlined.
 * The raised ＋ (the bar's only `brand` element) opens
 * the add sheet; recurring, categories and settings live in the avatar menu. On wide screens the
 * layout shows `Sidebar` instead.
 */
export function BottomBar({ current, onAdd, soon = [], base = "/app" }: BottomBarProps) {
  const t = useTranslations("nav");
  const tab = (key: (typeof TABS)[number]["key"]) => {
    const { to, icon } = TABS.find((x) => x.key === key) as (typeof TABS)[number];
    if (soon.includes(key)) {
      return (
        <span className="lk-tab is-soon">
          <Icon name={icon} variant="outline" className="lk-tab-ico" />
          {t(key)}
          <span className="lk-soon">{t("soon")}</span>
        </span>
      );
    }
    return (
      <Link
        to={`${base}${to}`}
        className="lk-tab"
        aria-current={current === key ? "page" : undefined}
      >
        <Icon name={icon} variant={current === key ? "filled" : "outline"} className="lk-tab-ico" />
        {t(key)}
      </Link>
    );
  };

  return (
    <nav aria-label={t("label")} className="lk-tabbar">
      {tab("home")}
      {/* Wambi lands just above the ＋ when something is celebrated; the ＋ stays tappable. */}
      <button
        type="button"
        className="lk-plus"
        aria-label={t("add")}
        onClick={onAdd}
        data-celebration-anchor="64"
        data-celebration-place="above"
      >
        <Icon name="plus" size={26} />
      </button>
      {tab("insights")}
    </nav>
  );
}
