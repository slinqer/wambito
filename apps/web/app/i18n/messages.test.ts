import { readdirSync, readFileSync, statSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import type { WambiMessageKey } from "@wambito/core";
import { createTranslator } from "use-intl/core";
import { describe, expect, it } from "vitest";
import { CATALOGS } from "./catalog.ts";
import { intlTag } from "./format.ts";
import adminEn from "./messages/admin.en.json" with { type: "json" };
import adminEs from "./messages/admin.es.json" with { type: "json" };
import appEn from "./messages/app.en.json" with { type: "json" };
import appEs from "./messages/app.es.json" with { type: "json" };
import appIt from "./messages/app.it.json" with { type: "json" };
import appPt from "./messages/app.pt.json" with { type: "json" };
import siteEn from "./messages/en.json" with { type: "json" };
import siteEs from "./messages/es.json" with { type: "json" };
import siteIt from "./messages/it.json" with { type: "json" };
import sitePt from "./messages/pt.json" with { type: "json" };

const { es, en } = CATALOGS;
const LANGUAGES = ["es", "en", "it", "pt"] as const;
const SITES = { es: siteEs, en: siteEn, it: siteIt, pt: sitePt } as const;
const APPS = { es: appEs, en: appEn, it: appIt, pt: appPt } as const;

type Tree = { [key: string]: string | Tree };

function flatten(tree: Tree, prefix = ""): Record<string, string> {
  const out: Record<string, string> = {};
  for (const [key, value] of Object.entries(tree)) {
    const path = prefix ? `${prefix}.${key}` : key;
    if (typeof value === "string") out[path] = value;
    else Object.assign(out, flatten(value, path));
  }
  return out;
}

const catalogs = {
  es: flatten(es),
  en: flatten(en),
  it: flatten(CATALOGS.it),
  pt: flatten(CATALOGS.pt),
} as const;

/** Exhaustive by construction: adding or removing a WambiMessageKey fails the type check. */
const WAMBI_KEYS = {
  first_of_day: { name: "café", category: "Comida" },
  on_track: { remaining: "120,00 €", daysLeft: 9 },
  near_limit: { category: "Comida", remaining: "8,00 €" },
  over_budget: { category: "Comida", over: "6,08 €" },
  income_received: { amount: "1.200,00 €", name: "Nómina", category: "Salario" },
  pending_paid: { amount: "45,00 €", name: "gym", category: "Vida" },
  month_last_day: { remaining: "120,00 €" },
  month_closed_green: { remaining: "120,00 €" },
} satisfies Record<WambiMessageKey, Record<string, string | number>>;

/** Sorted, de-duplicated argument names of an ICU message (`{name}`, `{name, plural, ...}`). */
function icuArguments(message: string): string[] {
  const names = new Set<string>();
  for (const match of message.matchAll(/\{\s*([A-Za-z_]\w*)\s*[,}]/g))
    names.add(match[1] as string);
  return [...names].sort();
}

/**
 * The plural/select shape of a message: each `{name, plural|select` and each branch key (`one`,
 * `other`, `=0`...), sorted. A translation that drops a branch or swaps plural for select differs.
 */
function icuShape(message: string): string[] {
  const parts = [
    ...[...message.matchAll(/\{\s*\w+\s*,\s*(plural|select|selectordinal)\s*,/g)].map(
      (m) => m[1] as string,
    ),
    ...[...message.matchAll(/(?:^|[\s,}])(zero|one|two|few|many|other|=\d+)\s*\{/g)].map(
      (m) => `branch:${m[1]}`,
    ),
  ];
  return parts.sort();
}

/** Sorted rich-text tag names of a message (`<mark>lukas</mark>` → `mark`), for `t.rich`. */
function richTags(message: string): string[] {
  return [...message.matchAll(/<([A-Za-z_]\w*)>/g)].map((match) => match[1] as string).sort();
}

/**
 * The codes only `/v1/admin/*` answers with. The panel speaks Spanish and English only (spec §10),
 * so their text is `admin.errors.<code>` in `admin.{es,en}.json`, not `errors.<code>` in the four
 * app catalogs.
 */
const ADMIN_ONLY_CODES = [
  "admin_verification_required",
  "passkey_verification_failed",
  "user_not_found",
  "is_guest",
  "cannot_target_self",
] as const;

function apiErrorCodes(): string[] {
  const root = fileURLToPath(new URL("../../../api/src", import.meta.url));
  const codes = new Set<string>();
  const walk = (dir: string) => {
    for (const name of readdirSync(dir)) {
      const path = join(dir, name);
      if (statSync(path).isDirectory()) walk(path);
      else if (path.endsWith(".ts") && !path.endsWith(".test.ts")) {
        const source = readFileSync(path, "utf8");
        for (const match of source.matchAll(/new ApiError\(\s*\d+,\s*"([a-z_]+)"/g)) {
          codes.add(match[1] as string);
        }
      }
    }
  };
  walk(root);
  return [...codes];
}

describe("message catalogs", () => {
  it("come in two parts, the public pages' and the app's, each namespace in one part only", () => {
    // What the landing, roadmap and legal pages render (Landing, Roadmap, LegalPage, SiteHeader,
    // Footer, ThemeToggle, Wambi): the root's IntlProvider holds only these, so the landing
    // ships nothing else.
    const site = ["app", "landing", "language", "legal", "mascot", "roadmap", "theme"];
    for (const language of LANGUAGES) {
      expect(Object.keys(SITES[language]).sort(), language).toEqual(site);
      expect(Object.keys(APPS[language]).sort(), language).toEqual(Object.keys(appEs).sort());
      expect(Object.keys(CATALOGS[language]).sort(), language).toEqual(
        [...site, ...Object.keys(appEs)].sort(),
      );
    }
    expect(Object.keys(appEs).filter((namespace) => site.includes(namespace))).toEqual([]);
  });

  it("every language has identical key sets: the same keys as es, none missing, none extra", () => {
    for (const language of LANGUAGES) {
      expect(Object.keys(catalogs[language]).sort(), language).toEqual(
        Object.keys(catalogs.es).sort(),
      );
    }
  });

  it("each catalog's own page parts are the same trees as the merged catalog", () => {
    for (const language of LANGUAGES) {
      expect(
        { ...flatten(SITES[language] as Tree), ...flatten(APPS[language] as Tree) },
        language,
      ).toEqual(catalogs[language]);
    }
  });

  it("uses the same ICU argument names as es for every key, in every language", () => {
    for (const language of LANGUAGES) {
      for (const key of Object.keys(catalogs.es)) {
        expect(icuArguments(catalogs[language][key] ?? ""), `${language}:${key}`).toEqual(
          icuArguments(catalogs.es[key] ?? ""),
        );
      }
    }
  });

  it("has the same plural and select branches as es for every key, in every language", () => {
    expect(icuShape("{n, plural, one {# día} other {# días}}")).toEqual([
      "branch:one",
      "branch:other",
      "plural",
    ]);
    let plurals = 0;
    for (const language of LANGUAGES) {
      for (const key of Object.keys(catalogs.es)) {
        const shape = icuShape(catalogs.es[key] ?? "");
        if (shape.length > 0 && language === "es") plurals++;
        expect(icuShape(catalogs[language][key] ?? ""), `${language}:${key}`).toEqual(shape);
      }
    }
    expect(plurals).toBeGreaterThan(10);
  });

  it("uses the same rich-text tags as es for every key, in every language", () => {
    for (const language of LANGUAGES) {
      for (const key of Object.keys(catalogs.es)) {
        expect(richTags(catalogs[language][key] ?? ""), `${language}:${key}`).toEqual(
          richTags(catalogs.es[key] ?? ""),
        );
      }
    }
  });

  it("keeps the line breaks of the one multi-line message (the feedback mail body)", () => {
    for (const language of LANGUAGES) {
      expect(catalogs[language]["settings.feedback.mail_body"]?.split("\n").length, language).toBe(
        2,
      );
    }
  });

  it("lists the four languages, each in its own name", () => {
    for (const language of LANGUAGES) {
      expect(catalogs[language]["language.es"], language).toBe("Español");
      expect(catalogs[language]["language.en"], language).toBe("English");
      expect(catalogs[language]["language.it"], language).toBe("Italiano");
      expect(catalogs[language]["language.pt"], language).toBe("Português");
    }
  });

  it("keeps the brand untranslated and the Colombian slang out of Italian and Portuguese", () => {
    for (const language of ["it", "pt"] as const) {
      expect(catalogs[language]["app.name"]).toBe("Wambito");
      for (const [key, value] of Object.entries(catalogs[language])) {
        expect(value, `${language}:${key}`).not.toMatch(/\blukas?\b|\bpalos?\b/i);
      }
    }
  });

  it("writes Portuguese as in Portugal: no Brazilian words", () => {
    // Unicode-aware boundaries: `\b` never matches next to an accented letter (você, ônibus).
    const brazilian =
      /(?<![\p{L}])(celular|tela|usuário|registrar|você|gastando|salvar|arquivo|deletar|baixar|aplicativo|cadastro|conta corrente|ônibus)(?![\p{L}])/iu;
    expect("obrigado, você sabe").toMatch(brazilian);
    expect("apanha o ônibus").toMatch(brazilian);
    expect("o teu telemóvel").not.toMatch(brazilian);
    expect("o Usuário").toMatch(brazilian);
    for (const [key, value] of Object.entries(catalogs.pt)) {
      expect(value, `pt:${key}`).not.toMatch(brazilian);
    }
  });

  it("never uses the old product or mascot name (the money slang is lowercase)", () => {
    for (const locale of LANGUAGES) {
      for (const [key, value] of Object.entries(catalogs[locale])) {
        expect(value, `${locale}:${key}`).not.toMatch(/Luk(?:itas)|\bLuk(?:as)\b/);
      }
    }
  });

  it("has no empty messages", () => {
    for (const locale of LANGUAGES) {
      for (const [key, value] of Object.entries(catalogs[locale])) {
        expect(value.trim(), `${locale}:${key}`).not.toBe("");
      }
    }
  });

  for (const locale of LANGUAGES) {
    describe(locale, () => {
      for (const [key, params] of Object.entries(WAMBI_KEYS)) {
        it(`has 3+ variants for wambi.${key} that all format`, () => {
          const variants = Object.keys(catalogs[locale]).filter((k) =>
            new RegExp(`^wambi\\.${key}\\.\\d+$`).test(k),
          );
          expect(variants.length).toBeGreaterThanOrEqual(3);
          // A bad ICU string or a missing param must fail the test, not fall back to the key path.
          const t = createTranslator({
            locale: intlTag(locale),
            messages: CATALOGS[locale],
            onError: (error) => {
              throw error;
            },
          });
          for (const variant of variants) {
            const text = t(variant as never, params as never);
            expect(text, variant).not.toBe(variant);
            expect(text, variant).not.toMatch(/[{}]/);
            expect(text.length, variant).toBeGreaterThan(0);
          }
        });
      }

      // After a save or a payment, Wambi says which movement it was (Task 12d).
      for (const key of ["first_of_day", "income_received", "pending_paid"] as const) {
        it(`names the movement in every wambi.${key} variant`, () => {
          const variants = Object.entries(catalogs[locale]).filter(([k]) =>
            new RegExp(`^wambi\\.${key}\\.\\d+$`).test(k),
          );
          for (const [variant, text] of variants) {
            expect(icuArguments(text), variant).toContain("name");
          }
        });
      }

      it("has no wambi messages for unknown keys", () => {
        const known = new Set(Object.keys(WAMBI_KEYS));
        for (const path of Object.keys(catalogs[locale])) {
          const match = /^wambi\.([a-z_]+)\./.exec(path);
          if (match) expect(known.has(match[1] as string), path).toBe(true);
        }
      });
    });
  }

  it("covers every API error code", () => {
    const codes = apiErrorCodes();
    expect(codes.length).toBeGreaterThan(10);
    // Each exception is a code the API really has: a stale entry would hide nothing but mislead.
    for (const code of ADMIN_ONLY_CODES) expect(codes, code).toContain(code);
    const userFacing = codes.filter(
      (code) => !(ADMIN_ONLY_CODES as readonly string[]).includes(code),
    );
    for (const code of [...userFacing, "generic"]) {
      for (const language of LANGUAGES) {
        expect(catalogs[language], `${language} errors.${code}`).toHaveProperty([`errors.${code}`]);
      }
    }
  });
});

describe("the admin panel's messages (Spanish and English only, spec §10)", () => {
  const ADMIN = { es: flatten(adminEs as Tree), en: flatten(adminEn as Tree) } as const;

  it("live in their own namespace, which no other catalog uses", () => {
    for (const catalog of [adminEs, adminEn]) expect(Object.keys(catalog)).toEqual(["admin"]);
    for (const language of LANGUAGES) {
      expect(Object.keys(CATALOGS[language]), language).not.toContain("admin");
    }
  });

  it("have the same keys, ICU arguments, branches and tags in es and en", () => {
    expect(Object.keys(ADMIN.en).sort()).toEqual(Object.keys(ADMIN.es).sort());
    for (const key of Object.keys(ADMIN.es)) {
      expect(icuArguments(ADMIN.en[key] ?? ""), key).toEqual(icuArguments(ADMIN.es[key] ?? ""));
      expect(icuShape(ADMIN.en[key] ?? ""), key).toEqual(icuShape(ADMIN.es[key] ?? ""));
      expect(richTags(ADMIN.en[key] ?? ""), key).toEqual(richTags(ADMIN.es[key] ?? ""));
    }
  });

  it("cover every code only the admin routes answer with", () => {
    for (const code of ADMIN_ONLY_CODES) {
      for (const language of ["es", "en"] as const) {
        expect(ADMIN[language], `${language} admin.errors.${code}`).toHaveProperty([
          `admin.errors.${code}`,
        ]);
      }
    }
  });

  it("are never empty and never use the old name", () => {
    for (const language of ["es", "en"] as const) {
      for (const [key, value] of Object.entries(ADMIN[language])) {
        expect(value.trim(), `${language}:${key}`).not.toBe("");
        expect(value, `${language}:${key}`).not.toMatch(/Luk(?:itas)|\bLuk(?:as)\b/);
      }
    }
  });
});

describe("deleting an account promises what is true (backups keep it up to 14 days)", () => {
  const DELETION = {
    es: "Borramos tu cuenta y todos tus movimientos de inmediato. Las copias de seguridad que los incluyan se borran solas en 14 días.",
    en: "We delete your account and all your entries right away. Backups that include them delete themselves within 14 days.",
    it: "Cancelliamo subito il tuo account e tutti i tuoi movimenti. Le copie di sicurezza che li includono si cancellano da sole entro 14 giorni.",
    pt: "Apagamos a tua conta e todos os teus movimentos de imediato. As cópias de segurança que os incluem apagam-se sozinhas em 14 dias.",
  } as const;

  for (const locale of LANGUAGES) {
    it(`${locale}: says when the backups go, and never "forever"`, () => {
      const lines = Object.entries(catalogs[locale]).filter(([key]) =>
        key.startsWith("settings.delete."),
      );
      expect(catalogs[locale]["settings.delete.lead"]).toBe(DELETION[locale]);
      for (const [key, line] of lines) {
        expect(line, key).not.toMatch(
          /para siempre|recuperarlos|no se puede deshacer|forever|for good|get them back|can't be undone|per sempre|irreversibil|non si può annullare|para sempre|irrevers|não se pode desfazer/i,
        );
      }
    });
  }
});

describe("the privacy answer claims only what open code shows", () => {
  const site = {
    es: flatten(siteEs as Tree),
    en: flatten(siteEn as Tree),
    it: flatten(siteIt as Tree),
    pt: flatten(sitePt as Tree),
  } as const;
  // The encryption happens on the device, in the open code, so anyone can check how it works.
  const ANSWER = {
    es: "El código es abierto: cualquiera puede revisar cómo se cifran.",
    en: "The code is open source: anyone can check how it is encrypted.",
    it: "Il codice è open source: chiunque può verificare come vengono cifrati.",
    pt: "O código é aberto: qualquer pessoa pode verificar como são encriptados.",
  } as const;

  for (const locale of LANGUAGES) {
    it(`${locale}: open code shows what the code does, not what a server does`, () => {
      expect(site[locale]["landing.faq.privacy.a"]).toContain(ANSWER[locale]);
      for (const [key, line] of Object.entries(site[locale])) {
        expect(line, key).not.toMatch(
          /comprobar qué hacemos|qué hacemos con ellos|check what we do|what we do with it|controllare cosa facciamo|verificare cosa facciamo|verificar o que fazemos|conferir o que fazemos/i,
        );
      }
    });
  }
});

describe("the automatic capture copy", () => {
  const site = {
    es: flatten(siteEs as Tree),
    en: flatten(siteEn as Tree),
    it: flatten(siteIt as Tree),
    pt: flatten(sitePt as Tree),
  } as const;
  const STEPS = ["pay", "reads", "decide", "learns", "next"];
  // Every word is checked in every locale: a word of any language counts.
  const LANGUAGE_WORDS = [
    "portugu[eéê]s",
    "portuguese",
    "portoghese",
    "espa[nñ]ol",
    "spanish",
    "espanhol",
    "spagnolo",
    "ingl[eéê]s",
    "english",
    "inglese",
    "italiano",
    "italian",
    "idiomas?",
    "languages?",
    "lingua",
    "lingue",
    "l[ií]nguas?",
  ].map((word) => new RegExp(`\\b${word}\\b`, "i"));

  const captureCopy = (locale: (typeof LANGUAGES)[number]) =>
    Object.entries(site[locale]).filter(
      ([key]) => key.startsWith("landing.capture.") || key.startsWith("roadmap.items.bank_alerts."),
    );

  it("the language words match every accented and plural form", () => {
    const forms = [
      "portugués",
      "português",
      "portugues",
      "portuguese",
      "portoghese",
      "español",
      "espanol",
      "spanish",
      "espanhol",
      "spagnolo",
      "inglés",
      "inglês",
      "ingles",
      "english",
      "inglese",
      "italiano",
      "italian",
      "idioma",
      "idiomas",
      "language",
      "languages",
      "lingua",
      "lingue",
      "língua",
      "línguas",
      "linguas",
    ];
    for (const form of forms) {
      expect(
        LANGUAGE_WORDS.some((word) => word.test(`en ${form}.`)),
        form,
      ).toBe(true);
    }
  });

  for (const locale of LANGUAGES) {
    it(`${locale}: has every step, with a title and a body`, () => {
      const keys = new Set(
        Object.keys(site[locale])
          .filter((key) => key.startsWith("landing.capture.steps."))
          .map((key) => key.split(".")[3]),
      );
      expect([...keys].sort()).toEqual([...STEPS].sort());
      for (const step of STEPS) {
        expect(site[locale][`landing.capture.steps.${step}.title`], step).toBeTruthy();
        expect(site[locale][`landing.capture.steps.${step}.body`], step).toBeTruthy();
      }
    });

    it(`${locale}: names no language`, () => {
      const lines = captureCopy(locale);
      expect(lines.length).toBeGreaterThan(20);
      for (const [key, line] of lines) {
        for (const word of LANGUAGE_WORDS) expect(line, `${key} ${word}`).not.toMatch(word);
      }
    });

    it(`${locale}: says Revolut and Google Wallet, with no "soon" badge on the card`, () => {
      const copy = site[locale];
      expect(copy["landing.capture.card.badge"]).toBeUndefined();
      expect(copy["landing.capture.card.body"]).toContain("Revolut");
      expect(copy["landing.capture.card.body"]).toContain("Google Wallet");
      expect(copy["landing.capture.steps.next.body"]).toContain("Revolut");
      expect(copy["landing.capture.steps.next.body"]).toContain("Google Wallet");
    });
  }
});
