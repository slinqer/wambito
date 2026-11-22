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
  /** The settings record's `recoveryKeySavedAt`. */
  savedAt: string | null;
  onRequest: (line: string) => void;
}

const meta = {
  title: "Settings/Add email",
  args: { claim: "ok", savedAt: null, onRequest: fn() },
  beforeEach: () => {
    current = null;
  },
  render: (args) => {
    current ??= fake(args.savedAt);
    return (
      <HomeStage
        onRequest={args.onRequest}
        mode="local"
        path="/app/settings"
        guest
        claim={args.claim}
        security={current.security}
      />
    );
  },
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
const KEY = "7QK2-M9XD-HT4V-PA3R-WE6N-BC8J-Y2T";

/** The vault's keys and the settings record in memory, with spies on the recovery key's effects. */
function fake(savedAt: string | null) {
  let recoveryKeySavedAt = savedAt;
  const commit = fn(async () => {});
  const markRecoveryKeySaved = fn(async () => {
    recoveryKeySavedAt = "2026-10-21T15:00:00.000Z";
  });
  const newRecoveryKey = fn(async () => ({ recoveryKey: KEY, commit }));
  const security = {
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
    newRecoveryKey,
    reloadKeys: async () => {},
    evaluatePrf: async () => null,
    addPasskeyWrap: async () => {},
    settings: async () => ({ recoveryKeySavedAt }),
    markRecoveryKeySaved,
    pairing: { userId: "u-ana" },
    findPairing: () => new Promise<never>(() => {}),
    scanSupported: () => false,
  } as unknown as NonNullable<Parameters<typeof HomeStage>[0]["security"]>;
  return {
    security,
    commit,
    newRecoveryKey,
    markRecoveryKeySaved,
    saved: () => recoveryKeySavedAt,
  };
}

/** The fake of the story on screen (a fresh one per story). */
let current: ReturnType<typeof fake> | null = null;

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

/** Types back the four characters `RecoveryKeySetup` asks for. */
async function typeBack(key: string) {
  const groups = key.split("-");
  for (const input of await within(document.body).findAllByRole("textbox", {
    name: /^Grupo \d, carácter \d$/,
  })) {
    const [, group, char] = /Grupo (\d), carácter (\d)/.exec(
      input.getAttribute("aria-label") as string,
    ) as RegExpExecArray;
    await userEvent.type(input, groups[Number(group) - 1]?.[Number(char) - 1] as string);
  }
}

/** No recovery key saved yet: its setup comes right after the email, with no way out until saved. */
export const KeyAfterTheEmail: Story = {
  name: "Recovery key after the email",
  play: async ({ canvasElement }) => {
    const dialog = await openAddEmail(canvasElement);
    await userEvent.type(await dialog.findByRole("textbox", { name: "Dígito 1 de 6" }), "123456");
    const body = within(document.body);
    await userEvent.click(await body.findByRole("button", { name: "Ya la guardé" }));
    // No Cancel, no "Ahora no": the key must be saved first.
    await expect(body.queryByRole("button", { name: "Ahora no" })).toBeNull();
    await expect(body.queryByRole("button", { name: "Cancelar" })).toBeNull();
    await expect(current?.saved()).toBeNull();
    await typeBack(KEY);
    await userEvent.click(await body.findByRole("button", { name: "Continuar" }));
    await waitFor(() => expect(current?.markRecoveryKeySaved).toHaveBeenCalledOnce());
    await expect(current?.commit).toHaveBeenCalledOnce();
    await expect(current?.saved()).not.toBeNull();
    await waitFor(() => expect(body.queryByRole("dialog")).toBeNull());
  },
};

/** The key was saved before: straight to done, no key screen. */
export const SavedKeySkipsSetup: Story = {
  name: "Saved key goes straight to done",
  args: { savedAt: "2026-10-20T10:00:00.000Z" },
  play: async ({ canvasElement }) => {
    const dialog = await openAddEmail(canvasElement);
    await userEvent.type(await dialog.findByRole("textbox", { name: "Dígito 1 de 6" }), "123456");
    await waitFor(() => expect(within(document.body).queryByRole("dialog")).toBeNull());
    await expect(current?.newRecoveryKey).not.toHaveBeenCalled();
  },
};

/** The email, the code, done: the profile shows the email and the Protect block goes. */
export const AddsTheEmail: Story = {
  name: "Adds the email",
  args: { savedAt: "2026-10-20T10:00:00.000Z" },
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
