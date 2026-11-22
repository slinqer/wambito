import type { Meta, StoryObj } from "@storybook/react-vite";
import { expect, fn, screen, userEvent, waitFor, within } from "storybook/test";
import { expectTarget } from "../../../.storybook/story-utils.ts";
import { SOUND_STORAGE_KEY } from "../../feedback/feedback.ts";
import { THEME_STORAGE_KEY } from "../../theme/theme-bootstrap.ts";
import { HomeStage, STORY_TODAY, storyPasskeys } from "../home/story-harness.tsx";
import { APP_VERSION, FEEDBACK_EMAIL } from "./feedback.ts";

/**
 * Settings (spec §2.7): language, theme, sound, time zone, currency (while it can still change),
 * passkeys, import, export, "Conecta tu asistente", and deleting the account after typing its email.
 */

interface Spies {
  onRequest(line: string, headers: Record<string, string>): void;
  onSave(filename: string, blob: Blob): void;
  signOut(): Promise<{ error: unknown }>;
  onCopy(text: string): Promise<void>;
}

const meta = {
  title: "Manage/Settings",
  args: {
    onRequest: fn(),
    onSave: fn(),
    signOut: fn(async () => ({ error: null })),
    onCopy: fn(async () => {}),
  },
  parameters: {
    viewport: {
      options: {
        phone: { name: "Phone", styles: { width: "390px", height: "844px" }, type: "mobile" },
        desktop: { name: "Desktop", styles: { width: "1280px", height: "800px" }, type: "desktop" },
      },
    },
  },
  globals: { viewport: { value: "phone", isRotated: false } },
} satisfies Meta<Spies>;

export default meta;
type Story = StoryObj<Spies>;
type Canvas = ReturnType<typeof within>;

const lines = (spy: Spies["onRequest"]) =>
  (spy as unknown as ReturnType<typeof fn>).mock.calls.map((call) => call[0] as string);
const writesTo = (spy: Spies["onRequest"], prefix: string) =>
  lines(spy).filter((line) => line.startsWith(prefix));

const title = (canvas: Canvas, name = "Ajustes") =>
  canvas.findByRole("heading", { level: 1, name });

const group = async (canvas: Canvas, name: string) =>
  within(await canvas.findByRole("group", { name }));

/** Waits until a toast saying `text` has fully faded in (so the a11y checks see it settled). */
const toastShown = (text: string | RegExp, role: "status" | "alert" = "status") =>
  waitFor(
    () => {
      const toast = screen.getByRole(role).querySelector<HTMLElement>(".lk-toast");
      expect(toast).toHaveTextContent(text);
      expect(toast && getComputedStyle(toast).opacity).toBe("1");
    },
    { timeout: 8000 },
  );

const dialogGone = () =>
  waitFor(() => expect(screen.queryByRole("dialog")).toBeNull(), { timeout: 8000 });

/** Opens the sheet a row leads to, by the row's name. */
const openRow = async (canvas: Canvas, name: string | RegExp) => {
  await userEvent.click(await canvas.findByRole("button", { name }));
  return within(await screen.findByRole("dialog"));
};

const stage = (args: Spies, extra: Partial<Parameters<typeof HomeStage>[0]> = {}) => (
  <HomeStage
    onRequest={args.onRequest}
    onSave={args.onSave}
    signOut={args.signOut}
    onCopy={args.onCopy}
    path="/app/settings/all"
    {...extra}
  />
);

/** Every section, each a region named by its heading, and who is signed in. */
export const Overview: Story = {
  render: (args) => stage(args),
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await expect(await title(canvas)).toBeVisible();
    await expect(canvas.getByText("Entraste como ana@example.com")).toBeVisible();
    await expect(canvas.getByRole("region", { name: "La dirección de Wambito" })).toBeVisible();
    for (const name of ["Apariencia", "Sonido y tacto", "Hora y moneda", "Entrar con tu huella"]) {
      await expect(canvas.getByRole("group", { name })).toBeVisible();
    }
    await expect(canvas.getByRole("button", { name: /^Idioma/ })).toHaveTextContent("Español");
    await expect(canvas.getByRole("button", { name: /^Tema/ })).toHaveTextContent("Noche");
    await expect(canvas.getByRole("switch", { name: "Sonido" })).toBeChecked();
    await expect(canvas.getByRole("link", { name: /^Importar movimientos/ })).toHaveAttribute(
      "href",
      "/app/import",
    );
    await expect(canvas.getByRole("button", { name: /^Descargar tus datos/ })).toBeVisible();
    await expect(canvas.getByRole("button", { name: /^Comentarios e ideas/ })).toBeVisible();
    await expectTarget(canvas.getByRole("button", { name: /^Eliminar tu cuenta/ }));
  },
};

/**
 * Deleting the account: the button stays off until the email is typed exactly (case and spaces
 * around it don't matter); then the account goes, the session ends and the landing shows.
 */
export const DeleteNeedsExactEmail: Story = {
  render: (args) => stage(args),
  play: async ({ canvasElement, args }) => {
    const canvas = within(canvasElement);
    await title(canvas);
    await userEvent.click(canvas.getByRole("button", { name: /^Eliminar tu cuenta/ }));
    const sheet = within(await screen.findByRole("dialog", { name: "¿Eliminar tu cuenta?" }));
    const confirm = sheet.getByRole("button", { name: "Sí, eliminar mi cuenta" });
    const email = sheet.getByRole("textbox", { name: "Escribe tu correo para confirmar" });
    await expect(confirm).toBeDisabled();
    await userEvent.type(email, "ana@example.co");
    await expect(confirm).toBeDisabled();
    await userEvent.clear(email);
    await userEvent.type(email, "otra@example.com");
    await expect(confirm).toBeDisabled();
    await userEvent.clear(email);
    await userEvent.type(email, "  ANA@Example.com ");
    await expect(confirm).toBeEnabled();
    await expect(writesTo(args.onRequest, "DELETE /api/v1/me")).toHaveLength(0);

    await userEvent.click(confirm);
    await expect(await canvas.findByText("Landing (stand-in)")).toBeVisible();
    await expect(writesTo(args.onRequest, "DELETE /api/v1/me")).toHaveLength(1);
    await expect(args.signOut).toHaveBeenCalledTimes(1);
  },
};

/**
 * Enter in the email field deletes only once the email matches, and a burst of Enters and taps
 * sends one DELETE.
 */
export const DeleteWithEnter: Story = {
  render: (args) => stage(args),
  play: async ({ canvasElement, args }) => {
    const canvas = within(canvasElement);
    await title(canvas);
    await userEvent.click(canvas.getByRole("button", { name: /^Eliminar tu cuenta/ }));
    const sheet = within(await screen.findByRole("dialog", { name: "¿Eliminar tu cuenta?" }));
    const email = sheet.getByRole("textbox", { name: "Escribe tu correo para confirmar" });
    await userEvent.type(email, "ana@example.co{Enter}");
    await expect(writesTo(args.onRequest, "DELETE /api/v1/me")).toHaveLength(0);
    await expect(sheet.getByRole("button", { name: "Sí, eliminar mi cuenta" })).toBeDisabled();

    await userEvent.type(email, "m{Enter}{Enter}");
    await userEvent.click(
      sheet.getByRole("button", { name: /Sí, eliminar mi cuenta|Eliminando…/ }),
    );
    await expect(await canvas.findByText("Landing (stand-in)")).toBeVisible();
    await expect(writesTo(args.onRequest, "DELETE /api/v1/me")).toHaveLength(1);
    await expect(args.signOut).toHaveBeenCalledTimes(1);
  },
};

/** Before deleting, the data can be downloaded; a failed delete says so and keeps the account. */
export const DeleteOffersExportAndSurvivesFailure: Story = {
  render: (args) => stage(args, { failDelete: true }),
  play: async ({ canvasElement, args }) => {
    const canvas = within(canvasElement);
    await title(canvas);
    await userEvent.click(canvas.getByRole("button", { name: /^Eliminar tu cuenta/ }));
    const dialog = await screen.findByRole("dialog", { name: "¿Eliminar tu cuenta?" });
    const sheet = within(dialog);
    await userEvent.click(sheet.getByRole("button", { name: "Descarga tus datos antes" }));
    await waitFor(() => expect(args.onSave).toHaveBeenCalledTimes(1));
    await expect((args.onSave as ReturnType<typeof fn>).mock.calls[0]?.[0]).toBe(
      `wambito-export-${STORY_TODAY}.json`,
    );

    await userEvent.type(
      sheet.getByRole("textbox", { name: "Escribe tu correo para confirmar" }),
      "ana@example.com",
    );
    await userEvent.click(sheet.getByRole("button", { name: "Sí, eliminar mi cuenta" }));
    await expect(
      await sheet.findByText(
        "Tuvimos un problema de nuestro lado. Inténtalo de nuevo en un momento.",
      ),
    ).toHaveAttribute("role", "alert");
    await expect(args.signOut).not.toHaveBeenCalled();
    await expect(dialog).toBeVisible();
    await expect(canvas.queryByText("Landing (stand-in)")).toBeNull();
  },
};

/** Switching language re-renders every label at once and saves it on the profile. */
export const SwitchLanguage: Story = {
  render: (args) => stage(args),
  play: async ({ canvasElement, args }) => {
    const canvas = within(canvasElement);
    await title(canvas);
    const sheet = await openRow(canvas, /^Idioma/);
    await userEvent.click(sheet.getByRole("radio", { name: "English" }));
    await expect(await title(canvas, "Settings")).toBeVisible();
    await dialogGone();
    await expect(canvas.getByRole("button", { name: /^Language/ })).toHaveTextContent("English");
    await expect(canvas.getByRole("switch", { name: "Sound" })).toBeVisible();
    await expect(document.documentElement.lang).toBe("en");
    await waitFor(() =>
      expect(writesTo(args.onRequest, "PATCH /api/v1/me")).toEqual([
        'PATCH /api/v1/me {"locale":"en"}',
      ]),
    );
    // Home speaks it too.
    await userEvent.click(canvas.getByRole("link", { name: "Back to home" }));
    await expect(await canvas.findByRole("region", { name: "Left this month" })).toBeVisible();
  },
};

/** The theme: auto, night or day, applied at once and kept on this device. */
export const Theme: Story = {
  render: (args) => stage(args),
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await title(canvas);
    let sheet = await openRow(canvas, /^Tema/);
    await expect(sheet.getByText("Automático sigue el modo de tu teléfono.")).toBeVisible();
    await userEvent.click(sheet.getByRole("radio", { name: "Día" }));
    await waitFor(() => expect(document.documentElement.dataset.theme).toBe("day"));
    await expect(localStorage.getItem(THEME_STORAGE_KEY)).toBe("day");
    await dialogGone();
    await expect(canvas.getByRole("button", { name: /^Tema/ })).toHaveTextContent("Día");
    sheet = await openRow(canvas, /^Tema/);
    await userEvent.click(sheet.getByRole("radio", { name: "Automático" }));
    await expect(localStorage.getItem(THEME_STORAGE_KEY)).toBe("auto");
    await dialogGone();
    sheet = await openRow(canvas, /^Tema/);
    await userEvent.click(sheet.getByRole("radio", { name: "Noche" }));
    await waitFor(() => expect(document.documentElement.dataset.theme).toBe("night"));
  },
};

/** Sound on and off: off stores `wambito.sound = "off"`, on removes it. */
export const Sound: Story = {
  render: (args) => stage(args),
  play: async ({ canvasElement }) => {
    localStorage.removeItem(SOUND_STORAGE_KEY);
    const canvas = within(canvasElement);
    await title(canvas);
    const sound = canvas.getByRole("switch", { name: "Sonido" });
    await expectTarget(sound);
    await userEvent.click(sound);
    await expect(sound).not.toBeChecked();
    await expect(localStorage.getItem(SOUND_STORAGE_KEY)).toBe("off");
    await userEvent.click(sound);
    await expect(sound).toBeChecked();
    await expect(localStorage.getItem(SOUND_STORAGE_KEY)).toBeNull();
  },
};

/** The time zone: searched by city (accents don't matter), saved on the profile. */
export const TimeZone: Story = {
  render: (args) => stage(args),
  play: async ({ canvasElement, args }) => {
    const canvas = within(canvasElement);
    await title(canvas);
    const time = await group(canvas, "Hora y moneda");
    await expect(time.getByText("Madrid")).toBeVisible();
    await userEvent.click(time.getByRole("button", { name: /^Zona horaria/ }));
    const sheet = within(await screen.findByRole("dialog", { name: "Elige tu zona horaria" }));
    await expect(sheet.getByText("Con ella sabemos cuándo empieza tu día y tu mes.")).toBeVisible();
    await userEvent.type(
      sheet.getByRole("searchbox", { name: "Busca tu ciudad o país" }),
      "bogotá",
    );
    await userEvent.click(await sheet.findByRole("button", { name: /^Bogota/ }));
    await dialogGone();
    await waitFor(() =>
      expect(writesTo(args.onRequest, "PATCH /api/v1/me")).toEqual([
        'PATCH /api/v1/me {"timezone":"America/Bogota"}',
      ]),
    );
    await toastShown("Listo: ahora usamos la hora de Bogota.");
    await expect(time.getByText("Bogota")).toBeVisible();
  },
};

/** A country finds its zones too, by Intl's name for them or a known alias. */
export const TimeZoneByCountry: Story = {
  render: (args) => stage(args),
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await title(canvas);
    await userEvent.click(canvas.getByRole("button", { name: /^Zona horaria/ }));
    const sheet = within(await screen.findByRole("dialog", { name: "Elige tu zona horaria" }));
    const search = sheet.getByRole("searchbox", { name: "Busca tu ciudad o país" });
    await userEvent.type(search, "colombia");
    await expect(await sheet.findByRole("button", { name: /^Bogota/ })).toBeVisible();
    await userEvent.clear(search);
    await userEvent.type(search, "españa");
    await expect(await sheet.findByRole("button", { name: /^Madrid/ })).toBeVisible();
  },
};

/** A search that finds nothing says so. */
export const TimeZoneNoMatch: Story = {
  render: (args) => stage(args),
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await title(canvas);
    await userEvent.click(canvas.getByRole("button", { name: /^Zona horaria/ }));
    const sheet = within(await screen.findByRole("dialog", { name: "Elige tu zona horaria" }));
    await userEvent.type(sheet.getByRole("searchbox", { name: "Busca tu ciudad o país" }), "zzzz");
    await expect(await sheet.findByText(/No encontramos «zzzz»/)).toBeVisible();
  },
};

/** An empty account can still change its currency (with an example of how amounts look). */
export const CurrencyOpen: Story = {
  render: (args) => stage(args, { data: "empty", noRecurrences: true }),
  play: async ({ canvasElement, args }) => {
    const canvas = within(canvasElement);
    await title(canvas);
    const time = await group(canvas, "Hora y moneda");
    await expect(time.getByRole("button", { name: /^Moneda/ })).toHaveTextContent("EUR");
    const sheet = await openRow(canvas, /^Moneda/);
    const euro = await sheet.findByRole("radio", { name: /Euro/ });
    await expect(euro).toBeChecked();
    await expect(euro).toBeEnabled();
    const peso = sheet.getByRole("radio", { name: /Peso colombiano/ });
    await expect(peso).toHaveAccessibleName(/\$50\.000 \(50 lukas\)/);
    await userEvent.click(peso);
    await waitFor(() =>
      expect(writesTo(args.onRequest, "PATCH /api/v1/me")).toEqual([
        'PATCH /api/v1/me {"currency":"COP"}',
      ]),
    );
    await toastShown("Listo: tu moneda ahora es COP.");
    await dialogGone();
    await expect(time.getByRole("button", { name: /^Moneda/ })).toHaveTextContent("COP");
  },
};

/** With transactions there is nothing to choose: a short line says why. */
export const CurrencyLocked: Story = {
  render: (args) => stage(args),
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await title(canvas);
    await canvas.findByRole("group", { name: "Hora y moneda" });
    const sheet = await openRow(canvas, /^Moneda/);
    await expect(
      await sheet.findByText(
        "Tu moneda es EUR. Ya tienes movimientos o recurrentes, así que se queda así.",
        {},
      ),
    ).toBeVisible();
    await expect(sheet.queryByRole("radio", { name: /Peso colombiano/ })).toBeNull();
  },
};

/**
 * The server decides: an account that looks empty here (only deleted transactions left) gets a
 * 409, and the choice turns into the same short line.
 */
export const CurrencyLockedByServer: Story = {
  render: (args) => stage(args, { data: "empty", noRecurrences: true, currencyLocked: true }),
  play: async ({ canvasElement, args }) => {
    const canvas = within(canvasElement);
    await title(canvas);
    const sheet = await openRow(canvas, /^Moneda/);
    await userEvent.click(await sheet.findByRole("radio", { name: /Dólar estadounidense/ }));
    await expect(
      await sheet.findByText(
        "Tu moneda es EUR. Ya tienes movimientos o recurrentes, así que se queda así.",
        {},
      ),
    ).toBeVisible();
    await expect(sheet.queryByRole("radio")).toBeNull();
    await expect(writesTo(args.onRequest, "PATCH /api/v1/me")).toHaveLength(1);
  },
};

/** Passkeys: listed, one added (the browser asks), one deleted after asking. */
export const Passkeys: Story = {
  render: (args) =>
    stage(args, {
      passkeys: storyPasskeys({
        initial: [
          {
            id: "pk-1",
            credentialId: "cred-1",
            name: null,
            createdAt: "2026-10-02T09:00:00.000Z",
            synced: true,
          },
        ],
      }),
    }),
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await title(canvas);
    const keys = await group(canvas, "Entrar con tu huella");
    await expect(await keys.findByText("Desde el 2 oct 2026 · sincronizada")).toBeVisible();
    await userEvent.click(keys.getByRole("button", { name: "Agregar una huella" }));
    await toastShown("Listo: ya puedes entrar con tu huella.");
    await waitFor(() =>
      expect(keys.getAllByRole("button", { name: /^Eliminar / })).toHaveLength(2),
    );

    await userEvent.click(
      keys.getByRole("button", { name: "Eliminar la huella creada el 2 oct 2026" }),
    );
    const sheet = within(await screen.findByRole("dialog", { name: "¿Eliminar esta huella?" }));
    await userEvent.click(sheet.getByRole("button", { name: "Sí, eliminar" }));
    await dialogGone();
    await waitFor(() =>
      expect(keys.getAllByRole("button", { name: /^Eliminar / })).toHaveLength(1),
    );
    await toastShown("Eliminamos la huella.");
  },
};

/** No passkeys yet, in a browser that can't make one: it says so, and email keeps working. */
export const PasskeysUnsupported: Story = {
  render: (args) => stage(args, { passkeys: storyPasskeys({ supported: false }) }),
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await title(canvas);
    const keys = await group(canvas, "Entrar con tu huella");
    await expect(await keys.findByText(/Aún no tienes ninguna/)).toBeVisible();
    await expect(
      keys.getByText("Este navegador no permite crear huellas. Sigue entrando con tu correo."),
    ).toBeVisible();
    await expect(keys.queryByRole("button", { name: "Agregar una huella" })).toBeNull();
  },
};

/** Export: JSON and CSV, each downloaded under the server's file name. */
export const Export: Story = {
  render: (args) => stage(args),
  play: async ({ canvasElement, args }) => {
    const canvas = within(canvasElement);
    await title(canvas);
    const data = await openRow(canvas, /^Descargar tus datos/);
    await expect(data.getByText(/Todo en JSON, o tus movimientos en CSV/)).toBeVisible();
    await userEvent.click(data.getByRole("button", { name: "Descargar CSV" }));
    await waitFor(() => expect(args.onSave).toHaveBeenCalledTimes(1));
    const [filename, blob] = (args.onSave as ReturnType<typeof fn>).mock.calls[0] as [string, Blob];
    await expect(filename).toBe(`wambito-export-${STORY_TODAY}.csv`);
    await expect(await blob.text()).toMatch(/^date,name,amount/);
    await dialogGone();
    const again = await openRow(canvas, /^Descargar tus datos/);
    await userEvent.click(again.getByRole("button", { name: "Descargar JSON" }));
    await waitFor(() => expect(args.onSave).toHaveBeenCalledTimes(2));
    await expect((args.onSave as ReturnType<typeof fn>).mock.calls[1]?.[0]).toBe(
      `wambito-export-${STORY_TODAY}.json`,
    );
  },
};

/** A failed export stays on the page and says why. */
export const ExportFails: Story = {
  render: (args) => stage(args, { failExport: true }),
  play: async ({ canvasElement, args }) => {
    const canvas = within(canvasElement);
    await title(canvas);
    const sheet = await openRow(canvas, /^Descargar tus datos/);
    await userEvent.click(sheet.getByRole("button", { name: "Descargar JSON" }));
    await toastShown(/Tuvimos un problema de nuestro lado/, "alert");
    await expect(args.onSave).not.toHaveBeenCalled();
    await expect(await title(canvas)).toBeVisible();
  },
};

/** The avatar menu leads here. */
export const FromAvatarMenu: Story = {
  render: (args) => <HomeStage onRequest={args.onRequest} />,
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await userEvent.click(await canvas.findByRole("button", { name: "Tu cuenta" }));
    const menu = within(canvasElement.querySelector(".lk-menu") as HTMLElement);
    const link = menu.getByRole("link", { name: "Ajustes" });
    await expect(link).toHaveAttribute("href", "/app/settings");
    await expectTarget(link);
    await userEvent.click(link);
    await expect(await title(canvas)).toBeVisible();
  },
};

/** Wide screens: the sidebar's Ajustes is a link, and the current page. */
export const Desktop: Story = {
  globals: { viewport: { value: "desktop", isRotated: false } },
  render: (args) => stage(args),
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await title(canvas);
    const nav = within(canvas.getByRole("navigation", { name: "Navegación principal" }));
    const link = nav.getByRole("link", { name: "Ajustes" });
    await expect(link).toHaveAttribute("aria-current", "page");
    await expect(link).not.toHaveTextContent("Pronto");
  },
};

/** Day theme, for the a11y checks (contrast) on every part. */
export const Day: Story = {
  globals: { theme: "day" },
  render: (args) => stage(args, { data: "empty", noRecurrences: true }),
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await title(canvas);
    await expect(await canvas.findByRole("button", { name: /^Moneda/ })).toHaveTextContent("EUR");
  },
};

/** In English. */
export const English: Story = {
  globals: { locale: "en" },
  render: (args) => stage(args),
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await title(canvas, "Settings");
    await expect(canvas.getByRole("button", { name: /^Language/ })).toHaveTextContent("English");
    await expect(canvas.getByRole("button", { name: /^Delete your account/ })).toBeVisible();
  },
};

/**
 * Comments and ideas: a link that opens the email app with a message to the founder, its subject
 * in the person's language and its body only the version and the language.
 */
export const Feedback: Story = {
  render: (args) => stage(args),
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await title(canvas);
    const card = await openRow(canvas, /^Comentarios e ideas/);
    await expect(card.getByText(/¿Algo no funciona/)).toBeVisible();
    const link = card.getByRole("link", { name: "Escribirnos" });
    await expect(link).toHaveAttribute(
      "href",
      `mailto:${FEEDBACK_EMAIL}?subject=Wambito%3A%20comentarios&body=%0A%0AVersi%C3%B3n%20de%20Wambito%3A%20${encodeURIComponent(APP_VERSION)}%0AIdioma%3A%20es`,
    );
    await expectTarget(link);
    await expect(
      card.getByText(`Si no se abre tu correo, escribe a ${FEEDBACK_EMAIL}.`),
    ).toBeVisible();
  },
};

/** The same in English: the subject and the body speak it. */
export const FeedbackEnglish: Story = {
  globals: { locale: "en" },
  render: (args) => stage(args),
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await title(canvas, "Settings");
    const card = await openRow(canvas, /^Feedback and ideas/);
    await expect(card.getByRole("link", { name: "Write to us" })).toHaveAttribute(
      "href",
      `mailto:${FEEDBACK_EMAIL}?subject=Wambito%3A%20feedback&body=%0A%0AWambito%20version%3A%20${encodeURIComponent(APP_VERSION)}%0ALanguage%3A%20en`,
    );
  },
};
