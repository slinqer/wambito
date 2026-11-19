import type { Meta, StoryObj } from "@storybook/react-vite";
import { MemoryRouter } from "react-router";
import { expect, fn, userEvent, waitFor, within } from "storybook/test";
import { expectTarget } from "../../../.storybook/story-utils.ts";
import { realClock } from "../../local/relay.ts";
import type { WebSignin } from "../../local/signin.ts";
import { QrSignIn } from "./QrSignIn.tsx";
import { SignInScreen } from "./SignInScreen.tsx";
import { createQrSignin, type QrSignin, type QrState } from "./signin-model.ts";

const never = <T,>() => new Promise<T>(() => {});

/** A request no phone answers. */
function request(): WebSignin {
  return {
    id: "0190a1b2-c3d4-7e5f-8a9b-0c1d2e3f4a5b",
    code: "ABCDEFGH",
    qr: "wambito://signin?id=0190a1b2-c3d4-7e5f-8a9b-0c1d2e3f4a5b&key=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
    expiresAt: new Date(Date.now() + 2 * 60 * 1000).toISOString(),
    number: never,
    ready: never,
    finish: never,
    cancel: () => {},
  };
}

/** The real model over a fake `startSignin` and a page that stays visible. */
function liveModel(): QrSignin {
  return createQrSignin({
    start: fn(async () => request()) as never,
    label: "Firefox on macOS",
    clock: realClock,
    visible: () => true,
    onVisibility: () => () => {},
  });
}

/** A model held in one state, for the states a story cannot wait for. */
function fixedModel(state: QrState, remember = true): QrSignin {
  return {
    state: () => state,
    subscribe: () => () => {},
    setRemember: fn(),
    remember: () => remember,
    retry: fn(),
    stop: fn(),
  };
}

const meta = {
  title: "Sign-in/QR",
  component: QrSignIn,
  decorators: [
    (Story) => (
      <MemoryRouter>
        <SignInScreen>
          <Story />
        </SignInScreen>
      </MemoryRouter>
    ),
  ],
  args: { model: fixedModel({ status: "opening" }), onSignedIn: fn(), timeZone: "Europe/Madrid" },
} satisfies Meta<typeof QrSignIn>;

export default meta;
type Story = StoryObj<typeof meta>;

export const Showing: Story = {
  args: { model: liveModel() },
  play: async ({ canvasElement, step }) => {
    const canvas = within(canvasElement);
    await step("the box is checked by default and the code reads ABCD EFGH", async () => {
      await expect(await canvas.findByText("ABCD EFGH")).toBeVisible();
      const box = canvas.getByRole("checkbox", {
        name: "Mantener la sesión abierta en este navegador",
      });
      await expect(box).toBeChecked();
      await expect(box).toBeEnabled();
      const qr = canvas.getByRole("img", { name: "ABCDEFGH" });
      await expect(decodeURIComponent(qr.getAttribute("src") ?? "")).toContain("<svg");
      await expect(
        canvas.getByText(
          "Escanéalo con Wambito en tu celular: Ajustes → Seguridad → Conectar otro dispositivo",
        ),
      ).toBeVisible();
      await expect(
        canvas.queryByText("No queda nada en este computador cuando cierres el navegador"),
      ).toBeNull();
    });
  },
};

export const Unticked: Story = {
  args: { model: liveModel() },
  play: async ({ canvasElement, args }) => {
    const canvas = within(canvasElement);
    await canvas.findByText("ABCD EFGH");
    const box = canvas.getByRole("checkbox", {
      name: "Mantener la sesión abierta en este navegador",
    });
    await userEvent.click(box);
    await expect(box).not.toBeChecked();
    await expect(
      canvas.getByText("No queda nada en este computador cuando cierres el navegador"),
    ).toBeVisible();
    // a new QR for the new value, after the box stays still
    await waitFor(() => expect(args.model.state().status).toBe("showing"));
    await expect(await canvas.findByText("ABCD EFGH")).toBeVisible();
  },
};

export const ApprovedWithNumber: Story = {
  args: { model: fixedModel({ status: "approved", request: request(), number: "042917" }) },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await expect(
      canvas.getByText("Si tu celular muestra un número, debe ser 042 917"),
    ).toBeVisible();
    await expect(
      canvas.getByRole("checkbox", { name: "Mantener la sesión abierta en este navegador" }),
    ).toBeDisabled();
  },
};

export const Finishing: Story = {
  args: { model: fixedModel({ status: "finishing" }) },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await expect(canvas.getByRole("status")).toHaveTextContent("Abriendo tus datos…");
    await expect(canvas.queryByRole("img", { name: "ABCDEFGH" })).toBeNull();
    await expect(canvas.queryByRole("checkbox")).toBeNull();
  },
};

export const Done: Story = {
  args: { model: fixedModel({ status: "done", userId: "user-1" }) },
  play: async ({ args }) => {
    await waitFor(() => expect(args.onSignedIn).toHaveBeenCalledWith("user-1"));
    await expect(args.onSignedIn).toHaveBeenCalledTimes(1);
  },
};

export const Expired: Story = {
  args: { model: fixedModel({ status: "failed", code: "expired" }) },
  play: async ({ canvasElement, args }) => {
    const canvas = within(canvasElement);
    await expect(canvas.getByText("Este código caducó")).toBeVisible();
    await expect(canvas.queryByRole("img", { name: "ABCDEFGH" })).toBeNull();
    const retry = canvas.getByRole("button", { name: "Reintentar" });
    await expectTarget(retry);
    await userEvent.click(retry);
    await expect(args.model.retry).toHaveBeenCalledTimes(1);
  },
};

export const TooMany: Story = {
  args: {
    model: fixedModel({
      status: "failed",
      code: "too_many",
      retryAt: Date.parse("2026-11-18T12:05:00Z"),
    }),
  },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    // 12:05 UTC in Madrid (UTC+1 in November); it retries by itself, so no button
    await expect(canvas.getByRole("alert")).toHaveTextContent(
      "Demasiados códigos desde aquí. Wambi pide otro a las 13:05.",
    );
    await expect(canvas.queryByRole("button", { name: "Reintentar" })).toBeNull();
  },
};

export const Offline: Story = {
  args: { model: fixedModel({ status: "failed", code: "offline" }) },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await expect(canvas.getByRole("alert")).toHaveTextContent(
      "No hay conexión. Inténtalo de nuevo cuando vuelvas a tenerla.",
    );
    await expect(canvas.getByRole("button", { name: "Reintentar" })).toBeVisible();
  },
};
