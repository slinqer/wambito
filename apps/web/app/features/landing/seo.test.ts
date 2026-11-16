import { describe, expect, it } from "vitest";
import { SITE_ORIGIN } from "../../site/config.ts";
import { sitemapXml } from "../../site/files.ts";
import {
  landingLinks,
  landingMeta,
  pageLinksFor,
  pageMeta,
  roadmapLinks,
  roadmapMeta,
} from "./seo.ts";

function metaContent(
  tags: ReturnType<typeof roadmapMeta>,
  key: "name" | "property",
  value: string,
) {
  const tag = tags.find((t) => (t as Record<string, unknown>)[key] === value);
  return (tag as { content?: string } | undefined)?.content;
}

describe("roadmapMeta", () => {
  it("gives each language its own title, description and URL", () => {
    const es = roadmapMeta("es");
    const en = roadmapMeta("en");
    expect(es).toContainEqual({ title: "Wambito · Lo que viene" });
    expect(en).toContainEqual({ title: "Wambito · What's next" });
    expect(metaContent(es, "name", "description")?.length).toBeGreaterThan(60);
    expect(metaContent(en, "name", "description")?.length).toBeGreaterThan(60);
    expect(metaContent(es, "property", "og:url")).toBe(`${SITE_ORIGIN}/roadmap`);
    expect(metaContent(en, "property", "og:url")).toBe(`${SITE_ORIGIN}/en/roadmap`);
    expect(metaContent(es, "property", "og:title")).toBe("Wambito · Lo que viene");
    expect(metaContent(es, "property", "og:image")).toBe(`${SITE_ORIGIN}/og-es.png`);
    expect(metaContent(en, "property", "og:site_name")).toBe("Wambito");
  });

  it("does not repeat the landing's description", () => {
    expect(metaContent(roadmapMeta("es"), "name", "description")).not.toBe(
      metaContent(landingMeta("es"), "name", "description"),
    );
  });
});

describe("roadmapLinks", () => {
  it("is canonical to itself and lists every language plus x-default to Spanish", () => {
    const links = roadmapLinks("en");
    expect(links).toContainEqual({ rel: "canonical", href: `${SITE_ORIGIN}/en/roadmap` });
    expect(links).toContainEqual({
      rel: "alternate",
      hrefLang: "es",
      href: `${SITE_ORIGIN}/roadmap`,
    });
    expect(links).toContainEqual({
      rel: "alternate",
      hrefLang: "en",
      href: `${SITE_ORIGIN}/en/roadmap`,
    });
    expect(links).toContainEqual({
      rel: "alternate",
      hrefLang: "x-default",
      href: `${SITE_ORIGIN}/roadmap`,
    });
  });

  it("leaves the landing's own links alone", () => {
    expect(landingLinks("es")).toContainEqual({ rel: "canonical", href: `${SITE_ORIGIN}/` });
  });
});

describe("Italian and Portuguese pages", () => {
  it("title and describe each page in its own language, at its own URL and share image", () => {
    const it = landingMeta("it");
    const pt = landingMeta("pt");
    expect(it).toContainEqual({ title: "Wambito · L'app che tiene i conti delle tue spese per te" });
    expect(pt).toContainEqual({ title: "Wambito · A app que gere as tuas despesas por ti" });
    expect(metaContent(it, "property", "og:url")).toBe(`${SITE_ORIGIN}/it`);
    expect(metaContent(pt, "property", "og:url")).toBe(`${SITE_ORIGIN}/pt`);
    expect(metaContent(it, "property", "og:image")).toBe(`${SITE_ORIGIN}/og-it.png`);
    expect(metaContent(pt, "property", "og:image")).toBe(`${SITE_ORIGIN}/og-pt.png`);
    expect(roadmapMeta("it")).toContainEqual({ title: "Wambito · In arrivo" });
    expect(roadmapMeta("pt")).toContainEqual({ title: "Wambito · O que vem aí" });
    expect(metaContent(roadmapMeta("it"), "property", "og:url")).toBe(`${SITE_ORIGIN}/it/roadmap`);
    expect(metaContent(roadmapMeta("pt"), "property", "og:url")).toBe(`${SITE_ORIGIN}/pt/roadmap`);
  });

  it("every page lists the four languages as alternates, plus x-default to Spanish", () => {
    for (const links of [
      landingLinks("it"),
      landingLinks("pt"),
      roadmapLinks("it"),
      roadmapLinks("pt"),
    ]) {
      const hrefLangs = links.flatMap((link) =>
        "rel" in link && link.rel === "alternate" ? [link.hrefLang] : [],
      );
      expect(hrefLangs).toEqual(["es", "en", "it", "pt", "x-default"]);
    }
    expect(landingLinks("pt")).toContainEqual({ rel: "canonical", href: `${SITE_ORIGIN}/pt` });
    expect(roadmapLinks("it")).toContainEqual({
      rel: "canonical",
      href: `${SITE_ORIGIN}/it/roadmap`,
    });
  });
});

describe("the automatic capture page", () => {
  it("has a title, description and URL in every language", () => {
    expect(pageMeta("automaticCapture", "es")).toContainEqual({
      title: "Wambito · Captura automática",
    });
    expect(metaContent(pageMeta("automaticCapture", "en"), "property", "og:url")).toBe(
      `${SITE_ORIGIN}/en/automatic-capture`,
    );
    expect(
      metaContent(pageMeta("automaticCapture", "pt"), "name", "description")?.length,
    ).toBeGreaterThan(40);
  });

  it("lists the four languages plus x-default and is in the sitemap", () => {
    const links = pageLinksFor("automaticCapture", "it");
    const hrefLangs = links.flatMap((link) =>
      "rel" in link && link.rel === "alternate" ? [link.hrefLang] : [],
    );
    expect(hrefLangs).toEqual(["es", "en", "it", "pt", "x-default"]);
    expect(links).toContainEqual({
      rel: "canonical",
      href: `${SITE_ORIGIN}/it/automatic-capture`,
    });
    expect(sitemapXml(SITE_ORIGIN)).toContain(`<loc>${SITE_ORIGIN}/pt/automatic-capture</loc>`);
  });
});

describe("pageMeta and pageLinksFor", () => {
  it("gives the privacy page its own title and URL, not the roadmap's", () => {
    const en = pageMeta("privacy", "en");
    expect(en).not.toContainEqual({ title: "Wambito · What's next" });
    expect(metaContent(en, "property", "og:url")).toBe(`${SITE_ORIGIN}/en/privacy`);
    expect(metaContent(en, "name", "description")?.length).toBeGreaterThan(20);
  });

  it("keeps the roadmap wrappers equal to the generic helpers", () => {
    expect(roadmapMeta("it")).toEqual(pageMeta("roadmap", "it"));
    expect(roadmapLinks("it")).toEqual(pageLinksFor("roadmap", "it"));
  });

  it("makes the account deletion page canonical to itself", () => {
    expect(pageLinksFor("deleteAccount", "es")).toContainEqual({
      rel: "canonical",
      href: `${SITE_ORIGIN}/delete-account`,
    });
  });
});
