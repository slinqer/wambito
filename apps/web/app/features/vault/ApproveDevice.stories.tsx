import type { Meta, StoryObj } from "@storybook/react-vite";
import { MemoryRouter } from "react-router";
import { expect, fn, userEvent, waitFor, within } from "storybook/test";
import { expectTarget } from "../../../.storybook/story-utils.ts";
import { type ApproverPairing, PairingError, type PairingErrorCode } from "../../local/pairing.ts";
import { ApproveDevice } from "./ApproveDevice.tsx";

const later = <T,>(value: T, ms = 300) =>
  new Promise<T>((resolve) => setTimeout(() => resolve(value), ms));

/** An approver pairing whose number and approve settle as the story says. */
function approver({
  number = async () => "042917",
  approve = () => later(undefined),
}: {
  number?: () => Promise<string>;
  approve?: () => Promise<void>;
} = {}): ApproverPairing {
  return { number, approve: fn(approve), cancel: fn() };
}

const meta = {
  title: "Vault/ApproveDevice",
  component: ApproveDevice,
  decorators: [
    (Story) => (
      <MemoryRouter>
        <Story />
      </MemoryRouter>
    ),
  ],
  args: {
    keys: { userId: "0190a1b2-c3d4-7e5f-8a9b-0c1d2e3f4a5b" },
    findPairing: fn(async () => approver()),
    scanSupported: (): boolean => false,
    onDone: fn(),
  },
} satisfies Meta<typeof ApproveDevice>;

export default meta;
type Story = StoryObj<typeof meta>;

const typeCode = async (canvas: ReturnType<typeof within>, code: string) => {
  await userEvent.type(canvas.getByLabelText("Código del dispositivo nuevo"), code);
  await userEvent.click(canvas.getByRole("button", { name: "Continuar" }));
};

export const TypeTheCode: Story = {
  play: async ({ canvasElement, args }) => {
    const canvas = within(canvasElement);
    await expect(
      canvas.getByRole("heading", { level: 1, name: "Aprobar un dispositivo nuevo" }),
    ).toBeVisible();
    await expect(canvas.queryByRole("button", { name: "Escanear el QR" })).toBeNull();
    await expectTarget(
      canvas.getByLabelText("Código del dispositivo nuevo").parentElement as HTMLElement,
    );
    await typeCode(canvas, "abcd efgh");
    await expect(args.findPairing).toHaveBeenCalledWith(
      expect.objectContaining({ userId: args.keys.userId, code: "abcd efgh" }),
    );
    await expect(await canvas.findByText("042 917")).toBeVisible();
    await expect(
      canvas.getByRole("heading", {
        name: "Comprueba que las dos pantallas muestran el mismo número",
      }),
    ).toBeVisible();
  },
};

export const TheyMatch: Story = {
  play: async ({ canvasElement, args }) => {
    const canvas = within(canvasElement);
    await typeCode(canvas, "ABCDEFGH");
    const match = await canvas.findByRole("button", { name: "Coinciden" });
    await expectTarget(match);
    await userEvent.click(match);
    const busy = canvas.getByRole("button", { name: "Aprobando…" });
    await expect(busy).toBeDisabled();
    await userEvent.click(busy);
    await expect(await canvas.findByRole("heading", { level: 1, name: "Listo" })).toBeVisible();
    const pairing = (await (args.findPairing as ReturnType<typeof fn>).mock.results[0]
      ?.value) as ApproverPairing;
    await expect(pairing.approve).toHaveBeenCalledTimes(1);
    await userEvent.click(canvas.getByRole("button", { name: "Cerrar" }));
    await expect(args.onDone).toHaveBeenCalledTimes(1);
  },
};

export const TheyDoNotMatch: Story = {
  play: async ({ canvasElement, args }) => {
    const canvas = within(canvasElement);
    await typeCode(canvas, "ABCDEFGH");
    await userEvent.click(await canvas.findByRole("button", { name: "No coinciden" }));
    await expect(
      await canvas.findByRole("heading", { level: 1, name: "No se compartió nada" }),
    ).toBeVisible();
    const pairing = (await (args.findPairing as ReturnType<typeof fn>).mock.results[0]
      ?.value) as ApproverPairing;
    await expect(pairing.cancel).toHaveBeenCalledTimes(1);
    await expect(pairing.approve).not.toHaveBeenCalled();
  },
};

/** "They match" only once the number is on screen: nothing to press while waiting. */
export const WaitingForTheNumber: Story = {
  args: { findPairing: fn(async () => approver({ number: () => new Promise(() => {}) })) },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await typeCode(canvas, "ABCDEFGH");
    await expect(await canvas.findByText(/Esperando al dispositivo nuevo/)).toBeVisible();
    await expect(canvas.queryByRole("button", { name: "Coinciden" })).toBeNull();
  },
};

const failing = (code: PairingErrorCode) =>
  fn(async (): Promise<ApproverPairing> => {
    throw new PairingError(code);
  });

export const BadCode: Story = {
  args: { findPairing: failing("bad_code") },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await typeCode(canvas, "ABCDEFGH");
    await expect(await canvas.findByRole("alert")).toHaveTextContent("no coincide con ninguna");
    await expect(canvas.getByLabelText("Código del dispositivo nuevo")).toHaveAttribute(
      "aria-invalid",
      "true",
    );
  },
};

export const Tampered: Story = {
  args: {
    findPairing: fn(async () =>
      approver({ number: () => Promise.reject(new PairingError("tampered")) }),
    ),
  },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await typeCode(canvas, "ABCDEFGH");
    await expect(await canvas.findByRole("alert")).toHaveTextContent(
      "Detente: puede que alguien esté interfiriendo. No se compartió nada.",
    );
    await expect(canvas.queryByRole("button", { name: "Coinciden" })).toBeNull();
  },
};

export const Expired: Story = {
  args: { findPairing: failing("expired") },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await typeCode(canvas, "ABCDEFGH");
    await userEvent.click(await canvas.findByRole("button", { name: "Empezar de nuevo" }));
    await waitFor(() =>
      expect(canvas.getByLabelText("Código del dispositivo nuevo")).toHaveValue(""),
    );
  },
};

export const Offline: Story = {
  args: { findPairing: failing("offline") },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await typeCode(canvas, "ABCDEFGH");
    await expect(await canvas.findByRole("alert")).toHaveTextContent("No hay conexión");
  },
};

/** Where `BarcodeDetector` exists (Chromium), a camera button; elsewhere the code alone. */
export const WithCamera: Story = {
  args: { scanSupported: () => true },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await expect(canvas.getByRole("button", { name: "Escanear el QR" })).toBeVisible();
  },
};

export const English: Story = {
  globals: { locale: "en" },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await expect(
      canvas.getByRole("heading", { level: 1, name: "Approve a new device" }),
    ).toBeVisible();
  },
};
