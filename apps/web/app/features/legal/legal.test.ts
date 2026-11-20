import { createTranslator } from "use-intl/core";
import { describe, expect, it } from "vitest";
import en from "../../i18n/messages/en.json" with { type: "json" };
import es from "../../i18n/messages/es.json" with { type: "json" };
import itMessages from "../../i18n/messages/it.json" with { type: "json" };
import ptMessages from "../../i18n/messages/pt.json" with { type: "json" };
import {
  ANALYTICS_RETENTION,
  DELETE_ACCOUNT_SECTIONS,
  LEGAL_MESSAGES,
  PRIVACY_SECTIONS,
  privacySections,
} from "./legal.ts";

type Section = { title?: string; body?: string };
type Legal = {
  title?: string;
  version?: string;
  sections?: Record<string, Section>;
};

const CATALOGS = { es, en, it: itMessages, pt: ptMessages } as const;
const PAGES = { privacy: PRIVACY_SECTIONS, deleteAccount: DELETE_ACCOUNT_SECTIONS } as const;
/** Every privacy section a catalog holds: the keyless list plus the two analytics-build ones. */
const ALL_PRIVACY = [...new Set([...PRIVACY_SECTIONS, ...privacySections(true)])].sort();

/** Each language's words for "the notification text never leaves your phone". */
const NOTIFICATION_STAYS: Record<keyof typeof CATALOGS, string> = {
  es: "nunca sale de tu teléfono",
  en: "never leaves your phone",
  it: "non lascia mai il tuo telefono",
  pt: "nunca sai do teu telemóvel",
};

/**
 * Each language's "end to end": the analytics sections must not use it, since plain accounts are
 * not encrypted; app data stays out because PostHog never loads in the app.
 */
const END_TO_END: Record<keyof typeof CATALOGS, string> = {
  es: "extremo a extremo",
  en: "end to end",
  it: "end-to-end",
  pt: "ponta a ponta",
};

function legal(locale: keyof typeof CATALOGS, page: keyof typeof PAGES): Legal {
  const tree = CATALOGS[locale].legal as unknown as Record<string, Legal>;
  return tree[LEGAL_MESSAGES[page]] ?? {};
}

describe("legal pages", () => {
  it("list their sections in the agreed order", () => {
    expect(PRIVACY_SECTIONS).toEqual([
      "controller",
      "data",
      "purposes",
      "storage",
      "not_done",
      "voice",
      "capture",
      "assistants",
      "guest",
      "self_hosted",
      "rights",
      "changes",
    ]);
    expect(DELETE_ACCOUNT_SECTIONS).toEqual(["in_app", "by_email", "what_goes", "backups"]);
  });

  it("privacy without analytics: today's list, unchanged", () => {
    expect(privacySections(false)).toEqual(PRIVACY_SECTIONS);
  });

  it("privacy with analytics: the analytics section after storage, its own not_done", () => {
    const sections = privacySections(true);
    expect(sections[sections.indexOf("storage") + 1]).toBe("analytics");
    expect(sections).toContain("not_done_with_analytics");
    expect(sections).not.toContain("not_done");
    expect(sections).toHaveLength(PRIVACY_SECTIONS.length + 1);
  });

  it("privacy (es): the analytics section names PostHog, the contact and the retention", () => {
    const t = createTranslator({ locale: "es", messages: es });
    const body = t.markup("legal.privacy.sections.analytics.body", {
      ...ANALYTICS_RETENTION,
      email: (chunks) => chunks,
    });
    expect(body).toContain("PostHog");
    expect(body).toContain("privacy@wambito.com");
    expect(body).toContain(String(ANALYTICS_RETENTION.eventsMonths));
    expect(body).toContain(String(ANALYTICS_RETENTION.recordingsDays));
  });

  for (const locale of Object.keys(CATALOGS) as (keyof typeof CATALOGS)[]) {
    describe(locale, () => {
      for (const page of Object.keys(PAGES) as (keyof typeof PAGES)[]) {
        it(`${page}: has a title, a version line and every section, none empty`, () => {
          const messages = legal(locale, page);
          expect(messages.title?.trim()).toBeTruthy();
          expect(messages.version?.trim()).toBeTruthy();
          const keys = Object.keys(messages.sections ?? {});
          if (page === "privacy") expect([...keys].sort()).toEqual(ALL_PRIVACY);
          else expect(keys).toEqual([...PAGES[page]]);
          for (const key of PAGES[page]) {
            const section = messages.sections?.[key];
            expect(section?.title?.trim(), `${key}.title`).toBeTruthy();
            expect(section?.body?.trim(), `${key}.body`).toBeTruthy();
          }
        });
      }

      it("privacy with analytics: every section has a title and a body", () => {
        const sections = legal(locale, "privacy").sections ?? {};
        for (const key of privacySections(true)) {
          expect(sections[key]?.title?.trim(), `${key}.title`).toBeTruthy();
          expect(sections[key]?.body?.trim(), `${key}.body`).toBeTruthy();
        }
      });

      it("privacy: the analytics section names the footer's withdraw link as the footer does", () => {
        const body = legal(locale, "privacy").sections?.analytics?.body ?? "";
        expect(body).toContain(CATALOGS[locale].landing.footer.cookies);
        expect(body).toContain("<email>privacy@wambito.com</email>");
        expect(body).toContain("PostHog Inc.");
      });

      it("privacy: the analytics sections say why app data stays out, without an E2E claim", () => {
        const sections = legal(locale, "privacy").sections ?? {};
        for (const key of ["analytics", "not_done_with_analytics"]) {
          const body = sections[key]?.body ?? "";
          expect(body, key).not.toContain(END_TO_END[locale]);
          expect(body, key).toContain("app.wambito.com");
        }
      });

      it("privacy: names the controller, the law and the contact", () => {
        const sections = legal(locale, "privacy").sections ?? {};
        expect(sections.controller?.body).toContain("privacy@wambito.com");
        expect(sections.rights?.body).toContain("privacy@wambito.com");
        expect(sections.controller?.body).toContain("Slinqer S.A.S.");
        expect(sections.controller?.body).toContain("1581");
      });

      it("privacy: automatic capture names its apps and keeps the notification on the phone", () => {
        const body = legal(locale, "privacy").sections?.capture?.body ?? "";
        expect(body).toContain("Revolut");
        expect(body).toContain("Google Wallet");
        expect(body).toContain(NOTIFICATION_STAYS[locale]);
      });

      it("says backups go within 14 days, on both pages", () => {
        expect(legal(locale, "privacy").sections?.storage?.body).toContain("14");
        expect(legal(locale, "deleteAccount").sections?.backups?.body).toContain("14");
      });

      it("deletion by email names the contact", () => {
        expect(legal(locale, "deleteAccount").sections?.by_email?.body).toContain(
          "privacy@wambito.com",
        );
      });
    });
  }
});
