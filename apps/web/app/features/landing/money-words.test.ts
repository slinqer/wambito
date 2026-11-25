import { describe, expect, it } from "vitest";
import type { Locale } from "../../i18n/format.ts";
import en from "../../i18n/messages/en.json" with { type: "json" };
import es from "../../i18n/messages/es.json" with { type: "json" };
import it_ from "../../i18n/messages/it.json" with { type: "json" };
import pt from "../../i18n/messages/pt.json" with { type: "json" };
import { type GenderedWord, headlineFor, MONEY_WORDS, type WordOf } from "./money-words.ts";

const MESSAGES = { es, en, pt, it: it_ };
const LOCALES = Object.keys(MESSAGES) as Locale[];

function headlines<L extends Locale>(locale: L): string[] {
  return (MONEY_WORDS[locale] as readonly WordOf<L>[]).map((word) => headlineFor(locale, word));
}

/** The four agreements, on a made-up word, to see each form even where no word needs it yet. */
function forms(locale: "es" | "pt" | "it"): string[] {
  return [
    [false, false],
    [false, true],
    [true, false],
    [true, true],
  ].map(([plural, feminine]) =>
    headlineFor(locale, { word: "x", flag: "", plural, feminine } as GenderedWord),
  );
}

describe("MONEY_WORDS", () => {
  for (const locale of LOCALES) {
    describe(locale, () => {
      it("starts with the prerendered headline", () => {
        const message = MESSAGES[locale].landing.hero.headline.replace(/<\/?mark>/g, "");
        expect(headlines(locale)[0]).toBe(message);
      });

      it("names each word once, and flags every word but the plain one", () => {
        const [first, ...rest] = MONEY_WORDS[locale];
        const words = MONEY_WORDS[locale].map((w) => w.word);
        expect(new Set(words).size).toBe(words.length);
        for (const word of rest) expect(word.flag).toMatch(/^\p{RI}\p{RI}$/u);
        expect(first.flag).toMatch(locale === "es" ? /^\p{RI}\p{RI}$/u : /^$/);
      });
    });
  }

  it("Spanish agrees the possessive in number with every word", () => {
    expect(headlines("es")).toEqual([
      "Wambi organiza tus lukas por ti.",
      "Wambi organiza tu lana por ti.",
      "Wambi organiza tu guita por ti.",
      "Wambi organiza tu pasta por ti.",
      "Wambi organiza tu plata por ti.",
      "Wambi organiza tus chavos por ti.",
      "Wambi organiza tu pisto por ti.",
      "Wambi organiza tus cuartos por ti.",
      "Wambi organiza tus reales por ti.",
    ]);
    expect(forms("es")).toEqual([
      "Wambi organiza tu x por ti.",
      "Wambi organiza tu x por ti.",
      "Wambi organiza tus x por ti.",
      "Wambi organiza tus x por ti.",
    ]);
  });

  it("English has nothing to agree", () => {
    expect(headlines("en")).toEqual([
      "Wambi sorts out your money for you.",
      "Wambi sorts out your bucks for you.",
      "Wambi sorts out your quid for you.",
      "Wambi sorts out your loonies for you.",
    ]);
  });

  it("Portuguese agrees the article and the possessive", () => {
    expect(headlines("pt")).toEqual([
      "O Wambi organiza o teu dinheiro por ti.",
      "O Wambi organiza a tua grana por ti.",
      "O Wambi organiza o teu guito por ti.",
      "O Wambi organiza o teu kumbu por ti.",
    ]);
    expect(forms("pt")).toEqual([
      "O Wambi organiza o teu x por ti.",
      "O Wambi organiza a tua x por ti.",
      "O Wambi organiza os teus x por ti.",
      "O Wambi organiza as tuas x por ti.",
    ]);
  });

  it("Italian agrees the article and the possessive", () => {
    expect(headlines("it")).toEqual([
      "Wambi organizza i tuoi soldi per te.",
      "Wambi organizza la tua grana per te.",
      "Wambi organizza i tuoi schei per te.",
      "Wambi organizza le tue palanche per te.",
      "Wambi organizza i tuoi franchi per te.",
    ]);
    expect(forms("it")).toEqual([
      "Wambi organizza il tuo x per te.",
      "Wambi organizza la tua x per te.",
      "Wambi organizza i tuoi x per te.",
      "Wambi organizza le tue x per te.",
    ]);
  });
});
