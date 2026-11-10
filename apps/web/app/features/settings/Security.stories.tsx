import type { Meta, StoryObj } from "@storybook/react-vite";
import { expect, fn, screen, userEvent, waitFor, within } from "storybook/test";
import { expectTarget } from "../../../.storybook/story-utils.ts";
import type { RotateResult } from "../../local/rotate.ts";
import { HomeStage, storyPasskeys } from "../home/story-harness.tsx";
import type { PasskeyItem, PasskeysApi } from "./passkeys.ts";
import type { RotateRequest, SecurityApi, SecuritySnapshot } from "./security.ts";
import type { SecurityWrap } from "./security-model.ts";

/**
 * Settings → Security for an encrypted account (`mode="local"`, stage 2b Task 8): the devices that
 * open the data, removing one (a key rotation), approving a new device, a new recovery key, the
 * passkeys that unlock, and the records that could not be read. Web-only, not in parity.json.
 */

const OWN = "0193a000-0000-7000-8000-00000000000a";
const LAPTOP = "0193a000-0000-7000-8000-00000000000b";
const FORGED = "0193a000-0000-7000-8000-00000000000c";
const REVOKED = "0193a000-0000-7000-8000-00000000000d";
const KEY = "7QK2-M9XD-HT4V-PA3R-WE6N-BC8J-Y2T";

const wrap = (over: Partial<SecurityWrap> & { id: string; kind: string }): SecurityWrap => ({
  ref: null,
  keyV: 1,
  wrapped: "w",
  publicKey: null,
  attestation: null,
  label: null,
  createdAt: "2026-10-01T10:00:00.000Z",
  ...over,
});

const WRAPS: SecurityWrap[] = [
  wrap({ id: "r", kind: "recovery" }),
  wrap({ id: OWN, kind: "device", label: "Chrome on macOS", createdAt: "2026-10-02T10:00:00Z" }),
  wrap({
    id: LAPTOP,
    kind: "device",
    label: "Firefox on Linux",
    createdAt: "2026-10-03T10:00:00Z",
  }),
  wrap({ id: FORGED, kind: "device", label: "Safari on iOS", createdAt: "2026-10-04T10:00:00Z" }),
  wrap({ id: REVOKED, kind: "device", label: "Edge on Windows" }),
  wrap({ id: "p1", kind: "passkey", ref: "cred-1" }),
];

const PASSKEYS: PasskeyItem[] = [
  {
    id: "pk-1",
    credentialId: "cred-1",
    name: null,
    createdAt: "2026-10-02T09:00:00.000Z",
    synced: true,
  },
  {
    id: "pk-2",
    credentialId: "cred-2",
    name: "Pixel 9",
    createdAt: "2026-10-05T10:00:00.000Z",
    synced: false,
  },
];

const coded = (code: string) => Object.assign(new Error(code), { code });

interface FakeOptions {
  unreadable?: number;
  /** What each rotate does, in turn (default: works). */
  rotate?: Array<"ok" | "wrong_recovery_key" | "rotated_elsewhere">;
  /** What the passkey touch gives. */
  touch?: "prf" | "no_prf" | "cancel";
}

/** The vault's keys in memory, with spies on every effect. */
function fakeSecurity({ unreadable = 3, rotate = [], touch = "prf" }: FakeOptions = {}) {
  let wraps = [...WRAPS];
  let attempt = 0;
  const commitRotate = fn(async (request: RotateRequest): Promise<RotateResult> => {
    const removed = new Set(request.remove);
    const dropped = wraps
      .filter(
        (w) => w.kind === "device" && (removed.has(w.id) || w.id === REVOKED || w.id === FORGED),
      )
      .map((w) => ({
        id: w.id,
        label: w.label ?? null,
        reason: removed.has(w.id)
          ? ("removed" as const)
          : w.id === REVOKED
            ? ("revoked" as const)
            : ("attestation" as const),
      }));
    const gone = new Set(dropped.map((d) => d.id));
    const kept = request.passkey?.credentialId;
    wraps = wraps
      .filter((w) => !gone.has(w.id))
      .filter((w) => w.kind !== "passkey" || w.ref === kept)
      .map((w) => ({ ...w, keyV: 2 }));
    return { keyV: 2, dropped };
  });
  const commitNewKey = fn(async () => {});
  const security = {
    load: fn(
      async (): Promise<SecuritySnapshot> => ({
        wraps,
        ownId: OWN,
        revoked: [REVOKED],
        verified: new Set([LAPTOP]),
        unreadable,
      }),
    ),
    rotate: fn(async (request: RotateRequest) => {
      const outcome = rotate[attempt++] ?? "ok";
      if (outcome !== "ok") throw coded(outcome);
      return {
        recoveryKey: "fresh" in request.recovery ? KEY : null,
        commit: () => commitRotate(request),
      };
    }),
    checkRecoveryKey: fn(async (text: string) => {
      if (text.trim().toUpperCase() !== KEY) throw coded("wrong_recovery_key");
    }),
    newRecoveryKey: fn(async () => ({ recoveryKey: KEY, commit: commitNewKey })),
    reloadKeys: fn(async () => {}),
    evaluatePrf: fn(async (ids?: string[]) => {
      if (touch === "cancel") return null;
      if (touch === "no_prf") throw coded("no_prf");
      return { credentialId: ids?.[0] ?? "cred-1", prf: new Uint8Array(32).fill(7) };
    }),
    addPasskeyWrap: fn(async ({ credentialId }: { credentialId: string; prf: Uint8Array }) => {
      wraps = [...wraps, wrap({ id: `p-${credentialId}`, kind: "passkey", ref: credentialId })];
    }),
    pairing: { userId: "u-ana" },
    findPairing: fn(() => new Promise<never>(() => {})),
    scanSupported: () => false,
  } satisfies SecurityApi;
  return { security, commitRotate, commitNewKey };
}

type Fake = ReturnType<typeof fakeSecurity>;

/** The fake of the story on screen, for its play function (a fresh one per story). */
let current: Fake | null = null;

interface Args {
  options: FakeOptions;
}

const meta = {
  title: "Settings/Security",
  args: { options: {} },
  beforeEach: () => {
    current = null;
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
type Story = StoryObj<Args & { fake?: Fake }>;
type Canvas = ReturnType<typeof within>;

const stage = (
  args: Args,
  extra: { guest?: boolean; mode?: "local" | "live"; passkeys?: PasskeysApi } = {},
) => {
  current ??= fakeSecurity(args.options);
  const fake = current;
  return (
    <HomeStage
      onRequest={() => {}}
      mode={extra.mode ?? "local"}
      path="/app/settings"
      passkeys={extra.passkeys ?? storyPasskeys({ initial: PASSKEYS })}
      security={fake.security}
      {...(extra.guest ? { guest: true } : {})}
    />
  );
};
const fakeOf = (_args: Args) => current as Fake;

const section = async (canvas: Canvas) =>
  within(await canvas.findByRole("region", { name: "Seguridad" }));

/** Types back the four characters `RecoveryKeySetup` asks for, then Continúa. */
async function typeBack(key: string) {
  await userEvent.click(await screen.findByRole("button", { name: "Ya la guardé" }));
  const groups = key.split("-");
  for (const input of screen.getAllByRole("textbox", { name: /^Grupo \d, carácter \d$/ })) {
    const [, group, char] = /Grupo (\d), carácter (\d)/.exec(
      input.getAttribute("aria-label") as string,
    ) as RegExpExecArray;
    await userEvent.type(input, groups[Number(group) - 1]?.[Number(char) - 1] as string);
  }
}

/**
 * This browser first, marked and with no Remove; the other devices with their added date; a
 * forged one "Sin verificar"; a revoked one not listed; the unreadable count.
 */
export const Overview: Story = {
  render: (args) => stage(args),
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    const security = await section(canvas);
    const items = await security.findAllByRole("listitem");
    await expect(items).toHaveLength(3);
    const [own, laptop, forged] = items.map((item) => within(item));
    await expect(own?.getByText("Chrome on macOS")).toBeVisible();
    await expect(own?.getByText("Este navegador")).toBeVisible();
    await expect(own?.queryByRole("button")).toBeNull();
    await expect(laptop?.getByText("Agregado el 3 oct 2026")).toBeVisible();
    await expect(laptop?.queryByText("Sin verificar")).toBeNull();
    await expectTarget(
      laptop?.getByRole("button", { name: "Quitar Firefox on Linux" }) as HTMLElement,
    );
    await expect(forged?.getByText("Sin verificar")).toBeVisible();
    await expect(forged?.getByRole("button", { name: "Quitar Safari on iOS" })).toBeVisible();
    await expect(security.queryByText("Edge on Windows")).toBeNull();
    await expect(
      security.getByRole("button", { name: "Aprobar un dispositivo nuevo" }),
    ).toBeVisible();
    await expect(
      security.getByRole("button", { name: "Nueva clave de recuperación" }),
    ).toBeVisible();
    await expect(security.getByText("No pudimos leer 3 elementos")).toBeVisible();
  },
};

/** "Could not read N items" shows only when N > 0. */
export const NothingUnreadable: Story = {
  args: { options: { unreadable: 0 } },
  render: (args) => stage(args),
  play: async ({ canvasElement }) => {
    const security = await section(within(canvasElement));
    await security.findAllByRole("listitem");
    await expect(security.queryByText(/No pudimos leer/)).toBeNull();
  },
};

/** Ruling 8: a guest has no recovery key; the section is not there (nor in the live app). */
export const HiddenForGuests: Story = {
  render: (args) => stage(args, { guest: true }),
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await canvas.findByRole("heading", { level: 1, name: "Ajustes" });
    await canvas.findByRole("region", { name: "Entrar con tu huella" });
    await expect(canvas.queryByRole("region", { name: "Seguridad" })).toBeNull();
  },
};

export const HiddenInTheLiveApp: Story = {
  render: (args) => stage(args, { mode: "live" }),
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await canvas.findByRole("region", { name: "Entrar con tu huella" });
    await expect(canvas.queryByRole("region", { name: "Seguridad" })).toBeNull();
  },
};

const openRemove = async (canvas: Canvas, name = "Firefox on Linux") => {
  const security = await section(canvas);
  await userEvent.click(await security.findByRole("button", { name: `Quitar ${name}` }));
  return within(await screen.findByRole("dialog", { name: `¿Quitar ${name}?` }));
};

/**
 * Remove asks for the recovery key or a new one; a wrong key keeps the sheet with the error; the
 * right one rotates, the sync takes the keys, and the sheet lists what was dropped.
 */
export const RemoveWithRecoveryKey: Story = {
  args: { options: { rotate: ["wrong_recovery_key"] } },
  render: (args) => stage(args),
  play: async ({ canvasElement, args }) => {
    const { security, commitRotate } = fakeOf(args);
    const sheet = await openRemove(within(canvasElement));
    const field = sheet.getByRole("textbox", { name: "Clave de recuperación" });
    await expect(sheet.getByRole("button", { name: "Sí, quitarlo" })).toBeDisabled();
    await expect(
      sheet.getByRole("button", { name: "¿No la tienes? Crea una clave de recuperación nueva" }),
    ).toBeEnabled();

    await userEvent.type(field, "AAAA-BBBB");
    await userEvent.click(sheet.getByRole("button", { name: "Sí, quitarlo" }));
    await expect(await sheet.findByRole("alert")).toHaveTextContent(
      "Esa clave no abre esta cuenta.",
    );
    await expect(field).toHaveAttribute("aria-invalid", "true");
    await expect(commitRotate).not.toHaveBeenCalled();

    await userEvent.clear(field);
    await userEvent.type(field, KEY);
    await userEvent.click(sheet.getByRole("button", { name: "Sí, quitarlo" }));
    const done = within(await screen.findByRole("dialog", { name: "Listo" }));
    await expect(done.getByText("Firefox on Linux ya no puede abrir tus datos.")).toBeVisible();
    await expect(done.getByText("Edge on Windows (quitado antes)")).toBeVisible();
    await expect(done.getByText("Safari on iOS (sin verificar)")).toBeVisible();
    await expect(done.getByText(/vuelve a activarlas/)).toBeVisible();
    await expect(security.rotate).toHaveBeenLastCalledWith({
      remove: [LAPTOP],
      recovery: { text: KEY },
    });
    await expect(commitRotate).toHaveBeenCalledTimes(1);
    await expect(security.reloadKeys).toHaveBeenCalledTimes(1);

    await userEvent.click(done.getByRole("button", { name: "Cerrar" }));
    const list = await section(within(canvasElement));
    await waitFor(() => expect(list.queryByText("Firefox on Linux")).toBeNull());
  },
};

/** Another device rotated first: the sheet says to try again after the refresh, and stays. */
export const RemoveRotatedElsewhere: Story = {
  args: { options: { rotate: ["rotated_elsewhere"] } },
  render: (args) => stage(args),
  play: async ({ canvasElement, args }) => {
    const { security } = fakeOf(args);
    const sheet = await openRemove(within(canvasElement));
    await userEvent.type(sheet.getByRole("textbox", { name: "Clave de recuperación" }), KEY);
    await userEvent.click(sheet.getByRole("button", { name: "Sí, quitarlo" }));
    await expect(await sheet.findByRole("alert")).toHaveTextContent(
      "Otro dispositivo cambió tus claves al mismo tiempo. Espera un momento a que se actualicen aquí e inténtalo otra vez.",
    );
    await expect(security.reloadKeys).toHaveBeenCalledTimes(1);
    await expect(screen.getByRole("dialog", { name: "¿Quitar Firefox on Linux?" })).toBeVisible();
  },
};

/**
 * "Make a new recovery key": a passkey touch confirms it (that passkey keeps its wrap), the new
 * key is shown, and nothing is committed until its four characters are typed back.
 */
export const RemoveWithNewKey: Story = {
  render: (args) => stage(args),
  play: async ({ canvasElement, args }) => {
    const { security, commitRotate } = fakeOf(args);
    const sheet = await openRemove(within(canvasElement));
    await userEvent.click(
      sheet.getByRole("button", { name: "¿No la tienes? Crea una clave de recuperación nueva" }),
    );
    await expect(
      await screen.findByRole("heading", { name: "Guarda tu clave de recuperación" }),
    ).toBeVisible();
    await expect(security.evaluatePrf).toHaveBeenCalledWith(["cred-1", "cred-2"]);
    const request = security.rotate.mock.calls[0]?.[0] as RotateRequest;
    await expect(request.recovery).toEqual({ fresh: true });
    await expect(request.passkey?.credentialId).toBe("cred-1");
    await expect(commitRotate).not.toHaveBeenCalled();

    await typeBack(KEY);
    await expect(commitRotate).not.toHaveBeenCalled();
    await userEvent.click(screen.getByRole("button", { name: "Continuar" }));
    await expect(await screen.findByRole("dialog", { name: "Listo" })).toBeVisible();
    await expect(commitRotate).toHaveBeenCalledTimes(1);
    await expect(security.reloadKeys).toHaveBeenCalledTimes(1);
  },
};

/** A touch that gave no PRF still confirms (Ruling 2); a cancelled one does not. */
export const RemoveWithNewKeyNoPrf: Story = {
  args: { options: { touch: "no_prf" } },
  render: (args) => stage(args),
  play: async ({ canvasElement, args }) => {
    const { security } = fakeOf(args);
    const sheet = await openRemove(within(canvasElement));
    await userEvent.click(
      sheet.getByRole("button", { name: "¿No la tienes? Crea una clave de recuperación nueva" }),
    );
    await screen.findByRole("heading", { name: "Guarda tu clave de recuperación" });
    const request = security.rotate.mock.calls[0]?.[0] as RotateRequest;
    await expect(request.passkey).toBeUndefined();
    await userEvent.click(screen.getByRole("button", { name: "Cancelar" }));
    await expect(
      await screen.findByRole("dialog", { name: "¿Quitar Firefox on Linux?" }),
    ).toBeVisible();
  },
};

/**
 * New recovery key: confirmed by the current key (a wrong one is refused), then the setup flow,
 * and `commit()` only after the four characters are typed back.
 */
export const NewRecoveryKey: Story = {
  render: (args) => stage(args),
  play: async ({ canvasElement, args }) => {
    const { security, commitNewKey } = fakeOf(args);
    const area = await section(within(canvasElement));
    await userEvent.click(area.getByRole("button", { name: "Nueva clave de recuperación" }));
    const sheet = within(
      await screen.findByRole("dialog", { name: "Crear una clave de recuperación nueva" }),
    );
    await expect(sheet.getByRole("button", { name: "Usar una huella" })).toBeVisible();
    const field = sheet.getByRole("textbox", { name: "Clave de recuperación actual" });
    await userEvent.type(field, "AAAA-BBBB");
    await userEvent.click(sheet.getByRole("button", { name: "Continuar" }));
    await expect(await sheet.findByRole("alert")).toHaveTextContent(
      "Esa clave no abre esta cuenta.",
    );
    await expect(security.newRecoveryKey).not.toHaveBeenCalled();

    await userEvent.clear(field);
    await userEvent.type(field, KEY);
    await userEvent.click(sheet.getByRole("button", { name: "Continuar" }));
    await screen.findByRole("heading", { name: "Guarda tu clave de recuperación" });
    await expect(security.newRecoveryKey).toHaveBeenCalledTimes(1);
    await expect(commitNewKey).not.toHaveBeenCalled();
    await typeBack(KEY);
    await expect(commitNewKey).not.toHaveBeenCalled();
    await userEvent.click(screen.getByRole("button", { name: "Continuar" }));
    await waitFor(() => expect(commitNewKey).toHaveBeenCalledTimes(1));
    await waitFor(
      () =>
        expect(
          screen.getByText(
            "Tu clave de recuperación nueva quedó guardada. La anterior ya no funciona.",
          ),
        ).toBeVisible(),
      { timeout: 8000 },
    );
  },
};

/** A cancelled passkey touch confirms nothing. */
export const NewRecoveryKeyCancelledTouch: Story = {
  args: { options: { touch: "cancel" } },
  render: (args) => stage(args),
  play: async ({ canvasElement, args }) => {
    const { security } = fakeOf(args);
    const area = await section(within(canvasElement));
    await userEvent.click(area.getByRole("button", { name: "Nueva clave de recuperación" }));
    const sheet = within(
      await screen.findByRole("dialog", { name: "Crear una clave de recuperación nueva" }),
    );
    await userEvent.click(sheet.getByRole("button", { name: "Usar una huella" }));
    await waitFor(() => expect(security.evaluatePrf).toHaveBeenCalledTimes(1));
    await expect(security.newRecoveryKey).not.toHaveBeenCalled();
    await expect(sheet.getByRole("button", { name: "Usar una huella" })).toBeEnabled();
  },
};

/** "Aprobar un dispositivo nuevo" opens the approval screen over Settings; Cancel closes it. */
export const ApproveANewDevice: Story = {
  render: (args) => stage(args),
  play: async ({ canvasElement }) => {
    const area = await section(within(canvasElement));
    await userEvent.click(area.getByRole("button", { name: "Aprobar un dispositivo nuevo" }));
    const takeover = within(
      await screen.findByRole("dialog", { name: "Aprobar un dispositivo nuevo" }),
    );
    await expect(
      takeover.getByRole("heading", { level: 1, name: "Aprobar un dispositivo nuevo" }),
    ).toBeVisible();
    await userEvent.click(takeover.getByRole("button", { name: "Cancelar" }));
    await waitFor(() =>
      expect(screen.queryByRole("dialog", { name: "Aprobar un dispositivo nuevo" })).toBeNull(),
    );
  },
};

/**
 * Each passkey says whether it opens the data; "Activar" touches that passkey and adds its wrap.
 */
export const PasskeysThatUnlock: Story = {
  render: (args) => stage(args),
  play: async ({ canvasElement, args }) => {
    const { security } = fakeOf(args);
    const canvas = within(canvasElement);
    const passkeys = within(await canvas.findByRole("region", { name: "Entrar con tu huella" }));
    await expect(await passkeys.findByText("Abre tus datos")).toBeVisible();
    await expect(passkeys.getByText("No abre tus datos")).toBeVisible();
    await userEvent.click(passkeys.getByRole("button", { name: "Activar Pixel 9 para tus datos" }));
    await waitFor(() => expect(security.addPasskeyWrap).toHaveBeenCalledTimes(1));
    await expect(security.evaluatePrf).toHaveBeenCalledWith(["cred-2"]);
    const touched = security.addPasskeyWrap.mock.calls[0]?.[0] as { prf: Uint8Array };
    await expect(touched.prf.every((x) => x === 0)).toBe(true);
    await waitFor(() => expect(passkeys.getAllByText("Abre tus datos")).toHaveLength(2));
    await expect(passkeys.queryByText("No abre tus datos")).toBeNull();
  },
};

/** A passkey whose provider gives no PRF: it says so, naming the recovery key and another device. */
export const PasskeyCannotUnlock: Story = {
  args: { options: { touch: "no_prf" } },
  render: (args) => stage(args),
  play: async ({ canvasElement, args }) => {
    const { security } = fakeOf(args);
    const passkeys = within(
      await within(canvasElement).findByRole("region", { name: "Entrar con tu huella" }),
    );
    await userEvent.click(
      await passkeys.findByRole("button", { name: "Activar Pixel 9 para tus datos" }),
    );
    await expect(await passkeys.findByRole("alert")).toHaveTextContent(
      "El proveedor de esta huella no puede abrir tus datos. Usa tu clave de recuperación o ábrelos desde otro dispositivo.",
    );
    await expect(security.addPasskeyWrap).not.toHaveBeenCalled();
  },
};

const OR_NEW = "¿No la tienes? Crea una clave de recuperación nueva";

/** A passkey list that never answers: the account may have passkeys, so no touch-free new key. */
const loadingPasskeys = (): PasskeysApi => ({
  ...storyPasskeys({ initial: PASSKEYS }),
  list: () => new Promise<PasskeyItem[]>(() => {}),
});

/** While the passkey list loads, "make a new recovery key" waits (disabled), in both sheets. */
export const NewKeyWaitsForThePasskeyList: Story = {
  render: (args) => stage(args, { passkeys: loadingPasskeys() }),
  play: async ({ canvasElement, args }) => {
    const { security } = fakeOf(args);
    const sheet = await openRemove(within(canvasElement));
    const orNew = sheet.getByRole("button", { name: OR_NEW });
    await expect(orNew).toBeDisabled();
    await userEvent.click(orNew, { pointerEventsCheck: 0 });
    await expect(security.rotate).not.toHaveBeenCalled();
    await expect(security.evaluatePrf).not.toHaveBeenCalled();
    await userEvent.keyboard("{Escape}");
    await waitFor(() => expect(screen.queryByRole("dialog")).toBeNull());

    const area = await section(within(canvasElement));
    await userEvent.click(area.getByRole("button", { name: "Nueva clave de recuperación" }));
    const newKey = within(
      await screen.findByRole("dialog", { name: "Crear una clave de recuperación nueva" }),
    );
    await expect(newKey.getByRole("button", { name: "Usar una huella" })).toBeDisabled();
  },
};

/** A passkey list that failed: no new key is offered, only the typed key, with a retry. */
export const NewKeyNotOfferedWhenThePasskeyListFailed: Story = {
  render: (args) => stage(args, { passkeys: storyPasskeys({ initial: PASSKEYS, failList: true }) }),
  play: async ({ canvasElement, args }) => {
    const { security } = fakeOf(args);
    const canvas = within(canvasElement);
    // the list's query gives up after its retries
    await canvas.findByText(
      "No pudimos cargar tus huellas. Inténtalo de nuevo en un momento.",
      {},
      { timeout: 15000 },
    );
    const sheet = await openRemove(canvas);
    await expect(sheet.queryByRole("button", { name: OR_NEW })).toBeNull();
    await expect(
      sheet.getByText(
        "No pudimos cargar tus huellas, así que todavía no podemos ofrecerte una clave nueva.",
      ),
    ).toBeVisible();
    await expect(sheet.getByRole("button", { name: "Reintentar" })).toBeVisible();
    await expect(sheet.getByRole("textbox", { name: "Clave de recuperación" })).toBeVisible();
    await expect(security.rotate).not.toHaveBeenCalled();
    await userEvent.keyboard("{Escape}");
    await waitFor(() => expect(screen.queryByRole("dialog")).toBeNull());

    const area = await section(within(canvasElement));
    await userEvent.click(area.getByRole("button", { name: "Nueva clave de recuperación" }));
    const newKey = within(
      await screen.findByRole("dialog", { name: "Crear una clave de recuperación nueva" }),
    );
    await expect(newKey.queryByRole("button", { name: "Usar una huella" })).toBeNull();
    await expect(newKey.getByRole("button", { name: "Reintentar" })).toBeVisible();
  },
};

/** The account has passkeys but this browser cannot touch one: only the typed key. */
export const OnlyTheTypedKeyWithoutTouch: Story = {
  render: (args) =>
    stage(args, { passkeys: storyPasskeys({ initial: PASSKEYS, supported: false }) }),
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await (await section(canvas)).findAllByRole("listitem");
    // the list has loaded
    await within(await canvas.findByRole("region", { name: "Entrar con tu huella" })).findByText(
      "Pixel 9",
    );
    const sheet = await openRemove(canvas);
    await expect(sheet.getByRole("textbox", { name: "Clave de recuperación" })).toBeVisible();
    await expect(sheet.queryByRole("button", { name: OR_NEW })).toBeNull();
  },
};

/** No passkeys at all: a new key needs no touch; the type-back confirms it. */
export const NewKeyWithoutPasskeys: Story = {
  render: (args) => stage(args, { passkeys: storyPasskeys({ initial: [] }) }),
  play: async ({ canvasElement, args }) => {
    const { security } = fakeOf(args);
    const canvas = within(canvasElement);
    await within(await canvas.findByRole("region", { name: "Entrar con tu huella" })).findByText(
      /Aún no tienes/,
    );
    const sheet = await openRemove(canvas);
    await userEvent.click(sheet.getByRole("button", { name: OR_NEW }));
    await screen.findByRole("heading", { name: "Guarda tu clave de recuperación" });
    await expect(security.evaluatePrf).not.toHaveBeenCalled();
  },
};
