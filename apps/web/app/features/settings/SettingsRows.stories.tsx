import type { Meta, StoryObj } from "@storybook/react-vite";
import { useState } from "react";
import { MemoryRouter } from "react-router";
import { expect, fn, userEvent, within } from "storybook/test";
import { expectTarget } from "../../../.storybook/story-utils.ts";
import { Icon } from "../../ui/Icon.tsx";
import { SettingsGroup, SettingsRow } from "./parts.tsx";

/** The light group and rows every settings category screen is made of. */
const meta = {
  title: "Manage/Settings rows",
  decorators: [
    (Story) => (
      <MemoryRouter>
        <div className="max-w-[390px] p-(--space-4)">
          <Story />
        </div>
      </MemoryRouter>
    ),
  ],
} satisfies Meta;

export default meta;
type Story = StoryObj<typeof meta>;

const icon = (name: "globe" | "volume" | "trash" | "phone" | "shield") => (
  <Icon name={name} size={20} />
);

function SwitchRow({ onChange }: { onChange?: (v: boolean) => void }) {
  const [on, setOn] = useState(true);
  return (
    <SettingsRow
      icon={icon("volume")}
      title="Sonido"
      line="Un clic al guardar un movimiento"
      trailing={{
        kind: "switch",
        checked: on,
        onChange: (v) => {
          setOn(v);
          onChange?.(v);
        },
      }}
    />
  );
}

const all = (onTrash?: () => void, onChange?: (v: boolean) => void) => (
  <SettingsGroup label="Preferencias">
    <SettingsRow
      icon={icon("globe")}
      title="Idioma"
      trailing={{ kind: "chevron", value: "Español" }}
      onPress={() => {}}
    />
    <SwitchRow onChange={onChange} />
    <SettingsRow
      icon={icon("phone")}
      title="Pixel 8"
      line="Activo hoy"
      trailing={{ kind: "chip", text: "este dispositivo" }}
    />
    <SettingsRow
      icon={icon("phone")}
      title="Portátil de casa"
      line="Último acceso hace tres semanas, desde Medellín"
      trailing={{ kind: "trash", label: "Quitar Portátil de casa", onPress: onTrash ?? (() => {}) }}
    />
    <SettingsRow
      icon={icon("trash")}
      title="Borrar mi cuenta"
      tone="danger"
      trailing={{ kind: "chevron" }}
      onPress={() => {}}
    />
  </SettingsGroup>
);

/** Night: one row of each trailing kind and a danger row. */
export const Night: Story = {
  render: () => all(fn(), fn()),
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    const toggle = await canvas.findByRole("switch", { name: "Sonido" });
    await expect(toggle).toHaveAttribute("aria-checked", "true");
    await userEvent.click(toggle);
    await expect(toggle).toHaveAttribute("aria-checked", "false");
    await expectTarget(toggle);
    await expect(canvas.getByText("Español")).toBeVisible();
    await expectTarget(await canvas.findByRole("button", { name: "Quitar Portátil de casa" }));
    await expect(canvas.getByText("este dispositivo")).toBeVisible();
  },
};

/** Day, for the contrast checks. */
export const Day: Story = {
  globals: { theme: "day" },
  render: () => all(),
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await expect(await canvas.findByRole("switch", { name: "Sonido" })).toBeVisible();
    await expect(canvas.getByRole("group", { name: "Preferencias" })).toBeVisible();
  },
};
