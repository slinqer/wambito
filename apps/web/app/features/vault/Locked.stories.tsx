import type { Meta, StoryObj } from "@storybook/react-vite";
import { MemoryRouter } from "react-router";
import { expect, fn, userEvent, within } from "storybook/test";
import { expectTarget } from "../../../.storybook/story-utils.ts";
import { Locked } from "./Locked.tsx";

const meta = {
  title: "Vault/Locked",
  component: Locked,
  decorators: [
    (Story) => (
      <MemoryRouter>
        <Story />
      </MemoryRouter>
    ),
  ],
  args: { onRetry: fn(), onSignOut: fn() },
} satisfies Meta<typeof Locked>;

export default meta;
type Story = StoryObj<typeof meta>;

export const Failed: Story = {
  play: async ({ canvasElement, args }) => {
    const canvas = within(canvasElement);
    await expect(
      canvas.getByRole("heading", { level: 1, name: "No pudimos abrir tus datos" }),
    ).toBeVisible();
    const retry = canvas.getByRole("button", { name: "Reintentar" });
    await expectTarget(retry);
    await userEvent.click(retry);
    await expect(args.onRetry).toHaveBeenCalledTimes(1);
    const signOut = canvas.getByRole("button", { name: "Cerrar sesión" });
    await expectTarget(signOut);
    await userEvent.click(signOut);
    await expect(args.onSignOut).toHaveBeenCalledTimes(1);
  },
};

/** A browser without X25519 in WebCrypto: no retry, only the way out. */
export const Unsupported: Story = {
  args: { kind: "unsupported" },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await expect(
      canvas.getByRole("heading", { level: 1, name: "Este navegador no puede guardar tu clave" }),
    ).toBeVisible();
    await expect(canvas.getByText(/Actualiza tu navegador/)).toBeVisible();
    await expect(canvas.queryByRole("button", { name: "Reintentar" })).toBeNull();
    await expect(canvas.getByRole("button", { name: "Cerrar sesión" })).toBeVisible();
  },
};

export const Offline: Story = {
  args: { kind: "offline" },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await expect(canvas.getByRole("heading", { level: 1, name: "Sin conexión" })).toBeVisible();
    // Pairing is Unlock's; Locked only retries or signs out.
    await expect(
      canvas.queryByRole("button", { name: "Aprobar desde otro dispositivo" }),
    ).toBeNull();
  },
};

export const Retrying: Story = {
  args: { retrying: true },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await expect(canvas.getByRole("button", { name: "Reintentando…" })).toBeDisabled();
  },
};
