import type { Meta, StoryObj } from "@storybook/react-vite";
import { MemoryRouter } from "react-router";
import { expect, fn, userEvent, waitFor, within } from "storybook/test";
import { Footer } from "../landing/Footer.tsx";
import type { AnalyticsConfig } from "./config.ts";
import { type BrowserSignals, CONSENT_KEY, encodeChoice } from "./consent.ts";
import type { ConsentDeps } from "./use-analytics-consent.ts";

const CONFIG: AnalyticsConfig = { key: "phc_story", host: "https://eu.i.posthog.com" };
const NOW = new Date("2026-11-19T12:00:00Z");

/** A `Storage` kept in memory, so the stories never touch the real `localStorage`. */
function memoryStorage(initial: Record<string, string> = {}): Storage {
  const items = new Map(Object.entries(initial));
  return {
    get length() {
      return items.size;
    },
    key: (index) => [...items.keys()][index] ?? null,
    getItem: (key) => items.get(key) ?? null,
    setItem: (key, value) => void items.set(key, String(value)),
    removeItem: (key) => void items.delete(key),
    clear: () => items.clear(),
  };
}

/** A `Storage` whose every method throws, like a browser with site data blocked. */
function blockedStorage(): Storage {
  const blocked = () => {
    throw new DOMException("blocked", "SecurityError");
  };
  return {
    get length(): number {
      return blocked();
    },
    key: blocked,
    getItem: blocked,
    setItem: blocked,
    removeItem: blocked,
    clear: blocked,
  };
}

type Loaded = {
  storage: Storage;
  start: ReturnType<typeof fn<NonNullable<ConsentDeps["start"]>>>;
  stop: ReturnType<typeof fn<NonNullable<ConsentDeps["stop"]>>>;
  signals: BrowserSignals;
};

/** Fresh fakes for each story: memory storage, `start`/`stop` spies and the browser's signals. */
function fakes(storage: () => Storage, signals: BrowserSignals = {}) {
  return async (): Promise<Loaded> => ({
    storage: storage(),
    start: fn(async () => {}),
    stop: fn(() => {}),
    signals,
  });
}

function storedChoice(storage: Storage): string | null {
  const raw = storage.getItem(CONSENT_KEY);
  return raw === null ? null : (JSON.parse(raw) as { choice: string }).choice;
}

const meta = {
  title: "Landing/Consent banner",
  component: Footer,
  parameters: { layout: "fullscreen" },
  decorators: [
    (Story) => (
      <MemoryRouter>
        <div className="lk-screen lk-landing">
          <Story />
        </div>
      </MemoryRouter>
    ),
  ],
  render: (_args, { loaded }) => {
    const { storage, start, stop, signals } = loaded as Loaded;
    return (
      <Footer
        consent={{ config: CONFIG, deps: { storage, start, stop, signals, now: () => NOW } }}
      />
    );
  },
} satisfies Meta<typeof Footer>;

export default meta;
type Story = StoryObj<typeof meta>;

/** First visit: the banner asks; "No, gracias" and "Sí, acepto" look the same, decline first. */
export const Ask: Story = {
  globals: { theme: "day" },
  loaders: [fakes(() => memoryStorage())],
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    const banner = await canvas.findByRole("region", { name: "Preferencias de cookies" });
    await expect(banner).toBeVisible();
    const decline = within(banner).getByRole("button", { name: "No, gracias" });
    const accept = within(banner).getByRole("button", { name: "Sí, acepto" });
    await expect(decline.className).toBe(accept.className);
    await expect(decline.getBoundingClientRect().height).toBe(
      accept.getBoundingClientRect().height,
    );
    // Decline comes first in the reading order.
    await expect(
      decline.compareDocumentPosition(accept) & Node.DOCUMENT_POSITION_FOLLOWING,
    ).toBeTruthy();
    await expect(
      within(banner).getByRole("link", { name: "política de privacidad" }),
    ).toHaveAttribute("href", "/privacy");
    await expect(banner).not.toHaveTextContent("Ahora:");
  },
};

/** Accepting stores `granted`, starts analytics once and closes the banner. */
export const AcceptStores: Story = {
  loaders: [fakes(() => memoryStorage())],
  play: async ({ canvasElement, loaded }) => {
    const { storage, start } = loaded as Loaded;
    const canvas = within(canvasElement);
    await userEvent.click(await canvas.findByRole("button", { name: "Sí, acepto" }));
    await expect(storedChoice(storage)).toBe("granted");
    await expect(start).toHaveBeenCalledTimes(1);
    await expect(start).toHaveBeenCalledWith(CONFIG);
    await waitFor(() => expect(canvas.queryByRole("region")).toBeNull());
  },
};

/** Declining stores `denied`, starts nothing and closes the banner. */
export const DeclineStores: Story = {
  loaders: [fakes(() => memoryStorage())],
  play: async ({ canvasElement, loaded }) => {
    const { storage, start, stop } = loaded as Loaded;
    const canvas = within(canvasElement);
    await userEvent.click(await canvas.findByRole("button", { name: "No, gracias" }));
    await expect(storedChoice(storage)).toBe("denied");
    await expect(start).not.toHaveBeenCalled();
    // Nothing was started, so there is nothing to stop.
    await expect(stop).not.toHaveBeenCalled();
    await waitFor(() => expect(canvas.queryByRole("region")).toBeNull());
  },
};

/** Already accepted: no banner; the footer link opens it with the choice, and declining stops. */
export const Reopen: Story = {
  loaders: [fakes(() => memoryStorage({ [CONSENT_KEY]: encodeChoice("granted", NOW) }))],
  play: async ({ canvasElement, loaded }) => {
    const { storage, start, stop } = loaded as Loaded;
    const canvas = within(canvasElement);
    await waitFor(() => expect(start).toHaveBeenCalledTimes(1));
    await expect(canvas.queryByRole("region")).toBeNull();
    await userEvent.click(canvas.getByRole("button", { name: "Preferencias de cookies" }));
    const banner = await canvas.findByRole("region", { name: "Preferencias de cookies" });
    await expect(banner).toHaveTextContent("Ahora: aceptaste.");
    await userEvent.click(within(banner).getByRole("button", { name: "No, gracias" }));
    await expect(stop).toHaveBeenCalledTimes(1);
    await expect(storedChoice(storage)).toBe("denied");
    await waitFor(() => expect(canvas.queryByRole("region")).toBeNull());
    // Focus goes back to the link that opened it.
    await expect(canvas.getByRole("button", { name: "Preferencias de cookies" })).toHaveFocus();
  },
};

/** Global Privacy Control on: no banner; the link opens a short note with only "Cerrar". */
export const BrowserSaysNo: Story = {
  loaders: [fakes(() => memoryStorage(), { globalPrivacyControl: true })],
  play: async ({ canvasElement, loaded }) => {
    const { start } = loaded as Loaded;
    const canvas = within(canvasElement);
    const link = await canvas.findByRole("button", { name: "Preferencias de cookies" });
    await expect(canvas.queryByRole("region")).toBeNull();
    await userEvent.click(link);
    const banner = await canvas.findByRole("region", { name: "Preferencias de cookies" });
    await expect(banner).toHaveTextContent(
      "Tu navegador pidió no ser rastreado, así que no te rastreamos.",
    );
    const buttons = within(banner).getAllByRole("button");
    await expect(buttons.map((button) => button.textContent)).toEqual(["Cerrar"]);
    await userEvent.click(buttons[0] as HTMLElement);
    await waitFor(() => expect(canvas.queryByRole("region")).toBeNull());
    await expect(start).not.toHaveBeenCalled();
  },
};

/** Storage blocked: the banner still asks, and accepting starts analytics for this page. */
export const BlockedStorage: Story = {
  loaders: [fakes(blockedStorage)],
  play: async ({ canvasElement, loaded }) => {
    const { start } = loaded as Loaded;
    const canvas = within(canvasElement);
    await canvas.findByRole("region", { name: "Preferencias de cookies" });
    await userEvent.click(canvas.getByRole("button", { name: "Sí, acepto" }));
    await expect(start).toHaveBeenCalledTimes(1);
    await waitFor(() => expect(canvas.queryByRole("region")).toBeNull());
  },
};

/** `Ask` in the night theme (the a11y addon checks the contrast). */
export const Dark: Story = {
  ...Ask,
  globals: { theme: "night" },
};

/** No PostHog key in the build: neither the banner nor the footer link. */
export const NoKey: Story = {
  loaders: [fakes(() => memoryStorage())],
  render: (_args, { loaded }) => {
    const { storage, start, stop, signals } = loaded as Loaded;
    return <Footer consent={{ config: null, deps: { storage, start, stop, signals } }} />;
  },
  play: async ({ canvasElement, loaded }) => {
    const { start } = loaded as Loaded;
    const canvas = within(canvasElement);
    // The footer has rendered (and its effects have run) before looking for what must be absent.
    await canvas.findByRole("link", { name: "Privacidad" });
    await new Promise((resolve) => setTimeout(resolve, 50));
    await expect(canvas.queryByRole("region")).toBeNull();
    await expect(canvas.queryByRole("button", { name: "Preferencias de cookies" })).toBeNull();
    await expect(start).not.toHaveBeenCalled();
  },
};
