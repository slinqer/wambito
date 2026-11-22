import type { Meta, StoryObj } from "@storybook/react-vite";
import { MemoryRouter } from "react-router";
import { expect, fn, userEvent, within } from "storybook/test";
import { expectTarget } from "../../../.storybook/story-utils.ts";
import { ANDROID_APK_HREF, ANDROID_RELEASE_HREF, STORE_LINKS } from "../landing/links.ts";
import { InstallApp } from "./InstallApp.tsx";

const meta = {
  title: "Vault/Install app",
  component: InstallApp,
  decorators: [
    (Story) => (
      <MemoryRouter>
        <Story />
      </MemoryRouter>
    ),
  ],
  args: { onContinue: fn() },
} satisfies Meta<typeof InstallApp>;

export default meta;
type Story = StoryObj<typeof meta>;

export const Default: Story = {
  play: async ({ canvasElement, args }) => {
    const canvas = within(canvasElement);
    await expect(
      canvas.getByRole("heading", { level: 1, name: "Wambito vive en tu teléfono" }),
    ).toBeVisible();
    const apk = canvas.getByRole("link", { name: "Descargar para Android" });
    await expectTarget(apk);
    await expect(apk).toHaveAttribute("href", ANDROID_APK_HREF);
    await expect(canvas.getByRole("link", { name: "Ver la versión en GitHub" })).toHaveAttribute(
      "href",
      ANDROID_RELEASE_HREF,
    );
    // Every store link is still null: no button for any of them.
    await expect(canvas.queryByRole("link", { name: "Google Play" })).toBeNull();
    await expect(canvas.queryByRole("link", { name: "F-Droid" })).toBeNull();
    await expect(canvas.queryByRole("link", { name: "App Store" })).toBeNull();
    const next = canvas.getByRole("button", { name: "Continuar en el navegador" });
    await expectTarget(next);
    await userEvent.click(next);
    await expect(args.onContinue).toHaveBeenCalledTimes(1);
  },
};

/** A store whose link is set shows its button, and only that one. */
export const WithGooglePlay: Story = {
  args: { links: { ...STORE_LINKS, play: "https://play.google.com/store/apps/details?id=demo" } },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await expect(canvas.getByRole("link", { name: "Google Play" })).toHaveAttribute(
      "href",
      "https://play.google.com/store/apps/details?id=demo",
    );
    await expect(canvas.queryByRole("link", { name: "F-Droid" })).toBeNull();
  },
};
