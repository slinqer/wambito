import { Link } from "react-router";
import { useTranslations } from "use-intl";
import { useLocale } from "../../i18n/IntlProvider.tsx";
import { COMING_SOON } from "../../site/config.ts";
import { LANDING_PATH, ROADMAP_PATH, type SitePage } from "../../site/paths.ts";
import { PressLink } from "../../ui/PressLink.tsx";
import { ThemeToggle } from "../../ui/ThemeToggle.tsx";
import { LanguageMenu } from "./LanguageMenu.tsx";
import { appLinkProps } from "./links.ts";
import { NewTabHint } from "./NewTabHint.tsx";

/**
 * The header of the landing and the roadmap: the wordmark (home), the section links (desktop
 * only: the phone header has no room), the way in, the language switch and the day/night switch. On the landing the
 * section links are anchors on the page; on the roadmap they lead back to the landing's sections.
 */
export function SiteHeader({ page }: { page: SitePage }) {
  const t = useTranslations("landing.nav");
  const name = useTranslations("app")("name");
  const { locale } = useLocale();
  const app = appLinkProps(locale, "sign-in");
  const home = page === "landing" ? "" : LANDING_PATH[locale];
  return (
    <header className="lk-landing-wrap">
      <div className="lk-landing-header">
        <Link to={LANDING_PATH[locale]} className="lk-landing-logo" aria-label={t("home")}>
          <span className="lk-logo">{name}</span>
        </Link>
        <nav aria-label={t("label")} className="lk-landing-nav">
          <a href={`${home}#how`} className="lk-landing-link lk-landing-nav-section">
            {t("how")}
          </a>
          <Link
            to={ROADMAP_PATH[locale]}
            className="lk-landing-link lk-landing-nav-section"
            aria-current={page === "roadmap" ? "page" : undefined}
          >
            {t("roadmap")}
          </Link>
          <a href={`${home}#faq`} className="lk-landing-link lk-landing-nav-section">
            {t("faq")}
          </a>
          <PressLink {...app} variant="secondary" size="sm">
            {t(COMING_SOON ? "sign_in_soon" : "sign_in")}
            <NewTabHint target={app.target} />
          </PressLink>
          <LanguageMenu page={page} />
          <ThemeToggle />
        </nav>
      </div>
    </header>
  );
}
