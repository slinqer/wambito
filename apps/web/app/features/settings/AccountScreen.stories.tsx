import type { Meta, StoryObj } from "@storybook/react-vite";
import { expect, fn, screen, userEvent, within } from "storybook/test";
import { expectTarget } from "../../../.storybook/story-utils.ts";
import { HomeStage, storyPasskeys } from "../home/story-harness.tsx";
import type { PasskeyItem } from "./passkeys.ts";
import type { SecurityApi, SecuritySnapshot } from "./security.ts";
import type { SecurityWrap } from "./security-model.ts";

/**
 * Cuenta y seguridad, the light version: the email, a group of passkeys, (encrypted accounts) a
 * group of devices and the recovery key, and the delete row in red. Web-only, not in parity.json.
 */

const OWN = "0193a000-0000-7000-8000-00000000000a";
const OTHER = "0193a000-0000-7000-8000-00000000000b";

const wrap = (over: Partial<SecurityWrap> & { id: string; kind: string }): SecurityWrap => ({
  ref: null,
  keyV: 1,
  wrapped: "w",
  publicKey: null,
  attestation: null,
  label: null,
  createdAt: "2026-11-03T10:00:00.000Z",
  ...over,
});

const PASSKEYS: PasskeyItem[] = [
  {
    id: "pk-1",
    credentialId: "cred-1",
    name: "Pixel 8",
    createdAt: "2026-11-03T09:00:00.000Z",
    synced: true,
  },
  {
    id: "pk-2",
    credentialId: "cred-2",
    name: "MacBook",
    createdAt: "2026-11-18T09:00:00.000Z",
    synced: false,
  },
];

function fakeSecurity(): SecurityApi {
  const wraps = [
    wrap({ id: "r", kind: "recovery" }),
    wrap({ id: OWN, kind: "device", label: "Chrome on macOS" }),
    wrap({ id: OTHER, kind: "device", label: "Pixel 8", createdAt: "2026-11-18T10:00:00Z" }),
    wrap({ id: "w1", kind: "passkey", ref: "cred-1" }),
    wrap({ id: "w2", kind: "passkey", ref: "cred-2" }),
  ];
  return {
    load: fn(
      async (): Promise<SecuritySnapshot> => ({
        wraps,
        ownId: OWN,
        revoked: [],
        verified: new Set([OTHER]),
        unreadable: 0,
      }),
    ),
    removeDevice: fn(async () => {}),
    rotate: fn(async () => {
      throw new Error("unused");
    }),
    checkRecoveryKey: fn(async () => {}),
    newRecoveryKey: fn(async () => ({
      recoveryKey: "7QK2-M9XD-HT4V-PA3R-WE6N-BC8J-Y2T",
      commit: async () => {},
    })),
    reloadKeys: fn(async () => {}),
    evaluatePrf: fn(async () => null),
    addPasskeyWrap: fn(async () => {}),
    settings: fn(async () => ({ recoveryKeySavedAt: null })),
    markRecoveryKeySaved: fn(async () => {}),
    pairing: { userId: "u-ana" },
    findPairing: fn(() => new Promise<never>(() => {})),
    scanSupported: () => false,
  } satisfies SecurityApi;
}

const meta = {
  title: "Settings/Account",
  parameters: {
    viewport: {
      options: {
        phone: { name: "Phone", styles: { width: "390px", height: "844px" }, type: "mobile" },
      },
    },
  },
  globals: { viewport: { value: "phone", isRotated: false } },
} satisfies Meta;

export default meta;
type Story = StoryObj<typeof meta>;

const plain = () => (
  <HomeStage
    onRequest={() => {}}
    path="/app/settings/account"
    passkeys={storyPasskeys({ initial: PASSKEYS })}
  />
);
const encrypted = () => (
  <HomeStage
    onRequest={() => {}}
    mode="local"
    path="/app/settings/account"
    passkeys={storyPasskeys({ initial: PASSKEYS })}
    security={fakeSecurity()}
  />
);

/** A plain account: the email, the passkeys group and the delete row; nothing about devices or keys. */
export const Plain: Story = {
  render: plain,
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await expect(
      await canvas.findByRole("heading", { level: 1, name: "Cuenta y seguridad" }),
    ).toBeVisible();
    await expect(canvas.getByText("ana@example.com")).toBeVisible();
    const keys = within(await canvas.findByRole("group", { name: "Entrar con tu huella" }));
    await expect(keys.getByText("Sin código, con tu huella o tu cara")).toBeVisible();
    await expect(await keys.findByText("Desde el 3 nov 2026 · sincronizada")).toBeVisible();
    await expect(keys.getByText("Desde el 18 nov 2026")).toBeVisible();
    await expectTarget(keys.getByRole("button", { name: /^Eliminar Pixel 8/ }));
    await expect(keys.getByRole("button", { name: "Agregar una huella" })).toBeVisible();
    await expect(canvas.queryByRole("group", { name: "Tus dispositivos" })).toBeNull();
    await expect(canvas.queryByText("Clave de recuperación")).toBeNull();
    await expect(canvas.getByRole("button", { name: /^Eliminar tu cuenta/ })).toBeVisible();
  },
};

/** An encrypted account: all four, this browser marked "Este" with no trash. */
export const Encrypted: Story = {
  render: encrypted,
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    const devices = within(await canvas.findByRole("group", { name: "Tus dispositivos" }));
    await expect(devices.getByText("Pueden abrir tus datos cifrados")).toBeVisible();
    await expect(await devices.findByText("Chrome on macOS")).toBeVisible();
    await expect(devices.getByText("Este")).toBeVisible();
    await expect(devices.queryByRole("button", { name: "Quitar Chrome on macOS" })).toBeNull();
    await expectTarget(await devices.findByRole("button", { name: "Quitar Pixel 8" }));
    await expect(devices.getByRole("button", { name: "Conectar otro dispositivo" })).toBeVisible();
    const recovery = canvas.getByRole("button", { name: /^Clave de recuperación/ });
    await expect(recovery).toHaveTextContent("Crea una nueva si la perdiste");
    await expect(canvas.getByRole("button", { name: /^Eliminar tu cuenta/ })).toBeVisible();
  },
};

/** The passkey's trash asks the existing question first; Cancelar leaves it. */
export const PasskeyTrashAsks: Story = {
  render: plain,
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await userEvent.click(await canvas.findByRole("button", { name: /^Eliminar MacBook/ }));
    const sheet = within(await screen.findByRole("dialog", { name: "¿Eliminar esta huella?" }));
    await expect(
      sheet.getByText("Ya no podrás entrar con ella. Tu correo sigue funcionando."),
    ).toBeVisible();
    await userEvent.click(sheet.getByRole("button", { name: "Cancelar" }));
    await expect(canvas.getByText("MacBook")).toBeVisible();
  },
};

/** The delete row opens the sheet with its full text and the export-first link. */
export const DeleteRowOpensSheet: Story = {
  render: plain,
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await userEvent.click(await canvas.findByRole("button", { name: /^Eliminar tu cuenta/ }));
    const sheet = within(await screen.findByRole("dialog", { name: "¿Eliminar tu cuenta?" }));
    await expect(sheet.getByText(/Se borran de inmediato tus movimientos/)).toBeVisible();
    await expect(sheet.getByRole("button", { name: "Descarga tus datos antes" })).toBeVisible();
    await expect(sheet.getByRole("button", { name: "Sí, eliminar mi cuenta" })).toBeDisabled();
  },
};

/** The recovery key row opens today's flow, whose first step says what it does. */
export const RecoveryRowOpensFlow: Story = {
  render: encrypted,
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await userEvent.click(await canvas.findByRole("button", { name: /^Clave de recuperación/ }));
    const sheet = within(
      await screen.findByRole("dialog", { name: "Crear una clave de recuperación nueva" }),
    );
    await expect(sheet.getByText(/Crea una nueva si la perdiste/)).toBeVisible();
  },
};
