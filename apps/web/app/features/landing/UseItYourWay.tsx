import type { ReactNode } from "react";
import { useTranslations } from "use-intl";
import { useLocale } from "../../i18n/IntlProvider.tsx";
import { COMING_SOON } from "../../site/config.ts";
import { cx } from "../../ui/cx.ts";
import { PressLink } from "../../ui/PressLink.tsx";
import { ANDROID_APK_HREF, ANDROID_RELEASE_HREF, appLinkProps } from "./links.ts";
import { NewTabHint } from "./NewTabHint.tsx";

function Icon({ tone, children }: { tone: "gold" | "candy" | "good"; children: ReactNode }) {
  return (
    <span className={cx("lk-landing-icon", `is-${tone}`)} aria-hidden="true">
      <svg viewBox="0 0 24 24">{children}</svg>
    </span>
  );
}

/**
 * Where Wambito lives: the web app today ("Empezar"), the Android app as a direct APK download from
 * the GitHub release (iOS still to come), and your AI assistant (Claude or ChatGPT, through MCP)
 * marked as coming soon. In the landing-only release the web and Android cards are marked as coming
 * soon too, unless `VITE_APP_URL` says where the app lives: then they open and download it.
 */
export function UseItYourWay() {
  const t = useTranslations("landing.ways");
  const { locale } = useLocale();
  const app = appLinkProps(locale);
  return (
    <section id="ways" className="lk-landing-section" aria-labelledby="ways-title">
      <div className="lk-landing-section-head">
        <h2 id="ways-title">{t("title")}</h2>
      </div>
      <ul className="lk-landing-cards is-ways">
        <li className={cx("lk-landing-card", !COMING_SOON && "is-live")}>
          <div className="lk-landing-card-head">
            <Icon tone="good">
              <circle cx="12" cy="12" r="9" />
              <path d="M3 12h18M12 3c2.5 2.6 3.8 5.6 3.8 9s-1.3 6.4-3.8 9c-2.5-2.6-3.8-5.6-3.8-9S9.5 5.6 12 3z" />
            </Icon>
            <h3>{t("web.title")}</h3>
          </div>
          <p>{t("web.body")}</p>
          <div className="lk-landing-card-foot">
            {COMING_SOON ? (
              <span className="lk-landing-soon">{t("soon")}</span>
            ) : (
              <PressLink {...app} variant="secondary" size="sm">
                {t("web.cta")}
                <NewTabHint target={app.target} />
              </PressLink>
            )}
          </div>
        </li>
        <li className={cx("lk-landing-card", !COMING_SOON && "is-live")}>
          <div className="lk-landing-card-head">
            <Icon tone="candy">
              <rect x="6.5" y="2.5" width="11" height="19" rx="2.5" />
              <path d="M11 18h2" />
            </Icon>
            <h3>{t("mobile.title")}</h3>
          </div>
          <p>{t("mobile.body")}</p>
          {COMING_SOON ? (
            <div className="lk-landing-card-foot">
              <span className="lk-landing-soon">{t("soon")}</span>
            </div>
          ) : (
            <>
              <p>{t("mobile.ios")}</p>
              <div className="lk-landing-card-foot lk-landing-capture-foot">
                <PressLink to={ANDROID_APK_HREF} variant="secondary" size="sm">
                  {t("mobile.cta")}
                </PressLink>
                <a
                  href={ANDROID_RELEASE_HREF}
                  target="_blank"
                  rel="noopener"
                  className="lk-landing-capture-link"
                >
                  {t("mobile.other")}
                  <NewTabHint target="_blank" />
                </a>
              </div>
            </>
          )}
        </li>
        <li className="lk-landing-card">
          <div className="lk-landing-card-head">
            <Icon tone="gold">
              <path d="M11 3c.6 4.6 2.4 6.4 7 7-4.6.6-6.4 2.4-7 7-.6-4.6-2.4-6.4-7-7 4.6-.6 6.4-2.4 7-7z" />
              <path d="M19 14.5c.3 1.6.9 2.2 2.5 2.5-1.6.3-2.2.9-2.5 2.5-.3-1.6-.9-2.2-2.5-2.5 1.6-.3 2.2-.9 2.5-2.5z" />
            </Icon>
            <div>
              <h3>{t("ai.title")}</h3>
              <span className="lk-landing-with">{t("ai.with")}</span>
            </div>
          </div>
          <p>{t("ai.body")}</p>
          <div className="lk-landing-card-foot">
            <span className="lk-landing-soon">{t("soon")}</span>
          </div>
        </li>
      </ul>
    </section>
  );
}
