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
  args: { onRetry: fn() },
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
  },
};

export const Offline: Story = {
  args: { kind: "offline" },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await expect(canvas.getByRole("heading", { level: 1, name: "Sin conexión" })).toBeVisible();
  },
};

export const Retrying: Story = {
  args: { retrying: true },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await expect(canvas.getByRole("button", { name: "Reintentando…" })).toBeDisabled();
  },
};
