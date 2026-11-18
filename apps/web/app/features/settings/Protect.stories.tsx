import type { Meta, StoryObj } from "@storybook/react-vite";
import { expect, fn, screen, userEvent, waitFor, within } from "storybook/test";
import { HomeStage } from "../home/story-harness.tsx";
import type { PasskeyItem, PasskeysApi } from "./passkeys.ts";
import type { SecurityApi, SecuritySnapshot } from "./security.ts";
import type { SecurityWrap } from "./security-model.ts";

/**
 * "Protect your data" (spec 2026-11-15 section 5.2) at the top of Settings → Security, for an
 * account without an email (`isAnonymous`, `mode="local"`): "N of 2" until the recovery key or a
 * passkey that opens the data is there, then a quiet list. Web-only, not in parity.json.
 */

const OWN = "0193a000-0000-7000-8000-00000000000a";
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

const passkey = (n: number): PasskeyItem => ({
  id: `pk-${n}`,
  credentialId: `cred-${n}`,
  name: null,
  createdAt: "2026-10-02T09:00:00.000Z",
  synced: true,
});

interface FakeOptions {
  /** The settings record's `recoveryKeySavedAt`. */
  savedAt?: string | null;
  /** The person's passkeys, and which of them have a wrap. */
  passkeys?: PasskeyItem[];
  wrapped?: string[];
  /**
   * What a new passkey's provider gives (default: a PRF, so it gets its wrap); `keep_fails`: a PRF,
   * but the wrap's PUT fails (the passkey stays, as `addPasskey` swallows it).
   */
  newPasskey?: "prf" | "no_prf" | "keep_fails";
  /** Whether this browser can make a passkey (default yes). */
  supported?: boolean;
}

/** The vault's keys and the person's passkeys in memory, with spies on every effect. */
function fake({
  savedAt = null,
  passkeys: initial = [],
  wrapped = [],
  newPasskey = "prf",
  supported = true,
}: FakeOptions = {}) {
  let wraps: SecurityWrap[] = [
    wrap({ id: "r", kind: "recovery" }),
    wrap({ id: OWN, kind: "device", label: "Chrome on macOS" }),
    ...wrapped.map((ref) => wrap({ id: `p-${ref}`, kind: "passkey", ref })),
  ];
  let recoveryKeySavedAt = savedAt;
  let items = [...initial];
  const commit = fn(async () => {});
  const security = {
    load: fn(
      async (): Promise<SecuritySnapshot> => ({
        wraps,
        ownId: OWN,
        revoked: [],
        verified: new Set(),
        unreadable: 0,
      }),
    ),
    removeDevice: fn(async () => {}),
    rotate: fn(async () => {
      throw new Error("not in these stories");
    }),
    checkRecoveryKey: fn(async () => {}),
    newRecoveryKey: fn(async () => ({ recoveryKey: KEY, commit })),
    reloadKeys: fn(async () => {}),
    evaluatePrf: fn(async () => null),
    addPasskeyWrap: fn(async ({ credentialId }: { credentialId: string; prf: Uint8Array }) => {
      if (newPasskey === "keep_fails") throw new Error("offline");
      wraps = [...wraps, wrap({ id: `p-${credentialId}`, kind: "passkey", ref: credentialId })];
    }),
    settings: fn(async () => ({ recoveryKeySavedAt })),
    markRecoveryKeySaved: fn(async () => {
      recoveryKeySavedAt = "2026-10-21T15:00:00.000Z";
    }),
    pairing: { userId: "u-ana" },
    findPairing: fn(() => new Promise<never>(() => {})),
    scanSupported: () => false,
  } satisfies SecurityApi;
  const passkeys: PasskeysApi = {
    supported: () => supported,
    list: async () => [...items],
    add: fn(async (vault) => {
      const item = passkey(items.length + 1);
      items = [...items, item];
      // A provider with PRF hands the new passkey's secret over; without it nothing is kept.
      if (newPasskey !== "no_prf" && vault?.keep) {
        try {
          await vault.keep({ credentialId: item.credentialId, prf: new Uint8Array(32).fill(7) });
        } catch {
          // as `addPasskey`: the passkey was added and signs in, it only does not open the data
        }
      }
      return "added" as const;
    }),
    remove: async (id) => {
      items = items.filter((item) => item.id !== id);
    },
  };
  return { security, passkeys, commit };
}

type Fake = ReturnType<typeof fake>;

/** The fake of the story on screen, for its play function (a fresh one per story). */
let current: Fake | null = null;

interface Args {
  options: FakeOptions;
  anonymous: boolean;
  onAddEmail: () => void;
}

const meta = {
  title: "Settings/Protect",
  args: { options: {}, anonymous: true, onAddEmail: fn() },
  beforeEach: () => {
    current = null;
  },
  render: (args) => {
    current ??= fake(args.options);
    return (
      <HomeStage
        onRequest={() => {}}
        mode="local"
        path="/app/settings"
        passkeys={current.passkeys}
        security={current.security}
        onAddEmail={args.onAddEmail}
        {...(args.anonymous ? { guest: true } : {})}
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

const fakeOf = () => current as Fake;

const protect = async (canvasElement: HTMLElement) =>
  within(await within(canvasElement).findByRole("region", { name: "Protege tus datos" }));

/** Types back the four characters `RecoveryKeySetup` asks for. */
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

/** Nothing done: "0 de 2" and the three steps, each with its button. */
export const ZeroOfTwo: Story = {
  name: "0 of 2",
  play: async ({ canvasElement, args }) => {
    const block = await protect(canvasElement);
    await expect(block.getByText("0 de 2")).toBeVisible();
    await expect(
      block.getByRole("button", { name: "Guarda una clave de recuperación" }),
    ).toBeVisible();
    await expect(block.getByRole("button", { name: "Agrega una huella" })).toBeVisible();
    await userEvent.click(block.getByRole("button", { name: "Agrega un email" }));
    await expect(args.onAddEmail).toHaveBeenCalledOnce();
    await expect(block.queryByText("Hecho")).toBeNull();
  },
};

/** The recovery key is saved: no count any more, a quiet list with step 1 "Hecho". */
export const OneOfTwo: Story = {
  name: "1 of 2",
  args: { options: { savedAt: "2026-10-20T10:00:00.000Z" } },
  play: async ({ canvasElement }) => {
    const block = await protect(canvasElement);
    await expect(block.getByText("Hecho")).toBeVisible();
    await expect(block.queryByText(/de 2$/)).toBeNull();
    await expect(
      block.queryByRole("button", { name: "Guarda una clave de recuperación" }),
    ).toBeNull();
    await expect(block.getByRole("button", { name: "Agrega una huella" })).toBeVisible();
  },
};

/** A passkey without a wrap (no PRF) signs in but does not count; the step says so. */
export const NoPrf: Story = {
  name: "no PRF",
  args: { options: { passkeys: [passkey(1)] } },
  play: async ({ canvasElement }) => {
    const block = await protect(canvasElement);
    await expect(
      await block.findByText(
        "Esta huella te deja entrar, pero no puede abrir tus datos. Agrega una clave de recuperación.",
      ),
    ).toBeVisible();
    await expect(block.getByText("0 de 2")).toBeVisible();
  },
};

/**
 * Ruling 16: step 1 asks for nothing (no current key, no touch); after the four characters the
 * key is committed and the checklist marks it saved.
 */
export const SaveRecoveryKey: Story = {
  name: '"Save a recovery key" shows the key setup without asking for a current key',
  play: async ({ canvasElement }) => {
    const { security, commit } = fakeOf();
    const block = await protect(canvasElement);
    await userEvent.click(block.getByRole("button", { name: "Guarda una clave de recuperación" }));
    await expect(await screen.findByText(KEY.split("-")[0] as string)).toBeVisible();
    await expect(screen.queryByLabelText("Clave de recuperación actual")).toBeNull();
    await expect(security.checkRecoveryKey).not.toHaveBeenCalled();
    await expect(security.evaluatePrf).not.toHaveBeenCalled();
    await typeBack(KEY);
    await userEvent.click(screen.getByRole("button", { name: "Continuar" }));
    await waitFor(() => expect(security.markRecoveryKeySaved).toHaveBeenCalledOnce());
    await expect(commit).toHaveBeenCalledOnce();
    const after = await protect(canvasElement);
    await expect(await after.findByText("Hecho")).toBeVisible();
    await expect(after.queryByText("0 de 2")).toBeNull();
  },
};

/** A passkey whose provider gives PRF gets its wrap: step 2 is done. */
export const AddPasskey: Story = {
  name: "add a passkey",
  play: async ({ canvasElement }) => {
    const { security } = fakeOf();
    const block = await protect(canvasElement);
    await userEvent.click(block.getByRole("button", { name: "Agrega una huella" }));
    await waitFor(() => expect(security.addPasskeyWrap).toHaveBeenCalledOnce());
    await expect(await block.findByText("Hecho")).toBeVisible();
    await expect(block.queryByRole("button", { name: "Agrega una huella" })).toBeNull();
  },
};

/** Without PRF the new passkey stays (it signs in), the step stays open with the no-PRF line. */
export const AddPasskeyWithoutPrf: Story = {
  name: "add a passkey without PRF",
  args: { options: { newPasskey: "no_prf" } },
  play: async ({ canvasElement }) => {
    const { security } = fakeOf();
    const block = await protect(canvasElement);
    await userEvent.click(block.getByRole("button", { name: "Agrega una huella" }));
    await expect(
      await block.findByText(/Esta huella te deja entrar, pero no puede abrir tus datos/),
    ).toBeVisible();
    await expect(security.addPasskeyWrap).not.toHaveBeenCalled();
    await expect(block.getByText("0 de 2")).toBeVisible();
  },
};

/**
 * The passkey was made with a PRF but its wrap could not be saved: the step says so and points to
 * Turn on in Passkeys, never the no-PRF line (the provider is not the cause).
 */
export const AddPasskeyKeepFails: Story = {
  name: "add a passkey whose wrap could not be saved",
  args: { options: { newPasskey: "keep_fails" } },
  play: async ({ canvasElement }) => {
    const { security } = fakeOf();
    const block = await protect(canvasElement);
    await userEvent.click(block.getByRole("button", { name: "Agrega una huella" }));
    await waitFor(() => expect(security.addPasskeyWrap).toHaveBeenCalledOnce());
    await expect(
      await block.findByText(
        "No pudimos vincular esta huella a tus datos. Inténtalo otra vez con «Activar» en «Entrar con tu huella».",
      ),
    ).toBeVisible();
    await expect(block.queryByText(/no puede abrir tus datos/)).toBeNull();
    await expect(block.getByText("0 de 2")).toBeVisible();
  },
};

/** No passkey step where this browser cannot make one. */
export const NoPasskeySupport: Story = {
  name: "no passkey support",
  args: { options: { supported: false } },
  play: async ({ canvasElement }) => {
    const block = await protect(canvasElement);
    await expect(
      block.getByRole("button", { name: "Guarda una clave de recuperación" }),
    ).toBeVisible();
    await expect(block.queryByRole("button", { name: "Agrega una huella" })).toBeNull();
  },
};

/** An account with an email never sees the block. */
export const WithAnEmail: Story = {
  name: "with an email",
  args: { anonymous: false },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await canvas.findByRole("region", { name: "Seguridad" });
    await expect(canvas.queryByRole("region", { name: "Protege tus datos" })).toBeNull();
  },
};
