import type { Meta, StoryObj } from "@storybook/react-vite";
import { expect, within } from "storybook/test";
import type { Assistant } from "../assistants/queries.ts";
import { HomeStage, storyPasskeys } from "../home/story-harness.tsx";
import type { PasskeyItem } from "./passkeys.ts";

/**
 * Settings as the phone draws it (docs/mobile/parity.md, "Settings"): the menu and each category
 * the web shares with the phone, at rest, at night in Spanish, by day in English, and at night in
 * Italian and European Portuguese. The pairs are in apps/mobile/test/parity/parity.json; the app's
 * side is `test/parity/settings_parity_test.dart` and `it_pt_parity_test.dart`.
 */

const CLAUDE: Assistant = {
  clientId: "https://claude.ai/oauth/mcp-oauth-client-metadata",
  name: "Claude",
  icon: null,
  uri: "https://claude.ai",
  domain: "claude.ai",
  scopes: ["finance:read", "finance:write", "offline_access"],
  connectedAt: "2026-10-02T09:00:00.000Z",
  lastUsedAt: "2026-10-20T18:30:00.000Z",
};

const CHATGPT: Assistant = {
  clientId: "dcr-chatgpt-1",
  name: "ChatGPT",
  icon: null,
  uri: "https://chatgpt.com",
  domain: "chatgpt.com",
  scopes: ["finance:read"],
  connectedAt: "2026-10-05T09:00:00.000Z",
  lastUsedAt: null,
};

/** The account's two passkeys (one named, one synced); the app's test hands it the same list. */
export const PARITY_PASSKEYS: PasskeyItem[] = [
  {
    id: "pk-1",
    credentialId: "cred-1",
    name: null,
    createdAt: "2026-10-02T09:00:00.000Z",
    synced: true,
  },
  {
    id: "pk-2",
    credentialId: "cred-2",
    name: "Pixel 9",
    createdAt: "2026-10-05T10:00:00.000Z",
    synced: false,
  },
];

type Screen = "menu" | "agents" | "account" | "preferences" | "data" | "more";

const PATHS: Record<Screen, string> = {
  menu: "/app/settings",
  agents: "/app/settings/agents",
  account: "/app/settings/account",
  preferences: "/app/settings/preferences",
  data: "/app/settings/data",
  more: "/app/settings/more",
};

function Stage({ screen }: { screen: Screen }) {
  return (
    <HomeStage
      onRequest={() => {}}
      path={PATHS[screen]}
      assistants={[CHATGPT, CLAUDE]}
      passkeys={storyPasskeys({ initial: PARITY_PASSKEYS })}
      // The phone shows its server's address: the default one.
      agentsOrigin="https://app.wambito.com"
    />
  );
}

const meta = {
  title: "Settings/Parity",
  component: Stage,
} satisfies Meta<typeof Stage>;

export default meta;
type Story = StoryObj<typeof meta>;

/** The menu's name (its navigation's label) in each language. */
const MENU: Record<"es" | "en" | "it" | "pt", string> = {
  es: "Ajustes",
  en: "Settings",
  it: "Impostazioni",
  pt: "Definições",
};

/** Waits until the screen has drawn what its API answered: the picture is of the page at rest. */
async function settled(canvasElement: HTMLElement, screen: Screen, lang: keyof typeof MENU) {
  const canvas = within(canvasElement);
  await canvas.findByRole("heading", { level: 1 });
  switch (screen) {
    case "menu":
      await expect(await canvas.findByRole("navigation", { name: MENU[lang] })).toBeVisible();
      break;
    case "agents":
      // Both grants listed, their dates written.
      await expect((await canvas.findAllByText(/2026 ·/)).length).toBe(2);
      break;
    case "account":
      await expect(await canvas.findByText("Pixel 9")).toBeVisible();
      break;
    case "preferences":
      await expect(await canvas.findByText("EUR")).toBeVisible();
      break;
    case "data":
    case "more":
      break;
  }
  // The pictures are at rest: no focus ring.
  (document.activeElement as HTMLElement | null)?.blur();
}

const story = (screen: Screen, lang: keyof typeof MENU, theme: "night" | "day"): Story => ({
  args: { screen },
  globals: { theme, locale: lang },
  play: ({ canvasElement }) => settled(canvasElement, screen, lang),
});

export const MenuNight = story("menu", "es", "night");
export const MenuDayEnglish = story("menu", "en", "day");
export const MenuItalian = story("menu", "it", "night");
export const MenuPortuguese = story("menu", "pt", "night");

export const AgentsNight = story("agents", "es", "night");
export const AgentsDayEnglish = story("agents", "en", "day");
export const AgentsItalian = story("agents", "it", "night");
export const AgentsPortuguese = story("agents", "pt", "night");

export const AccountNight = story("account", "es", "night");
export const AccountDayEnglish = story("account", "en", "day");
export const AccountItalian = story("account", "it", "night");
export const AccountPortuguese = story("account", "pt", "night");

export const PreferencesNight = story("preferences", "es", "night");
export const PreferencesDayEnglish = story("preferences", "en", "day");
export const PreferencesItalian = story("preferences", "it", "night");
export const PreferencesPortuguese = story("preferences", "pt", "night");

export const DataNight = story("data", "es", "night");
export const DataDayEnglish = story("data", "en", "day");
export const DataItalian = story("data", "it", "night");
export const DataPortuguese = story("data", "pt", "night");

export const MoreNight = story("more", "es", "night");
export const MoreDayEnglish = story("more", "en", "day");
export const MoreItalian = story("more", "it", "night");
export const MorePortuguese = story("more", "pt", "night");
