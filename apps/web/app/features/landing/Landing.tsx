import { useRef } from "react";
import { useTranslations } from "use-intl";
import { useLocale } from "../../i18n/IntlProvider.tsx";
import { COMING_SOON } from "../../site/config.ts";
import { cx } from "../../ui/cx.ts";
import { PressLink } from "../../ui/PressLink.tsx";
import { AgentDemo } from "./AgentDemo.tsx";
import { AutomaticCapture } from "./AutomaticCapture.tsx";
import { Faq } from "./Faq.tsx";
import { Footer } from "./Footer.tsx";
import { Hero } from "./Hero.tsx";
import { HowItWorks } from "./HowItWorks.tsx";
import { appLinkProps } from "./links.ts";
import { NewTabHint } from "./NewTabHint.tsx";
import { useButtonGlow } from "./pointer-glow.ts";
import { SiteHeader } from "./SiteHeader.tsx";
import { UseItYourWay } from "./UseItYourWay.tsx";
import "./landing.css";

/**
 * A button label in two halves around Wambi, which read back as the label with a space between
 * them: after " ·" when there is one ("Muy pronto ·" / "Síguelo en GitHub"), else at the first
 * space ("Crear" / "cuenta").
 */
export function seatHalves(label: string): [string, string] {
  const dot = label.indexOf(" · ");
  if (dot >= 0) return [label.slice(0, dot + 2), label.slice(dot + 3)];
  const space = label.indexOf(" ");
  if (space < 0) return [label, ""];
  return [label.slice(0, space), label.slice(space + 1)];
}

/**
 * The last nudge: a big title, where Wambito comes from (or, before the app opens, that it is being
 * built in the open), and one big "Crear cuenta" with Wambi sitting in its middle, resting, eyes
 * closed (`docs/brand/wambi-resting.webp`): the label splits around him, "CREAR CUENTA", and his
 * legs hang in the gap. He is a picture on top of the button that lets the pointer through: the
 * whole button stays pressable under him, and its name is the label as it reads.
 */
function Closing() {
  const t = useTranslations("landing");
  const { locale } = useLocale();
  const app = appLinkProps(locale, "create");
  // Honest about where the app is: not open yet, or open to everyone.
  const closingBody = COMING_SOON ? "closing.body_soon" : "closing.body";
  const [before, after] = seatHalves(t(COMING_SOON ? "hero.cta_soon" : "hero.cta"));
  return (
    <section id="closing" className="lk-landing-section" aria-labelledby="closing-title">
      <div className="lk-landing-closing">
        <h2 id="closing-title">{t("closing.title")}</h2>
        <p>{t(closingBody)}</p>
        <div className="lk-landing-seat">
          <PressLink {...app} className={cx("lk-landing-seat-cta", COMING_SOON && "is-soon")}>
            <span className="lk-landing-seat-before">{before}</span>{" "}
            <span className="lk-landing-seat-gap" aria-hidden="true" />
            <span className="lk-landing-seat-after">{after}</span>
            <NewTabHint target={app.target} />
          </PressLink>
          <span
            className="lk-landing-spot is-closing"
            data-wambi-spot="closing"
            data-wambi-pose="resting"
            aria-hidden="true"
          >
            <img
              className="lk-landing-resting"
              src="/wambi/resting.webp"
              alt=""
              width={512}
              height={512}
              loading="lazy"
              decoding="async"
            />
          </span>
        </div>
      </div>
    </section>
  );
}

/**
 * The landing page (`/` in Spanish, `/en` in English), prerendered to static HTML: everything here
 * renders without JavaScript and in the URL's language.
 */
export function Landing() {
  const root = useRef<HTMLDivElement>(null);
  useButtonGlow(root);
  return (
    <div ref={root} className="lk-screen lk-landing">
      <SiteHeader page="landing" />
      <main className="lk-landing-wrap">
        <Hero />
        <AutomaticCapture />
        <HowItWorks />
        <AgentDemo />
        <UseItYourWay />
        <Faq />
        <Closing />
      </main>
      <Footer />
    </div>
  );
}
