import type { Meta, StoryObj } from "@storybook/react-vite";
import { useState } from "react";
import { MemoryRouter, Outlet, Route, Routes } from "react-router";
import { expect, userEvent, waitFor, within } from "storybook/test";
import { exposeStoryFetch } from "../../.storybook/parity.ts";
import { ApiProvider } from "../api/ApiProvider.tsx";
import { CategoryDetail } from "../features/categories/CategoryDetail.tsx";
import { AppShell } from "../features/home/AppShell.tsx";
import { Home } from "../features/home/Home.tsx";
import { SettingsAll } from "../features/home/story-harness.tsx";
import { Insights } from "../features/insights/Insights.tsx";
import { RecurringPage } from "../features/recurring/RecurringPage.tsx";
import { SettingsMenu } from "../features/settings/SettingsMenu.tsx";
import { AppMessages } from "../i18n/AppMessages.tsx";
import { type Locale } from "../i18n/format.ts";
import { IntlProvider, useLocale } from "../i18n/IntlProvider.tsx";
import { ToastProvider } from "../ui/Toast.tsx";
import { DemoBanner } from "./DemoBanner.tsx";
import { createDemoBackend } from "./demo-backend.ts";
import { DEMO_SEED } from "./demo-data.ts";
import { fakeClock } from "./fake-clock.ts";

/**
 * The page's clock in these stories: mid-afternoon on 21 October 2026, for the screens (which ask
 * `new Date()` which month it is) and the backend alike, so the figures below hold on any real date.
 */
const NOW = new Date("2026-10-21T18:00:00Z");

/**
 * `VITE_STORY_SYSTEM_DATE=2026-11-15` pretends the machine's own date is another one, to check
 * that nothing here still reads the real clock (`fakeClock` stacks on top of it).
 */
const SYSTEM_DATE = import.meta.env.VITE_STORY_SYSTEM_DATE as string | undefined;

/**
 * The demo as routes/demo.tsx builds it, in a memory router: the app's shell and screens under
 * `/demo`, against the real in-memory backend (Valentina, in the toolbar's language), with the
 * banner on top.
 */
function DemoStage({ path }: { path: string }) {
  const storyLocale = useLocale().locale;
  const [locale, setLocale] = useState<Locale>(storyLocale);
  // The backend reads the same (faked) clock as the screens: `new Date()`.
  const [backend] = useState(() => createDemoBackend(DEMO_SEED[storyLocale]));
  const [fetchImpl] = useState(() => exposeStoryFetch(backend.fetch));
  return (
    <IntlProvider locale={locale} onLocaleChange={setLocale}>
      <AppMessages>
        <MemoryRouter initialEntries={[path]}>
          <ApiProvider mode="demo" fetch={fetchImpl}>
            <ToastProvider>
              <Routes>
                <Route
                  path="/demo"
                  element={
                    <AppShell banner={<DemoBanner />}>
                      <Outlet />
                    </AppShell>
                  }
                >
                  <Route index element={<Home />} />
                  <Route path="categories/:id" element={<CategoryDetail />} />
                  <Route path="recurring" element={<RecurringPage />} />
                  <Route path="insights" element={<Insights />} />
                  <Route path="settings" element={<SettingsMenu />} />
                  <Route path="settings/all" element={<SettingsAll />} />
                </Route>
              </Routes>
            </ToastProvider>
          </ApiProvider>
        </MemoryRouter>
      </AppMessages>
    </IntlProvider>
  );
}

const meta = {
  title: "Demo/Screens",
  component: DemoStage,
  parameters: { layout: "fullscreen" },
  beforeEach: () => {
    const restoreSystem = SYSTEM_DATE ? fakeClock(new Date(SYSTEM_DATE)) : () => {};
    const restore = fakeClock(NOW);
    return () => {
      restore();
      restoreSystem();
    };
  },
} satisfies Meta<typeof DemoStage>;

export default meta;
type Story = StoryObj<typeof meta>;

/**
 * Valentina's home in pesos: the banner on top, $638.100 left of $3.980.000 this month, and every
 * link into the app stays under /demo.
 */
export const HomeInPesos: Story = {
  args: { path: "/demo" },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await expect(await canvas.findByRole("complementary", { name: "Demo" })).toBeVisible();
    const hero = await canvas.findByRole("region", { name: "Te quedan este mes" });
    await waitFor(() => expect(hero).toHaveTextContent(/\$[\d.]+/));
    await expect(
      await canvas.findByRole("meter", { name: "Gastado $3.341.900 de $3.980.000" }),
    ).toBeVisible();
    const hrefs = [...canvasElement.querySelectorAll("a[href]")].map((a) => a.getAttribute("href"));
    await expect(hrefs.filter((href) => href?.startsWith("/app"))).toEqual([]);
    await expect(hrefs).toContain("/demo/insights");
    // October 2026 on any real date: the month on screen is the clock's.
    await expect(canvas.getByRole("group", { name: "Mes" })).toHaveTextContent("Octubre");
  },
};

/** Insights in pesos: October's spending by category, rent first, from the same clock. */
export const InsightsInPesos: Story = {
  args: { path: "/demo/insights" },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await expect(
      await canvas.findByText("Arriendo fue lo que más lukas se llevó en octubre: $1.800.000."),
    ).toBeVisible();
    const hrefs = [...canvasElement.querySelectorAll("a[href]")].map((a) => a.getAttribute("href"));
    await expect(hrefs.filter((href) => href?.startsWith("/app"))).toEqual([]);
    // The a11y check runs on the settled screen: nothing loading, nothing mid-fade (as in
    // Insights.stories.tsx).
    await waitFor(
      () => {
        expect(canvasElement.querySelector("[aria-busy='true']")).toBeNull();
        const moving = canvasElement.querySelectorAll<HTMLElement>(
          "section, li, .lk-insight-body, [style*='opacity']",
        );
        for (const el of moving) expect(getComputedStyle(el).opacity).toBe("1");
      },
      { timeout: 8000 },
    );
  },
};

/**
 * Settings in the demo, by day and in English: passkeys, import, export and deleting the account
 * are off, each with the note; language, theme, sound and time zone still work.
 */
export const SettingsOffByDay: Story = {
  args: { path: "/demo/settings/all" },
  globals: { theme: "day", locale: "en" },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await canvas.findByRole("heading", { name: "Settings", level: 1 });
    // No sign-in happened: the line says whose made-up account this is.
    await expect(canvas.getByText("You're viewing Valentina's demo.")).toBeVisible();
    await expect(canvas.queryByText(/Signed in as/)).toBeNull();
    const note = "Not available in the demo. Create your account to use it.";
    await expect(canvas.getAllByText(note)).toHaveLength(3);
    for (const name of [
      "Download JSON",
      "Download CSV",
      "Import from Budge",
      "Delete my account",
    ]) {
      const button = canvas.getByRole("button", { name });
      await expect(button).toBeDisabled();
      await expect(button).toHaveAccessibleDescription(note);
    }
    await expect(canvas.getByRole("button", { name: /Add a fingerprint/ })).toBeDisabled();
    // The four apps to connect and the address, but no grants: the demo asks the API nothing.
    const assistants = within(canvas.getByRole("region", { name: "Wambito's address" }));
    await expect(
      assistants.getByRole("textbox", { name: "The Wambito address for assistants" }),
    ).toHaveValue(`${window.location.origin}/mcp`);
    await expect(canvas.getByRole("button", { name: "Connect Claude" })).toBeVisible();
    await expect(canvas.queryByRole("button", { name: /^Revoke/ })).toBeNull();
    await expect(canvas.getByRole("link", { name: "Back to home" })).toHaveAttribute(
      "href",
      "/demo",
    );
    // The language still switches: the demo's profile changes in memory.
    await userEvent.click(canvas.getByRole("radio", { name: "Español" }));
    await canvas.findByRole("heading", { name: "Ajustes", level: 1 });
  },
};
