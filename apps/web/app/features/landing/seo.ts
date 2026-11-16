import type { LinkDescriptor, MetaDescriptor } from "react-router";
import { createTranslator } from "use-intl/core";
import { intlTag, LOCALES, type Locale } from "../../i18n/format.ts";
import en from "../../i18n/messages/en.json" with { type: "json" };
import es from "../../i18n/messages/es.json" with { type: "json" };
import it from "../../i18n/messages/it.json" with { type: "json" };
import pt from "../../i18n/messages/pt.json" with { type: "json" };
import { SITE_ORIGIN } from "../../site/config.ts";
import { LANDING_PATH, PAGE_PATH, type SitePage } from "../../site/paths.ts";
import { landingFontPreloads } from "./font-preloads.ts";

export { LANDING_PATH };

/** The 1200×630 share images rendered by `scripts/og/render.ts`. */
const OG_IMAGE = { width: 1200, height: 630 };

const CATALOGS = { es, en, it, pt } as const;

/** Absolute URLs use the site's origin (`VITE_SITE_URL`, see `app/site/config.ts`). */
function absolute(path: string): string {
  return `${SITE_ORIGIN}${path}`;
}

interface PageTags {
  locale: Locale;
  path: string;
  title: string;
  description: string;
  imageAlt: string;
}

/** Title, description and Open Graph / Twitter tags of a public page. */
function tags({ locale, path, title, description, imageAlt }: PageTags): MetaDescriptor[] {
  const url = absolute(path);
  const image = absolute(`/og-${locale}.png`);
  return [
    { title },
    { name: "description", content: description },
    { property: "og:type", content: "website" },
    { property: "og:site_name", content: "Wambito" },
    { property: "og:title", content: title },
    { property: "og:description", content: description },
    { property: "og:url", content: url },
    { property: "og:image", content: image },
    { property: "og:image:width", content: String(OG_IMAGE.width) },
    { property: "og:image:height", content: String(OG_IMAGE.height) },
    { property: "og:image:alt", content: imageAlt },
    { name: "twitter:card", content: "summary_large_image" },
  ];
}

/** Canonical and `hreflang` alternates of a public page: every language, itself included, plus `x-default` → Spanish. */
function pageLinks(page: SitePage, locale: Locale): LinkDescriptor[] {
  const paths = PAGE_PATH[page];
  return [
    { rel: "canonical", href: absolute(paths[locale]) },
    ...LOCALES.map((language) => ({
      rel: "alternate",
      hrefLang: language,
      href: absolute(paths[language]),
    })),
    { rel: "alternate", hrefLang: "x-default", href: absolute(paths.es) },
  ];
}

/** Title, description and Open Graph / Twitter tags for a landing page. */
export function landingMeta(locale: Locale): MetaDescriptor[] {
  const t = createTranslator({
    locale: intlTag(locale),
    messages: CATALOGS[locale],
    namespace: "landing.meta",
  });
  return tags({
    locale,
    path: LANDING_PATH[locale],
    title: t("title"),
    description: t("description"),
    imageAlt: t("image_alt"),
  });
}

/**
 * Canonical and `hreflang` alternates (each page lists every language, itself included, plus
 * `x-default` → Spanish), and the fonts' preloads. (No image preload: the hero has no Wambi any
 * more; he waits further down the page.)
 */
export function landingLinks(locale: Locale): LinkDescriptor[] {
  return [...pageLinks("landing", locale), ...landingFontPreloads()];
}

/** The i18n namespace holding each page's `meta` (title and description). */
const META_NAMESPACE = {
  roadmap: "roadmap.meta",
  privacy: "legal.privacy.meta",
  deleteAccount: "legal.delete_account.meta",
  automaticCapture: "landing.capture.page.meta",
} as const satisfies Record<Exclude<SitePage, "landing">, string>;

/**
 * A secondary page's own title and description. It shares the landing's 1200×630 share image (and
 * its alt text, which describes that image).
 */
export function pageMeta(page: Exclude<SitePage, "landing">, locale: Locale): MetaDescriptor[] {
  const messages = CATALOGS[locale];
  const t = createTranslator({
    locale: intlTag(locale),
    messages,
    namespace: META_NAMESPACE[page],
  });
  const image = createTranslator({ locale: intlTag(locale), messages, namespace: "landing.meta" });
  return tags({
    locale,
    path: PAGE_PATH[page][locale],
    title: t("title"),
    description: t("description"),
    imageAlt: image("image_alt"),
  });
}

/** Canonical and `hreflang` alternates of a secondary page. */
export function pageLinksFor(page: Exclude<SitePage, "landing">, locale: Locale): LinkDescriptor[] {
  return [...pageLinks(page, locale), ...landingFontPreloads()];
}

/** The roadmap page's meta. */
export function roadmapMeta(locale: Locale): MetaDescriptor[] {
  return pageMeta("roadmap", locale);
}

/** Canonical and `hreflang` alternates of the roadmap page. */
export function roadmapLinks(locale: Locale): LinkDescriptor[] {
  return pageLinksFor("roadmap", locale);
}
