import type { Meta, StoryObj } from "@storybook/react-vite";
import { MemoryRouter } from "react-router";
import { expect, userEvent, within } from "storybook/test";
import { expectEdge, expectFocusRing, expectTarget } from "../../.storybook/story-utils.ts";
import { PressLink } from "./PressLink.tsx";

const meta = {
  title: "UI/PressLink",
  component: PressLink,
  decorators: [
    (Story) => (
      <MemoryRouter>
        <Story />
      </MemoryRouter>
    ),
  ],
  args: { to: "/create-account?lang=es", children: "Crear cuenta" },
} satisfies Meta<typeof PressLink>;

export default meta;
type Story = StoryObj<typeof meta>;

/** A link dressed as the primary button: solid brand edge, 44px, focus ring, no underline. */
export const Primary: Story = {
  play: async ({ canvasElement }) => {
    const link = within(canvasElement).getByRole("link", { name: "Crear cuenta" });
    await expect(link).toHaveAttribute("href", "/create-account?lang=es");
    await expect(link).toHaveClass("lk-btn", "lk-btn-primary");
    await expect(getComputedStyle(link).textDecorationLine).toBe("none");
    await expectEdge(link, 6);
    await expectTarget(link);
    await userEvent.tab();
    await expectFocusRing(link);
  },
};

/** The small secondary variant, e.g. "Entrar" in the landing header. */
export const SecondarySmall: Story = {
  args: { variant: "secondary", size: "sm", to: "/sign-in?lang=en", children: "Sign in" },
  globals: { theme: "day", locale: "en" },
  play: async ({ canvasElement }) => {
    const link = within(canvasElement).getByRole("link", { name: "Sign in" });
    await expect(link).toHaveClass("lk-btn-secondary", "lk-btn-sm");
    await expectEdge(link, 3);
    await expectTarget(link);
  },
};
