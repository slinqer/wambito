import { Link } from "react-router";
import { useTranslations } from "use-intl";
import { useLocale } from "../../i18n/IntlProvider.tsx";
import { AUTOMATIC_CAPTURE_PATH } from "../../site/paths.ts";
import { DemoMoneyContext, MainPicture } from "../capture/CaptureDemos.tsx";
import "../capture/capture.css";
import { useDemoMoney } from "./demo-money.ts";
import { useRotatingPlay } from "./play-on-view.ts";

/**
 * The picture's steps, ms after it starts: Google Wallet's notification drops in, the arrow
 * appears, then "Logged in Wambito" with the expense rises in; it holds `HOLD` ms and starts over
 * while it is on screen. Empty (`idle`) between rounds; whole and still (`done`) without JavaScript
 * and under reduced motion (`useRotatingPlay`).
 */
const STEPS = [
  ["notify", 0],
  ["arrow", 900],
  ["logged", 1500],
] as const;
const HOLD = 4000;

/**
 * Automatic capture, right under the hero: it is what catches people's attention first, since
 * logging every expense by hand is what they hate most. The text on one side (Android only, for
 * now), and on the other a panel where a Google Wallet notification turns into a logged expense
 * (the capture page's main picture, decorative), played on a loop while it is on screen. The link opens the
 * page that explains it step by step. `pace` scales the timing (stories only).
 */
export function AutomaticCapture({ pace = 1 }: { pace?: number }) {
  const t = useTranslations("landing.capture");
  const { locale } = useLocale();
  const { ref, phase } = useRotatingPlay(1, STEPS, HOLD, { pace });
  const money = useDemoMoney();
  return (
    <section id="capture" className="lk-landing-section" aria-labelledby="capture-title">
      <div className="lk-landing-split">
        <div className="lk-landing-split-text">
          <span className="lk-landing-eyebrow">{t("card.eyebrow")}</span>
          <h2 id="capture-title">{t("card.title")}</h2>
          <p>{t("card.body")}</p>
          <Link to={AUTOMATIC_CAPTURE_PATH[locale]} className="lk-landing-capture-link">
            {t("card.link")}
          </Link>
        </div>
        <div
          ref={ref}
          className="lk-landing-panel lk-landing-capture-play"
          data-phase={phase}
          aria-hidden="true"
        >
          <DemoMoneyContext.Provider value={money}>
            <MainPicture source="googlewallet" />
          </DemoMoneyContext.Provider>
        </div>
      </div>
    </section>
  );
}
