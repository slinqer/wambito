import { useTranslations } from "use-intl";
import { useLocale } from "../../i18n/IntlProvider.tsx";
import { COMING_SOON } from "../../site/config.ts";
import { cx } from "../../ui/cx.ts";
import { PressLink } from "../../ui/PressLink.tsx";
import { appLinkProps, demoLinkProps } from "./links.ts";
import { MoneyHeadline } from "./MoneyHeadline.tsx";
import { NewTabHint } from "./NewTabHint.tsx";

/**
 * The headline with "lukas" ("money", "dinheiro", "soldi") on a gold marker, taking turns with what
 * money is called elsewhere, one line about what Wambito does, one primary action, "Crear cuenta"
 * (`/create-account`), and "Pruébalo sin cuenta" (the demo) beside it. Without an app to open
 * (landing-only, coming soon) there is no demo either, so only the primary action shows.
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
            <PressLink {...app} className={cx(COMING_SOON && "is-soon")}>
              {t(COMING_SOON ? "cta_soon" : "cta")}
              <NewTabHint target={app.target} />
            </PressLink>
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
