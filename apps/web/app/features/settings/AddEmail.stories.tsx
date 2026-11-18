import type { Meta, StoryObj } from "@storybook/react-vite";
import { expect, fn, userEvent, waitFor, within } from "storybook/test";
import { HomeStage } from "../home/story-harness.tsx";

/**
 * "Protect your data" step 3 (spec 2026-11-15 section 5.2): an account without an email adds one in
 * Settings. The email, then the 6-digit code (the story's backend takes 123456), then the profile
 * shows the email and the Protect block is gone. An email that already has an account is refused
 * with the words to bring this data into it from the phone (the web never merges). Web-only, not
 * in parity.json.
 */

interface Args {
  claim: "ok" | "taken";
  onRequest: (line: string) => void;
}

const meta = {
  title: "Settings/Add email",
  args: { claim: "ok", onRequest: fn() },
  render: (args) => (
    <HomeStage
      onRequest={args.onRequest}
      mode="local"
      path="/app/settings"
      guest
      claim={args.claim}
      security={SECURITY}
    />
  ),
  parameters: {
    viewport: {
      options: {
        phone: { name: "Phone", styles: { width: "390px", height: "844px" }, type: "mobile" },
      },
    },
  },
  globals: { viewport: { value: "phone", isRotated: false } },
} satisfies Meta<Args>;

export default meta;
type Story = StoryObj<typeof meta>;

const OWN = "0193a000-0000-7000-8000-00000000000a";
const SECURITY = {
  load: async () => ({
    wraps: [
      {
        id: "r",
        kind: "recovery",
        ref: null,
        keyV: 1,
        wrapped: "w",
        publicKey: null,
        attestation: null,
        label: null,
        createdAt: "2026-10-01T10:00:00.000Z",
      },
    ],
    ownId: OWN,
    revoked: [],
    verified: new Set<string>(),
    unreadable: 0,
  }),
  rotate: async () => {
    throw new Error("not in these stories");
  },
  checkRecoveryKey: async () => {},
  newRecoveryKey: async () => {
    throw new Error("not in these stories");
  },
  reloadKeys: async () => {},
  evaluatePrf: async () => null,
  addPasskeyWrap: async () => {},
  settings: async () => ({ recoveryKeySavedAt: null }),
  markRecoveryKeySaved: async () => {},
  pairing: { userId: "u-ana" },
  findPairing: () => new Promise<never>(() => {}),
  scanSupported: () => false,
} as unknown as NonNullable<Parameters<typeof HomeStage>[0]["security"]>;

async function openAddEmail(canvasElement: HTMLElement) {
  const block = within(
    await within(canvasElement).findByRole("region", { name: "Protege tus datos" }),
  );
  await userEvent.click(await block.findByRole("button", { name: "Agrega un email" }));
  const dialog = within(await within(document.body).findByRole("dialog"));
  await userEvent.type(await dialog.findByLabelText("Tu email"), "ana@ejemplo.com");
  await userEvent.click(dialog.getByRole("button", { name: "Enviar código" }));
  return dialog;
}

/** The email, the code, done: the profile shows the email and the Protect block goes. */
export const AddsTheEmail: Story = {
  name: "Adds the email",
  play: async ({ canvasElement, args }) => {
    const dialog = await openAddEmail(canvasElement);
    await userEvent.type(await dialog.findByRole("textbox", { name: "Dígito 1 de 6" }), "123456");
    await waitFor(() =>
      expect(args.onRequest).toHaveBeenCalledWith(
        'POST /api/v1/me/claim-email/verify {"email":"ana@ejemplo.com","code":"123456"}',
        expect.anything(),
      ),
    );
    await waitFor(() => expect(within(canvasElement).queryByText("Protege tus datos")).toBeNull());
    await expect(await within(canvasElement).findByText(/ana@ejemplo\.com/)).toBeVisible();
  },
};

/** A wrong code is sign-in's message, and the boxes start over. */
export const WrongCode: Story = {
  name: "Wrong code",
  play: async ({ canvasElement }) => {
    const dialog = await openAddEmail(canvasElement);
    await userEvent.type(await dialog.findByRole("textbox", { name: "Dígito 1 de 6" }), "000000");
    await expect(await dialog.findByText(/Ese código no es correcto/)).toBeVisible();
  },
};

/** The email already has an account: no merge on the web, the phone is the way. */
export const EmailTaken: Story = {
  name: "Email taken",
  args: { claim: "taken" },
  play: async ({ canvasElement }) => {
    const dialog = await openAddEmail(canvasElement);
    await expect(
      await dialog.findByText(
        "Este email ya tiene una cuenta de Wambito. Abre Wambito en tu teléfono para traer estos datos a ella.",
      ),
    ).toBeVisible();
  },
};
