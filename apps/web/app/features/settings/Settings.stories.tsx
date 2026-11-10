import type { Meta, StoryObj } from "@storybook/react-vite";
import { expect, fn, screen, userEvent, waitFor, within } from "storybook/test";
import { expectTarget } from "../../../.storybook/story-utils.ts";
import { SOUND_STORAGE_KEY } from "../../feedback/feedback.ts";
import { THEME_STORAGE_KEY } from "../../theme/theme-bootstrap.ts";
import type { Assistant } from "../assistants/queries.ts";
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

const region = async (canvas: Canvas, name: string) =>
  within(await canvas.findByRole("region", { name }));

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

const stage = (args: Spies, extra: Partial<Parameters<typeof HomeStage>[0]> = {}) => (
  <HomeStage
    onRequest={args.onRequest}
    onSave={args.onSave}
    signOut={args.signOut}
    onCopy={args.onCopy}
    path="/app/settings"
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
    for (const name of [
      "Preferencias",
      "Hora y moneda",
      "Entrar con tu huella",
      "Tus datos",
      "Conecta tu asistente",
      "Comentarios e ideas",
      "Eliminar tu cuenta",
    ]) {
      await expect(canvas.getByRole("region", { name })).toBeVisible();
    }
    await expect(canvas.getByRole("radio", { name: "Español" })).toBeChecked();
    await expect(canvas.getByRole("radio", { name: "Noche" })).toBeChecked();
    await expect(canvas.getByRole("switch", { name: "Sonidos" })).toBeChecked();
    await expect(canvas.getByRole("link", { name: "Importar desde Budge" })).toHaveAttribute(
      "href",
      "/app/import",
    );
    await expectTarget(canvas.getByRole("button", { name: "Eliminar mi cuenta" }));
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
    await userEvent.click(canvas.getByRole("button", { name: "Eliminar mi cuenta" }));
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
    await userEvent.click(canvas.getByRole("button", { name: "Eliminar mi cuenta" }));
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
    await userEvent.click(canvas.getByRole("button", { name: "Eliminar mi cuenta" }));
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
    await expect(canvas.getByRole("group", { name: "Idioma" })).toBeVisible();
    await userEvent.click(canvas.getByRole("radio", { name: "English" }));
    await expect(await title(canvas, "Settings")).toBeVisible();
    await expect(canvas.getByRole("group", { name: "Language" })).toBeVisible();
    await expect(canvas.getByRole("radio", { name: "English" })).toBeChecked();
    await expect(canvas.getByRole("switch", { name: "Sounds" })).toBeVisible();
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
    await userEvent.click(canvas.getByRole("radio", { name: "Día" }));
    await waitFor(() => expect(document.documentElement.dataset.theme).toBe("day"));
    await expect(localStorage.getItem(THEME_STORAGE_KEY)).toBe("day");
    await userEvent.click(canvas.getByRole("radio", { name: "Automático" }));
    await expect(localStorage.getItem(THEME_STORAGE_KEY)).toBe("auto");
    await userEvent.click(canvas.getByRole("radio", { name: "Noche" }));
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
    const sound = canvas.getByRole("switch", { name: "Sonidos" });
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
    const time = await region(canvas, "Hora y moneda");
    await expect(time.getByText("Madrid")).toBeVisible();
    await userEvent.click(time.getByRole("button", { name: "Cambiar zona horaria" }));
    const sheet = within(await screen.findByRole("dialog", { name: "Elige tu zona horaria" }));
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
    await userEvent.click(canvas.getByRole("button", { name: "Cambiar zona horaria" }));
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
    await userEvent.click(canvas.getByRole("button", { name: "Cambiar zona horaria" }));
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
    const time = await region(canvas, "Hora y moneda");
    const euro = await time.findByRole("radio", { name: /Euro/ });
    await expect(euro).toBeChecked();
    await expect(euro).toBeEnabled();
    const peso = time.getByRole("radio", { name: /Peso colombiano/ });
    await expect(peso).toHaveAccessibleName(/\$50\.000 \(50 lukas\)/);
    await userEvent.click(peso);
    await waitFor(() =>
      expect(writesTo(args.onRequest, "PATCH /api/v1/me")).toEqual([
        'PATCH /api/v1/me {"currency":"COP"}',
      ]),
    );
    await toastShown("Listo: tu moneda ahora es COP.");
    await expect(peso).toBeChecked();
  },
};

/** With transactions there is nothing to choose: a short line says why. */
export const CurrencyLocked: Story = {
  render: (args) => stage(args),
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await title(canvas);
    const time = await region(canvas, "Hora y moneda");
    await expect(
      await time.findByText(
        "Tu moneda es EUR. Ya tienes movimientos o recurrentes, así que se queda así.",
        {},
      ),
    ).toBeVisible();
    await expect(time.queryByRole("radio", { name: /Peso colombiano/ })).toBeNull();
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
    const time = await region(canvas, "Hora y moneda");
    await userEvent.click(await time.findByRole("radio", { name: /Dólar estadounidense/ }));
    await expect(
      await time.findByText(
        "Tu moneda es EUR. Ya tienes movimientos o recurrentes, así que se queda así.",
        {},
      ),
    ).toBeVisible();
    await expect(time.queryByRole("radio")).toBeNull();
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
    const keys = await region(canvas, "Entrar con tu huella");
    await expect(await keys.findByText("Creada el 2 oct 2026")).toBeVisible();
    await userEvent.click(keys.getByRole("button", { name: "Agregar una huella" }));
    await toastShown("Listo: ya puedes entrar con tu huella.");
    await waitFor(() => expect(keys.getAllByRole("listitem")).toHaveLength(2));

    await userEvent.click(
      keys.getByRole("button", { name: "Eliminar la huella creada el 2 oct 2026" }),
    );
    const sheet = within(await screen.findByRole("dialog", { name: "¿Eliminar esta huella?" }));
    await userEvent.click(sheet.getByRole("button", { name: "Sí, eliminar" }));
    await dialogGone();
    await waitFor(() => expect(keys.getAllByRole("listitem")).toHaveLength(1));
    await toastShown("Eliminamos la huella.");
  },
};

/** No passkeys yet, in a browser that can't make one: it says so, and email keeps working. */
export const PasskeysUnsupported: Story = {
  render: (args) => stage(args, { passkeys: storyPasskeys({ supported: false }) }),
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await title(canvas);
    const keys = await region(canvas, "Entrar con tu huella");
    await expect(
      await keys.findByText("Aún no tienes ninguna: entras con el código de tu correo."),
    ).toBeVisible();
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
    const data = await region(canvas, "Tus datos");
    await userEvent.click(data.getByRole("button", { name: "Descargar CSV" }));
    await waitFor(() => expect(args.onSave).toHaveBeenCalledTimes(1));
    const [filename, blob] = (args.onSave as ReturnType<typeof fn>).mock.calls[0] as [string, Blob];
    await expect(filename).toBe(`wambito-export-${STORY_TODAY}.csv`);
    await expect(await blob.text()).toMatch(/^date,name,amount/);
    await userEvent.click(data.getByRole("button", { name: "Descargar JSON" }));
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
    await userEvent.click(canvas.getByRole("button", { name: "Descargar JSON" }));
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
    await expect(await canvas.findByRole("radio", { name: /Euro/ })).toBeChecked();
  },
};

/** In English. */
export const English: Story = {
  globals: { locale: "en" },
  render: (args) => stage(args),
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await title(canvas, "Settings");
    await expect(canvas.getByRole("radio", { name: "English" })).toBeChecked();
    await expect(canvas.getByRole("button", { name: "Delete my account" })).toBeVisible();
  },
};

/**
 * Where the page stops so a card below the fold fills the phone's viewport: the card starts this
 * many px under the top of it, or as near as the page's end lets it (the same rule as Insights'
 * scrolled stories). The app's test scrolls to the same place.
 */
const SCROLL_GAP = 16;

async function scrollTo(card: HTMLElement) {
  window.scrollTo(0, card.getBoundingClientRect().top + window.scrollY - SCROLL_GAP);
  await waitFor(() => expect(window.scrollY).toBeGreaterThan(0));
}

/** The page as the phone app draws it (docs/mobile/parity.md): every card, from the top. */
export const AppSections: Story = {
  render: (args) => stage(args),
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await title(canvas);
    await expect(canvas.getByRole("switch", { name: "Sonidos" })).toBeChecked();
  },
};

/** The same by day and in English. */
export const AppSectionsDayEnglish: Story = {
  globals: { theme: "day", locale: "en" },
  render: (args) => stage(args),
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await title(canvas, "Settings");
    await expect(canvas.getByRole("switch", { name: "Sounds" })).toBeChecked();
  },
};

/** The same page at night in Italian and European Portuguese: the longer words of its rows. */
export const AppSectionsItalian: Story = {
  globals: { theme: "night", locale: "it" },
  render: (args) => stage(args),
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await title(canvas, "Impostazioni");
    await expect(canvas.getByRole("switch", { name: "Suoni" })).toBeChecked();
  },
};

export const AppSectionsPortuguese: Story = {
  globals: { theme: "night", locale: "pt" },
  render: (args) => stage(args),
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await title(canvas, "Definições");
    await expect(canvas.getByRole("switch", { name: "Sons" })).toBeChecked();
  },
};

/** Sounds turned off with a tap: the switch is off, and the keyboard's ring is on it. */
export const AppSectionsSoundOff: Story = {
  render: (args) => stage(args),
  beforeEach: () => {
    localStorage.removeItem(SOUND_STORAGE_KEY);
    return () => localStorage.removeItem(SOUND_STORAGE_KEY);
  },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await title(canvas);
    const sound = canvas.getByRole("switch", { name: "Sonidos" });
    await userEvent.click(sound);
    await expect(sound).not.toBeChecked();
  },
};

/** The currency still open (an empty account), its options scrolled to the top of the picture. */
export const AppSectionsCurrencyOpen: Story = {
  render: (args) => stage(args, { data: "empty", noRecurrences: true }),
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await title(canvas);
    const time = await region(canvas, "Hora y moneda");
    await time.findByRole("radio", { name: /Euro/ });
    await canvas.findByText("Aún no tienes ninguna: entras con el código de tu correo.");
    // The currency's own options, not the whole card, fill the top of the picture.
    await scrollTo(time.getByRole("radio", { name: /Euro/ }).closest("fieldset") as HTMLElement);
  },
};

/** The passkeys listed (one named, one synced), scrolled into view. */
export const AppSectionsPasskeys: Story = {
  render: (args) =>
    stage(args, {
      data: "empty",
      noRecurrences: true,
      passkeys: storyPasskeys({
        initial: [
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
        ],
      }),
    }),
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await title(canvas);
    const keys = await region(canvas, "Entrar con tu huella");
    await keys.findByText("Creada el 2 oct 2026");
    await scrollTo(canvas.getByRole("region", { name: "Entrar con tu huella" }));
  },
};

/** "Tus datos" (import and export) near the foot of the page, scrolled into view. */
export const AppSectionsData: Story = {
  render: (args) => stage(args, { data: "empty", noRecurrences: true }),
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await title(canvas);
    // The passkeys' list has loaded: the page is as tall as it will be.
    await canvas.findByText("Aún no tienes ninguna: entras con el código de tu correo.");
    await scrollTo(canvas.getByRole("region", { name: "Tus datos" }));
  },
};

/** The time zone sheet, open, after searching a country. */
export const TimeZoneSheetOpen: Story = {
  render: (args) => stage(args),
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await title(canvas);
    await userEvent.click(canvas.getByRole("button", { name: "Cambiar zona horaria" }));
    const sheet = within(await screen.findByRole("dialog", { name: "Elige tu zona horaria" }));
    await userEvent.type(
      sheet.getByRole("searchbox", { name: "Busca tu ciudad o país" }),
      "colombia",
    );
    await expect(await sheet.findByRole("button", { name: /^Bogota/ })).toBeVisible();
  },
};

/** The zone in use among the results: it says "Actual". */
export const TimeZoneSheetCurrent: Story = {
  render: (args) => stage(args),
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await title(canvas);
    await userEvent.click(canvas.getByRole("button", { name: "Cambiar zona horaria" }));
    const sheet = within(await screen.findByRole("dialog", { name: "Elige tu zona horaria" }));
    await userEvent.type(
      sheet.getByRole("searchbox", { name: "Busca tu ciudad o país" }),
      "madrid",
    );
    await expect(await sheet.findByText("Actual")).toBeVisible();
  },
};

/** The question before deleting a passkey, open. */
export const PasskeyRemoveSheetOpen: Story = {
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
    const keys = await region(canvas, "Entrar con tu huella");
    await userEvent.click(
      await keys.findByRole("button", { name: "Eliminar la huella creada el 2 oct 2026" }),
    );
    await expect(
      await screen.findByRole("dialog", { name: "¿Eliminar esta huella?" }),
    ).toBeVisible();
  },
};

/** The card that deletes the account, at the foot of the page, scrolled into view. */
export const AppSectionsDelete: Story = {
  render: (args) => stage(args, { data: "empty", noRecurrences: true }),
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await title(canvas);
    // The passkeys' list has loaded: the page is as tall as it will be.
    await canvas.findByText("Aún no tienes ninguna: entras con el código de tu correo.");
    await scrollTo(canvas.getByRole("region", { name: "Eliminar tu cuenta" }));
  },
};

/** Opens the deletion sheet from the card, scrolled into view first as the phone's test does. */
async function openDeleteSheet(canvas: Canvas) {
  await title(canvas);
  await canvas.findByText("Aún no tienes ninguna: entras con el código de tu correo.");
  const card = canvas.getByRole("region", { name: "Eliminar tu cuenta" });
  await scrollTo(card);
  await userEvent.click(within(card).getByRole("button", { name: "Eliminar mi cuenta" }));
  const dialog = await screen.findByRole("dialog", { name: "¿Eliminar tu cuenta?" });
  return { dialog, sheet: within(dialog) };
}

/** The question before deleting the account: what goes, the export, the email to type. */
export const DeleteSheetOpen: Story = {
  render: (args) => stage(args, { data: "empty", noRecurrences: true }),
  play: async ({ canvasElement }) => {
    const { sheet } = await openDeleteSheet(within(canvasElement));
    await expect(sheet.getByRole("button", { name: "Sí, eliminar mi cuenta" })).toBeDisabled();
  },
};

/** The email typed (in capitals, with spaces around it): the deleting button is on. */
export const DeleteSheetReady: Story = {
  render: (args) => stage(args, { data: "empty", noRecurrences: true }),
  play: async ({ canvasElement }) => {
    const { sheet } = await openDeleteSheet(within(canvasElement));
    await userEvent.type(
      sheet.getByRole("textbox", { name: "Escribe tu correo para confirmar" }),
      "  ANA@Example.com ",
    );
    await expect(sheet.getByRole("button", { name: "Sí, eliminar mi cuenta" })).toBeEnabled();
  },
};

/** A delete the server refused: the sheet stays, with the reason under the field. */
export const DeleteSheetFailed: Story = {
  render: (args) => stage(args, { data: "empty", noRecurrences: true, failDelete: true }),
  play: async ({ canvasElement, args }) => {
    const { sheet } = await openDeleteSheet(within(canvasElement));
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
    // Whether the button keeps the focus depends on when the browser disables it while it deletes;
    // the picture is of the sheet at rest, with the focus nowhere.
    (document.activeElement as HTMLElement | null)?.blur();
  },
};

/** The same sheet by day and in English. */
export const DeleteSheetDayEnglish: Story = {
  globals: { theme: "day", locale: "en" },
  render: (args) => stage(args, { data: "empty", noRecurrences: true }),
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await title(canvas, "Settings");
    await canvas.findByText("You don't have one yet: you sign in with the code in your email.");
    const card = canvas.getByRole("region", { name: "Delete your account" });
    await scrollTo(card);
    await userEvent.click(within(card).getByRole("button", { name: "Delete my account" }));
    await expect(await screen.findByRole("dialog", { name: "Delete your account?" })).toBeVisible();
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
    const card = await region(canvas, "Comentarios e ideas");
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
    const card = await region(canvas, "Feedback and ideas");
    await expect(card.getByRole("link", { name: "Write to us" })).toHaveAttribute(
      "href",
      `mailto:${FEEDBACK_EMAIL}?subject=Wambito%3A%20feedback&body=%0A%0AWambito%20version%3A%20${encodeURIComponent(APP_VERSION)}%0ALanguage%3A%20en`,
    );
  },
};

/** The card between "Tus datos" and deleting the account, scrolled into view. */
export const AppSectionsFeedback: Story = {
  render: (args) => stage(args, { data: "empty", noRecurrences: true }),
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await title(canvas);
    await canvas.findByText("Aún no tienes ninguna: entras con el código de tu correo.");
    await scrollTo(canvas.getByRole("region", { name: "Comentarios e ideas" }));
  },
};

const CLAUDE: Assistant = {
  clientId: "https://claude.ai/oauth/mcp-oauth-client-metadata",
  name: "Claude",
  icon: null,
  uri: "https://claude.ai",
  domain: "claude.ai",
  scopes: ["finance:read", "finance:write", "offline_access"],
  connectedAt: "2026-10-02T09:00:00.000Z",
  lastUsedAt: "2026-10-20T18:30:00.000Z",
};

const CHATGPT: Assistant = {
  clientId: "dcr-chatgpt-1",
  name: "ChatGPT",
  icon: null,
  uri: "https://chatgpt.com",
  domain: "chatgpt.com",
  scopes: ["finance:read"],
  connectedAt: "2026-10-05T09:00:00.000Z",
  lastUsedAt: null,
};

/**
 * "Conecta tu asistente": the MCP's address on this origin with "Copiar", the steps for Claude
 * and ChatGPT, two things to ask, and the connected assistants with where each comes from.
 */
export const Assistants: Story = {
  render: (args) => stage(args, { assistants: [CLAUDE, CHATGPT] }),
  play: async ({ canvasElement, args }) => {
    const canvas = within(canvasElement);
    await title(canvas);
    const card = await region(canvas, "Conecta tu asistente");
    const url = `${window.location.origin}/mcp`;
    await expect(
      card.getByRole("textbox", { name: "La dirección de Wambito para asistentes" }),
    ).toHaveValue(url);
    const copy = card.getByRole("button", { name: "Copiar la dirección" });
    await expectTarget(copy);
    await userEvent.click(copy);
    await expect(args.onCopy).toHaveBeenCalledWith(url);
    await toastShown("Listo: copiamos la dirección.");
    await expect(card.getByText("En Claude")).toBeVisible();
    await expect(card.getByText(/Settings → Connectors → Add custom connector/)).toBeVisible();
    await expect(card.getByText("En ChatGPT")).toBeVisible();
    await expect(card.getByText(/Depende de tu plan de ChatGPT/)).toBeVisible();
    await expect(card.getByText("anota 18 lukas en almuerzo")).toBeVisible();
    await expect(card.getByText("¿cómo voy este mes?")).toBeVisible();
    await expect(await card.findByText("Desde claude.ai")).toBeVisible();
    await expect(card.getByText("Conectado el 2 oct 2026")).toBeVisible();
    await expect(card.getByText("Último uso: 20 oct 2026")).toBeVisible();
    await expect(card.getByText("Desde chatgpt.com")).toBeVisible();
    await expect(card.getByText("Aún sin usar")).toBeVisible();
  },
};

/** Revocar asks first; then the API forgets it, the list is read again and the row is gone. */
export const AssistantRevoke: Story = {
  render: (args) => stage(args, { assistants: [CLAUDE, CHATGPT] }),
  play: async ({ canvasElement, args }) => {
    const canvas = within(canvasElement);
    await title(canvas);
    const card = await region(canvas, "Conecta tu asistente");
    await userEvent.click(await card.findByRole("button", { name: "Revocar Claude" }));
    const sheet = within(await screen.findByRole("dialog", { name: "¿Revocar Claude?" }));
    await expect(writesTo(args.onRequest, "DELETE /api/v1/me/assistants")).toHaveLength(0);
    await userEvent.click(sheet.getByRole("button", { name: "Sí, revocar" }));
    await toastShown("Listo: Claude ya no tiene acceso.");
    await dialogGone();
    await expect(writesTo(args.onRequest, "DELETE /api/v1/me/assistants")).toEqual([
      `DELETE /api/v1/me/assistants/${encodeURIComponent(CLAUDE.clientId)}`,
    ]);
    await waitFor(() => expect(card.queryByRole("button", { name: "Revocar Claude" })).toBeNull());
    await expect(card.getByRole("button", { name: "Revocar ChatGPT" })).toBeVisible();
  },
};

/** A failed revoke says so, and keeps the sheet open and the row. */
export const AssistantRevokeFails: Story = {
  render: (args) => stage(args, { assistants: [CLAUDE], failRevoke: true }),
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await title(canvas);
    const card = await region(canvas, "Conecta tu asistente");
    await userEvent.click(await card.findByRole("button", { name: "Revocar Claude" }));
    const dialog = await screen.findByRole("dialog", { name: "¿Revocar Claude?" });
    await userEvent.click(within(dialog).getByRole("button", { name: "Sí, revocar" }));
    await toastShown("No pudimos revocarlo. Inténtalo otra vez.", "alert");
    await expect(dialog).toBeVisible();
  },
};

/** None connected yet. */
export const AssistantsEmpty: Story = {
  render: (args) => stage(args),
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await title(canvas);
    const card = await region(canvas, "Conecta tu asistente");
    await expect(await card.findByText("Aún no conectas ningún asistente.")).toBeVisible();
  },
};
