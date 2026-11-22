import { useRef } from "react";
import { Link } from "react-router";
import { useTranslations } from "use-intl";
import { LOCALES } from "../../i18n/format.ts";
import { useLocale } from "../../i18n/IntlProvider.tsx";
import {
  DELETE_ACCOUNT_PATH,
  PAGE_PATH,
  PRIVACY_PATH,
  ROADMAP_PATH,
  type SitePage,
} from "../../site/paths.ts";
import { ConsentBanner } from "../analytics/ConsentBanner.tsx";
import { type AnalyticsConfig, SITE_ANALYTICS_CONFIG } from "../analytics/config.ts";
import { type ConsentDeps, useAnalyticsConsent } from "../analytics/use-analytics-consent.ts";
import { COPYRIGHT_YEAR } from "./links.ts";

/**
 * Language switch (the same page in the other language), the roadmap, privacy and account deletion
 * links and the copyright. The active language is marked `aria-current="true"` (a filled pill) and
 * the current page `aria-current="page"` (the gold underline), so the two never look alike. `page`
 * is the page it sits on (the landing by default): the language switch keeps it.
 *
 * Every public page renders it, so it also mounts the cookie banner and, when the build has a
 * PostHog key, the "Cookie preferences" link that opens it again. `consent` is for stories only
 * (a fake config, and fakes for storage, signals and PostHog); pages never pass it.
 */
export function Footer({
  page = "landing",
  consent: seam,
}: {
  page?: SitePage;
  consent?: { config?: AnalyticsConfig | null; deps?: ConsentDeps };
}) {
  const t = useTranslations();
  const { locale } = useLocale();
  const config = seam?.config === undefined ? SITE_ANALYTICS_CONFIG : seam.config;
  const consent = useAnalyticsConsent(config, seam?.deps);
  const preferences = useRef<HTMLButtonElement>(null);
  return (
    <footer className="lk-landing-wrap lk-landing-site-footer">
      <div className="lk-landing-footer">
        <span className="lk-logo">{t("app.name")}</span>
        <div className="lk-landing-footer-links">
          <nav aria-label={t("landing.footer.language")}>
            <ul className="lk-landing-langs">
              {LOCALES.map((option) => (
                <li key={option}>
                  <Link
                    to={PAGE_PATH[page][option]}
                    className="lk-landing-link"
                    lang={option}
                    hrefLang={option}
                    aria-current={option === locale ? "true" : undefined}
                  >
                    {t(`language.${option}`)}
                  </Link>
                </li>
              ))}
            </ul>
          </nav>
          <Link
            to={ROADMAP_PATH[locale]}
            className="lk-landing-link"
            aria-current={page === "roadmap" ? "page" : undefined}
          >
            {t("landing.footer.roadmap")}
          </Link>
          <Link
            to={PRIVACY_PATH[locale]}
            className="lk-landing-link"
            aria-current={page === "privacy" ? "page" : undefined}
          >
            {t("landing.footer.privacy")}
          </Link>
          {config && (
            <button
              ref={preferences}
              type="button"
              className="lk-landing-link"
              aria-expanded={consent.ready && consent.open}
              onClick={consent.reopen}
            >
              {t("landing.footer.cookies")}
            </button>
          )}
          <Link
            to={DELETE_ACCOUNT_PATH[locale]}
            className="lk-landing-link"
            aria-current={page === "deleteAccount" ? "page" : undefined}
          >
            {t("landing.footer.delete_account")}
          </Link>
        </div>
        <p className="lk-landing-copyright">
          {t("landing.footer.copyright", { year: String(COPYRIGHT_YEAR) })}
        </p>
      </div>
      <ConsentBanner consent={consent} returnFocus={preferences} />
    </footer>
  );
}
