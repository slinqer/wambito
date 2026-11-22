import type { Meta, StoryObj } from "@storybook/react-vite";
import { expect, fn, screen, userEvent, waitFor, within } from "storybook/test";
import { HomeStage } from "../home/story-harness.tsx";
import type { Assistant } from "./queries.ts";

/**
 * "Mis agentes" (spec 2026-11-22 "Mis agentes, inside"): the four AI apps with their state, a
 * "Conectar" sheet per app with Wambi's handshake scene and the steps, the connector address, and
 * any other client that was let in. Web-only, not in parity.json.
 */

interface Spies {
  onRequest(line: string, headers: Record<string, string>): void;
  onCopy(text: string): Promise<void>;
}

const meta = {
  title: "Settings/Agents",
  args: { onRequest: fn(), onCopy: fn(async () => {}) },
  parameters: {
    viewport: {
      options: {
        phone: { name: "Phone", styles: { width: "390px", height: "844px" }, type: "mobile" },
      },
    },
  },
  globals: { viewport: { value: "phone", isRotated: false } },
} satisfies Meta<Spies>;

export default meta;
type Story = StoryObj<Spies>;

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

const CURSOR: Assistant = {
  clientId: "dcr-cursor-1",
  name: "Cursor",
  icon: null,
  uri: "https://cursor.com",
  domain: "cursor.com",
  scopes: ["finance:read"],
  connectedAt: "2026-10-08T09:00:00.000Z",
  lastUsedAt: null,
};

const stage = (args: Spies, extra: Partial<Parameters<typeof HomeStage>[0]> = {}) => (
  <HomeStage
    onRequest={args.onRequest}
    onCopy={args.onCopy}
    path="/app/settings/agents"
    {...extra}
  />
);

const page = (canvasElement: HTMLElement) =>
  within(canvasElement).findByRole("heading", { level: 1, name: "Mis agentes" });

const writesTo = (spy: Spies["onRequest"], prefix: string) =>
  (spy as unknown as ReturnType<typeof fn>).mock.calls
    .map((call) => call[0] as string)
    .filter((line) => line.startsWith(prefix));

const toastShown = (text: string | RegExp) =>
  waitFor(
    () => {
      const toast = screen.getByRole("status").querySelector<HTMLElement>(".lk-toast");
      expect(toast).toHaveTextContent(text);
      expect(toast && getComputedStyle(toast).opacity).toBe("1");
    },
    { timeout: 8000 },
  );

const rowsOf = (canvasElement: HTMLElement) => [
  ...canvasElement.querySelectorAll<HTMLElement>("[data-agent]"),
];

/** The four apps in order; connected ones with dates and Revocar, the rest with Conectar; Cursor last. */
export const List: Story = {
  render: (args) => stage(args, { assistants: [CURSOR, CHATGPT, CLAUDE] }),
  play: async ({ canvasElement }) => {
    await page(canvasElement);
    const canvas = within(canvasElement);
    await canvas.findByText("Conectado el 2 oct 2026 · usado el 20 oct 2026");
    const rows = rowsOf(canvasElement);
    await expect(rows.map((row) => row.dataset.agent)).toEqual([
      "claude",
      "chatgpt",
      "lumo",
      "grok",
      "dcr-cursor-1",
    ]);
    const [claude, chatgpt, lumo, grok, cursor] = rows.map((row) => within(row)) as [
      ReturnType<typeof within>,
      ReturnType<typeof within>,
      ReturnType<typeof within>,
      ReturnType<typeof within>,
      ReturnType<typeof within>,
    ];
    await expect(claude.getByText("Conectado el 2 oct 2026 · usado el 20 oct 2026")).toBeVisible();
    await expect(claude.getByRole("button", { name: "Revocar Claude" })).toBeVisible();
    await expect(claude.queryByRole("button", { name: /Conectar/ })).toBeNull();
    await expect(chatgpt.getByText("Conectado el 5 oct 2026 · aún sin usar")).toBeVisible();
    await expect(chatgpt.getByRole("button", { name: "Revocar ChatGPT" })).toBeVisible();
    await expect(lumo.getByText("Sin conectar")).toBeVisible();
    await expect(lumo.getByRole("button", { name: "Conectar Lumo+" })).toBeVisible();
    await expect(grok.getByText("Sin conectar")).toBeVisible();
    await expect(grok.getByRole("button", { name: "Conectar Grok" })).toBeVisible();
    await expect(cursor.getByText("Cursor")).toBeVisible();
    await expect(
      cursor.getByText("Desde cursor.com · Conectado el 8 oct 2026 · aún sin usar"),
    ).toBeVisible();
    await expect(cursor.getByRole("button", { name: "Revocar Cursor" })).toBeVisible();
    // The four brands have their logo; the unknown client the generic chat icon.
    await expect(rows[0]?.querySelector("svg")).not.toBeNull();
    await expect(cursor.getByTestId("generic-agent-icon")).toBeVisible();
    // The connector address stays under the list.
    await expect(
      canvas.getByRole("textbox", { name: "La dirección de Wambito para asistentes" }),
    ).toHaveValue(`${window.location.origin}/mcp`);
  },
};

const EVIL_CLAUDE: Assistant = {
  clientId: "dcr-evil-1",
  name: "Claude",
  icon: null,
  uri: "https://evil.example",
  domain: "evil.example",
  scopes: ["finance:read"],
  connectedAt: "2026-10-09T09:00:00.000Z",
  lastUsedAt: null,
};

/** A client named Claude from a foreign domain is its own row with the domain, apart from the real Claude. */
export const ForeignClaude: Story = {
  render: (args) => stage(args, { assistants: [EVIL_CLAUDE, CLAUDE] }),
  play: async ({ canvasElement }) => {
    await page(canvasElement);
    await within(canvasElement).findByText("Conectado el 2 oct 2026 · usado el 20 oct 2026");
    const rows = rowsOf(canvasElement);
    await expect(rows.map((row) => row.dataset.agent)).toEqual([
      "claude",
      "chatgpt",
      "lumo",
      "grok",
      "dcr-evil-1",
    ]);
    const [real, , , , other] = rows.map((row) => within(row));
    await expect(real?.getByText("Conectado el 2 oct 2026 · usado el 20 oct 2026")).toBeVisible();
    await expect(
      other?.getByText("Desde evil.example · Conectado el 9 oct 2026 · aún sin usar"),
    ).toBeVisible();
    await expect(other?.getByTestId("generic-agent-icon")).toBeVisible();
  },
};

/** Nothing connected: four rows to connect. */
export const NoneConnected: Story = {
  render: (args) => stage(args),
  play: async ({ canvasElement }) => {
    await page(canvasElement);
    const canvas = within(canvasElement);
    await canvas.findByRole("button", { name: "Conectar Claude" });
    await expect(canvas.getAllByText("Sin conectar")).toHaveLength(4);
    await expect(canvas.queryByRole("button", { name: /Revocar/ })).toBeNull();
  },
};

/** Conectar opens the sheet: scene, three steps, the help link, examples and Listo. */
export const ConnectClaude: Story = {
  render: (args) => stage(args),
  play: async ({ canvasElement, args }) => {
    await page(canvasElement);
    await userEvent.click(
      await within(canvasElement).findByRole("button", { name: "Conectar Claude" }),
    );
    const dialog = await screen.findByRole("dialog", { name: "Conectar Claude" });
    const sheet = within(dialog);
    await expect(dialog.querySelector("img")).toHaveAttribute(
      "src",
      "/wambi/handshake-claude.webp",
    );
    const steps = sheet.getAllByRole("listitem");
    await expect(steps).toHaveLength(3 + 2);
    await expect(sheet.getByText("Copia la dirección del conector")).toBeVisible();
    await expect(sheet.getByText("Añadir conector personalizado")).toBeVisible();
    await expect(
      sheet.getByText("Claude te pedirá entrar: usa tu cuenta de Wambito y acepta el permiso."),
    ).toBeVisible();
    await expect(sheet.getByRole("link", { name: "Abrir Claude ↗" })).toHaveAttribute(
      "href",
      "https://claude.ai/settings/connectors",
    );
    await expect(sheet.getByRole("link", { name: "la ayuda de Claude ↗" })).toHaveAttribute(
      "href",
      "https://support.claude.com/en/articles/11175166-getting-started-with-custom-connectors-using-remote-mcp",
    );
    await expect(sheet.getByText("anota 18 lukas en almuerzo")).toBeVisible();
    await userEvent.click(sheet.getByRole("button", { name: "Copiar la dirección" }));
    await expect(args.onCopy).toHaveBeenCalledWith(`${window.location.origin}/mcp`);
    await userEvent.click(sheet.getByRole("button", { name: "Listo" }));
    await waitFor(() => expect(screen.queryByRole("dialog")).toBeNull(), { timeout: 8000 });
  },
};

/** ChatGPT's sheet has its notice and its own steps and links. */
export const ConnectChatGpt: Story = {
  render: (args) => stage(args),
  play: async ({ canvasElement }) => {
    await page(canvasElement);
    await userEvent.click(
      await within(canvasElement).findByRole("button", { name: "Conectar ChatGPT" }),
    );
    const sheet = within(await screen.findByRole("dialog", { name: "Conectar ChatGPT" }));
    await expect(sheet.getByText(/Se agrega desde la web de ChatGPT/)).toBeVisible();
    await expect(sheet.getByText("Create as a plugin")).toBeVisible();
    await expect(sheet.getByRole("link", { name: "Abrir chatgpt.com ↗" })).toHaveAttribute(
      "href",
      "https://chatgpt.com/plugins",
    );
    await expect(sheet.getByRole("link", { name: "la ayuda de OpenAI ↗" })).toBeVisible();
  },
};

/** Lumo+ and Grok: their notice, button and company in the help line. */
export const ConnectLumoAndGrok: Story = {
  render: (args) => stage(args),
  play: async ({ canvasElement }) => {
    await page(canvasElement);
    await userEvent.click(
      await within(canvasElement).findByRole("button", { name: "Conectar Lumo+" }),
    );
    const lumo = within(await screen.findByRole("dialog", { name: "Conectar Lumo+" }));
    await expect(lumo.getByText(/Solo desde la app de escritorio de Lumo/)).toBeVisible();
    await expect(lumo.getByRole("link", { name: "Descargar Lumo ↗" })).toBeVisible();
    await expect(lumo.getByRole("link", { name: "la ayuda de Proton ↗" })).toBeVisible();
    await userEvent.click(lumo.getByRole("button", { name: "Listo" }));
    await waitFor(() => expect(screen.queryByRole("dialog")).toBeNull(), { timeout: 8000 });
    await userEvent.click(within(canvasElement).getByRole("button", { name: "Conectar Grok" }));
    const grok = within(await screen.findByRole("dialog", { name: "Conectar Grok" }));
    await expect(grok.getByText(/planes de pago de Grok/)).toBeVisible();
    await expect(grok.getByRole("link", { name: "Abrir Grok ↗" })).toBeVisible();
    await expect(grok.getByRole("link", { name: "la ayuda de xAI ↗" })).toBeVisible();
  },
};

/** Revocar asks first, then the grant is gone and the app goes back to Conectar. */
export const Revoke: Story = {
  render: (args) => stage(args, { assistants: [CLAUDE] }),
  play: async ({ canvasElement, args }) => {
    await page(canvasElement);
    const canvas = within(canvasElement);
    await userEvent.click(await canvas.findByRole("button", { name: "Revocar Claude" }));
    const sheet = within(await screen.findByRole("dialog", { name: "¿Revocar Claude?" }));
    await expect(writesTo(args.onRequest, "DELETE /api/v1/me/assistants")).toHaveLength(0);
    await userEvent.click(sheet.getByRole("button", { name: "Sí, revocar" }));
    await toastShown("Listo: Claude ya no tiene acceso.");
    await expect(writesTo(args.onRequest, "DELETE /api/v1/me/assistants")).toEqual([
      `DELETE /api/v1/me/assistants/${encodeURIComponent(CLAUDE.clientId)}`,
    ]);
    await canvas.findByRole("button", { name: "Conectar Claude" });
  },
};

const CLAUDE_OLD: Assistant = {
  ...CLAUDE,
  clientId: "dcr-claude-old",
  connectedAt: "2026-09-01T09:00:00.000Z",
};

/** Two grants of one app: Revocar ends both and the app goes back to Conectar. */
export const RevokeSeveral: Story = {
  render: (args) => stage(args, { assistants: [CLAUDE_OLD, CLAUDE] }),
  play: async ({ canvasElement, args }) => {
    await page(canvasElement);
    const canvas = within(canvasElement);
    await userEvent.click(await canvas.findByRole("button", { name: "Revocar Claude" }));
    const sheet = within(await screen.findByRole("dialog", { name: "¿Revocar Claude?" }));
    await userEvent.click(sheet.getByRole("button", { name: "Sí, revocar" }));
    await canvas.findByRole("button", { name: "Conectar Claude" });
    await toastShown("Listo: Claude ya no tiene acceso.");
    await expect(writesTo(args.onRequest, "DELETE /api/v1/me/assistants").sort()).toEqual(
      [CLAUDE.clientId, CLAUDE_OLD.clientId]
        .map((id) => `DELETE /api/v1/me/assistants/${encodeURIComponent(id)}`)
        .sort(),
    );
  },
};

/** A guest sees why an email comes first, and nothing to connect. */
export const Guest: Story = {
  render: (args) => stage(args, { guest: true }),
  play: async ({ canvasElement }) => {
    await page(canvasElement);
    const canvas = within(canvasElement);
    await expect(await canvas.findByText("Primero agrega un email")).toBeVisible();
    await expect(canvas.queryByRole("button", { name: /Conectar/ })).toBeNull();
  },
};

/**
 * Coming back to the tab after connecting elsewhere reads the list again: the new Claude grant
 * shows as connected, with its toast once.
 */
export const FocusRefetch: Story = {
  render: (args) => stage(args, { laterAssistants: [CLAUDE] }),
  play: async ({ canvasElement }) => {
    await page(canvasElement);
    const canvas = within(canvasElement);
    await canvas.findByRole("button", { name: "Conectar Claude" });
    window.dispatchEvent(new Event("focus"));
    await canvas.findByRole("button", { name: "Revocar Claude" });
    await toastShown("Claude quedó conectado.");
    window.dispatchEvent(new Event("focus"));
    await new Promise((resolve) => setTimeout(resolve, 300));
    await expect(screen.getAllByText("Claude quedó conectado.")).toHaveLength(1);
  },
};

/** The first load never toasts, even with grants already there. */
export const NoToastOnFirstLoad: Story = {
  render: (args) => stage(args, { assistants: [CLAUDE] }),
  play: async ({ canvasElement }) => {
    await page(canvasElement);
    await within(canvasElement).findByRole("button", { name: "Revocar Claude" });
    await new Promise((resolve) => setTimeout(resolve, 300));
    await expect(screen.queryByText("Claude quedó conectado.")).toBeNull();
  },
};

/** English, by day. */
export const SheetEnglishDay: Story = {
  globals: { locale: "en", theme: "day" },
  render: (args) => stage(args),
  play: async ({ canvasElement }) => {
    await within(canvasElement).findByRole("heading", { level: 1, name: "My agents" });
    await userEvent.click(
      await within(canvasElement).findByRole("button", { name: "Connect ChatGPT" }),
    );
    const sheet = within(await screen.findByRole("dialog", { name: "Connect ChatGPT" }));
    await expect(sheet.getByRole("button", { name: "Done" })).toBeVisible();
    await expect(sheet.getByRole("link", { name: "OpenAI's help ↗" })).toBeVisible();
  },
};
