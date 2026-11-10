import type { Meta, StoryObj } from "@storybook/react-vite";
import { MemoryRouter } from "react-router";
import { expect, fn, userEvent, waitFor, within } from "storybook/test";
import { expectTarget } from "../../../.storybook/story-utils.ts";
import { PairingError, type PairingErrorCode } from "../../local/pairing.ts";
import { PairNewDevice, type PairNewDeviceRequest } from "./PairNewDevice.tsx";

/** A request whose number and finish settle as the story says (never, by default). */
function request({
  number = () => new Promise<string>(() => {}),
  finish = () => new Promise<unknown>(() => {}),
}: {
  number?: () => Promise<string>;
  finish?: () => Promise<unknown>;
} = {}): PairNewDeviceRequest {
  return {
    code: "ABCDEFGH",
    qr: "wambito://pair?id=0190a1b2-c3d4-7e5f-8a9b-0c1d2e3f4a5b&key=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
    expiresAt: "2026-11-10T12:10:00Z",
    number,
    finish,
    cancel: fn(),
  };
}

const failing = (code: PairingErrorCode) => () => Promise.reject(new PairingError(code));
const later = <T,>(value: T, ms = 300) =>
  new Promise<T>((resolve) => setTimeout(() => resolve(value), ms));

const meta = {
  title: "Vault/PairNewDevice",
  component: PairNewDevice,
  decorators: [
    (Story) => (
      <MemoryRouter>
        <Story />
      </MemoryRouter>
    ),
  ],
  args: {
    start: fn(async () => request()),
    onBack: fn(),
    timeZone: "Europe/Madrid",
  },
} satisfies Meta<typeof PairNewDevice>;

export default meta;
type Story = StoryObj<typeof meta>;

export const Waiting: Story = {
  play: async ({ canvasElement, args }) => {
    const canvas = within(canvasElement);
    await expect(
      canvas.getByRole("heading", { level: 1, name: "Abre tus datos desde otro dispositivo" }),
    ).toBeVisible();
    // The code in two groups of four, and the QR as an SVG image named by the code.
    await expect(await canvas.findByText("ABCD EFGH")).toBeVisible();
    const qr = canvas.getByRole("img", { name: "ABCDEFGH" });
    await expect(qr.getAttribute("src")).toMatch(/^data:image\/svg\+xml,/);
    await expect(decodeURIComponent(qr.getAttribute("src") ?? "")).toContain("<svg");
    await expect(canvas.getByText(/Esperando a tu otro dispositivo/)).toBeVisible();
    // 12:10 UTC in the account's zone (Madrid, UTC+1 in November).
    await expect(canvas.getByText("Este código sirve hasta las 13:10.")).toBeVisible();
    await expect(args.start).toHaveBeenCalledTimes(1);
    const back = canvas.getByRole("button", { name: "Volver" });
    await expectTarget(back);
    await userEvent.click(back);
    await expect(args.onBack).toHaveBeenCalledTimes(1);
  },
};

export const NumberShown: Story = {
  args: { start: fn(async () => request({ number: () => later("042917") })) },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await canvas.findByText("ABCD EFGH");
    // Not before number() resolves.
    await expect(canvas.queryByText("042 917")).toBeNull();
    await expect(await canvas.findByText("042 917")).toBeVisible();
    await expect(
      canvas.getByRole("heading", {
        name: "Comprueba que las dos pantallas muestran el mismo número",
      }),
    ).toBeVisible();
  },
};

export const Done: Story = {
  args: {
    start: fn(async () =>
      request({ number: async () => "042917", finish: () => later({ keys: true }, 100) }),
    ),
  },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await expect(await canvas.findByText(/Listo/)).toBeVisible();
  },
};

export const Expired: Story = {
  args: { start: fn(async () => request({ finish: failing("expired") })) },
  play: async ({ canvasElement, args }) => {
    const canvas = within(canvasElement);
    await expect(
      await canvas.findByRole("heading", { level: 1, name: "Este código caducó" }),
    ).toBeVisible();
    await expect(canvas.queryByRole("img", { name: "ABCDEFGH" })).toBeNull();
    const restart = canvas.getByRole("button", { name: "Empezar de nuevo" });
    await expectTarget(restart);
    await userEvent.click(restart);
    await waitFor(() => expect(args.start).toHaveBeenCalledTimes(2));
  },
};

export const Tampered: Story = {
  args: { start: fn(async () => request({ finish: failing("tampered") })) },
  play: async ({ canvasElement, args }) => {
    const canvas = within(canvasElement);
    await expect(await canvas.findByRole("alert")).toHaveTextContent(
      "Detente: puede que alguien esté interfiriendo. No se compartió nada.",
    );
    await expect(canvas.queryByText("ABCD EFGH")).toBeNull();
    await userEvent.click(canvas.getByRole("button", { name: "Volver" }));
    await expect(args.onBack).toHaveBeenCalledTimes(1);
  },
};

export const Offline: Story = {
  args: { start: fn(failing("offline")) },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await expect(await canvas.findByRole("alert")).toHaveTextContent("No hay conexión");
    await expect(canvas.getByRole("button", { name: "Empezar de nuevo" })).toBeVisible();
  },
};

/** A cancel (back, or a restart) is not an error: nothing is shown for it. */
export const Cancelled: Story = {
  args: { start: fn(async () => request({ finish: failing("cancelled") })) },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await canvas.findByText("ABCD EFGH");
    await new Promise((resolve) => setTimeout(resolve, 50));
    await expect(canvas.queryByRole("alert")).toBeNull();
  },
};

export const English: Story = {
  globals: { locale: "en" },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await expect(
      canvas.getByRole("heading", { level: 1, name: "Open your data from another device" }),
    ).toBeVisible();
  },
};
