import type { Meta, StoryObj } from "@storybook/react-vite";
import { expect, fn, screen, userEvent, waitFor, within } from "storybook/test";
import { expectTarget } from "../../../.storybook/story-utils.ts";
import { HomeStage } from "../home/story-harness.tsx";

/**
 * The search screen: the hint before anything is asked, the results with the server's totals, the
 * category sheet, and what it says when nothing matches or the search fails.
 */

interface Spies {
  onRequest(line: string, headers: Record<string, string>): void;
}

const meta = {
  title: "Manage/Search",
  args: { onRequest: fn() },
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

const BOX = "Busca por nombre o nota";

/** Nothing asked yet: Wambi says what can be searched, and no request is made. */
export const Hint: Story = {
  render: (args) => <HomeStage onRequest={args.onRequest} path="/app/search" />,
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await expect(await canvas.findByRole("heading", { level: 1, name: "Buscar" })).toBeVisible();
    await expect(canvas.getByText("Busca por nombre, nota, categoría…")).toBeVisible();
    await expectTarget(
      canvas.getByRole("searchbox", { name: BOX }).closest(".lk-input") as Element,
    );
    await expect(canvas.queryByTestId("search-totals")).toBeNull();
  },
};

/** The filters in the URL are applied on arrival: rows and the totals over every match. */
export const Results: Story = {
  render: (args) => <HomeStage onRequest={args.onRequest} path="/app/search?q=pingo" />,
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await expect(await canvas.findByRole("button", { name: /^pingo doce/ })).toBeVisible();
    await expect(canvas.getByTestId("search-totals")).toHaveTextContent(
      /^1 movimiento · gastos 194,12\s€ · ingresos 0,00\s€$/,
    );
  },
};

/** Typing waits for a pause, then searches; the kind narrows it. */
export const TypeAndFilter: Story = {
  render: (args) => <HomeStage onRequest={args.onRequest} path="/app/search" />,
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await userEvent.type(await canvas.findByRole("searchbox", { name: BOX }), "sal");
    await expect(await canvas.findByRole("button", { name: /^Salario/ })).toBeVisible();
    await userEvent.click(canvas.getByRole("tab", { name: "Gastos" }));
    await expect(await canvas.findByText("No encontré nada con «sal»")).toBeVisible();
  },
};

/** Categories are picked in a sheet, any number at once; the button counts them. */
export const CategorySheet: Story = {
  render: (args) => <HomeStage onRequest={args.onRequest} path="/app/search" />,
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await userEvent.click(await canvas.findByRole("button", { name: "Categoría" }));
    const sheet = within(await screen.findByRole("dialog", { name: "Categoría" }));
    await userEvent.click(sheet.getByRole("button", { name: "Supermercado" }));
    await userEvent.click(sheet.getByRole("button", { name: "Ocio" }));
    await userEvent.click(sheet.getByRole("button", { name: "Listo" }));
    await waitFor(() => expect(screen.queryByRole("dialog")).toBeNull(), { timeout: 8000 });
    await expect(await canvas.findByRole("button", { name: "Categoría · 2" })).toBeVisible();
    await expect(await canvas.findByRole("button", { name: /^pingo doce/ })).toBeVisible();
    await expect(canvas.queryByRole("button", { name: /^desayuno/ })).toBeNull();
  },
};

/** Text that matches nothing says so with the text. */
export const None: Story = {
  render: (args) => <HomeStage onRequest={args.onRequest} path="/app/search?q=zzzz" />,
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await expect(await canvas.findByText("No encontré nada con «zzzz»")).toBeVisible();
  },
};

/** Filters without text that match nothing say so without a word. */
export const NoneFilters: Story = {
  render: (args) => (
    <HomeStage
      onRequest={args.onRequest}
      path="/app/search?status=paid&kind=income&category=cat-fun"
    />
  ),
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await expect(await canvas.findByText("No encontré nada con esos filtros")).toBeVisible();
  },
};

/** A failed search keeps the screen and offers to try again. */
export const Failed: Story = {
  render: (args) => <HomeStage onRequest={args.onRequest} path="/app/search?q=pingo" failSearch />,
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await expect(await canvas.findByRole("alert")).toBeVisible();
    await expectTarget(canvas.getByRole("button", { name: "Reintentar" }));
  },
};
