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
  args: {
    onUnlock: fn(async (): Promise<UnlockError | null> => null),
    onPasskey: fn(async (): Promise<UnlockError | null> => null),
    passkeysSupported: (): boolean => true,
    onPair: fn(),
    onSignOut: fn(),
  },
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
    // The recovery key, a passkey, another device, and sign-out (plus the screen's own).
    await expect(canvas.getAllByRole("button")).toHaveLength(5);
    const pair = canvas.getByRole("button", { name: "Desde otro dispositivo" });
    await expectTarget(pair);
    await userEvent.click(pair);
    await expect(args.onPair).toHaveBeenCalledTimes(1);
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

export const UsePasskey: Story = {
  play: async ({ canvasElement, args }) => {
    const canvas = within(canvasElement);
    await userEvent.click(canvas.getByRole("button", { name: "Usar una llave de acceso" }));
    await expect(args.onPasskey).toHaveBeenCalledTimes(1);
    await expect(args.onUnlock).not.toHaveBeenCalled();
    await expect(canvas.queryByRole("alert")).toBeNull();
  },
};

export const PasskeyWithoutPrf: Story = {
  args: { onPasskey: fn(async () => "no_prf" as const) },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await userEvent.click(canvas.getByRole("button", { name: "Usar una llave de acceso" }));
    const alert = await canvas.findByRole("alert");
    // The two other ways: the recovery key, and another device.
    await expect(alert).toHaveTextContent("clave de recuperación");
    await expect(alert).toHaveTextContent("otro dispositivo");
  },
};

export const PasskeyWithoutWrap: Story = {
  args: { onPasskey: fn(async () => "no_passkey_wrap" as const) },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await userEvent.click(canvas.getByRole("button", { name: "Usar una llave de acceso" }));
    await expect(await canvas.findByRole("alert")).toHaveTextContent("clave de recuperación");
  },
};

export const NoPasskeys: Story = {
  args: { passkeysSupported: () => false },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await expect(canvas.queryByRole("button", { name: "Usar una llave de acceso" })).toBeNull();
    // The screen's own buttons, another device and sign-out.
    await expect(canvas.getAllByRole("button")).toHaveLength(4);
  },
};

/** Another device removed this browser: the vault is gone, and the notice says what was lost. */
export const Removed: Story = {
  args: { notice: "removed" },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await expect(canvas.getByRole("status")).toHaveTextContent(
      "Este navegador se eliminó de tu cuenta desde otro dispositivo. Los cambios que aún no se habían sincronizado aquí se perdieron. Para volver a abrir tus datos, escribe tu clave de recuperación o usa otro dispositivo.",
    );
    await expect(canvas.getByLabelText("Clave de recuperación")).toBeVisible();
  },
};
