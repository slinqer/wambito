import type { Meta, StoryObj } from "@storybook/react-vite";
import { MemoryRouter } from "react-router";
import { expect, fn, screen, userEvent, within } from "storybook/test";
import { HomeStage } from "../home/story-harness.tsx";
import { VaultLoading } from "./VaultGate.tsx";

/**
 * A preview account's app (`<ApiProvider mode="local">`, stage 2a): settings turns off import
 * and export with a "not available yet" note (the assistants' list works); passkeys and deleting the
 * account stay. Web-only, not in parity.json.
 */
interface Spies {
  onRequest(line: string): void;
}

const meta = {
  title: "Vault/LocalMode",
  args: { onRequest: fn() },
} satisfies Meta<Spies>;

export default meta;
type Story = StoryObj<Spies>;

const NOTE = "Todavía no está disponible con el cifrado de extremo a extremo. Llega pronto.";

/** Through the menu: Tus datos turns import and export off with the note; Mis agentes lists the
 * apps without it; Cuenta y seguridad keeps deleting the account, without the export. */
export const Settings: Story = {
  render: (args) => <HomeStage mode="local" path="/app/settings" onRequest={args.onRequest} />,
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await canvas.findByRole("heading", { level: 1, name: "Ajustes" });
    const open = async (row: RegExp, heading: string) => {
      const menu = within(await canvas.findByRole("navigation", { name: "Ajustes" }));
      await userEvent.click(menu.getByRole("link", { name: row }));
      await canvas.findByRole("heading", { level: 1, name: heading });
    };
    const back = async () => {
      await userEvent.click(canvas.getByRole("link", { name: "Volver a Ajustes" }));
      await canvas.findByRole("heading", { level: 1, name: "Ajustes" });
    };

    await open(/^Tus datos/, "Tus datos");
    await expect(canvas.queryByRole("link", { name: /^Importar movimientos/ })).toBeNull();
    await expect(canvas.queryByRole("button", { name: /^Descargar tus datos/ })).toBeNull();
    await expect(canvas.getByText(NOTE)).toBeVisible();
    await back();

    // an assistant on an encrypted account is listed and revoked here (stage 4); the note is the demo's
    await open(/^Mis agentes/, "Mis agentes");
    await expect(await canvas.findByRole("button", { name: "Conectar Claude" })).toBeVisible();
    await expect(canvas.queryByText(NOTE)).toBeNull();
    await back();

    // deleting the account is the account's, not its finances: it stays on, without the export
    await open(/^Cuenta y seguridad/, "Cuenta y seguridad");
    const remove = await canvas.findByRole("button", { name: /^Eliminar tu cuenta/ });
    await expect(remove).toBeEnabled();
    await userEvent.click(remove);
    const sheet = within(await screen.findByRole("dialog", { name: "¿Eliminar tu cuenta?" }));
    await expect(sheet.queryByRole("button", { name: "Descarga tus datos antes" })).toBeNull();
  },
};

export const Loading: Story = {
  render: () => (
    <MemoryRouter>
      <VaultLoading />
    </MemoryRouter>
  ),
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await expect(
      canvas.getByRole("heading", { level: 1, name: "Abriendo tus datos…" }),
    ).toBeVisible();
  },
};
