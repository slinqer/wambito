import type { ReactNode } from "react";
import { Link } from "react-router";
import { useTranslations } from "use-intl";
import { useLocale } from "../../i18n/IntlProvider.tsx";
import { DELETE_ACCOUNT_PATH, PRIVACY_PATH } from "../../site/paths.ts";
import { analyticsConfig } from "../analytics/config.ts";
import { Footer } from "../landing/Footer.tsx";
import { SiteHeader } from "../landing/SiteHeader.tsx";
import {
  ANALYTICS_RETENTION,
  DELETE_ACCOUNT_SECTIONS,
  LEGAL_MESSAGES,
  type LegalPageName,
  PRIVACY_EMAIL,
  privacySections,
} from "./legal.ts";
import "../landing/landing.css";
import "./legal.css";

/** The build's PostHog switch (a build-time constant): only a keyed build's policy covers analytics. */
const SITE_ANALYTICS = analyticsConfig() !== null;

function sections(page: LegalPageName, withAnalytics: boolean): readonly string[] {
  return page === "privacy" ? privacySections(withAnalytics) : DELETE_ACCOUNT_SECTIONS;
}

/*
 * A page's section keys pair with its own namespace only (`legal.test.ts` checks every pair), which
 * the key types cannot express; any one real key stands for them all.
 */
type SectionTitle = "privacy.sections.rights.title";
type SectionBody = "privacy.sections.rights.body";

/** Where a body's `<link>` leads: each legal page points at the other one. */
const OTHER_PAGE = { privacy: DELETE_ACCOUNT_PATH, deleteAccount: PRIVACY_PATH } as const;

/**
 * The privacy policy (`/privacy`) and the account deletion page (`/delete-account`), prerendered
 * per language on the landing's look: a title, the version date, and one `h2` section per key of
 * `legal.<page>.sections`. A body's `<email>` is a mail link to privacy@wambito.com and its
 * `<link>` the other legal page. The privacy policy has its analytics section only in a build with a
 * PostHog key; `withAnalytics` overrides that for stories only.
 */
export function LegalPage({
  page,
  withAnalytics = SITE_ANALYTICS,
}: {
  page: LegalPageName;
  withAnalytics?: boolean;
}) {
  const t = useTranslations("legal");
  const ns = LEGAL_MESSAGES[page];
  const { locale } = useLocale();
  const values = {
    ...ANALYTICS_RETENTION,
    email: (chunks: ReactNode) => <a href={`mailto:${PRIVACY_EMAIL}`}>{chunks}</a>,
    link: (chunks: ReactNode) => <Link to={OTHER_PAGE[page][locale]}>{chunks}</Link>,
  };
  return (
    <div className="lk-screen lk-landing">
      <SiteHeader page={page} />
      <main className="lk-landing-wrap lk-legal">
        <article className="lk-legal-article">
          <header className="lk-legal-intro">
            <h1>{t(`${ns}.title`)}</h1>
            <p className="lk-legal-version">{t(`${ns}.version`)}</p>
          </header>
          {sections(page, withAnalytics).map((key) => (
            <section key={key} className="lk-legal-section" aria-labelledby={`legal-${key}`}>
              <h2 id={`legal-${key}`}>{t(`${ns}.sections.${key}.title` as SectionTitle)}</h2>
              <p>{t.rich(`${ns}.sections.${key}.body` as SectionBody, values)}</p>
            </section>
          ))}
        </article>
      </main>
      <Footer page={page} />
    </div>
  );
}
