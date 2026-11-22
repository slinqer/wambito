import { useTranslations } from "use-intl";
import { COMING_SOON } from "../../site/config.ts";
import { cx } from "../../ui/cx.ts";
import { PressLink } from "../../ui/PressLink.tsx";
import { BRAND_LOGOS, type BrandLogoName } from "./brand-logos.ts";
import { ANDROID_APK_HREF } from "./links.ts";

/** A bare brand mark beside a label (a button, a store), decorative: the label names it. */
function Mark({ name }: { name: BrandLogoName }) {
  return (
    <svg className="lk-landing-mark-logo" viewBox="0 0 24 24" data-logo={name} aria-hidden="true">
      <path d={BRAND_LOGOS[name]} />
    </svg>
  );
}

/**
 * A store Wambito is not in yet, shaped like the button it will become (its mark and name) with
 * the coming-soon badge inside; dashed and muted, and not a link, so it never looks pressable.
 */
function Store({ name, label, soon }: { name: BrandLogoName; label: string; soon: string }) {
  return (
    <span className="lk-btn lk-btn-sm lk-landing-store">
      <Mark name={name} />
      <span>{label}</span>
      <span className="lk-landing-soon">{soon}</span>
    </span>
  );
}

/** A brand's logo in the card's icon box, decorative: the card's heading names the brand. */
function Logo({ name, tone }: { name: BrandLogoName; tone?: "good" }) {
  return (
    <span className={cx("lk-landing-icon is-logo", tone && `is-${tone}`)} aria-hidden="true">
      <svg viewBox="0 0 24 24" data-logo={name}>
        <path d={BRAND_LOGOS[name]} />
      </svg>
    </span>
  );
}

/**
 * Where to get Wambito: the Android app as a direct APK download from the GitHub release, beside
 * Google Play (coming soon), and the iOS app (coming soon on the App Store), each store shaped
 * like a button. Your agent has its own section
 * above (`AgentDemo.tsx`). In the landing-only release the GitHub download is left out, unless
 * `VITE_APP_URL` says where the app lives.
 */
export function UseItYourWay() {
  const t = useTranslations("landing.ways");
  return (
    <section id="ways" className="lk-landing-section" aria-labelledby="ways-title">
      <div className="lk-landing-section-head">
        <h2 id="ways-title">{t("title")}</h2>
      </div>
      <ul className="lk-landing-cards is-ways">
        <li className={cx("lk-landing-card", !COMING_SOON && "is-live")}>
          <div className="lk-landing-card-head">
            <Logo name="android" tone="good" />
            <h3>{t("android.title")}</h3>
          </div>
          <p>{t("android.body")}</p>
          <div className="lk-landing-card-foot lk-landing-stores">
            {COMING_SOON ? null : (
              <PressLink to={ANDROID_APK_HREF} variant="secondary" size="sm">
                <Mark name="github" />
                {t("android.cta")}
              </PressLink>
            )}
            <Store name="googleplay" label="Google Play" soon={t("soon")} />
          </div>
        </li>
        <li className="lk-landing-card">
          <div className="lk-landing-card-head">
            <Logo name="apple" />
            <h3>{t("ios.title")}</h3>
          </div>
          <p>{t("ios.body")}</p>
          <div className="lk-landing-card-foot lk-landing-stores">
            <Store name="appstore" label="App Store" soon={t("soon")} />
          </div>
        </li>
      </ul>
    </section>
  );
}
