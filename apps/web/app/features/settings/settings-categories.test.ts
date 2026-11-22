import { describe, expect, it } from "vitest";
import { isSettingsCategory, settingsCategories } from "./settings-categories.ts";

describe("settingsCategories", () => {
  it("lists the web's categories in order, with no capture", () => {
    expect(settingsCategories()).toEqual(["agents", "account", "preferences", "data", "more"]);
  });
});

describe("isSettingsCategory", () => {
  it("accepts the web's categories", () => {
    for (const category of settingsCategories()) {
      expect(isSettingsCategory(category)).toBe(true);
    }
  });

  it("refuses anything else, capture included", () => {
    expect(isSettingsCategory("capture")).toBe(false);
    expect(isSettingsCategory("")).toBe(false);
    expect(isSettingsCategory("Agents")).toBe(false);
  });
});
