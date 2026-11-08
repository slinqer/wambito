import type { Meta, StoryObj } from "@storybook/react-vite";
import { MemoryRouter } from "react-router";
import { expect, fn, userEvent, within } from "storybook/test";
import { expectTarget } from "../../../.storybook/story-utils.ts";
import { Unlock, type UnlockError } from "./Unlock.tsx";

const meta = {
  title: "Vault/Unlock",
  component: Unlock,
  decorators: [
    (Story) => (
      <MemoryRouter>
        <Story />
      </MemoryRouter>
    ),
  ],
  args: { onUnlock: fn(async (): Promise<UnlockError | null> => null), onSignOut: fn() },
} satisfies Meta<typeof Unlock>;

export default meta;
type Story = StoryObj<typeof meta>;

const typeKey = async (canvas: ReturnType<typeof within>, text: string) => {
  await userEvent.type(canvas.getByLabelText("Clave de recuperación"), text);
  await userEvent.click(canvas.getByRole("button", { name: "Abrir mis datos" }));
};

export const Ready: Story = {
  play: async ({ canvasElement, args }) => {
    const canvas = within(canvasElement);
    await expect(
      canvas.getByRole("heading", { level: 1, name: "Abre tus datos aquí" }),
    ).toBeVisible();
    await expect(canvas.getByText(/llave de acceso o desde otro dispositivo/)).toBeVisible();
    // The other ways are announced, not offered: the screen's own buttons and sign-out only.
    await expect(canvas.getAllByRole("button")).toHaveLength(3);
    await userEvent.click(canvas.getByRole("button", { name: "Cerrar sesión" }));
    await expect(args.onSignOut).toHaveBeenCalledTimes(1);
    await expectTarget(canvas.getByLabelText("Clave de recuperación").parentElement as HTMLElement);
    await expect(canvas.getByRole("button", { name: "Abrir mis datos" })).toBeDisabled();
    await typeKey(canvas, "  7qk2 m9xd-ht4v ");
    await expect(args.onUnlock).toHaveBeenCalledWith("  7qk2 m9xd-ht4v ");
  },
};

export const BadFormat: Story = {
  args: { onUnlock: fn(async () => "bad_recovery_key" as const) },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await typeKey(canvas, "nope");
    await expect(await canvas.findByRole("alert")).toHaveTextContent(
      "no tiene el formato correcto",
    );
    await expect(canvas.getByLabelText("Clave de recuperación")).toHaveAttribute(
      "aria-invalid",
      "true",
    );
    // Typing again clears it.
    await userEvent.type(canvas.getByLabelText("Clave de recuperación"), "x");
    await expect(canvas.queryByRole("alert")).toBeNull();
  },
};

export const WrongKey: Story = {
  args: { onUnlock: fn(async () => "wrong_recovery_key" as const) },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await typeKey(canvas, "7QK2-M9XD-HT4V-R3WB-N8YC-5FJ6-A0Z");
    await expect(await canvas.findByRole("alert")).toHaveTextContent("no abre esta cuenta");
    await expect(canvas.getByRole("button", { name: "Abrir mis datos" })).toBeEnabled();
  },
};

export const Offline: Story = {
  args: { onUnlock: fn(async () => "offline" as const) },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await typeKey(canvas, "7QK2");
    await expect(await canvas.findByRole("alert")).toHaveTextContent("No hay conexión");
  },
};

export const Opening: Story = {
  args: { onUnlock: fn(() => new Promise<UnlockError | null>(() => {})) },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await typeKey(canvas, "7QK2");
    await expect(await canvas.findByRole("button", { name: "Abriendo…" })).toBeDisabled();
  },
};
