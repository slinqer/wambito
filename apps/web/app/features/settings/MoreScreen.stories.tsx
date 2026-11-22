import type { Meta, StoryObj } from "@storybook/react-vite";
import { expect, screen, userEvent, within } from "storybook/test";
import { HomeStage } from "../home/story-harness.tsx";
import { APP_VERSION, FEEDBACK_EMAIL } from "./feedback.ts";

/** Más on the web: one row, "Comentarios e ideas", that opens today's form in a sheet. */
const meta = {
  title: "Settings/More",
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

export const Feedback: Story = {
  render: () => <HomeStage onRequest={() => {}} path="/app/settings/more" />,
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await expect(await canvas.findByRole("heading", { level: 1, name: "Más" })).toBeVisible();
    const row = canvas.getByRole("button", { name: /^Comentarios e ideas/ });
    await expect(row).toHaveTextContent("Cuéntanos qué mejorar");
    await userEvent.click(row);
    const sheet = within(await screen.findByRole("dialog", { name: "Comentarios e ideas" }));
    await expect(sheet.getByRole("link", { name: "Escribirnos" })).toHaveAttribute(
      "href",
      `mailto:${FEEDBACK_EMAIL}?subject=Wambito%3A%20comentarios&body=%0A%0AVersi%C3%B3n%20de%20Wambito%3A%20${encodeURIComponent(APP_VERSION)}%0AIdioma%3A%20es`,
    );
    await expect(
      sheet.getByText(`Si no se abre tu correo, escribe a ${FEEDBACK_EMAIL}.`),
    ).toBeVisible();
  },
};
