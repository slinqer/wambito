import type { Meta, StoryObj } from "@storybook/react-vite";
import { MemoryRouter } from "react-router";
import { expect, fn, userEvent, waitFor, within } from "storybook/test";
import { expectTarget } from "../../../.storybook/story-utils.ts";
import { Locked } from "./Locked.tsx";
import { RecoveryKeySetup } from "./RecoveryKeySetup.tsx";
import { Unlock } from "./Unlock.tsx";

const KEY = "7QK2-M9XD-HT4V-R3WB-N8YC-5FJ6-A0Z";

const inRouter = (Story: () => React.ReactElement) => (
  <MemoryRouter>
    <Story />
  </MemoryRouter>
);

/** The first run: the key, copy, download, and four characters back before going on. */
const setup = {
  title: "Vault/RecoveryKeySetup",
  component: RecoveryKeySetup,
  decorators: [inRouter],
  args: {
    recoveryKey: KEY,
    positions: [1, 6, 14, 26],
    now: new Date("2026-11-08T12:00:00Z"),
    onContinue: fn(),
    onCopy: fn(async () => {}),
    onSave: fn(),
  },
} satisfies Meta<typeof RecoveryKeySetup>;

export default setup;
type Story = StoryObj<typeof setup>;

export const Show: Story = {
  play: async ({ canvasElement, args }) => {
    const canvas = within(canvasElement);
    await expect(
      canvas.getByRole("heading", { level: 1, name: "Guarda tu clave de recuperación" }),
    ).toBeVisible();
    await expect(canvas.getByText(/ni siquiera Wambito/)).toBeVisible();
    const group = canvas.getByRole("group", { name: "Tu clave de recuperación" });
    await expect(group).toHaveTextContent("7QK2M9XDHT4VR3WBN8YC5FJ6A0Z");
    for (const name of ["Copiar", "Descargar como .txt", "Ya la guardé"]) {
      await expectTarget(canvas.getByRole("button", { name }));
    }
    await userEvent.click(canvas.getByRole("button", { name: "Copiar" }));
    await expect(args.onCopy).toHaveBeenCalledWith(KEY);
    await canvas.findByRole("button", { name: "Copiada" });
    await userEvent.click(canvas.getByRole("button", { name: "Descargar como .txt" }));
    const [file] = (args.onSave as ReturnType<typeof fn>).mock.calls[0] as [
      { name: string; content: string },
    ];
    await expect(file.name).toBe("wambito-recovery-key.txt");
    await expect(file.content).toContain(KEY);
    await expect(file.content.trim().split("\n").filter(Boolean)).toHaveLength(4);
    await expect(file.content).toContain("2026");
  },
};

/** The next step names four positions; Continue waits until they match. */
export const ConfirmFourCharacters: Story = {
  play: async ({ canvasElement, args }) => {
    const canvas = within(canvasElement);
    await userEvent.click(canvas.getByRole("button", { name: "Ya la guardé" }));
    await expect(
      await canvas.findByRole("heading", { level: 1, name: "Comprueba que la guardaste" }),
    ).toBeVisible();
    await expect(canvas.getByText(/1, 6, 14 y 26/)).toBeVisible();
    await expect(canvas.queryByRole("group", { name: "Tu clave de recuperación" })).toBeNull();
    const next = canvas.getByRole("button", { name: "Continuar" });
    await expect(next).toBeDisabled();
    // 1 → 7, 6 → 9, 14 → 3, 26 → 0 (the key without dashes: 7QK2M9XDHT4VR3WBN8YC5FJ6A0Z)
    const wrong = ["7", "9", "3", "1"];
    const labels = ["Carácter 1", "Carácter 6", "Carácter 14", "Carácter 26"];
    for (const [i, label] of labels.entries()) {
      await userEvent.type(canvas.getByLabelText(label), wrong[i] as string);
    }
    await expect(await canvas.findByRole("alert")).toHaveTextContent("No coinciden");
    await expect(next).toBeDisabled();
    await userEvent.clear(canvas.getByLabelText("Carácter 26"));
    await userEvent.type(canvas.getByLabelText("Carácter 26"), "0");
    await waitFor(() => expect(next).toBeEnabled());
    await expect(canvas.queryByRole("alert")).toBeNull();
    await expectTarget(next);
    await userEvent.click(next);
    await expect(args.onContinue).toHaveBeenCalledTimes(1);
  },
};

export const ConfirmCaseBlind: Story = {
  args: { positions: [1, 2, 3, 4] },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await userEvent.click(canvas.getByRole("button", { name: "Ya la guardé" }));
    for (const [n, c] of [
      [1, "7"],
      [2, "q"],
      [3, "k"],
      [4, "2"],
    ] as const) {
      await userEvent.type(await canvas.findByLabelText(`Carácter ${n}`), c);
    }
    await waitFor(() => expect(canvas.getByRole("button", { name: "Continuar" })).toBeEnabled());
  },
};

export const GoBackToTheKey: Story = {
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await userEvent.click(canvas.getByRole("button", { name: "Ya la guardé" }));
    await userEvent.click(await canvas.findByRole("button", { name: "Ver la clave otra vez" }));
    await expect(
      await canvas.findByRole("group", { name: "Tu clave de recuperación" }),
    ).toBeVisible();
  },
};

export const Narrow: Story = {
  parameters: { viewport: { defaultViewport: "mobile1" } },
  decorators: [
    (Story) => (
      <div data-testid="narrow" style={{ width: 320 }}>
        <Story />
      </div>
    ),
  ],
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await expect(canvas.getByRole("button", { name: "Ya la guardé" })).toBeVisible();
    // Nothing sticks out of the 320px column.
    const frame = canvasElement.querySelector<HTMLElement>("[data-testid=narrow]");
    const right = (frame as HTMLElement).getBoundingClientRect().right;
    for (const element of canvasElement.querySelectorAll("button, input, h1, p")) {
      await expect(element.getBoundingClientRect().right).toBeLessThanOrEqual(right + 0.5);
    }
  },
};
