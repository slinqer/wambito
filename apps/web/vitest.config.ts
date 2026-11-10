import { fileURLToPath } from "node:url";
import { storybookTest } from "@storybook/addon-vitest/vitest-plugin";
import tailwindcss from "@tailwindcss/vite";
import react from "@vitejs/plugin-react";
import { playwright } from "@vitest/browser-playwright";
import { defineConfig } from "vitest/config";

export default defineConfig({
  plugins: [react(), tailwindcss()],
  // Pre-bundled up front: discovering them mid-run makes Vite reload the browser and fail the run.
  optimizeDeps: {
    include: [
      "motion/react",
      "react-router",
      "use-intl",
      "@wambito/core > zod",
      "three",
      "@react-three/fiber",
      "three/examples/jsm/environments/RoomEnvironment.js",
      "@tanstack/react-query",
      "recharts",
      "openapi-fetch",
      "better-auth/react",
      "better-auth/client/plugins",
      "@better-auth/passkey/client",
      "uqr",
    ],
  },
  test: {
    projects: [
      {
        extends: true,
        test: {
          name: "unit",
          include: ["app/**/*.test.{ts,tsx}", "scripts/**/*.test.ts"],
          environment: "node",
        },
      },
      {
        extends: true,
        // Every story is a test: it renders, runs its play function and the a11y checks.
        plugins: [
          storybookTest({ configDir: fileURLToPath(new URL(".storybook", import.meta.url)) }),
        ],
        test: {
          name: "storybook",
          // The stories animate in real time. Run after the Node projects (API integration tests
          // with their Postgres containers, unit tests), not beside them, and on fewer pages at
          // once: a starved browser drops frames and its springs miss the stories' waits.
          sequence: { groupOrder: 1 },
          maxWorkers: 4,
          browser: {
            enabled: true,
            headless: true,
            provider: playwright(),
            instances: [{ browser: "chromium" }],
          },
        },
      },
    ],
  },
});
