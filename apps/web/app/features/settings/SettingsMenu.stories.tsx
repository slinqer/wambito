import type { Meta, StoryObj } from "@storybook/react-vite";
import { expect, fn, userEvent, within } from "storybook/test";
import { HomeStage } from "../home/story-harness.tsx";
import type { SecurityApi, SecuritySnapshot } from "./security.ts";

/**
 * The settings menu (spec 2026-11-22 "The menu"): one row per category on its own URL, with
 * "Protege tus datos" above them for an account without an email. Web-only, not in parity.json.
 */

interface Args {
  onRequest(line: string, headers: Record<string, string>): void;
}

const meta = {
  title: "Settings/Menu",
  args: { onRequest: fn() },
  render: (args) => <HomeStage onRequest={args.onRequest} path="/app/settings" />,
  parameters: {
    viewport: {
      options: {
        phone: { name: "Phone", styles: { width: "390px", height: "844px" }, type: "mobile" },
      },
    },
  },
  globals: { viewport: { value: "phone", isRotated: false } },
} satisfies Meta<Args>;

export default meta;
type Story = StoryObj<typeof meta>;

const rows = (canvasElement: HTMLElement) =>
  within(canvasElement).findByRole("navigation", { name: "Ajustes" });

/** Five categories in order, each with its line; the preferences line is live. Night theme. */
export const Night: Story = {
  play: async ({ canvasElement }) => {
    const nav = within(await rows(canvasElement));
    const links = nav.getAllByRole("link");
    await expect(links).toHaveLength(5);
    const expected = [
      ["Mis agentes", "ChatGPT · Claude · Lumo+ · Grok", "/app/settings/agents"],
      ["Cuenta y seguridad", "Passkeys, dispositivos, clave", "/app/settings/account"],
      ["Preferencias", "Español · Noche · EUR", "/app/settings/preferences"],
      ["Tus datos", "Importar, exportar", "/app/settings/data"],
      ["Más", "Comentarios", "/app/settings/more"],
    ] as const;
    for (const [i, [title, line, href]] of expected.entries()) {
      await expect(links[i]).toHaveAccessibleName(`${title} ${line}`);
      await expect(links[i]).toHaveAttribute("href", href);
    }
    // No capture on the web, and no sign-out or version here.
    await expect(within(canvasElement).queryByText("Captura")).toBeNull();
    await expect(within(canvasElement).queryByRole("button", { name: "Cerrar sesión" })).toBeNull();
  },
};

/** The day theme. */
export const Day: Story = {
  globals: { theme: "day" },
  play: async ({ canvasElement }) => {
    const nav = within(await rows(canvasElement));
    await expect(nav.getByRole("link", { name: /Preferencias/ })).toHaveTextContent("Día");
  },
};

/** In English, with the live line in English too. */
export const English: Story = {
  globals: { locale: "en" },
  play: async ({ canvasElement }) => {
    const nav = within(await within(canvasElement).findByRole("navigation", { name: "Settings" }));
    await expect(nav.getByRole("link", { name: /My agents/ })).toBeVisible();
    await expect(nav.getByRole("link", { name: /Preferences/ })).toHaveTextContent(
      "English · Night · EUR",
    );
  },
};

/** A row opens its category on its own page, and the back link returns to the menu. */
export const OpensACategoryAndBack: Story = {
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await userEvent.click(await canvas.findByRole("link", { name: /Tus datos/ }));
    await expect(await canvas.findByRole("heading", { level: 1, name: "Tus datos" })).toBeVisible();
    await userEvent.click(canvas.getByRole("link", { name: "Volver a Ajustes" }));
    await expect(await rows(canvasElement)).toBeVisible();
  },
};

/** An address that is not a category says so, and leads back to the menu. */
export const UnknownCategory: Story = {
  render: (args) => <HomeStage onRequest={args.onRequest} path="/app/settings/nope" />,
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await expect(
      await canvas.findByRole("heading", { level: 1, name: "No encontramos esa sección" }),
    ).toBeVisible();
    await expect(canvas.getByRole("link", { name: "Volver a Ajustes" })).toHaveAttribute(
      "href",
      "/app/settings",
    );
  },
};

const OWN = "0193a000-0000-7000-8000-00000000000a";

/** An account without an email, on a preview vault: "Protege tus datos" sits above the rows. */
export const GuestWithProtect: Story = {
  render: (args) => {
    const security = {
      load: async (): Promise<SecuritySnapshot> => ({
        wraps: [
          {
            id: "r",
            kind: "recovery",
            ref: null,
            keyV: 1,
            wrapped: "w",
            publicKey: null,
            attestation: null,
            label: null,
            createdAt: "2026-10-01T10:00:00.000Z",
          },
        ],
        ownId: OWN,
        revoked: [],
        verified: new Set(),
        unreadable: 0,
      }),
      removeDevice: async () => {},
      rotate: async () => {
        throw new Error("not in this story");
      },
      checkRecoveryKey: async () => {},
      newRecoveryKey: async () => ({
        recoveryKey: "7QK2-M9XD-HT4V-PA3R-WE6N-BC8J-Y2T",
        commit: async () => {},
      }),
      reloadKeys: async () => {},
      evaluatePrf: async () => null,
      addPasskeyWrap: async () => {},
      settings: async () => ({ recoveryKeySavedAt: null }),
      markRecoveryKeySaved: async () => {},
      pairing: { userId: "u-ana" },
      findPairing: () => new Promise<never>(() => {}),
      scanSupported: () => false,
    } satisfies SecurityApi;
    return (
      <HomeStage
        onRequest={args.onRequest}
        mode="local"
        guest
        path="/app/settings"
        security={security}
      />
    );
  },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    const block = await canvas.findByRole("region", { name: "Protege tus datos" });
    await expect(block).toBeVisible();
    // The block comes first in the page, the rows after it.
    const nav = await rows(canvasElement);
    await expect(
      block.compareDocumentPosition(nav) & Node.DOCUMENT_POSITION_FOLLOWING,
    ).toBeTruthy();
    await expect(within(nav).getAllByRole("link")).toHaveLength(5);
  },
};
