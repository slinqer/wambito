import type { ReactNode } from "react";
import { Link } from "react-router";
import { useTranslations } from "use-intl";
import { useLocale } from "../../i18n/IntlProvider.tsx";
import { PRIVACY_PATH } from "../../site/paths.ts";
import { GITHUB_HREF } from "./links.ts";
import { NewTabHint } from "./NewTabHint.tsx";

/** A text link to the source code on GitHub, opened in a new tab. */
function CodeLink({ children }: { children: ReactNode }) {
  return (
    <a href={GITHUB_HREF} target="_blank" rel="noopener">
      {children}
      <NewTabHint target="_blank" />
    </a>
  );
}

/** The questions, in order. Open source is one of them (it has no section of its own). */
const QUESTIONS = ["what", "import", "passwords", "privacy", "free", "open"] as const;

/**
 * Frequently asked questions as native `<details>`: they open and close without JavaScript. An
 * answer can link to the source code (`<github>GitHub</github>` in the catalog) and to the privacy
 * policy (`<privacy>…</privacy>`).
 */
export function Faq() {
  const t = useTranslations("landing.faq");
  const { locale } = useLocale();
  return (
    <section id="faq" className="lk-landing-section" aria-labelledby="faq-title">
      <div className="lk-landing-section-head">
        <h2 id="faq-title">{t("title")}</h2>
      </div>
      <ul className="lk-landing-faq">
        {QUESTIONS.map((key) => (
          <li key={key}>
            <details>
              <summary>{t(`${key}.q`)}</summary>
              <p className="lk-landing-answer">
                {t.rich(`${key}.a`, {
                  github: (chunks) => <CodeLink>{chunks}</CodeLink>,
                  privacy: (chunks) => <Link to={PRIVACY_PATH[locale]}>{chunks}</Link>,
                })}
              </p>
            </details>
          </li>
        ))}
      </ul>
    </section>
  );
}
