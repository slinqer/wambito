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

const KEY = "7QK2-M9XD-HT4V-R3WB-N8YC-5FJ6-A0Z";

/** This browser's last passkey touch gave no PRF: the recovery key leads, with the line. */
const NO_PRF = { noPrfHere: true, passkeyWrap: true };
/** The account has no passkey wrap: nothing a passkey could open. */
const NO_WRAP = { noPrfHere: false, passkeyWrap: false };
const NO_PRF_LINE =
  "Tu huella te deja entrar, pero tu gestor de contraseñas no le permite abrir tus datos.";

type Canvas = ReturnType<typeof within>;
const more = (canvas: Canvas) => canvas.getByRole("button", { name: "Más opciones" });

const typeKey = async (canvas: Canvas, text: string) => {
  await userEvent.type(canvas.getByLabelText("Clave de recuperación"), text);
  await expect(canvas.getByRole("button", { name: "Abrir mis datos" })).toBeEnabled();
  await userEvent.click(canvas.getByRole("button", { name: "Abrir mis datos" }));
};

/** The recovery key leads (key-first): typing, pasting shapes, the pairing and the way out. */
export const Ready: Story = {
  args: { means: NO_PRF },
  play: async ({ canvasElement, args }) => {
    const canvas = within(canvasElement);
    await expect(
      canvas.getByRole("heading", { level: 1, name: "Abre tus datos aquí" }),
    ).toBeVisible();
    // Paste, the key's submit, another device, "More options" and sign-out (and the screen's own).
    await expect(canvas.getAllByRole("button", { name: "Pegar" })).toHaveLength(1);
    await expect(canvas.getAllByRole("button")).toHaveLength(6);
    const pair = canvas.getByRole("button", { name: "Desde otro dispositivo" });
    await expectTarget(pair);
    await userEvent.click(pair);
    await expect(args.onPair).toHaveBeenCalledTimes(1);
    await userEvent.click(canvas.getByRole("button", { name: "Cerrar sesión" }));
    await expect(args.onSignOut).toHaveBeenCalledTimes(1);
    await expectTarget(canvas.getByLabelText("Clave de recuperación").parentElement as HTMLElement);
    await expect(canvas.getByRole("button", { name: "Abrir mis datos" })).toBeDisabled();
    // Typed in any shape, the field shows the key in groups and submits it grouped.
    const field = canvas.getByLabelText("Clave de recuperación");
    await userEvent.type(field, "  7qk2 m9xd-ht4v r3wb n8yc 5fj6 a0");
    await expect(field).toHaveValue("7QK2-M9XD-HT4V-R3WB-N8YC-5FJ6-A0");
    await expect(canvas.getByRole("button", { name: "Abrir mis datos" })).toBeDisabled();
    await userEvent.type(field, "z");
    await expect(field).toHaveValue(KEY);
    await userEvent.click(canvas.getByRole("button", { name: "Abrir mis datos" }));
    await expect(args.onUnlock).toHaveBeenCalledWith(KEY);
  },
};

export const BadFormat: Story = {
  args: { means: NO_PRF, onUnlock: fn(async () => "bad_recovery_key" as const) },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await typeKey(canvas, KEY);
    await expect(await canvas.findByRole("alert")).toHaveTextContent(
      "no tiene el formato correcto",
    );
    await expect(canvas.getByLabelText("Clave de recuperación")).toHaveAttribute(
      "aria-invalid",
      "true",
    );
    // Editing again clears it.
    await userEvent.type(canvas.getByLabelText("Clave de recuperación"), "{Backspace}");
    await expect(canvas.queryByRole("alert")).toBeNull();
  },
};

export const WrongKey: Story = {
  args: { means: NO_PRF, onUnlock: fn(async () => "wrong_recovery_key" as const) },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await typeKey(canvas, KEY);
    await expect(await canvas.findByRole("alert")).toHaveTextContent("no abre esta cuenta");
    await expect(canvas.getByRole("button", { name: "Abrir mis datos" })).toBeEnabled();
  },
};

export const Offline: Story = {
  args: { means: NO_PRF, onUnlock: fn(async () => "offline" as const) },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await typeKey(canvas, KEY);
    await expect(await canvas.findByRole("alert")).toHaveTextContent("No hay conexión");
  },
};

export const Opening: Story = {
  args: { means: NO_PRF, onUnlock: fn(() => new Promise<UnlockError | null>(() => {})) },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await typeKey(canvas, KEY);
    await expect(await canvas.findByRole("button", { name: "Abriendo…" })).toBeDisabled();
  },
};

/**
 * This browser's last passkey touch gave no PRF: the field and the line lead, the pairing below,
 * and another passkey waits under "More options" (closed by default).
 */
export const KeyFirst: Story = {
  args: { means: NO_PRF },
  play: async ({ canvasElement, args }) => {
    const canvas = within(canvasElement);
    await expect(canvas.getByLabelText("Clave de recuperación")).toBeVisible();
    await expect(canvas.getByText(NO_PRF_LINE)).toBeVisible();
    await expect(canvas.getByRole("button", { name: "Abrir mis datos" })).toHaveClass(
      "lk-btn-primary",
    );
    await expect(canvas.getByRole("button", { name: "Desde otro dispositivo" })).toBeVisible();
    await expect(more(canvas)).toHaveAttribute("aria-expanded", "false");
    await expect(canvas.queryByRole("button", { name: "Usar otra huella" })).toBeNull();
    await expect(canvas.queryByRole("button", { name: "Abrir con mi huella" })).toBeNull();
    await userEvent.click(more(canvas));
    await expect(more(canvas)).toHaveAttribute("aria-expanded", "true");
    const other = canvas.getByRole("button", { name: "Usar otra huella" });
    await expectTarget(other);
    await userEvent.click(other);
    await expect(args.onPasskey).toHaveBeenCalledTimes(1);
  },
};

/** No passkey wrap on the account: nothing to try under "More options" but the key itself. */
export const KeyFirstWithoutWrap: Story = {
  args: { means: { noPrfHere: true, passkeyWrap: false } },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await expect(canvas.getByLabelText("Clave de recuperación")).toBeVisible();
    await expect(canvas.getByText(NO_PRF_LINE)).toBeVisible();
    await expect(canvas.queryByRole("button", { name: "Más opciones" })).toBeNull();
    await expect(canvas.queryByRole("button", { name: /huella/ })).toBeNull();
  },
};

/**
 * The account has a passkey wrap and this browser can touch one: "Abrir con mi huella" leads, the
 * pairing below, the recovery key under "More options" (not in the document until opened).
 */
export const PasskeyFirst: Story = {
  play: async ({ canvasElement, args }) => {
    const canvas = within(canvasElement);
    const passkey = canvas.getByRole("button", { name: "Abrir con mi huella" });
    await expect(passkey).toHaveClass("lk-btn-primary");
    await expectTarget(passkey);
    await expect(canvas.getByRole("button", { name: "Desde otro dispositivo" })).toHaveClass(
      "lk-btn-secondary",
    );
    await expect(canvas.queryByLabelText("Clave de recuperación")).toBeNull();
    await expect(canvas.queryByText(NO_PRF_LINE)).toBeNull();
    await expect(more(canvas)).toHaveAttribute("aria-expanded", "false");
    await userEvent.click(more(canvas));
    await expect(canvas.getByLabelText("Clave de recuperación")).toBeVisible();
    // No touch until the person taps.
    await expect(args.onPasskey).not.toHaveBeenCalled();
    await typeKey(canvas, KEY);
    await expect(args.onUnlock).toHaveBeenCalledWith(KEY);
  },
};

/** No passkey wrap: "Desde otro dispositivo" leads, the recovery key under "More options". */
export const PairFirst: Story = {
  args: { means: NO_WRAP },
  play: async ({ canvasElement, args }) => {
    const canvas = within(canvasElement);
    const pair = canvas.getByRole("button", { name: "Desde otro dispositivo" });
    await expect(pair).toHaveClass("lk-btn-primary");
    await expect(canvas.queryByRole("button", { name: /huella/ })).toBeNull();
    await expect(canvas.queryByLabelText("Clave de recuperación")).toBeNull();
    await userEvent.click(more(canvas));
    await expect(canvas.getByLabelText("Clave de recuperación")).toBeVisible();
    await userEvent.click(pair);
    await expect(args.onPair).toHaveBeenCalledTimes(1);
  },
};

/** The consent page: no pairing and no passkey wrap: the field leads, with no disclosure. */
export const ConsentNoPairing: Story = {
  args: { means: NO_WRAP, onPair: undefined, lead: null, exitLabel: "Cancelar" },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await expect(canvas.getByLabelText("Clave de recuperación")).toBeVisible();
    await expect(canvas.queryByRole("button", { name: "Más opciones" })).toBeNull();
    await expect(canvas.queryByRole("button", { name: /huella/ })).toBeNull();
    await expect(canvas.queryByText(NO_PRF_LINE)).toBeNull();
    await expect(canvas.getByRole("button", { name: "Cancelar" })).toBeVisible();
  },
};

export const UsePasskey: Story = {
  play: async ({ canvasElement, args }) => {
    const canvas = within(canvasElement);
    await userEvent.click(canvas.getByRole("button", { name: "Abrir con mi huella" }));
    await expect(args.onPasskey).toHaveBeenCalledTimes(1);
    await expect(args.onUnlock).not.toHaveBeenCalled();
    await expect(canvas.queryByRole("alert")).toBeNull();
    // Cancelled or worked: "More options" stays closed.
    await expect(more(canvas)).toHaveAttribute("aria-expanded", "false");
  },
};

/** A passkey without PRF: the error, and "More options" opens by itself on the recovery key. */
export const PasskeyFails: Story = {
  args: { onPasskey: fn(async () => "no_prf" as const) },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await userEvent.click(canvas.getByRole("button", { name: "Abrir con mi huella" }));
    const alert = await canvas.findByRole("alert");
    // The two other ways: the recovery key, and another device.
    await expect(alert).toHaveTextContent("Esta huella no puede abrir tus datos");
    await expect(alert).toHaveTextContent("clave de recuperación");
    await expect(alert).toHaveTextContent("otro dispositivo");
    await expect(more(canvas)).toHaveAttribute("aria-expanded", "true");
    await expect(canvas.getByLabelText("Clave de recuperación")).toBeVisible();
  },
};

export const PasskeyWithoutWrap: Story = {
  args: { onPasskey: fn(async () => "no_passkey_wrap" as const) },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await userEvent.click(canvas.getByRole("button", { name: "Abrir con mi huella" }));
    await expect(await canvas.findByRole("alert")).toHaveTextContent("clave de recuperación");
    await expect(more(canvas)).toHaveAttribute("aria-expanded", "true");
    await expect(canvas.getByLabelText("Clave de recuperación")).toBeVisible();
  },
};

/** No passkeys in this browser: the pairing leads, the recovery key under "More options". */
export const NoPasskeys: Story = {
  args: { passkeysSupported: () => false },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await expect(canvas.queryByRole("button", { name: /huella/ })).toBeNull();
    await expect(canvas.getByRole("button", { name: "Desde otro dispositivo" })).toHaveClass(
      "lk-btn-primary",
    );
    // Another device, "More options" and sign-out (and the screen's own).
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
    await expect(canvas.getByRole("button", { name: "Abrir con mi huella" })).toBeVisible();
    await userEvent.click(more(canvas));
    await expect(canvas.getByLabelText("Clave de recuperación")).toBeVisible();
  },
};

/** A new key version did not verify: the vault is kept, the notice asks to unlock again. */
export const Unverified: Story = {
  args: { notice: "unverified" },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await expect(canvas.getByRole("status")).toHaveTextContent(
      "Este navegador no pudo verificar la clave nueva de tu cuenta y dejó de sincronizar. Tus datos aquí están a salvo. Para seguir, usa tu huella o escribe tu clave de recuperación.",
    );
    await expect(canvas.getByRole("button", { name: "Abrir con mi huella" })).toBeVisible();
    await userEvent.click(more(canvas));
    await expect(canvas.getByLabelText("Clave de recuperación")).toBeVisible();
  },
};
