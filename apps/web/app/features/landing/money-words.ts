import type { Locale } from "../../i18n/format.ts";

/**
 * What money is called around the world in each language, for the headline's marker ("Wambi
 * organiza tus lukas por ti." → "Wambi organiza tu lana por ti." → …, "Wambi sorts out your money
 * for you." → "… your bucks …" → …). In Spanish, Portuguese and Italian each word carries its
 * gender and number, so the possessive before it agrees with it. The first is the prerendered one: it must match
 * the `landing.hero.headline` message.
 */
export interface MoneyWord {
  word: string;
  /** The flag of where it is said, shown after the marker; none for the plain word. */
  flag: string;
}

export interface GenderedWord extends MoneyWord {
  plural: boolean;
  feminine: boolean;
}

/** English has no agreement; the other languages' words carry their gender and number. */
export type WordOf<L extends Locale> = L extends "en" ? MoneyWord : GenderedWord;

type Words<W> = readonly [W, ...W[]];

export const MONEY_WORDS: { readonly [L in Locale]: Words<WordOf<L>> } = {
  es: [
    { word: "lukas", flag: "🇨🇴", plural: true, feminine: true }, // Colombia
    { word: "lana", flag: "🇲🇽", plural: false, feminine: true }, // México
    { word: "guita", flag: "🇦🇷", plural: false, feminine: true }, // Argentina
    { word: "pasta", flag: "🇪🇸", plural: false, feminine: true }, // España
    { word: "plata", flag: "🇨🇱", plural: false, feminine: true }, // Chile
    { word: "chavos", flag: "🇵🇷", plural: true, feminine: false }, // Puerto Rico
    { word: "pisto", flag: "🇬🇹", plural: false, feminine: false }, // Guatemala
    { word: "cuartos", flag: "🇩🇴", plural: true, feminine: false }, // República Dominicana
    { word: "reales", flag: "🇻🇪", plural: true, feminine: false }, // Venezuela
  ],
  en: [
    { word: "money", flag: "" },
    { word: "bucks", flag: "🇺🇸" }, // United States
    { word: "quid", flag: "🇬🇧" }, // United Kingdom
    { word: "loonies", flag: "🇨🇦" }, // Canada
  ],
  pt: [
    { word: "dinheiro", flag: "", plural: false, feminine: false },
    { word: "grana", flag: "🇧🇷", plural: false, feminine: true }, // Brasil
    { word: "guito", flag: "🇵🇹", plural: false, feminine: false }, // Portugal
    { word: "kumbu", flag: "🇦🇴", plural: false, feminine: false }, // Angola
  ],
  it: [
    { word: "soldi", flag: "", plural: true, feminine: false },
    { word: "grana", flag: "🇮🇹", plural: false, feminine: true }, // everywhere in Italy
    { word: "schei", flag: "🇮🇹", plural: true, feminine: false }, // Veneto
    { word: "palanche", flag: "🇮🇹", plural: true, feminine: true }, // Liguria
    { word: "franchi", flag: "🇨🇭", plural: true, feminine: false }, // Svizzera italiana
  ],
};

/** How long each word stays before the next one rolls in, in ms. */
export const MONEY_WORD_HOLD = 2800;

/**
 * The headline around a word, in pieces: who does it ("Wambi", "O Wambi"); what does not change
 * and what agrees before the word ("organiza tu" + "s", "organizza " + "i tuoi"); and what comes
 * after it ("por ti"), before the full stop.
 */
export interface Phrase {
  subject: string;
  lead: readonly [string, string];
  tail: string;
}

const PHRASES: { readonly [L in Locale]: (word: WordOf<L>) => Phrase } = {
  es: (word) => ({
    subject: "Wambi",
    lead: ["organiza tu", word.plural ? "s" : ""],
    tail: "por ti",
  }),
  en: () => ({ subject: "Wambi", lead: ["sorts out your", ""], tail: "for you" }),
  pt: ({ plural, feminine }) => ({
    subject: "O Wambi",
    lead: ["organiza ", feminine ? (plural ? "as tuas" : "a tua") : plural ? "os teus" : "o teu"],
    tail: "por ti",
  }),
  it: ({ plural, feminine }) => ({
    subject: "Wambi",
    lead: ["organizza ", feminine ? (plural ? "le tue" : "la tua") : plural ? "i tuoi" : "il tuo"],
    tail: "per te",
  }),
};

/** The headline's pieces around a word of that language. */
export function phraseFor<L extends Locale>(locale: L, word: WordOf<L>): Phrase {
  return PHRASES[locale](word);
}

/** The whole headline for a word, as it reads. */
export function headlineFor<L extends Locale>(locale: L, word: WordOf<L>): string {
  const { subject, lead, tail } = phraseFor(locale, word);
  return `${subject} ${lead.join("")} ${word.word} ${tail}.`;
}
