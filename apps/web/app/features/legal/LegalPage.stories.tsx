import type { Meta, StoryObj } from "@storybook/react-vite";
import { MemoryRouter } from "react-router";
import { expect, within } from "storybook/test";
import { LegalPage } from "./LegalPage.tsx";

const meta = {
  title: "Legal/LegalPage",
  component: LegalPage,
  parameters: { layout: "fullscreen" },
  args: { page: "privacy" },
  decorators: [
    (Story) => (
      <MemoryRouter>
        <Story />
      </MemoryRouter>
    ),
  ],
} satisfies Meta<typeof LegalPage>;

export default meta;
type Story = StoryObj<typeof meta>;

/** The privacy policy in Spanish, night theme: the version date and twelve sections. */
export const Privacy: Story = {
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await expect(canvas.getByRole("heading", { level: 1 })).toHaveTextContent(
      "Política de privacidad",
    );
    await expect(canvas.getByText("Versión del 5 de noviembre de 2026")).toBeVisible();
    await expect(canvas.getAllByRole("heading", { level: 2 })).toHaveLength(12);
    const mail = canvas.getAllByRole("link", { name: "privacy@wambito.com" });
    await expect(mail[0]).toHaveAttribute("href", "mailto:privacy@wambito.com");
    await expect(canvas.getByRole("link", { name: "borrar tu cuenta" })).toHaveAttribute(
      "href",
      "/delete-account",
    );
  },
};

/** The account deletion page in English, day theme: four sections, a link back to the policy. */
export const DeleteAccountEnglish: Story = {
  args: { page: "deleteAccount" },
  globals: { theme: "day", locale: "en" },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await expect(canvas.getByRole("heading", { level: 1 })).toHaveTextContent(
      "Delete your account",
    );
    await expect(canvas.getAllByRole("heading", { level: 2 }).map((h) => h.textContent)).toEqual([
      "From the app",
      "By email",
      "What is deleted",
      "Backups",
    ]);
    await expect(canvas.getByRole("link", { name: "privacy policy" })).toHaveAttribute(
      "href",
      "/en/privacy",
    );
  },
};
