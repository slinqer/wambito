/**
 * The settings menu's categories on the web, in the order the menu shows them. The web has no
 * capture: that one lives on the phone.
 */

export type SettingsCategory = "agents" | "account" | "preferences" | "data" | "more";

const categories: readonly SettingsCategory[] = [
  "agents",
  "account",
  "preferences",
  "data",
  "more",
];

/** The web's categories, in menu order. */
export function settingsCategories(): SettingsCategory[] {
  return [...categories];
}

/** Whether `x` is one of the web's categories. */
export function isSettingsCategory(x: string): x is SettingsCategory {
  return (categories as readonly string[]).includes(x);
}
