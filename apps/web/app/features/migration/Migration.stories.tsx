import type { Meta, StoryObj } from "@storybook/react-vite";
import { MemoryRouter } from "react-router";
import { expect, fn, userEvent, waitFor, within } from "storybook/test";
import { expectTarget } from "../../../.storybook/story-utils.ts";
import type { UnlockError } from "../vault/Unlock.tsx";
import { MigrationScreen } from "./MigrationScreen.tsx";

const KEY = "7QK2-M9XD-HT4V-R3WB-N8YC-5FJ6-A0Z";

/** The switch day's flow, one story per state; the model is `migration-flow.ts`. */
const meta = {
  title: "Migration/Screen",
  component: MigrationScreen,
  decorators: [
    (Story) => (
      <MemoryRouter>
        <Story />
      </MemoryRouter>
    ),
  ],
  args: {
    state: { status: "intro" },
    onBegin: fn(),
    onConfirmKey: fn(),
    onUnlock: fn(async (): Promise<UnlockError | null> => null),
    onRetry: fn(),
    onRestart: fn(),
    onContinue: fn(),
    onSignOut: fn(),
    positions: [1, 2, 3, 4],
  },
} satisfies Meta<typeof MigrationScreen>;

export default meta;
type Story = StoryObj<typeof meta>;

export const Intro: Story = {
  play: async ({ canvasElement, args }) => {
    const canvas = within(canvasElement);
    await expect(
      canvas.getByRole("heading", { level: 1, name: "Protege tus datos" }),
    ).toBeVisible();
    await expect(canvas.getByText(/solo tú podrás leer tus movimientos/)).toBeVisible();
    const start = canvas.getByRole("button", { name: "Empezar" });
    await expectTarget(start);
    await userEvent.click(start);
    await expect(args.onBegin).toHaveBeenCalledTimes(1);
    const signOut = canvas.getByRole("button", { name: "Cerrar sesión" });
    await expectTarget(signOut);
    await userEvent.click(signOut);
    await expect(args.onSignOut).toHaveBeenCalledTimes(1);
  },
};

export const Checking: Story = {
  args: { state: { status: "checking" } },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await expect(canvas.getByRole("heading", { level: 1, name: "Un momento…" })).toBeVisible();
    await expect(within(canvas.getByRole("main")).queryByRole("button")).toBeNull();
  },
};

/** The existing setup screen: the key, then four characters back. */
export const Keys: Story = {
  args: { state: { status: "keys", recoveryKey: KEY, busy: false } },
  play: async ({ canvasElement, args }) => {
    const canvas = within(canvasElement);
    await expect(canvas.getByRole("group", { name: "Tu clave de recuperación" })).toBeVisible();
    const saved = canvas.getByRole("button", { name: "Ya la guardé" });
    await expectTarget(saved);
    await userEvent.click(saved);
    for (const [n, c] of [
      [1, "7"],
      [2, "Q"],
      [3, "K"],
      [4, "2"],
    ] as const) {
      await userEvent.type(await canvas.findByLabelText(`Grupo 1, carácter ${n}`), c);
    }
    const next = canvas.getByRole("button", { name: "Continuar" });
    await waitFor(() => expect(next).toBeEnabled());
    await expectTarget(next);
    await userEvent.click(next);
    await expect(args.onConfirmKey).toHaveBeenCalledTimes(1);
  },
};

/** The account's keys were made in another browser: the recovery key opens them here. */
export const Unlock: Story = {
  args: { state: { status: "unlock" } },
  play: async ({ canvasElement, args }) => {
    const canvas = within(canvasElement);
    await expect(canvas.getByText(/ya tiene una clave de recuperación/)).toBeVisible();
    await userEvent.type(canvas.getByLabelText("Clave de recuperación"), KEY);
    const open = canvas.getByRole("button", { name: "Abrir mis datos" });
    await expectTarget(open);
    await userEvent.click(open);
    await expect(args.onUnlock).toHaveBeenCalledWith(KEY);
  },
};

export const Copying: Story = {
  args: { state: { status: "copying", done: 120, total: 480 } },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await expect(
      canvas.getByRole("heading", { level: 1, name: "Cifrando tus datos… 120 de 480" }),
    ).toBeVisible();
    const bar = canvas.getByRole("progressbar", { name: "Progreso del cifrado" });
    await expect(bar).toHaveAttribute("aria-valuenow", "120");
    await expect(bar).toHaveAttribute("aria-valuemax", "480");
    // Nothing to press while it copies: leaving would only start it over.
    await expect(within(canvas.getByRole("main")).queryByRole("button")).toBeNull();
  },
};

export const Finishing: Story = {
  args: { state: { status: "finishing" } },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await expect(
      canvas.getByRole("heading", { level: 1, name: "Comprobando que no falte nada…" }),
    ).toBeVisible();
    await expect(within(canvas.getByRole("main")).queryByRole("button")).toBeNull();
  },
};

export const Done: Story = {
  args: { state: { status: "done" } },
  play: async ({ canvasElement, args }) => {
    const canvas = within(canvasElement);
    await expect(
      canvas.getByRole("heading", { level: 1, name: "Listo: tu cuenta está cifrada." }),
    ).toBeVisible();
    const next = canvas.getByRole("button", { name: "Continuar" });
    await expectTarget(next);
    await userEvent.click(next);
    await expect(args.onContinue).toHaveBeenCalledTimes(1);
  },
};

export const CountMismatch: Story = {
  args: { state: { status: "failed", problem: "count_mismatch", retrying: false } },
  play: async ({ canvasElement, args }) => {
    const canvas = within(canvasElement);
    await expect(
      canvas.getByRole("heading", { level: 1, name: "Tus datos siguen a salvo" }),
    ).toBeVisible();
    await expect(
      canvas.getByText("Algo no cuadró y no borramos nada. Inténtalo de nuevo."),
    ).toBeVisible();
    const retry = canvas.getByRole("button", { name: "Reintentar" });
    await expectTarget(retry);
    await userEvent.click(retry);
    await expect(args.onRetry).toHaveBeenCalledTimes(1);
    const signOut = canvas.getByRole("button", { name: "Cerrar sesión" });
    await expectTarget(signOut);
  },
};

export const TakenOver: Story = {
  args: { state: { status: "failed", problem: "taken_over", retrying: false } },
  play: async ({ canvasElement, args }) => {
    const canvas = within(canvasElement);
    await expect(
      canvas.getByText("Esta migración sigue en otra pestaña o dispositivo."),
    ).toBeVisible();
    const here = canvas.getByRole("button", { name: "Seguir aquí" });
    await expectTarget(here);
    await userEvent.click(here);
    await expect(args.onRetry).toHaveBeenCalledTimes(1);
  },
};

export const Offline: Story = {
  args: { state: { status: "failed", problem: "offline", retrying: false } },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await expect(canvas.getByText(/Sin conexión/)).toBeVisible();
    await expectTarget(canvas.getByRole("button", { name: "Reintentar" }));
  },
};

export const Retrying: Story = {
  args: { state: { status: "failed", problem: "server", retrying: true } },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await expect(canvas.getByText(/Algo falló y no borramos nada/)).toBeVisible();
    await expect(canvas.getByRole("button", { name: "Reintentando…" })).toBeDisabled();
  },
};

export const NoLocalVault: Story = {
  args: { state: { status: "noLocalVault", busy: false } },
  play: async ({ canvasElement, args }) => {
    const canvas = within(canvasElement);
    await expect(
      canvas.getByRole("heading", { level: 1, name: "Esta migración empezó en otro lugar" }),
    ).toBeVisible();
    const restart = canvas.getByRole("button", { name: "Empezar de nuevo aquí" });
    await expectTarget(restart);
    await userEvent.click(restart);
    await expect(args.onRestart).toHaveBeenCalledTimes(1);
    const signOut = canvas.getByRole("button", { name: "Cerrar sesión" });
    await expectTarget(signOut);
    await userEvent.click(signOut);
    await expect(args.onSignOut).toHaveBeenCalledTimes(1);
  },
};

export const NoLocalVaultBusy: Story = {
  args: { state: { status: "noLocalVault", busy: true } },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await expect(canvas.getByRole("button", { name: "Empezar de nuevo aquí" })).toBeDisabled();
  },
};
