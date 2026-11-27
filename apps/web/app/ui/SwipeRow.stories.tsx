import type { Meta, StoryObj } from "@storybook/react-vite";
import { expect, fn, spyOn, userEvent, waitFor, within } from "storybook/test";
import { fingerDrag, translateX } from "../../.storybook/story-utils.ts";
import { SwipeRow, type SwipeRowProps } from "./SwipeRow.tsx";
import { TransactionRow } from "./TransactionRow.tsx";

/** A row as home lists it: a TransactionRow inside its SwipeRow, in a phone-wide column. */
function Demo({
  pending = false,
  ...props
}: Omit<SwipeRowProps, "children" | "right"> & {
  pending?: boolean;
  onEdit?: () => void;
  onPay?: () => Promise<void>;
}) {
  const { onEdit = () => {}, onPay = async () => {}, ...rest } = props;
  return (
    <div className="flex max-w-[360px] flex-col gap-(--space-2)">
      <SwipeRow
        {...rest}
        right={pending ? { kind: "paid", run: () => void onPay() } : { kind: "edit", run: onEdit }}
      >
        <TransactionRow
          name={pending ? "Spotify" : "continente"}
          categoryName={pending ? "suscripciones" : "Supermercado"}
          glyph={pending ? "☂️" : "🛒"}
          amount={pending ? -699 : -608}
          currency="EUR"
          status={pending ? "pending" : "paid"}
          onOpen={onEdit}
          {...(pending ? { onPay } : {})}
        />
      </SwipeRow>
      <button type="button" className="lk-more-row">
        Fuera de la fila
      </button>
    </div>
  );
}

const meta = {
  title: "UI/SwipeRow",
  component: Demo,
  args: { onDelete: fn(), onEdit: fn(), onPay: fn(async () => {}) },
} satisfies Meta<typeof Demo>;

export default meta;

/** Springs settle well within this, even on a busy machine running every story at once. */
const SETTLE = { timeout: 8000 };
type Story = StoryObj<typeof meta>;

const rowOf = (canvasElement: HTMLElement) =>
  canvasElement.querySelector<HTMLElement>("[data-swipe-row]") as HTMLElement;
const faceOf = (row: HTMLElement) =>
  row.querySelector<HTMLElement>(".lk-swipe-face") as HTMLElement;

/** Swiped left past 40 % of its width: the row slides out, folds away, and is deleted. */
export const DeletePastThreshold: Story = {
  play: async ({ canvasElement, args }) => {
    const row = rowOf(canvasElement);
    const width = row.getBoundingClientRect().width;
    await fingerDrag(row, { dx: -width * 0.6, steps: 14 });
    await waitFor(() => expect(args.onDelete).toHaveBeenCalledOnce(), SETTLE);
    await waitFor(() => expect(row.getBoundingClientRect().height).toBeLessThan(1));
    await expect(args.onEdit).not.toHaveBeenCalled();
  },
};

/**
 * A short swipe leaves Borrar open (and reachable); a tap elsewhere closes it; swiped open again,
 * tapping Borrar deletes. Closed, the action is out of the tab order and hidden from assistive
 * technology.
 */
export const ShortSwipeStaysOpen: Story = {
  play: async ({ canvasElement, args }) => {
    const canvas = within(canvasElement);
    const row = rowOf(canvasElement);
    await expect(canvas.queryByRole("button", { name: "Borrar" })).toBeNull();
    await fingerDrag(row, { dx: -70, steps: 12, stepMs: 24 });
    const remove = await canvas.findByRole("button", { name: "Borrar" });
    // The action draws the app's icon, not an emoji.
    await expect(remove.querySelector(".lk-swipe-glyph svg")).not.toBeNull();
    await expect(remove.textContent).not.toContain("🗑");
    await waitFor(() => expect(translateX(faceOf(row))).toBeCloseTo(-88, 0), SETTLE);
    await expect(args.onDelete).not.toHaveBeenCalled();

    await userEvent.click(canvas.getByRole("button", { name: "Fuera de la fila" }));
    await waitFor(() => expect(canvas.queryByRole("button", { name: "Borrar" })).toBeNull());
    await waitFor(() => expect(translateX(faceOf(row))).toBeCloseTo(0, 0), SETTLE);

    await fingerDrag(row, { dx: -70, steps: 12, stepMs: 24 });
    await userEvent.click(await canvas.findByRole("button", { name: "Borrar" }));
    await waitFor(() => expect(args.onDelete).toHaveBeenCalledOnce(), SETTLE);
    await expect(remove).toBeTruthy();
  },
};

/** Swiped right past the threshold: Editar runs, and the row springs back. */
export const RightEdits: Story = {
  play: async ({ canvasElement, args }) => {
    const row = rowOf(canvasElement);
    const width = row.getBoundingClientRect().width;
    await fingerDrag(row, { dx: width * 0.6, steps: 14 });
    await waitFor(() => expect(args.onEdit).toHaveBeenCalledOnce(), SETTLE);
    await waitFor(() => expect(translateX(faceOf(row))).toBeCloseTo(0, 0), SETTLE);
    await expect(args.onDelete).not.toHaveBeenCalled();
  },
};

/** On a pending row the right side is Pagado: swiping it marks the row paid. */
export const RightOnPendingPays: Story = {
  args: { pending: true },
  play: async ({ canvasElement, args }) => {
    const canvas = within(canvasElement);
    const row = rowOf(canvasElement);
    await fingerDrag(row, { dx: 60, steps: 12, stepMs: 24 });
    await expect(await canvas.findByRole("button", { name: "Pagado" })).toBeVisible();
    await userEvent.click(canvas.getByRole("button", { name: "Fuera de la fila" }));
    await waitFor(() => expect(translateX(faceOf(row))).toBeCloseTo(0, 0), SETTLE);

    const width = row.getBoundingClientRect().width;
    await fingerDrag(row, { dx: width * 0.6, steps: 14 });
    await waitFor(() => expect(args.onPay).toHaveBeenCalledOnce(), SETTLE);
    await expect(args.onEdit).not.toHaveBeenCalled();
  },
};

/** A haptic tick when the finger crosses the threshold, and again when it comes back under. */
export const TicksAtTheThreshold: Story = {
  play: async ({ canvasElement, args }) => {
    const vibrate = spyOn(navigator, "vibrate").mockImplementation(() => true);
    try {
      const row = rowOf(canvasElement);
      const box = row.getBoundingClientRect();
      // Out past 40 %, then back to 10 % (slowly) before letting go: two ticks, no delete.
      await fingerDrag(row, {
        from: { x: box.right - 20, y: box.top + box.height / 2 },
        path: [
          { dx: -box.width * 0.5, steps: 10 },
          { dx: -box.width * 0.1, steps: 20 },
        ],
        stepMs: 24,
      });
      const ticks = vibrate.mock.calls.filter(([pattern]) => JSON.stringify(pattern) === "[10]");
      await expect(ticks).toHaveLength(2);
      await expect(args.onDelete).not.toHaveBeenCalled();
    } finally {
      vibrate.mockRestore();
    }
  },
};

/** Keyboard users never land on the hidden actions: Tab goes from the row to its pending badge. */
export const KeyboardSkipsClosedActions: Story = {
  args: { pending: true },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await userEvent.tab();
    const open = canvas.getByRole("button", { name: /^Spotify/ });
    await expect(open).toHaveFocus();
    await expect(open).toHaveAccessibleDescription(
      "Tócalo para editarlo o borrarlo; Pendiente lo marca pagado.",
    );
    await userEvent.tab();
    await expect(canvas.getByRole("button", { name: /Pendiente/ })).toHaveFocus();
    await userEvent.tab();
    await expect(canvas.getByRole("button", { name: "Fuera de la fila" })).toHaveFocus();
  },
};

/** A vertical move (a scroll) never opens the row. */
export const VerticalMoveIsAScroll: Story = {
  play: async ({ canvasElement, args }) => {
    const canvas = within(canvasElement);
    const row = rowOf(canvasElement);
    await fingerDrag(row, { dx: -20, dy: -120, steps: 12 });
    await expect(translateX(faceOf(row))).toBe(0);
    await expect(canvas.queryByRole("button", { name: "Borrar" })).toBeNull();
    await expect(args.onDelete).not.toHaveBeenCalled();
  },
};

/** English, day theme: Delete and Edit. */
export const DayEnglish: Story = {
  globals: { theme: "day", locale: "en" },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    const row = rowOf(canvasElement);
    await fingerDrag(row, { dx: -70, steps: 12, stepMs: 24 });
    await expect(await canvas.findByRole("button", { name: "Delete" })).toBeVisible();
    await userEvent.click(canvas.getByRole("button", { name: "Fuera de la fila" }));
    await waitFor(() => expect(translateX(faceOf(row))).toBeCloseTo(0, 0), SETTLE);
    await fingerDrag(row, { dx: 70, steps: 12, stepMs: 24 });
    await expect(await canvas.findByRole("button", { name: "Edit" })).toBeVisible();
  },
};

/** A tap that lands while the row springs back still lets it settle (it never freezes part-way). */
export const TapMidSpringSettles: Story = {
  play: async ({ canvasElement, args }) => {
    const row = rowOf(canvasElement);
    // Slow and short: it springs back closed (a flick would delete).
    await fingerDrag(row, { dx: -32, steps: 8, stepMs: 24 });
    await fingerDrag(row, { steps: 0 });
    await waitFor(() => expect(translateX(faceOf(row))).toBeCloseTo(0, 0), SETTLE);
    await expect(args.onDelete).not.toHaveBeenCalled();
  },
};
