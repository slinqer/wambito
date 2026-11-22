import type { Meta, StoryObj } from "@storybook/react-vite";
import { useState } from "react";
import { MemoryRouter, Route, Routes } from "react-router";
import { expect, fn, userEvent, waitFor, within } from "storybook/test";
import { expectTarget } from "../../../.storybook/story-utils.ts";
import { ApiProvider } from "../../api/ApiProvider.tsx";
import { Consent } from "./Consent.tsx";
import { type ConsentApi, ConsentError } from "./consent-api.ts";
import type { ConsentKeys, ConsentProblem, PublicClient } from "./consent-model.ts";

/** Ten minutes from the story's start, as Better Auth signs it. */
const EXP = Math.floor(Date.now() / 1000) + 600;

const query = (scope: string, exp = EXP) =>
  `?response_type=code&client_id=${encodeURIComponent("https://claude.ai/oauth/mcp-oauth-client-metadata")}` +
  `&redirect_uri=${encodeURIComponent("https://claude.ai/api/mcp/auth_callback")}` +
  `&scope=${encodeURIComponent(scope)}&state=st&exp=${exp}&sig=s1g`;

const FULL = query("finance:read finance:write offline_access");

const CLAUDE: PublicClient = { name: "Claude", icon: null, domain: "claude.ai" };

interface StageProps {
  search: string;
  guest: boolean;
  client: () => Promise<PublicClient>;
  decide: ConsentApi["decide"];
  putAssistantWrap: ConsentApi["putAssistantWrap"];
  revoke: ConsentApi["revoke"];
  go: (url: string) => void;
  /**
   * An encrypted account; `device`: this browser holds its vault; `passkeyWrap` (default true):
   * the account has one; `noPrfHere`: the last passkey touched here gave no PRF.
   */
  encrypted?: { device: boolean; passkeyWrap?: boolean; noPrfHere?: boolean };
}

/** A vault that opens one made-up data key, from whatever source it is asked. */
const storyKeys = ({
  device,
  passkeyWrap = true,
  noPrfHere = false,
}: NonNullable<StageProps["encrypted"]>): ConsentKeys => ({
  userId: "u_story",
  device,
  means: { passkeyWrap, noPrfHere },
  open: async (_source, fn) => {
    const dk = crypto.getRandomValues(new Uint8Array(32));
    try {
      return await fn(dk, 1);
    } finally {
      dk.fill(0);
    }
  },
  touchPasskey: async () => ({ credentialId: "Y3JlZA", prf: new Uint8Array(32).fill(1) }),
});

/** The consent screen at `/oauth/consent<search>`, with Better Auth and the page load stood in for. */
function ConsentStage({
  search,
  guest,
  client,
  decide,
  putAssistantWrap,
  revoke,
  go,
  encrypted,
}: StageProps) {
  const [api] = useState<ConsentApi>(() => ({
    client: () => client(),
    decide,
    putAssistantWrap,
    revoke,
  }));
  const [keys] = useState(() => (encrypted ? storyKeys(encrypted) : undefined));
  return (
    <MemoryRouter initialEntries={[`/oauth/consent${search}`]}>
      <ApiProvider fetch={async () => new Response(null, { status: 404 })}>
        <Routes>
          <Route
            path="/oauth/consent"
            element={
              <Consent
                api={api}
                guest={guest}
                go={go}
                passkeysSupported={() => true}
                {...(keys ? { keys } : {})}
              />
            }
          />
        </Routes>
      </ApiProvider>
    </MemoryRouter>
  );
}

const refuse = (problem: ConsentProblem) => async (): Promise<never> => {
  throw new ConsentError(problem);
};

const meta = {
  title: "Assistants/Consent",
  component: ConsentStage,
  args: {
    search: FULL,
    guest: false,
    client: fn(async () => CLAUDE),
    decide: fn<StageProps["decide"]>(async (accept) =>
      accept
        ? "https://claude.ai/api/mcp/auth_callback?code=c0de&state=st"
        : "https://claude.ai/api/mcp/auth_callback?error=access_denied&state=st",
    ),
    putAssistantWrap: fn<StageProps["putAssistantWrap"]>(async () => undefined),
    revoke: fn<StageProps["revoke"]>(async () => undefined),
    go: fn(),
  },
} satisfies Meta<typeof ConsentStage>;

export default meta;
type Story = StoryObj<typeof meta>;

type Canvas = ReturnType<typeof within>;

const title = (canvas: Canvas, name = "Claude quiere acceder a tus finanzas") =>
  canvas.findByRole("heading", { level: 1, name });

/**
 * Who asks, where it comes from (the domain its client_id lives on, in bold), and what it could
 * do, in plain words. The heading has the focus.
 */
export const Request: Story = {
  play: async ({ canvasElement, args }) => {
    const canvas = within(canvasElement);
    const heading = await title(canvas);
    await waitFor(() => expect(heading).toHaveFocus());
    await expect(canvas.getByText("Desde claude.ai")).toBeVisible();
    await expect(
      canvas.getByText("Revisa que sea el sitio de tu asistente. Si no lo reconoces, cancela."),
    ).toBeVisible();
    const permissions = within(canvas.getByRole("list"));
    await expect(permissions.getAllByRole("listitem").map((li) => li.textContent)).toEqual([
      "Ver tus movimientos y reportes",
      "Anotar, cambiar y borrar movimientos, presupuestos y categorías",
      "Seguir conectado hasta que lo desconectes",
    ]);
    await expectTarget(canvas.getByRole("button", { name: "Permitir" }));
    await expectTarget(canvas.getByRole("button", { name: "Cancelar" }));
    await expect(args.client).toHaveBeenCalledTimes(1);
    await expect(args.decide).not.toHaveBeenCalled();
  },
};

/** Read-only: one line, and in English by day (contrast is checked in both themes). */
export const ReadOnlyDayEnglish: Story = {
  args: {
    search: query("finance:read"),
    client: fn(async () => ({ ...CLAUDE, name: "ChatGPT", domain: "chatgpt.com" })),
  },
  globals: { theme: "day", locale: "en" },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await title(canvas, "ChatGPT wants to access your finances");
    await expect(canvas.getByText("From chatgpt.com")).toBeVisible();
    const permissions = within(canvas.getByRole("list"));
    await expect(permissions.getAllByRole("listitem").map((li) => li.textContent)).toEqual([
      "See your entries and reports",
    ]);
    await expect(canvas.getByRole("button", { name: "Allow" })).toBeVisible();
  },
};

/** No domain to show: it says so, in place of the domain. */
export const UnknownDomain: Story = {
  args: { client: fn(async () => ({ name: "MiAsistente", icon: null, domain: null })) },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await title(canvas, "MiAsistente quiere acceder a tus finanzas");
    await expect(
      canvas.getByText("No sabemos de qué sitio viene. Conéctalo solo si tú lo agregaste."),
    ).toBeVisible();
  },
};

/** Permitir posts accept: true with the page's signed query, then follows the returned URL. */
export const Allow: Story = {
  play: async ({ canvasElement, args }) => {
    const canvas = within(canvasElement);
    await title(canvas);
    const allow = canvas.getByRole("button", { name: "Permitir" });
    await userEvent.dblClick(allow);
    await waitFor(() =>
      expect(args.go).toHaveBeenCalledWith(
        "https://claude.ai/api/mcp/auth_callback?code=c0de&state=st",
      ),
    );
    // Two taps, one answer.
    await expect(args.decide).toHaveBeenCalledTimes(1);
    await expect(args.decide).toHaveBeenCalledWith(true, FULL.slice(1));
  },
};

/** Cancelar posts accept: false and goes back to the assistant with its refusal. */
export const Cancel: Story = {
  play: async ({ canvasElement, args }) => {
    const canvas = within(canvasElement);
    await title(canvas);
    await userEvent.click(canvas.getByRole("button", { name: "Cancelar" }));
    await waitFor(() =>
      expect(args.go).toHaveBeenCalledWith(
        "https://claude.ai/api/mcp/auth_callback?error=access_denied&state=st",
      ),
    );
    await expect(args.decide).toHaveBeenCalledWith(false, FULL.slice(1));
  },
};

/** A guest is asked to save their progress, and there is no Permitir; Cancelar still answers. */
export const Guest: Story = {
  args: { guest: true },
  play: async ({ canvasElement, args }) => {
    const canvas = within(canvasElement);
    await title(canvas);
    await expect(canvas.getByRole("region", { name: "Primero agrega un email" })).toBeVisible();
    await expect(canvas.queryByRole("button", { name: "Permitir" })).toBeNull();
    await userEvent.click(canvas.getByRole("button", { name: "Cancelar" }));
    await waitFor(() => expect(args.decide).toHaveBeenCalledWith(false, FULL.slice(1)));
  },
};

/** When the API says the session is a guest's after all, Permitir gives way to the same panel. */
export const GuestRefused: Story = {
  args: { decide: fn<StageProps["decide"]>(refuse("guest")) },
  play: async ({ canvasElement, args }) => {
    const canvas = within(canvasElement);
    await title(canvas);
    await userEvent.click(canvas.getByRole("button", { name: "Permitir" }));
    await expect(
      await canvas.findByRole("region", { name: "Primero agrega un email" }),
    ).toBeVisible();
    await expect(canvas.queryByRole("button", { name: "Permitir" })).toBeNull();
    await expect(args.go).not.toHaveBeenCalled();
  },
};

/** A link past its ten minutes says to start again from the assistant, without asking anything. */
export const ExpiredOnArrival: Story = {
  args: { search: query("finance:read", Math.floor(Date.now() / 1000) - 60) },
  play: async ({ canvasElement, args }) => {
    const canvas = within(canvasElement);
    const heading = await title(canvas, "Este enlace ya no sirve");
    await waitFor(() => expect(heading).toHaveFocus());
    await expect(canvas.queryByRole("button", { name: "Permitir" })).toBeNull();
    await expect(args.client).not.toHaveBeenCalled();
  },
};

/** A signature Better Auth refuses (it ran out while the page was open, or was changed). */
export const ExpiredOnAnswer: Story = {
  args: { decide: fn<StageProps["decide"]>(refuse("expired")) },
  play: async ({ canvasElement, args }) => {
    const canvas = within(canvasElement);
    await title(canvas);
    await userEvent.click(canvas.getByRole("button", { name: "Permitir" }));
    await title(canvas, "Este enlace ya no sirve");
    await expect(
      canvas.getByText(
        "Pasó mucho tiempo o el enlace cambió. Vuelve a tu asistente y empieza a conectar Wambito otra vez.",
      ),
    ).toBeVisible();
    await expect(args.go).not.toHaveBeenCalled();
  },
};

/** No signature at all: nothing to answer. */
export const Unsigned: Story = {
  args: { search: "?client_id=x&scope=finance%3Aread" },
  play: async ({ canvasElement }) => {
    await title(within(canvasElement), "Este enlace ya no sirve");
  },
};

/** No connection: it says so, and Permitir can be tapped again. */
export const Offline: Story = {
  args: { decide: fn<StageProps["decide"]>(refuse("network")) },
  play: async ({ canvasElement, args }) => {
    const canvas = within(canvasElement);
    await title(canvas);
    await userEvent.click(canvas.getByRole("button", { name: "Permitir" }));
    await expect(
      await canvas.findByText("Sin conexión. Revisa tu internet e inténtalo de nuevo."),
    ).toHaveAttribute("role", "alert");
    await expect(canvas.getByRole("button", { name: "Permitir" })).toBeEnabled();
    await expect(args.go).not.toHaveBeenCalled();
  },
};

/** The assistant could not be read: the error, and a retry. */
export const ClientFailed: Story = {
  args: { client: fn<StageProps["client"]>(refuse("generic")) },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await expect(
      await canvas.findByText("No pudimos completar la conexión. Inténtalo de nuevo."),
    ).toHaveAttribute("role", "alert");
    await expect(canvas.getByRole("button", { name: "Reintentar" })).toBeVisible();
  },
};

/**
 * An encrypted account whose vault is open in this browser: it says what connecting means, and
 * Permitir, with no touch, posts the consent with the assistant's secret, then saves its key.
 */
export const EncryptedVaultHere: Story = {
  args: { encrypted: { device: true } },
  play: async ({ canvasElement, args }) => {
    const canvas = within(canvasElement);
    await title(canvas);
    await expect(
      canvas.getByText(/Wambito abre tus datos en su servidor solo para responder a tu asistente/),
    ).toBeVisible();
    await userEvent.click(canvas.getByRole("button", { name: "Permitir" }));
    await waitFor(() =>
      expect(args.go).toHaveBeenCalledWith(
        "https://claude.ai/api/mcp/auth_callback?code=c0de&state=st",
      ),
    );
    await expect(args.decide).toHaveBeenCalledWith(
      true,
      FULL.slice(1),
      expect.stringMatching(/^[A-Za-z0-9_-]{43}$/),
    );
    await expect(args.putAssistantWrap).toHaveBeenCalledWith(
      expect.objectContaining({
        ref: "https://claude.ai/oauth/mcp-oauth-client-metadata",
        keyV: 1,
      }),
    );
    await expect(args.revoke).not.toHaveBeenCalled();
  },
};

/**
 * An encrypted account with nothing in this browser and a passkey wrap: Permitir asks for the
 * passkey first, the recovery key under "More options" (no pairing on this page).
 */
export const EncryptedUnlock: Story = {
  args: { encrypted: { device: false } },
  play: async ({ canvasElement, args }) => {
    const canvas = within(canvasElement);
    await title(canvas);
    await userEvent.click(canvas.getByRole("button", { name: "Permitir" }));
    await title(canvas, "Abre tus datos para conectarlo");
    await expect(canvas.getByRole("button", { name: "Abrir con mi huella" })).toBeVisible();
    await expect(canvas.queryByLabelText("Clave de recuperación")).toBeNull();
    await expect(canvas.queryByRole("button", { name: "Desde otro dispositivo" })).toBeNull();
    await userEvent.click(canvas.getByRole("button", { name: "Más opciones" }));
    await expect(canvas.getByLabelText("Clave de recuperación")).toBeVisible();
    await expect(args.decide).not.toHaveBeenCalled();
    await userEvent.click(canvas.getByRole("button", { name: "Abrir con mi huella" }));
    await waitFor(() => expect(args.go).toHaveBeenCalled());
    await expect(args.putAssistantWrap).toHaveBeenCalledTimes(1);
  },
};

/** No passkey wrap on the account: nothing else to offer here, so the recovery key leads alone. */
export const EncryptedUnlockKeyOnly: Story = {
  args: { encrypted: { device: false, passkeyWrap: false } },
  play: async ({ canvasElement, args }) => {
    const canvas = within(canvasElement);
    await title(canvas);
    await userEvent.click(canvas.getByRole("button", { name: "Permitir" }));
    await title(canvas, "Abre tus datos para conectarlo");
    await expect(canvas.getByLabelText("Clave de recuperación")).toBeVisible();
    await expect(canvas.queryByRole("button", { name: "Más opciones" })).toBeNull();
    await expect(canvas.queryByRole("button", { name: /huella/ })).toBeNull();
    await expect(args.decide).not.toHaveBeenCalled();
  },
};

/** The last passkey touched here gave no PRF: the recovery key and the line lead. */
export const EncryptedUnlockNoPrfHere: Story = {
  args: { encrypted: { device: false, noPrfHere: true } },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await title(canvas);
    await userEvent.click(canvas.getByRole("button", { name: "Permitir" }));
    await title(canvas, "Abre tus datos para conectarlo");
    await expect(canvas.getByLabelText("Clave de recuperación")).toBeVisible();
    await expect(
      canvas.getByText(
        "Tu huella te deja entrar, pero tu gestor de contraseñas no le permite abrir tus datos.",
      ),
    ).toBeVisible();
    await userEvent.click(canvas.getByRole("button", { name: "Más opciones" }));
    await expect(canvas.getByRole("button", { name: "Usar otra huella" })).toBeVisible();
  },
};

/**
 * Consented, but the key was not saved: it says so and does not go back to the assistant.
 * Reintentar revokes that consent and consents again with a new secret.
 */
export const WrapFailed: Story = {
  args: {
    encrypted: { device: true },
    putAssistantWrap: fn<StageProps["putAssistantWrap"]>(refuse("generic")),
  },
  play: async ({ canvasElement, args }) => {
    const canvas = within(canvasElement);
    await title(canvas);
    await userEvent.click(canvas.getByRole("button", { name: "Permitir" }));
    await expect(
      await canvas.findByText(
        "Se permitió, pero su clave no se guardó, así que todavía no puede leer nada.",
      ),
    ).toHaveAttribute("role", "alert");
    await expect(args.go).not.toHaveBeenCalled();
    await userEvent.click(canvas.getByRole("button", { name: "Reintentar" }));
    await waitFor(() => expect(args.putAssistantWrap).toHaveBeenCalledTimes(2));
    await expect(args.revoke).toHaveBeenCalledWith(
      "https://claude.ai/oauth/mcp-oauth-client-metadata",
    );
    const [first, second] = (args.decide as ReturnType<typeof fn>).mock.calls;
    await expect(second?.[2]).not.toBe(first?.[2]);
    await expect(args.go).not.toHaveBeenCalled();
  },
};

/**
 * Another account signed in on this browser meanwhile (the wrap PUT names this one: 409): it says
 * to reload, offers no retry, and revokes nothing (the cookie's account is someone else's).
 */
export const SessionChanged: Story = {
  args: {
    encrypted: { device: true },
    putAssistantWrap: fn<StageProps["putAssistantWrap"]>(refuse("session_changed")),
  },
  play: async ({ canvasElement, args }) => {
    const canvas = within(canvasElement);
    await title(canvas);
    await userEvent.click(canvas.getByRole("button", { name: "Permitir" }));
    await expect(
      await canvas.findByText(
        "Se inició sesión con otra cuenta en este navegador. Recarga la página.",
      ),
    ).toHaveAttribute("role", "alert");
    await expect(canvas.queryByRole("button", { name: "Reintentar" })).toBeNull();
    await expect(args.revoke).not.toHaveBeenCalled();
    await expect(args.go).not.toHaveBeenCalled();
  },
};
