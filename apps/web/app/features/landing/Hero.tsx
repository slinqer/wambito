import { useTranslations } from "use-intl";
import { useLocale } from "../../i18n/IntlProvider.tsx";
import { COMING_SOON } from "../../site/config.ts";
import { PressLink } from "../../ui/PressLink.tsx";
import { appLinkProps, demoLinkProps } from "./links.ts";
import { MoneyHeadline } from "./MoneyHeadline.tsx";
import { NewTabHint } from "./NewTabHint.tsx";

/**
 * The headline with "lukas" ("money", "dinheiro", "soldi") on a gold marker, taking turns with what
 * money is called elsewhere, one line about what Wambito does, one primary action, "Descargar la
 * app", which scrolls down to the downloads (`#ways`, "Úsalo como prefieras"), and "Demo" beside
 * it. Without an app to open (landing-only, coming soon) there is nothing to download and no demo
 * either, so only "Muy pronto · Síguelo en GitHub" shows.
 */
export function Hero() {
  const t = useTranslations("landing.hero");
  const { locale } = useLocale();
  const app = appLinkProps(locale, "create");
  const demo = demoLinkProps(locale);
  return (
    <section id="hero" className="lk-landing-hero" aria-labelledby="hero-title">
      <div className="lk-landing-hero-text">
        <MoneyHeadline />
        <p className="lk-landing-description">
          {t.rich("description", {
            lead: (chunks) => <span className="lk-landing-lead">{chunks}</span>,
          })}
        </p>
        <div className="lk-landing-cta">
          <div className="lk-landing-cta-actions">
            {COMING_SOON ? (
              <PressLink {...app} className="is-soon">
                {t("cta_soon")}
                <NewTabHint target={app.target} />
              </PressLink>
            ) : (
              <a
                href="#ways"
                className="lk-btn lk-btn-primary inline-flex min-h-11 min-w-11 items-center justify-center gap-(--space-2) no-underline"
              >
                {t("cta_download")}
              </a>
            )}
            {demo && (
              <PressLink {...demo} variant="secondary">
                {t("cta_demo")}
              </PressLink>
            )}
          </div>
        </div>
      </div>
    </section>
  );
}
