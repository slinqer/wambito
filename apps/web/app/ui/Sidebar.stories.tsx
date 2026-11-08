import type { Meta, StoryObj } from "@storybook/react-vite";
import { MemoryRouter } from "react-router";
import { expect, fn, userEvent, within } from "storybook/test";
import { expectFocusRing, expectTarget } from "../../.storybook/story-utils.ts";
import { Sidebar } from "./Sidebar.tsx";

const meta = {
  title: "UI/Sidebar",
  component: Sidebar,
  parameters: { layout: "fullscreen" },
  decorators: [
    (Story) => (
      <MemoryRouter>
        <div className="lk-screen flex min-h-[560px]">
          <Story />
        </div>
      </MemoryRouter>
    ),
  ],
  args: { current: "home", onAdd: fn() },
} satisfies Meta<typeof Sidebar>;

export default meta;
type Story = StoryObj<typeof meta>;

/** Desktop navigation: the six sections as links and a primary "Agregar". */
export const Home: Story = {
  play: async ({ canvasElement, args }) => {
    const canvas = within(canvasElement);
    const nav = canvas.getByRole("navigation", { name: "Navegación principal" });
    const links = within(nav).getAllByRole("link");
    await expect(links.map((l) => [l.textContent, l.getAttribute("href")])).toEqual([
      ["Inicio", "/app"],
      ["Buscar", "/app/search"],
      ["Análisis", "/app/insights"],
      ["Recurrentes", "/app/recurring"],
      ["Categorías", "/app"],
      ["Ajustes", "/app/settings"],
    ]);
    await expect(links[0]).toHaveAttribute("aria-current", "page");
    for (const link of links) await expectTarget(link);

    const add = within(nav).getByRole("button", { name: "Agregar" });
    await expect(add).toHaveClass("lk-btn-primary");
    await userEvent.click(add);
    await expect(args.onAdd).toHaveBeenCalledOnce();
  },
};

/** The current section is marked; links show the focus ring from the keyboard. */
export const Categories: Story = {
  args: { current: "categories" },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    const categories = canvas.getByRole("link", { name: "Categorías" });
    await expect(categories).toHaveAttribute("aria-current", "page");
    await expect(canvas.getByRole("link", { name: "Inicio" })).not.toHaveAttribute("aria-current");
    await userEvent.tab();
    await expectFocusRing(canvas.getByRole("link", { name: "Inicio" }));
  },
};

export const SettingsDayEnglish: Story = {
  args: { current: "settings" },
  globals: { theme: "day", locale: "en" },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await expect(canvas.getByRole("link", { name: "Settings" })).toHaveAttribute(
      "aria-current",
      "page",
    );
    await expect(canvas.getByRole("button", { name: "Add" })).toBeVisible();
  },
};
