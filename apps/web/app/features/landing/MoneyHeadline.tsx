import { type ReactNode, useEffect, useLayoutEffect, useRef, useState } from "react";
import { useTranslations } from "use-intl";
import type { Locale } from "../../i18n/format.ts";
import { useLocale } from "../../i18n/IntlProvider.tsx";
import { useReducedMotionPreference } from "../../ui/motion-tokens.ts";
import { MONEY_WORD_HOLD, MONEY_WORDS, phraseFor, type WordOf } from "./money-words.ts";

/**
 * The headline, with what money is called around the world in this language taking turns on the
 * gold marker ("Tus lukas 🇨🇴" → "Tu lana 🇲🇽" → …, "Your money" → "Your bucks 🇺🇸" → …), each with
 * its country's flag, and the words around it agreeing with each word ("Tu(s)", "clar(a/o)(s)";
 * "O teu"/"A tua", "I tuoi"/"La tua"). Screen readers and search engines get the message as it is
 * (the prerendered first word); the turning words are decorative. It starts turning once hydrated,
 * waits while the tab is hidden, and holds on the first word under reduced motion. Every word's
 * headline is also laid out unseen in the same place, so the headline is as tall as its tallest
 * one from the first paint and the page below never moves.
 */
export function MoneyHeadline() {
  const t = useTranslations("landing.hero");
  const { locale } = useLocale();
  const reduceMotion = useReducedMotionPreference();
  const words = MONEY_WORDS[locale] as readonly WordOf<Locale>[];
  const index = useTurns(words.length, MONEY_WORD_HOLD, !reduceMotion);
  const entry = words[index] ?? (words[0] as WordOf<Locale>);
  return (
    <h1 id="hero-title" className="lk-landing-headline">
      <span className="sr-only">{t.rich("headline", { mark: (chunks) => chunks })}</span>
      <span aria-hidden="true">
        <Words locale={locale} entry={entry} piece={(text) => <Swap text={text} />} />
      </span>
      {/* Every headline, unseen in the same place, so the tallest one sets the height. */}
      {words.map((word) => (
        <span key={word.word} className="lk-landing-headline-size">
          <Words locale={locale} entry={word} piece={(text) => <Still text={text} />} />
        </span>
      ))}
    </h1>
  );
}

/** Wambito's own icon as a tile between the words: decorative. */
function AppTile() {
  return (
    <span className="lk-landing-tile is-app" data-tile="app">
      <img src="/favicon.svg" alt="" width={64} height={64} decoding="async" />
    </span>
  );
}

/** A bank notification turning into a logged expense (a bell with a check): decorative. */
function NoticeTile() {
  return (
    <span className="lk-landing-tile is-notice" data-tile="notice">
      <svg viewBox="0 0 24 24">
        <path d="M6 16V11a6 6 0 0 1 12 0v5l1.5 2h-15z" />
        <path d="M10 20.5a2.2 2.2 0 0 0 4 0" />
      </svg>
    </span>
  );
}

/** The headline around a word, with `piece` for each part that turns. */
function Words({
  locale,
  entry,
  piece,
}: {
  locale: Locale;
  entry: WordOf<Locale>;
  piece: (text: string) => ReactNode;
}) {
  const { lead, middle, last } = phraseFor(locale, entry);
  return (
    <>
      <span className="lk-swap-word">
        {lead[0]}
        {piece(lead[1])}
      </span>{" "}
      <span className="lk-swap-word">
        <span className="lk-landing-marker">
          {piece(entry.word)}
          <span className="lk-landing-flag">{piece(entry.flag)}</span>
        </span>
        ,
      </span>{" "}
      <AppTile /> {middle}{" "}
      <span className="lk-swap-word">
        <NoticeTile /> {last[0]}
        {piece(last[1])}.
      </span>
    </>
  );
}

/** Steps 0, 1, … count-1, 0 … every `hold` ms while `enabled` and the tab is visible; else 0. */
function useTurns(count: number, hold: number, enabled: boolean): number {
  const [index, setIndex] = useState(0);
  useEffect(() => {
    if (!enabled) {
      setIndex(0);
      return;
    }
    const timer = window.setInterval(() => {
      if (!document.hidden) setIndex((i) => (i + 1) % count);
    }, hold);
    return () => window.clearInterval(timer);
  }, [count, hold, enabled]);
  return index;
}

/** ms: a little longer than the roll (`--lk-swap-time` in landing.css). */
const SETTLE_FALLBACK = 600;

/**
 * A piece of text that, when it changes, rolls the old one up and out while the new one rises in,
 * and eases its width from the old text's to the new one's so the words around it slide along.
 */
function Swap({ text }: { text: string }) {
  const box = useRef<HTMLSpanElement>(null);
  const shown = useRef(text);
  const [leaving, setLeaving] = useState<string | null>(null);

  useLayoutEffect(() => {
    if (shown.current === text) return;
    setLeaving(shown.current);
    shown.current = text;
  }, [text]);

  // Both texts are in the DOM now: measure them, pin the old width, then ease to the new one.
  useLayoutEffect(() => {
    const el = box.current;
    if (leaving === null || !el) return;
    const [entering, left] = el.children as unknown as [HTMLElement, HTMLElement];
    el.style.width = `${left.offsetWidth}px`;
    el.getBoundingClientRect();
    el.style.width = `${entering.offsetWidth}px`;
    // In case the roll's `animationend` never comes (no frames painted, animations off).
    const fallback = window.setTimeout(settle, SETTLE_FALLBACK);
    return () => window.clearTimeout(fallback);
  }, [leaving]);

  // The roll and the width share one duration: once the old text is gone the width is settled,
  // and goes back to the text's own (so a late web font still fits).
  function settle() {
    setLeaving(null);
    if (box.current) box.current.style.width = "";
  }

  return (
    <span ref={box} className="lk-swap">
      <span key={text} className={leaving === null ? undefined : "lk-swap-in"}>
        {text}
      </span>
      {leaving !== null && (
        <span key={`out-${leaving}`} className="lk-swap-out" onAnimationEnd={settle}>
          {leaving}
        </span>
      )}
    </span>
  );
}

/** A `Swap`'s text, as it sits when it is not turning. */
function Still({ text }: { text: string }) {
  return (
    <span className="lk-swap">
      <span>{text}</span>
    </span>
  );
}
