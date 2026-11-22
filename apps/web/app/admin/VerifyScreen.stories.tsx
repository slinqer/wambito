import type { Meta, StoryObj } from "@storybook/react-vite";
import { MemoryRouter } from "react-router";
import { expect, fn, userEvent, waitFor, within } from "storybook/test";
import { expectTarget } from "../../.storybook/story-utils.ts";
import { AdminMessages } from "./AdminMessages.tsx";
import { VerifyScreen } from "./VerifyScreen.tsx";

const meta = {
  title: "Admin/VerifyScreen",
  component: VerifyScreen,
  decorators: [
    (Story) => (
      <MemoryRouter initialEntries={["/admin"]}>
        <AdminMessages>
          <Story />
        </AdminMessages>
      </MemoryRouter>
    ),
  ],
  args: { verification: "idle", onVerify: fn() },
} satisfies Meta<typeof VerifyScreen>;

export default meta;
type Story = StoryObj<typeof meta>;

/** The entry screen: why the panel asks, and one button that opens the passkey prompt. */
export const Verify: Story = {
  play: async ({ canvasElement, args }) => {
    const canvas = within(canvasElement);
    const heading = canvas.getByRole("heading", { level: 1, name: "Confirma que eres tú" });
    await waitFor(() => expect(heading).toHaveFocus());
    await expect(
      canvas.getByText(
        "El panel de administración pide tu passkey cada 15 minutos. Tu dispositivo te pedirá el PIN, la huella o la cara.",
      ),
    ).toBeVisible();
    // One action only (the header's day/night switch aside).
    const main = within(canvas.getByRole("main"));
    await expect(main.getAllByRole("button")).toHaveLength(1);
    const button = canvas.getByRole("button", { name: "Confirmar con tu passkey" });
    await expectTarget(button);
    await userEvent.click(button);
    await expect(args.onVerify).toHaveBeenCalledOnce();
  },
};

/** The same screen in English, by day (contrast is checked in both themes). */
export const VerifyDayEnglish: Story = {
  globals: { theme: "day", locale: "en" },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await expect(canvas.getByRole("heading", { level: 1, name: "Confirm it's you" })).toBeVisible();
    await expect(canvas.getByRole("button", { name: "Confirm with your passkey" })).toBeVisible();
  },
};

/** Italian and Portuguese have no panel copy: the panel speaks English to them (spec §10). */
export const VerifyItalianFallsBackToEnglish: Story = {
  globals: { locale: "it" },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await expect(canvas.getByRole("heading", { level: 1, name: "Confirm it's you" })).toBeVisible();
  },
};

/** While the browser asks for the passkey the button waits and cannot be tapped again. */
export const VerifyBusy: Story = {
  args: { verification: "busy" },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await expect(canvas.getByRole("button", { name: "Esperando la passkey…" })).toBeDisabled();
  },
};

/** An admin with no passkey cannot use the panel: the screen says so and links to settings. */
export const VerifyNoPasskey: Story = {
  args: { verification: "no_passkey" },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await expect(
      canvas.getByRole("heading", { level: 1, name: "Necesitas una passkey" }),
    ).toBeVisible();
    await expect(
      canvas.getByText("Para usar el panel, añade una passkey a tu cuenta en los ajustes."),
    ).toBeVisible();
    await expect(within(canvas.getByRole("main")).queryByRole("button")).toBeNull();
    const link = canvas.getByRole("link", { name: "Ir a ajustes" });
    await expect(link).toHaveAttribute("href", "/app/settings/account");
    await expectTarget(link);
  },
};

/** The API refused the assertion: the error is read out and the button stays to try again. */
export const VerifyFailed: Story = {
  args: { verification: "failed" },
  play: async ({ canvasElement, args }) => {
    const canvas = within(canvasElement);
    await expect(canvas.getByRole("alert")).toHaveTextContent(
      "No se pudo confirmar la passkey. Inténtalo otra vez.",
    );
    const button = canvas.getByRole("button", { name: "Confirmar con tu passkey" });
    await expect(button).toHaveAttribute("aria-describedby", "admin-verify-error");
    await userEvent.click(button);
    await expect(args.onVerify).toHaveBeenCalledOnce();
  },
};
