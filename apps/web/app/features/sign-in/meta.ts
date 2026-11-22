import type { MetaDescriptor } from "react-router";
import { createTranslator } from "use-intl/core";
import { CATALOGS } from "../../i18n/catalog.ts";
import { langFrom } from "./auth.ts";

/** The tab title of a sign-in screen, in the language of `?lang=` (Spanish by default). Not indexed. */
export function signInMeta(
  screen: "sign_in" | "sign_in.create" | "verify",
  search: string,
): MetaDescriptor[] {
  const locale = langFrom(new URLSearchParams(search).get("lang")) ?? "es";
  const t = createTranslator({ locale, messages: CATALOGS[locale], namespace: screen });
  return [{ title: t("meta_title") }, { name: "robots", content: "noindex" }];
}
