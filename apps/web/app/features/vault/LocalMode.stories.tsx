import type { Meta, StoryObj } from "@storybook/react-vite";
import { MemoryRouter } from "react-router";
import { expect, fn, screen, userEvent, within } from "storybook/test";
import { HomeStage } from "../home/story-harness.tsx";
import { VaultLoading } from "./VaultGate.tsx";

/**
 * A preview account's app (`<ApiProvider mode="local">`, stage 2a): settings turns off import,
 * export and the assistants' list with a "not available yet" note; passkeys and deleting the
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

export const Settings: Story = {
  render: (args) => <HomeStage mode="local" path="/app/settings" onRequest={args.onRequest} />,
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await canvas.findByRole("heading", { level: 1, name: "Ajustes" });
    const data = within(await canvas.findByRole("region", { name: "Tus datos" }));
    await expect(data.getByRole("button", { name: "Importar desde Budge" })).toBeDisabled();
    await expect(data.getByRole("button", { name: "Descargar JSON" })).toBeDisabled();
    await expect(data.getByText(NOTE)).toBeVisible();
    const assistants = within(await canvas.findByRole("region", { name: "Conecta tu asistente" }));
    await expect(assistants.getByText(NOTE)).toBeVisible();
    // deleting the account is the account's, not its finances: it stays on, without the export
    const remove = canvas.getByRole("button", { name: "Eliminar mi cuenta" });
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
