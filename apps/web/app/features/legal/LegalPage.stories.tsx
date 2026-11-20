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

/** The privacy policy in Spanish, night theme, as a build without a PostHog key: twelve sections. */
export const Privacy: Story = {
  args: { withAnalytics: false },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await expect(canvas.getByRole("heading", { level: 1 })).toHaveTextContent(
      "Política de privacidad",
    );
    await expect(canvas.getByText("Versión del 20 de noviembre de 2026")).toBeVisible();
    await expect(canvas.getAllByRole("heading", { level: 2 })).toHaveLength(12);
    await expect(canvas.getByText(/No usamos rastreadores, ni analítica/)).toBeVisible();
    await expect(canvas.queryByText(/PostHog/)).toBeNull();
    const mail = canvas.getAllByRole("link", { name: "privacy@wambito.com" });
    await expect(mail[0]).toHaveAttribute("href", "mailto:privacy@wambito.com");
    await expect(canvas.getByRole("link", { name: "borrar tu cuenta" })).toHaveAttribute(
      "href",
      "/delete-account",
    );
  },
};

/**
 * The privacy policy of a build with a PostHog key: the analytics section after storage, with the
 * retention filled in, and the "what we don't do" that names PostHog.
 */
export const PrivacyWithAnalytics: Story = {
  args: { withAnalytics: true },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    const titles = canvas.getAllByRole("heading", { level: 2 }).map((h) => h.textContent);
    await expect(titles).toHaveLength(13);
    await expect(titles[titles.indexOf("Dónde se guarda") + 1]).toBe("Analítica en wambito.com");
    const analytics = canvas.getByRole("region", { name: "Analítica en wambito.com" });
    await expect(analytics).toHaveTextContent("12 meses");
    await expect(analytics).toHaveTextContent("30 días");
    await expect(
      within(analytics).getByRole("link", { name: "privacy@wambito.com" }),
    ).toHaveAttribute("href", "mailto:privacy@wambito.com");
    await expect(canvas.queryByText(/No usamos rastreadores, ni analítica/)).toBeNull();
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
