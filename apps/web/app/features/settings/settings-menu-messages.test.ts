import { describe, expect, it } from "vitest";
import { CATALOGS } from "../../i18n/catalog.ts";
import { settingsCategories } from "./settings-categories.ts";

type Menu = Record<string, string | Record<string, string>>;

describe("settings.menu messages", () => {
  for (const locale of ["es", "en", "it", "pt"] as const) {
    const menu = (CATALOGS[locale].settings as { menu?: Menu }).menu;

    it(`${locale}: every category has a title and a line`, () => {
      expect(menu).toBeDefined();
      for (const category of settingsCategories()) {
        const entry = menu?.[category] as Record<string, string> | undefined;
        expect(entry?.title, `${category}.title`).toBeTruthy();
        expect(entry?.line, `${category}.line`).toBeTruthy();
      }
    });

    it(`${locale}: the preferences line takes the language, the theme and the currency`, () => {
      const line = (menu?.preferences as Record<string, string> | undefined)?.line ?? "";
      for (const slot of ["{language}", "{theme}", "{currency}"]) expect(line).toContain(slot);
    });

    it(`${locale}: the back link and the unknown-category page are worded`, () => {
      for (const key of ["back", "back_short", "not_found_title", "not_found_lead"]) {
        expect(menu?.[key], key).toBeTruthy();
      }
    });
  }
});
