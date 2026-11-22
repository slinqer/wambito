import type { Meta, StoryObj } from "@storybook/react-vite";
import { expect, fn, screen, userEvent, waitFor, within } from "storybook/test";
import { expectTarget } from "../../../.storybook/story-utils.ts";
import { SOUND_STORAGE_KEY } from "../../feedback/feedback.ts";
import { THEME_STORAGE_KEY } from "../../theme/theme-bootstrap.ts";
import { HomeStage } from "../home/story-harness.tsx";

/**
 * Preferencias, the light version: "Apariencia" (Idioma and Tema as value rows that open a sheet),
 * "Sonido y tacto" (a switch) and "Hora y moneda" (value rows that open the pickers). Web-only,
 * not in parity.json.
 */
interface Spies {
  onRequest(line: string, headers: Record<string, string>): void;
}

const meta = {
  title: "Settings/Preferences",
  args: { onRequest: fn() },
  parameters: {
    viewport: {
      options: {
        phone: { name: "Phone", styles: { width: "390px", height: "844px" }, type: "mobile" },
      },
    },
  },
  globals: { viewport: { value: "phone", isRotated: false } },
} satisfies Meta<Spies>;

export default meta;
type Story = StoryObj<Spies>;

const page = (args: Spies) => (
  <HomeStage onRequest={args.onRequest} path="/app/settings/preferences" />
);

const dialogGone = () =>
  waitFor(() => expect(screen.queryByRole("dialog")).toBeNull(), { timeout: 8000 });

/** The three groups, one line per row, the current values on the right. */
export const Rows: Story = {
  render: page,
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await expect(
      await canvas.findByRole("heading", { level: 1, name: "Preferencias" }),
    ).toBeVisible();
    const look = within(await canvas.findByRole("group", { name: "Apariencia" }));
    await expect(look.getByRole("button", { name: /^Idioma/ })).toHaveTextContent("Español");
    await expect(look.getByRole("button", { name: /^Tema/ })).toHaveTextContent("Noche");
    const sound = within(await canvas.findByRole("group", { name: "Sonido y tacto" }));
    const toggle = sound.getByRole("switch", { name: "Sonido" });
    await expectTarget(toggle);
    await expect(toggle).toHaveAccessibleDescription(/Un sonido corto al anotar/);
    await expect(toggle).toHaveAccessibleDescription(/Suenan al anotar y al celebrar/);
    const time = within(await canvas.findByRole("group", { name: "Hora y moneda" }));
    await expect(time.getByRole("button", { name: /^Zona horaria/ })).toHaveTextContent("Madrid");
    await expect(await time.findByRole("button", { name: /^Moneda/ })).toHaveTextContent("EUR");
  },
};

/** Idioma opens a sheet with today's choices; the pick applies at once, the sheet closes. */
export const LanguageSheet: Story = {
  render: page,
  play: async ({ canvasElement, args }) => {
    const canvas = within(canvasElement);
    await userEvent.click(await canvas.findByRole("button", { name: /^Idioma/ }));
    const sheet = within(await screen.findByRole("dialog", { name: "Idioma" }));
    await expect(sheet.getByRole("radio", { name: "Español" })).toBeChecked();
    await userEvent.click(sheet.getByRole("radio", { name: "English" }));
    await expect(
      await canvas.findByRole("heading", { level: 1, name: "Preferences" }),
    ).toBeVisible();
    await dialogGone();
    await expect(canvas.getByRole("button", { name: /^Language/ })).toHaveTextContent("English");
    await waitFor(() =>
      expect(
        (args.onRequest as unknown as ReturnType<typeof fn>).mock.calls
          .map((call) => call[0] as string)
          .filter((line) => line.startsWith("PATCH /api/v1/me")),
      ).toEqual(['PATCH /api/v1/me {"locale":"en"}']),
    );
  },
};

/** Tema opens its sheet with its hint; the pick applies at once and is kept on this device. */
export const ThemeSheet: Story = {
  render: page,
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await userEvent.click(await canvas.findByRole("button", { name: /^Tema/ }));
    const sheet = within(await screen.findByRole("dialog", { name: "Tema" }));
    await expect(sheet.getByText("Automático sigue el modo de tu teléfono.")).toBeVisible();
    await userEvent.click(sheet.getByRole("radio", { name: "Día" }));
    await waitFor(() => expect(document.documentElement.dataset.theme).toBe("day"));
    await expect(localStorage.getItem(THEME_STORAGE_KEY)).toBe("day");
    await dialogGone();
    await expect(canvas.getByRole("button", { name: /^Tema/ })).toHaveTextContent("Día");
    await userEvent.click(canvas.getByRole("button", { name: /^Tema/ }));
    await userEvent.click(
      within(await screen.findByRole("dialog", { name: "Tema" })).getByRole("radio", {
        name: "Noche",
      }),
    );
    await waitFor(() => expect(document.documentElement.dataset.theme).toBe("night"));
  },
};

/** Sonido: off stores `wambito.sound = "off"`, on removes it. */
export const SoundSwitch: Story = {
  render: page,
  play: async ({ canvasElement }) => {
    localStorage.removeItem(SOUND_STORAGE_KEY);
    const canvas = within(canvasElement);
    const sound = await canvas.findByRole("switch", { name: "Sonido" });
    await userEvent.click(sound);
    await expect(sound).not.toBeChecked();
    await expect(localStorage.getItem(SOUND_STORAGE_KEY)).toBe("off");
    await userEvent.click(sound);
    await expect(localStorage.getItem(SOUND_STORAGE_KEY)).toBeNull();
  },
};

/** With movements the currency is locked: its row still opens a sheet that says why. */
export const CurrencyLockedSheet: Story = {
  render: page,
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await canvas.findByRole("group", { name: "Hora y moneda" });
    await userEvent.click(await canvas.findByRole("button", { name: /^Moneda/ }));
    const sheet = within(await screen.findByRole("dialog", { name: "Moneda" }));
    await expect(
      await sheet.findByText(
        "Tu moneda es EUR. Ya tienes movimientos o recurrentes, así que se queda así.",
      ),
    ).toBeVisible();
  },
};
