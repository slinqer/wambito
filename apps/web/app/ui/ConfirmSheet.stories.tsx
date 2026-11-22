import type { Meta, StoryObj } from "@storybook/react-vite";
import { useState } from "react";
import { expect, fn, screen, userEvent, waitFor, within } from "storybook/test";
import { useTranslations } from "use-intl";
import { ConfirmSheet } from "./ConfirmSheet.tsx";
import { PressButton } from "./PressButton.tsx";

function ConfirmHarness({
  initiallyOpen = false,
  failing = false,
  onConfirm,
}: {
  initiallyOpen?: boolean;
  failing?: boolean;
  onConfirm?: () => void;
}) {
  const t = useTranslations("settings.passkeys");
  const tx = useTranslations("transaction");
  const [open, setOpen] = useState(initiallyOpen);
  return (
    <>
      <PressButton variant="secondary" onClick={() => setOpen(true)}>
        {tx("delete")}
      </PressButton>
      <ConfirmSheet
        open={open}
        onClose={() => setOpen(false)}
        title={t("remove_title")}
        body={t("remove_body")}
        confirmLabel={t("remove_confirm")}
        onConfirm={async () => {
          onConfirm?.();
          if (failing) throw new Error("not this time");
        }}
      />
    </>
  );
}

/** Waits for the open sheet to finish sliding in, so the a11y run sees it in place. */
async function settled(name: string): Promise<HTMLElement> {
  const dialog = await screen.findByRole("dialog", { name });
  await waitFor(() => expect(new DOMMatrix(getComputedStyle(dialog).transform).m42).toBe(0));
  return dialog;
}

const meta = {
  title: "UI/ConfirmSheet",
  component: ConfirmHarness,
  args: { onConfirm: fn() },
} satisfies Meta<typeof ConfirmHarness>;

export default meta;
type Story = StoryObj<typeof meta>;

/** The question, what it means, and the two ways out: the action in the danger color, Cancelar. */
export const Open: Story = {
  args: { initiallyOpen: true },
  play: async () => {
    const dialog = await settled("¿Eliminar esta huella?");
    const sheet = within(dialog);
    await expect(
      sheet.getByText("Ya no podrás entrar con ella. Tu correo sigue funcionando."),
    ).toBeVisible();
    await expect(sheet.getByRole("button", { name: "Sí, eliminar" })).toBeEnabled();
    await expect(sheet.getByRole("button", { name: "Cancelar" })).toBeEnabled();
  },
};

/** The same by day and in English. */
export const OpenDayEnglish: Story = {
  args: { initiallyOpen: true },
  globals: { theme: "day", locale: "en" },
  play: async () => {
    await settled("Delete this fingerprint?");
  },
};

/** Confirming does it and closes the sheet. */
export const Confirms: Story = {
  play: async ({ canvasElement, args }) => {
    await userEvent.click(within(canvasElement).getByRole("button", { name: "Eliminar" }));
    const dialog = await settled("¿Eliminar esta huella?");
    await userEvent.click(within(dialog).getByRole("button", { name: "Sí, eliminar" }));
    await expect(args.onConfirm).toHaveBeenCalledOnce();
    await waitFor(() => expect(screen.queryByRole("dialog")).toBeNull());
  },
};

/** A failed action keeps the sheet open for another try. */
export const StaysWhenItFails: Story = {
  args: { failing: true },
  play: async ({ canvasElement, args }) => {
    await userEvent.click(within(canvasElement).getByRole("button", { name: "Eliminar" }));
    const dialog = await settled("¿Eliminar esta huella?");
    await userEvent.click(within(dialog).getByRole("button", { name: "Sí, eliminar" }));
    await waitFor(() => expect(args.onConfirm).toHaveBeenCalledOnce());
    await expect(dialog).toBeVisible();
  },
};

/** Cancelar leaves things as they were. */
export const CancelLeaves: Story = {
  play: async ({ canvasElement, args }) => {
    await userEvent.click(within(canvasElement).getByRole("button", { name: "Eliminar" }));
    const dialog = await settled("¿Eliminar esta huella?");
    await userEvent.click(within(dialog).getByRole("button", { name: "Cancelar" }));
    await waitFor(() => expect(screen.queryByRole("dialog")).toBeNull());
    await expect(args.onConfirm).not.toHaveBeenCalled();
  },
};
