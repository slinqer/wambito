import { defineConfig, devices } from "@playwright/test";

const baseURL = "http://localhost:5173";

/** App flows against `pnpm dev` and the dev stack (`docker compose up -d`, with the API's clock
 * pinned: see e2e/global-setup.ts). The landing specs run against the built site instead: see
 * playwright.built.config.ts (`pnpm e2e:landing`, `e2e:landing-only`, `e2e:landing-only-app`,
 * `e2e:landing-analytics`). */
export default defineConfig({
  testDir: "./e2e",
  testIgnore: /landing(-wambi|-only|-only-app|-analytics)?\.spec\.ts$/,
  globalSetup: "./e2e/global-setup.ts",
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  // Assertions wait for a state (a sheet gone after a save and its slide-out, a total updated),
  // never for a time: give them 10 s, not 5, so a busy machine or CI runner still sees it come.
  expect: { timeout: 10_000 },
  reporter: process.env.CI ? "github" : "list",
  use: { baseURL, trace: "on-first-retry" },
  projects: [
    {
      name: "phone",
      use: {
        ...devices["Desktop Chrome"],
        viewport: { width: 390, height: 844 },
        isMobile: true,
        hasTouch: true,
      },
    },
    {
      name: "desktop",
      use: { ...devices["Desktop Chrome"], viewport: { width: 1280, height: 800 } },
    },
  ],
  webServer: { command: "pnpm dev", url: baseURL, reuseExistingServer: !process.env.CI },
});
