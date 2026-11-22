import type { Meta, StoryObj } from "@storybook/react-vite";
import { expect, fn, screen, userEvent, waitFor, within } from "storybook/test";
import { HomeStage, STORY_TODAY } from "../home/story-harness.tsx";

/**
 * Tus datos, the light version: "Importar movimientos" (a chevron to the import page; a
 * "Próximamente" chip on an encrypted account) and "Descargar tus datos" (the export choices in a
 * sheet). Web-only, not in parity.json.
 */
interface Spies {
  onSave(filename: string, blob: Blob): void;
}

const meta = {
  title: "Settings/Data",
  args: { onSave: fn() },
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

/** Waits until the toast saying `text` has fully faded in (so the a11y checks see it settled). */
const toastShown = (text: string | RegExp) =>
  waitFor(
    () => {
      const toast = screen.getByRole("status").querySelector<HTMLElement>(".lk-toast");
      expect(toast).toHaveTextContent(text);
      expect(toast && getComputedStyle(toast).opacity).toBe("1");
    },
    { timeout: 8000 },
  );

/** Import is a link to the import page; export opens the sheet and downloads as it always did. */
export const ImportAndExport: Story = {
  render: (args) => (
    <HomeStage onRequest={() => {}} onSave={args.onSave} path="/app/settings/data" />
  ),
  play: async ({ canvasElement, args }) => {
    const canvas = within(canvasElement);
    await expect(await canvas.findByRole("heading", { level: 1, name: "Tus datos" })).toBeVisible();
    const link = canvas.getByRole("link", { name: /^Importar movimientos/ });
    await expect(link).toHaveAttribute("href", "/app/import");
    await expect(link).toHaveTextContent("Desde Budge");
    await expect(link).toHaveAccessibleDescription("Importa lo que llevas en Budge.");
    const row = canvas.getByRole("button", { name: /^Descargar tus datos/ });
    await expect(row).toHaveTextContent("En JSON o CSV");
    await userEvent.click(row);
    const sheet = within(await screen.findByRole("dialog", { name: "Descarga tus datos" }));
    await userEvent.click(sheet.getByRole("button", { name: "Descargar CSV" }));
    await waitFor(() => expect(args.onSave).toHaveBeenCalledTimes(1));
    const [filename] = (args.onSave as ReturnType<typeof fn>).mock.calls[0] as [string, Blob];
    await expect(filename).toBe(`wambito-export-${STORY_TODAY}.csv`);
    await toastShown(`Listo: descargamos wambito-export-${STORY_TODAY}.csv.`);
  },
};

/** An encrypted account: import says "Próximamente" and has no chevron or link; export is off too. */
export const Encrypted: Story = {
  render: (args) => (
    <HomeStage onRequest={() => {}} onSave={args.onSave} mode="local" path="/app/settings/data" />
  ),
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await canvas.findByRole("heading", { level: 1, name: "Tus datos" });
    await expect(canvas.queryByRole("link", { name: /^Importar movimientos/ })).toBeNull();
    const row = canvas.getByText("Importar movimientos").closest(".lk-row") as HTMLElement;
    await expect(within(row).getByText("Próximamente")).toBeVisible();
    await expect(row.querySelector(".lk-row-end")).toBeNull();
    await expect(canvas.queryByRole("button", { name: /^Descargar tus datos/ })).toBeNull();
    await expect(
      canvas.getByText(
        "Todavía no está disponible con el cifrado de extremo a extremo. Llega pronto.",
      ),
    ).toBeVisible();
  },
};
