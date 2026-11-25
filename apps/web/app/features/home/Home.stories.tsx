import type { Meta, StoryObj } from "@storybook/react-vite";
import { lastDay, monthOf } from "@wambito/core";
import { expect, fireEvent, fn, screen, userEvent, waitFor, within } from "storybook/test";
import {
  backgroundBehind,
  contrastRatio,
  expectBoundaryContrast,
  expectSunk,
  expectTarget,
  fingerDrag,
} from "../../../.storybook/story-utils.ts";
import { HomeStage, STORY_TODAY } from "./story-harness.tsx";

/**
 * Home (spec §2.5) and the add/edit sheet (§2.6) against a fake API: this month's budgets and
 * transactions, adding, editing, undoing, paying a pending one, and the cards around them.
 */

interface Spies {
  onRequest(line: string, headers: Record<string, string>): void;
}

const meta = {
  title: "Home/Home",
  args: { onRequest: fn() },
  // Phone first: the stories run at 390×844 (the vitest addon sizes the page from this global).
  parameters: {
    viewport: {
      options: {
        phone: { name: "Phone", styles: { width: "390px", height: "844px" }, type: "mobile" },
        desktop: { name: "Desktop", styles: { width: "1280px", height: "800px" }, type: "desktop" },
        short: { name: "Short phone", styles: { width: "360px", height: "640px" }, type: "mobile" },
        se: { name: "Small phone", styles: { width: "375px", height: "667px" }, type: "mobile" },
      },
    },
  },
  globals: { viewport: { value: "phone", isRotated: false } },
} satisfies Meta<Spies>;

export default meta;
type Story = StoryObj<Spies>;

type Canvas = ReturnType<typeof within>;

const calls = (spy: Spies["onRequest"]) =>
  (spy as unknown as ReturnType<typeof fn>).mock.calls.map(
    (call) => [call[0] as string, call[1] as Record<string, string>] as const,
  );
const posts = (spy: Spies["onRequest"]) =>
  calls(spy).filter(([line]) => line.startsWith("POST /api/v1/transactions "));

const NBSP = " ";
const eur = (text: string) => `${text}${NBSP}€`;
/** An accessible name ending in an amount in euros (any space before the sign). */
const endsInEuros = (start: string, amount: string) => new RegExp(`^${start} ${amount}\\s€$`);

/** Waits for a toast (the regions exist, empty, before any toast shows) and returns it. */
async function toastSaying(text: string, role: "status" | "alert" = "status") {
  let found: HTMLElement | null = null;
  await waitFor(() => {
    const region = screen.getByRole(role);
    expect(region).toHaveTextContent(text);
    const toast = region.querySelector<HTMLElement>(".lk-toast");
    expect(toast && getComputedStyle(toast).opacity).toBe("1");
    found = toast;
  });
  return within(found as unknown as HTMLElement);
}

const hero = (canvas: Canvas) => canvas.findByRole("region", { name: "Te quedan este mes" });

/** Opens the add sheet from the bottom bar's ＋. */
async function openAdd(canvas: Canvas) {
  await userEvent.click(await canvas.findByRole("button", { name: "Agregar" }));
  return within(await screen.findByRole("dialog", { name: "Nuevo gasto" }));
}

/** Picks a category chip in the sheet (the default is the month's most used, Restaurante). */
async function pickCategory(sheet: Canvas, name: string) {
  await userEvent.click(
    within(sheet.getByRole("group", { name: "Categoría" })).getByRole("button", { name }),
  );
}

/** Types an amount on the sheet's keypad: digits and the decimal comma. */
async function typeAmount(sheet: Canvas, text: string) {
  const keypad = within(sheet.getByRole("group", { name: "Teclado numérico" }));
  for (const key of text) {
    await userEvent.click(keypad.getByRole("button", { name: key === "," ? "Coma decimal" : key }));
  }
}

/** The sheet slides out (`--sheet`); on a loaded machine its frames come late, so wait long. */
const dialogGone = () =>
  waitFor(() => expect(screen.queryByRole("dialog")).toBeNull(), { timeout: 8000 });

// -- Home ------------------------------------------------------------------------------------------

/** The month at a glance: what is left, Wambi, and one row per spending category. */
export const Budgets: Story = {
  render: (args) => <HomeStage onRequest={args.onRequest} />,
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    const region = await hero(canvas);
    await waitFor(() => expect(region).toHaveTextContent(eur("501,13")));
    await expect(region).toHaveTextContent(`Gastado ${eur("718,87")}`);
    await expect(region).toHaveTextContent(`de ${eur("1220,00")}`);
    // Movimientos comes first and is the default; Categorías is one tap away.
    const tabs = canvas.getAllByRole("tab");
    await expect(tabs.map((tab) => tab.textContent)).toEqual(["Movimientos", "Categorías"]);
    await expect(canvas.getByRole("tab", { name: "Movimientos" })).toHaveAttribute(
      "aria-selected",
      "true",
    );
    // The tabs sit on the page's own background: no darker band of their own around them
    // (founder decision 2026-10-24).
    const strip = canvasElement.querySelector(".lk-tabs-sticky");
    await expect(strip).not.toBeNull();
    await expect(getComputedStyle(strip as Element).backgroundColor).toBe("rgba(0, 0, 0, 0)");
    await userEvent.click(canvas.getByRole("tab", { name: "Categorías" }));
    const panel = within(canvas.getByRole("tabpanel", { name: "Categorías" }));
    // Status in words, never color alone.
    await expect(
      panel.getByRole("button", { name: endsInEuros("Supermercado Te pasaste", "14,12") }),
    ).toBeVisible();
    await expect(
      panel.getByRole("button", { name: endsInEuros("Restaurante Quedan", "41,58") }),
    ).toBeVisible();
    // Categories are managed here: Gastos | Ingresos, "Nueva categoría", and no archived ones yet.
    const kinds = panel.getAllByRole("tab");
    await expect(kinds.map((tab) => tab.textContent)).toEqual(["Gastos", "Ingresos"]);
    await expect(panel.getByRole("tab", { name: "Gastos" })).toHaveAttribute(
      "aria-selected",
      "true",
    );
    // As on the phone: the switch takes its whole row, and "Nueva categoría" is a dashed row
    // after the categories, so the page's one purple + stays the add-a-movement button.
    const add = panel.getByRole("button", { name: "Nueva categoría" });
    await expectTarget(add);
    await expect(add).toHaveClass("lk-add-row");
    await expect(add).not.toHaveClass("lk-btn-primary");
    const rows = panel.getAllByRole("button", { name: /Quedan|Te pasaste|Sin presupuesto/ });
    const last = rows.at(-1);
    if (!last) throw new Error("no category rows");
    await expect(last.compareDocumentPosition(add) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy();
    await expect(add.getBoundingClientRect().height).toBeGreaterThanOrEqual(52);
    await expect(panel.queryByRole("button", { name: /^Archivadas/ })).toBeNull();
    await expect(panel.queryByRole("button", { name: /^Salario/ })).toBeNull();
    // Wambi talks about the month: the worst category first, except on its last day, when he
    // talks about what is left (core's wambiMessage).
    const lastDayOfMonth = STORY_TODAY === lastDay(monthOf(STORY_TODAY));
    await expect(
      canvas.getByText(lastDayOfMonth ? new RegExp(eur("501,13")) : /Supermercado/, {
        selector: ".lk-bubble",
      }),
    ).toBeVisible();
    await expectTarget(canvas.getByRole("button", { name: "Agregar" }));
    await expectTarget(canvas.getByRole("button", { name: "Tu cuenta" }));
  },
};

/** The same month by day: today on top, then the past, the upcoming pending last. */
export const Transactions: Story = {
  render: (args) => <HomeStage onRequest={args.onRequest} />,
  play: async ({ canvasElement, args }) => {
    const canvas = within(canvasElement);
    await hero(canvas);
    await userEvent.click(canvas.getByRole("tab", { name: "Movimientos" }));
    const panel = within(canvas.getByRole("tabpanel", { name: "Movimientos" }));
    const days = await panel.findAllByRole("region");
    await expect(days[0]).toHaveAccessibleName(/^Hoy · /);
    await expect(
      within(days[0] as HTMLElement).getByRole("button", { name: /^desayuno/ }),
    ).toBeVisible();
    // Paying the pending subscription: the badge turns "Pagado" and a status toast says so.
    const pay = panel.getByRole("button", { name: "Pendiente, marcar como pagado" });
    await expectTarget(pay);
    await userEvent.click(pay);
    await expect(await panel.findByText("Pagado")).toBeVisible();
    await toastSaying(`Pagado: Spotify · −${eur("3,53")}`);
    await waitFor(() =>
      expect(calls(args.onRequest).map(([line]) => line)).toContainEqual(
        expect.stringMatching(/^PATCH \/api\/v1\/transactions\/\S+ \{"status":"paid"\}$/),
      ),
    );
  },
};

/** Detected transactions carry their mark; the filter keeps them, OK and "Confirmar todos" confirm. */
export const DetectedTransactions: Story = {
  render: (args) => <HomeStage onRequest={args.onRequest} detected />,
  play: async ({ canvasElement, args }) => {
    const canvas = within(canvasElement);
    await hero(canvas);
    await userEvent.click(canvas.getByRole("tab", { name: "Movimientos" }));
    const panel = within(canvas.getByRole("tabpanel", { name: "Movimientos" }));
    await expect(await panel.findByText("por revisar · de Revolut")).toBeVisible();
    await expect(panel.getByText("por revisar · de Google Wallet")).toBeVisible();
    // The filter keeps only them.
    const filter = panel.getByRole("button", { name: /^Por revisar · 2$/ });
    await expect(filter).toHaveTextContent("Por revisar · 2");
    await userEvent.click(filter);
    await expect(panel.queryByRole("button", { name: /^desayuno/ })).toBeNull();
    // OK confirms one: only that PATCH goes out and its mark is gone.
    await userEvent.click(panel.getByRole("button", { name: "Bien: Mercadona" }));
    await waitFor(() => expect(panel.queryByText("por revisar · de Revolut")).toBeNull());
    await waitFor(() =>
      expect(calls(args.onRequest).map(([line]) => line)).toContainEqual(
        expect.stringMatching(/^PATCH \/api\/v1\/transactions\/\S+ \{"needsReview":false\}$/),
      ),
    );
    // Confirmar todos confirms the rest in one request.
    await userEvent.click(panel.getByRole("button", { name: "Confirmar todos" }));
    await waitFor(() => expect(panel.queryByText(/por revisar/)).toBeNull());
    await waitFor(() =>
      expect(calls(args.onRequest).map(([line]) => line)).toContainEqual(
        expect.stringMatching(/^POST \/api\/v1\/transactions\/review \{"ids":\["\S+"\]\}$/),
      ),
    );
    await expect(await panel.findByRole("button", { name: /^desayuno/ })).toBeVisible();
  },
};

/** Saving the edit of a detected transaction confirms it in the same PATCH, as on the phone. */
export const EditConfirmsDetected: Story = {
  render: (args) => <HomeStage onRequest={args.onRequest} detected />,
  play: async ({ canvasElement, args }) => {
    const canvas = within(canvasElement);
    await hero(canvas);
    await userEvent.click(canvas.getByRole("tab", { name: "Movimientos" }));
    const panel = within(canvas.getByRole("tabpanel", { name: "Movimientos" }));
    await userEvent.click(await panel.findByRole("button", { name: /^Mercadona/ }));
    const edit = within(await screen.findByRole("dialog", { name: "Editar movimiento" }));
    await userEvent.click(edit.getByRole("button", { name: "Guardar cambios" }));
    await dialogGone();
    await waitFor(() =>
      expect(calls(args.onRequest).map(([line]) => line)).toContainEqual(
        expect.stringMatching(/^PATCH \/api\/v1\/transactions\/\S+ \{"needsReview":false\}$/),
      ),
    );
    await waitFor(() => expect(panel.queryByText("por revisar · de Revolut")).toBeNull());
    await expect(panel.getByText("por revisar · de Google Wallet")).toBeVisible();
  },
};

/** The choice of list is remembered on this device, and a sideways swipe switches it. */
export const ViewRememberedAndSwiped: Story = {
  render: (args) => <HomeStage onRequest={args.onRequest} />,
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await hero(canvas);
    const card = canvas.getByRole("region", { name: "Te quedan este mes" });
    // The pages follow the finger: dragged left (from the summary card), Categorías comes in.
    await fingerDrag(card, { dx: -260, steps: 16 });
    await waitFor(() =>
      expect(canvas.getByRole("tab", { name: "Categorías" })).toHaveAttribute(
        "aria-selected",
        "true",
      ),
    );
    // The choice wins over the default after a reload.
    await userEvent.click(canvas.getByRole("button", { name: "Recargar (stand-in)" }));
    await hero(canvas);
    await expect(canvas.getByRole("tab", { name: "Categorías" })).toHaveAttribute(
      "aria-selected",
      "true",
    );
    // A mostly vertical drag is a scroll, not a swipe.
    const list = canvas.getByRole("tabpanel", { name: "Categorías" });
    await fingerDrag(list, { dx: -60, dy: 240, steps: 12 });
    await expect(canvas.getByRole("tab", { name: "Categorías" })).toHaveAttribute(
      "aria-selected",
      "true",
    );
    // Dragged right, anywhere on Categorías (its rows do not swipe): back to Movimientos.
    await fingerDrag(list, { dx: 260, steps: 16 });
    await waitFor(() =>
      expect(canvas.getByRole("tab", { name: "Movimientos" })).toHaveAttribute(
        "aria-selected",
        "true",
      ),
    );
  },
};

// -- The add sheet ---------------------------------------------------------------------------------

/** A recent name fills the name and picks its usual category; the other shortcuts stay. */
export const ShortcutPicksCategory: Story = {
  render: (args) => <HomeStage onRequest={args.onRequest} />,
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await hero(canvas);
    const sheet = await openAdd(canvas);
    const chips = within(sheet.getByRole("group", { name: "Categoría" }));
    const shortcuts = within(await sheet.findByRole("group", { name: "Nombres recientes" }));
    await userEvent.click(chips.getByRole("button", { name: "Ocio" }));
    await userEvent.click(await shortcuts.findByRole("button", { name: "continente" }));
    await expect(sheet.getByRole("textbox", { name: "Nombre (opcional)" })).toHaveValue(
      "continente",
    );
    await expect(chips.getByRole("button", { name: "Supermercado" })).toHaveAttribute(
      "aria-pressed",
      "true",
    );
    await expect(chips.getByRole("button", { name: "Ocio" })).toHaveAttribute(
      "aria-pressed",
      "false",
    );
    // The full list stays after a pick (the API filters only while typing).
    await expect(await shortcuts.findByRole("button", { name: "cine" })).toBeVisible();
  },
};

/** Nothing to save at 0: Guardar waits for an amount. */
export const SaveDisabledAtZero: Story = {
  render: (args) => <HomeStage onRequest={args.onRequest} />,
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await hero(canvas);
    const sheet = await openAdd(canvas);
    const save = sheet.getByRole("button", { name: "Guardar" });
    await expect(save).toBeDisabled();
    await typeAmount(sheet, "0,0");
    await expect(save).toBeDisabled();
    await typeAmount(sheet, "5");
    await expect(save).toBeEnabled();
    await userEvent.click(sheet.getByRole("button", { name: "Borrar dígito" }));
    await expect(save).toBeDisabled();
  },
};

/** Two quick taps on Guardar make one request, with the key the sheet got when it opened. */
export const DoubleClickSavesOnce: Story = {
  render: (args) => <HomeStage onRequest={args.onRequest} createDelayMs={300} />,
  play: async ({ canvasElement, args }) => {
    const canvas = within(canvasElement);
    await hero(canvas);
    const sheet = await openAdd(canvas);
    await typeAmount(sheet, "6,08");
    await pickCategory(sheet, "Supermercado");
    await userEvent.dblClick(sheet.getByRole("button", { name: "Guardar" }));
    await toastSaying(`Gasto en Supermercado: ${eur("6,08")}`);
    const sent = posts(args.onRequest);
    await expect(sent).toHaveLength(1);
    await expect(sent[0]?.[1]["idempotency-key"]).toMatch(
      /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/,
    );
    await expect(sent[0]?.[0]).toContain('"amount":-608');
    await expect(sent[0]?.[0]).toContain('"name":"Supermercado"');
  },
};

/**
 * The API fails: what is left goes back to what it was, and the error is announced with
 * Reintentar, which sends the same request again.
 */
export const FailingCreateRollsBack: Story = {
  render: (args) => <HomeStage onRequest={args.onRequest} failCreate createDelayMs={400} />,
  play: async ({ canvasElement, args }) => {
    const canvas = within(canvasElement);
    const region = await hero(canvas);
    await waitFor(() => expect(region).toHaveTextContent(eur("501,13")));
    const sheet = await openAdd(canvas);
    await typeAmount(sheet, "6,08");
    await pickCategory(sheet, "Supermercado");
    await userEvent.click(sheet.getByRole("button", { name: "Guardar" }));
    // Optimistic: it shows at once...
    await waitFor(() => expect(region).toHaveTextContent(eur("495,05")));
    // ...and goes back when the API fails.
    const failed = await toastSaying("Tuvimos un problema de nuestro lado", "alert");
    await waitFor(() => expect(region).toHaveTextContent(eur("501,13")));
    // A server error may pass: Reintentar sends the same request again (same key).
    await userEvent.click(failed.getByRole("button", { name: "Reintentar" }));
    await waitFor(() => expect(region).toHaveTextContent(eur("495,05")));
    await toastSaying("Tuvimos un problema de nuestro lado", "alert");
    await waitFor(() => expect(region).toHaveTextContent(eur("501,13")));
    const sent = posts(args.onRequest);
    await expect(sent).toHaveLength(2);
    await expect(sent[1]?.[1]["idempotency-key"]).toBe(sent[0]?.[1]["idempotency-key"]);
    await expect(sent[1]?.[0]).toBe(sent[0]?.[0]);
  },
};

/** Deshacer on the saved toast deletes what was just saved. */
export const UndoDeletes: Story = {
  render: (args) => <HomeStage onRequest={args.onRequest} />,
  play: async ({ canvasElement, args }) => {
    const canvas = within(canvasElement);
    const region = await hero(canvas);
    const sheet = await openAdd(canvas);
    await typeAmount(sheet, "6,08");
    await pickCategory(sheet, "Supermercado");
    await userEvent.click(sheet.getByRole("button", { name: "Guardar" }));
    const toast = await toastSaying(`Gasto en Supermercado: ${eur("6,08")}`);
    // Saved without a name: it can get one later.
    await expect(toast.getByRole("button", { name: "Ponerle nombre" })).toBeVisible();
    await userEvent.click(await toast.findByRole("button", { name: "Deshacer" }));
    await waitFor(() =>
      expect(calls(args.onRequest).map(([line]) => line)).toContainEqual(
        expect.stringMatching(/^DELETE \/api\/v1\/transactions\/\S+$/),
      ),
    );
    await waitFor(() => expect(region).toHaveTextContent(eur("501,13")));
    // The saved toast fades out: let it go, so the accessibility check after the story does not
    // measure its buttons half transparent.
    await waitFor(() =>
      expect(screen.queryByRole("button", { name: "Ponerle nombre" })).toBeNull(),
    );
  },
};

/** "Ponerle nombre" opens the saved transaction with the name field ready to type. */
export const NameItLater: Story = {
  render: (args) => <HomeStage onRequest={args.onRequest} />,
  play: async ({ canvasElement, args }) => {
    const canvas = within(canvasElement);
    await hero(canvas);
    const sheet = await openAdd(canvas);
    await typeAmount(sheet, "12");
    await pickCategory(sheet, "Supermercado");

    await userEvent.click(sheet.getByRole("button", { name: "Guardar" }));
    const toast = await toastSaying("Gasto en Supermercado");
    await userEvent.click(await toast.findByRole("button", { name: "Ponerle nombre" }));
    const edit = within(await screen.findByRole("dialog", { name: "Editar movimiento" }));
    const name = edit.getByRole("textbox", { name: "Nombre (opcional)" });
    await waitFor(() => expect(name).toHaveFocus());
    await userEvent.type(name, "lidl");
    await userEvent.click(edit.getByRole("button", { name: "Guardar cambios" }));
    await dialogGone();
    await waitFor(() =>
      expect(calls(args.onRequest).map(([line]) => line)).toContainEqual(
        expect.stringMatching(/^PATCH \/api\/v1\/transactions\/\S+ \{"name":"lidl"\}$/),
      ),
    );
  },
};

/**
 * A name that starts with the category's: the field shows the category name only as the
 * placeholder until it is first edited, so typing "Supermercado Éxito" never empties it at the
 * 12th character and the whole name is saved.
 */
export const NameItWithTheCategoryName: Story = {
  render: (args) => <HomeStage onRequest={args.onRequest} />,
  play: async ({ canvasElement, args }) => {
    const canvas = within(canvasElement);
    await hero(canvas);
    const sheet = await openAdd(canvas);
    await typeAmount(sheet, "12");
    await pickCategory(sheet, "Supermercado");

    await userEvent.click(sheet.getByRole("button", { name: "Guardar" }));
    const toast = await toastSaying("Gasto en Supermercado");
    await userEvent.click(await toast.findByRole("button", { name: "Ponerle nombre" }));
    const edit = within(await screen.findByRole("dialog", { name: "Editar movimiento" }));
    const name = edit.getByRole("textbox", { name: "Nombre (opcional)" });
    await waitFor(() => expect(name).toHaveFocus());
    await expect(name).toHaveValue("");
    await userEvent.type(name, "Supermercado Éxito");
    await expect(name).toHaveValue("Supermercado Éxito");
    await userEvent.click(edit.getByRole("button", { name: "Guardar cambios" }));
    await dialogGone();
    await waitFor(() =>
      expect(calls(args.onRequest).map(([line]) => line)).toContainEqual(
        expect.stringMatching(
          /^PATCH \/api\/v1\/transactions\/\S+ \{"name":"Supermercado Éxito"\}$/,
        ),
      ),
    );
  },
};

/** An income: the toggle, the income categories, and its own words in the toast. */
export const AddIncome: Story = {
  render: (args) => <HomeStage onRequest={args.onRequest} />,
  play: async ({ canvasElement, args }) => {
    const canvas = within(canvasElement);
    await hero(canvas);
    const sheet = await openAdd(canvas);
    await userEvent.click(sheet.getByRole("tab", { name: "Ingreso" }));
    const income = within(await screen.findByRole("dialog", { name: "Nuevo ingreso" }));
    const chips = within(income.getByRole("group", { name: "Categoría" }));
    await expect(chips.getByRole("button", { name: "Salario" })).toHaveAttribute(
      "aria-pressed",
      "true",
    );
    await expect(chips.queryByRole("button", { name: "Supermercado" })).toBeNull();
    await typeAmount(income, "100");
    await userEvent.click(income.getByRole("button", { name: "Guardar" }));
    await toastSaying(`Ingreso de Salario: ${eur("100,00")}`);
    await expect(posts(args.onRequest)[0]?.[0]).toContain('"amount":10000');
  },
};

/**
 * "Más opciones": opened, it shows the date (today) and pending, with the note under them. The
 * story rests with the sheet open on them (the mobile parity picture of it); `MoreOptionsSent`
 * saves.
 */
export const MoreOptions: Story = {
  render: (args) => <HomeStage onRequest={args.onRequest} />,
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await hero(canvas);
    const sheet = await openAdd(canvas);
    await typeAmount(sheet, "39,9");
    await pickCategory(sheet, "Supermercado");

    const more = sheet.getByRole("button", { name: /^Más opciones/ });
    await expect(more).toHaveAttribute("aria-expanded", "false");
    await userEvent.click(more);
    await expect(more).toHaveAttribute("aria-expanded", "true");
    await userEvent.click(sheet.getByRole("checkbox", { name: "Pendiente (aún no lo pagas)" }));
    await expect(sheet.getByLabelText("Fecha")).toHaveValue(
      new Intl.DateTimeFormat("en-CA", { timeZone: "Europe/Madrid" }).format(new Date()),
    );
    await expect(sheet.getByRole("textbox", { name: "Nota (opcional)" })).toBeVisible();
  },
};

/** "Más opciones": another date and pending, kept in what is sent. */
export const MoreOptionsSent: Story = {
  render: (args) => <HomeStage onRequest={args.onRequest} />,
  play: async ({ canvasElement, args }) => {
    const canvas = within(canvasElement);
    await hero(canvas);
    const sheet = await openAdd(canvas);
    await typeAmount(sheet, "39,9");
    await pickCategory(sheet, "Supermercado");

    const more = sheet.getByRole("button", { name: /^Más opciones/ });
    await expect(more).toHaveAttribute("aria-expanded", "false");
    await userEvent.click(more);
    await userEvent.click(sheet.getByRole("checkbox", { name: "Pendiente (aún no lo pagas)" }));
    const date = sheet.getByLabelText("Fecha");
    await expect(date).toHaveValue(
      new Intl.DateTimeFormat("en-CA", { timeZone: "Europe/Madrid" }).format(new Date()),
    );
    await userEvent.click(sheet.getByRole("button", { name: "Guardar" }));
    await toastSaying("Gasto en Supermercado");
    await expect(posts(args.onRequest)[0]?.[0]).toContain('"status":"pending"');
  },
};

/**
 * "Más opciones" → "Repetir": every year, and the row says so; the save carries the recurrence
 * (made by the API from this movement, which stays paid). An end before the date is refused.
 */
export const MoreOptionsRepeat: Story = {
  render: (args) => <HomeStage onRequest={args.onRequest} />,
  play: async ({ canvasElement, args }) => {
    const canvas = within(canvasElement);
    await hero(canvas);
    const sheet = await openAdd(canvas);
    await typeAmount(sheet, "39,9");
    await pickCategory(sheet, "Supermercado");

    const more = sheet.getByRole("button", { name: /^Más opciones/ });
    await userEvent.click(more);
    await userEvent.click(sheet.getByRole("checkbox", { name: "Repetir" }));
    await userEvent.click(sheet.getByRole("tab", { name: "Cada año" }));
    await expect(more).toHaveTextContent("Cada año");
    await expect(sheet.getByText(/Los siguientes llegan como pendientes/)).toBeVisible();

    const end = sheet.getByLabelText("Hasta (opcional)");
    await userEvent.type(end, "2000-01-01");
    await expect(sheet.getByRole("alert")).toHaveTextContent("La fecha final va después");
    await expect(sheet.getByRole("button", { name: "Guardar" })).toBeDisabled();
    await userEvent.clear(end);

    await userEvent.click(sheet.getByRole("button", { name: "Guardar" }));
    await toastSaying("Gasto en Supermercado");
    const sent = posts(args.onRequest)[0]?.[0] ?? "";
    await expect(sent).toContain('"status":"paid"');
    await expect(sent).toContain('"repeat":{"frequency":"yearly","endDate":null}');
  },
};

/**
 * The same screens in Italian and European Portuguese, at night: the longer words of the tabs, the
 * bottom bar and the sheet's buttons (spec §3), and the mobile parity picture of each.
 */
const WORDS = {
  it: {
    remaining: "Ti restano questo mese",
    movements: "Movimenti",
    add: "Aggiungi",
    sheet: "Nuova spesa",
    keypad: "Tastierino numerico",
    decimal: "Virgola decimale",
    category: "Categoria",
    more: /^Altre opzioni/,
    pending: "In sospeso (non l'hai ancora pagato)",
  },
  pt: {
    remaining: "Restam-te este mês",
    movements: "Movimentos",
    add: "Adicionar",
    sheet: "Nova despesa",
    keypad: "Teclado numérico",
    decimal: "Vírgula decimal",
    category: "Categoria",
    more: /^Mais opções/,
    pending: "Pendente (ainda não pagaste)",
  },
} as const;

function transactionsIn(locale: keyof typeof WORDS): Story {
  const w = WORDS[locale];
  return {
    globals: { theme: "night", locale },
    render: (args) => <HomeStage onRequest={args.onRequest} />,
    play: async ({ canvasElement }) => {
      const canvas = within(canvasElement);
      await canvas.findByRole("region", { name: w.remaining });
      await userEvent.click(canvas.getByRole("tab", { name: w.movements }));
      await canvas.findByRole("tabpanel", { name: w.movements });
    },
  };
}

function moreOptionsIn(locale: keyof typeof WORDS): Story {
  const w = WORDS[locale];
  return {
    globals: { theme: "night", locale },
    render: (args) => <HomeStage onRequest={args.onRequest} />,
    play: async ({ canvasElement }) => {
      const canvas = within(canvasElement);
      await canvas.findByRole("region", { name: w.remaining });
      await userEvent.click(await canvas.findByRole("button", { name: w.add }));
      const sheet = within(await screen.findByRole("dialog", { name: w.sheet }));
      const keypad = within(sheet.getByRole("group", { name: w.keypad }));
      for (const key of "39,9") {
        await userEvent.click(keypad.getByRole("button", { name: key === "," ? w.decimal : key }));
      }
      await userEvent.click(
        within(sheet.getByRole("group", { name: w.category })).getByRole("button", {
          name: "Supermercado",
        }),
      );
      const more = sheet.getByRole("button", { name: w.more });
      await userEvent.click(more);
      await expect(more).toHaveAttribute("aria-expanded", "true");
      await userEvent.click(sheet.getByRole("checkbox", { name: w.pending }));
    },
  };
}

export const TransactionsItalian: Story = transactionsIn("it");
export const TransactionsPortuguese: Story = transactionsIn("pt");
export const MoreOptionsItalian: Story = moreOptionsIn("it");
export const MoreOptionsPortuguese: Story = moreOptionsIn("pt");

/** In pesos the sheet adds the lukas hint, small, and so does the saved toast. */
export const PesosHint: Story = {
  render: (args) => <HomeStage onRequest={args.onRequest} currency="COP" />,
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await hero(canvas);
    const sheet = await openAdd(canvas);
    await typeAmount(sheet, "50000");
    const amount = sheet.getByTestId("amount");
    await expect(amount).toHaveTextContent("$50.000 (50 lukas)");
    await expect(within(amount).getByText("(50 lukas)")).toHaveClass("text-ink-muted");
    await userEvent.click(sheet.getByRole("button", { name: "Guardar" }));
    await toastSaying("Gasto en Comida: $50.000 (50 lukas)");
  },
};

/** Tapping a row edits it; Eliminar removes it with Deshacer, which brings it back. */
export const EditAndDelete: Story = {
  render: (args) => <HomeStage onRequest={args.onRequest} />,
  play: async ({ canvasElement, args }) => {
    const canvas = within(canvasElement);
    await hero(canvas);
    await userEvent.click(canvas.getByRole("tab", { name: "Movimientos" }));
    const panel = within(canvas.getByRole("tabpanel", { name: "Movimientos" }));
    await userEvent.click(await panel.findByRole("button", { name: /^cine/ }));
    const edit = within(await screen.findByRole("dialog", { name: "Editar movimiento" }));
    await expect(edit.getByTestId("amount")).toHaveTextContent(eur("262,80"));
    await expect(
      within(edit.getByRole("group", { name: "Categoría" })).getByRole("button", { name: "Ocio" }),
    ).toHaveAttribute("aria-pressed", "true");
    await userEvent.click(edit.getByRole("button", { name: "Eliminar" }));
    await dialogGone();
    const toast = await toastSaying("Eliminado: cine");
    await waitFor(() => expect(panel.queryByRole("button", { name: /^cine/ })).toBeNull());
    await userEvent.click(toast.getByRole("button", { name: "Deshacer" }));
    // The "De vuelta" toast replaces the first: wait until it has finished fading in, or axe
    // reads its text mid-fade (1.14:1) when the story ends.
    await toastSaying("De vuelta: cine");
    // It slides back in (unfolding from nothing), then it is fully there.
    const back = await panel.findByRole("button", { name: /^cine/ });
    await waitFor(() => expect(back).toBeVisible());
    const lines = calls(args.onRequest).map(([line]) => line);
    await expect(lines).toContainEqual(expect.stringMatching(/^DELETE /));
    await expect(lines).toContainEqual(expect.stringMatching(/\/restore$/));
  },
};

// -- Empty states and the rest ------------------------------------------------------------------------

/**
 * A new account that skipped the setup: no budgets, no transactions. What was spent instead of
 * what is left, an invitation to the first entry, and two gentle nudges.
 */
export const EmptyMonth: Story = {
  render: (args) => <HomeStage onRequest={args.onRequest} data="empty" />,
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    const region = await canvas.findByRole("region", { name: "Gastado este mes" });
    await expect(region).toHaveTextContent(eur("0,00"));
    await expect(await canvas.findByText("Ponle presupuesto a tus categorías")).toBeVisible();
    await expect(await canvas.findByText("Trae tu historial")).toBeVisible();
    // The history card leads to the import; the budgets card to the categories.
    await expect(canvas.getByRole("link", { name: "Traer mi historial" })).toHaveAttribute(
      "href",
      "/app/import",
    );
    // The budgets card opens the Categorías tab, where the categories are managed.
    const toCategories = canvas.getByRole("link", { name: "Ir a Categorías" });
    await expect(toCategories).toHaveAttribute("href", "/app");
    await userEvent.click(toCategories);
    await expect(canvas.getByRole("tab", { name: "Categorías" })).toHaveAttribute(
      "aria-selected",
      "true",
    );
    await userEvent.click(canvas.getByRole("button", { name: "Ahora no: Trae tu historial" }));
    await waitFor(() => expect(canvas.queryByText("Trae tu historial")).toBeNull());
    await userEvent.click(canvas.getByRole("tab", { name: "Movimientos" }));
    const panel = within(canvas.getByRole("tabpanel", { name: "Movimientos" }));
    await expect(panel.getByText(/Aún no hay movimientos/)).toBeVisible();
    await userEvent.click(panel.getByRole("button", { name: "Agregar gasto" }));
    const sheet = await screen.findByRole("dialog", { name: "Nuevo gasto" });
    await expect(sheet).toBeVisible();
    // Closed again: the story rests on the empty month itself (the mobile parity picture of it).
    await userEvent.click(within(sheet).getByRole("button", { name: "Cerrar" }));
    await dialogGone();
  },
};

/** No categories at all (everything deselected in the setup): one tap brings the suggestions. */
export const NoCategories: Story = {
  render: (args) => <HomeStage onRequest={args.onRequest} data="no-categories" />,
  play: async ({ canvasElement, args }) => {
    const canvas = within(canvasElement);
    const use = await canvas.findByRole("button", { name: "Usar las sugeridas" });
    await userEvent.click(use);
    await waitFor(() =>
      expect(
        calls(args.onRequest).filter(([line]) => line.startsWith("POST /api/v1/categories")),
      ).toHaveLength(8),
    );
    // The tabs come back once the new categories are read again: wait for them, not a moment.
    await userEvent.click(
      await canvas.findByRole("tab", { name: "Categorías" }, { timeout: 5000 }),
    );
    await expect(await canvas.findByRole("button", { name: /^Supermercado/ })).toBeVisible();
  },
};

/** Day theme: the a11y checks (contrast included) run on the whole screen. */
export const DayTheme: Story = {
  globals: { theme: "day" },
  render: (args) => <HomeStage onRequest={args.onRequest} />,
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    const region = await hero(canvas);
    await waitFor(() => expect(region).toHaveTextContent(eur("501,13")));
    await userEvent.click(canvas.getByRole("tab", { name: "Movimientos" }));
    await canvas.findAllByRole("region", { name: /^Hoy/ });
  },
};

/** The sheet in day theme, open, for the a11y checks. */
export const SheetDayTheme: Story = {
  globals: { theme: "day" },
  render: (args) => <HomeStage onRequest={args.onRequest} currency="COP" />,
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await hero(canvas);
    const sheet = await openAdd(canvas);
    await typeAmount(sheet, "15500");
    await expect(sheet.getByTestId("amount")).toHaveTextContent("$15.500 (15,5 lukas)");
    await expectPressableKeys(sheet);
  },
};

/**
 * The keys stand apart from the white sheet by day (a 3:1 outline, not a faint underline), and a
 * pressed key both sinks and darkens.
 */
async function expectPressableKeys(sheet: Canvas) {
  const keys = within(sheet.getByRole("group", { name: "Teclado numérico" })).getAllByRole(
    "button",
  );
  for (const key of keys) await expectBoundaryContrast(key);
  const five = sheet.getByRole("button", { name: "5" });
  const face = getComputedStyle(five).backgroundColor;
  await expect(contrastRatio(face, backgroundBehind(five.parentElement))).toBeGreaterThan(1.05);
  five.classList.add("is-pressed");
  await expectSunk(five, 3);
  await expect(getComputedStyle(five).backgroundColor).not.toBe(face);
  five.classList.remove("is-pressed");
}

/** The edit sheet by day, on the pending Spotify: keys, Eliminar and "Más opciones" stand out. */
export const EditSheetDayTheme: Story = {
  globals: { theme: "day" },
  render: (args) => <HomeStage onRequest={args.onRequest} />,
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await hero(canvas);
    await userEvent.click(canvas.getByRole("tab", { name: "Movimientos" }));
    const panel = within(canvas.getByRole("tabpanel", { name: "Movimientos" }));
    await userEvent.click(await panel.findByRole("button", { name: /^Spotify/ }));
    const edit = within(await screen.findByRole("dialog", { name: "Editar movimiento" }));
    await expect(edit.getByRole("button", { name: /^Más opciones/ })).toHaveTextContent(
      "Pendiente",
    );
    await expectPressableKeys(edit);
    await expectBoundaryContrast(edit.getByRole("button", { name: "Eliminar" }));
    await expectBoundaryContrast(edit.getByRole("button", { name: /^Más opciones/ }));
  },
};

/** The avatar menu: the theme switch, sign-out, and the sections that live there. */
export const AvatarMenu: Story = {
  render: (args) => <HomeStage onRequest={args.onRequest} />,
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await hero(canvas);
    const avatar = canvas.getByRole("button", { name: "Tu cuenta" });
    await expect(avatar).toHaveAttribute("aria-expanded", "false");
    await userEvent.click(avatar);
    await expect(avatar).toHaveAttribute("aria-expanded", "true");
    await expect(canvas.getByRole("button", { name: "Cambiar a modo día" })).toBeVisible();
    await expect(canvas.getByRole("button", { name: "Cerrar sesión" })).toBeVisible();
    const menu = within(canvasElement.querySelector(".lk-menu") as HTMLElement);
    await expect(menu.getByRole("link", { name: "Ajustes" })).toHaveAttribute(
      "href",
      "/app/settings",
    );
    await expect(menu.queryByText("Pronto")).toBeNull();
    await expectTarget(menu.getByRole("link", { name: "Categorías" }));
    await expect(menu.getByRole("link", { name: "Recurrentes" })).toHaveAttribute(
      "href",
      "/app/recurring",
    );
    await userEvent.keyboard("{Escape}");
    await expect(avatar).toHaveAttribute("aria-expanded", "false");
    await expect(avatar).toHaveFocus();
    // From the menu to the Categorías tab (categories have no page of their own).
    await userEvent.click(avatar);
    await expect(menu.getByRole("link", { name: "Categorías" })).toHaveAttribute("href", "/app");
    await userEvent.click(menu.getByRole("link", { name: "Categorías" }));
    await expect(avatar).toHaveAttribute("aria-expanded", "false");
    await expect(await canvas.findByRole("tab", { name: "Categorías" })).toHaveAttribute(
      "aria-selected",
      "true",
    );
    await expect(
      await within(canvas.getByRole("tabpanel", { name: "Categorías" })).findByRole("button", {
        name: "Nueva categoría",
      }),
    ).toBeVisible();
  },
};

/** A budget row opens that category's detail, in the month on screen. */
export const BudgetRowOpensDetail: Story = {
  render: (args) => <HomeStage onRequest={args.onRequest} />,
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await hero(canvas);
    await userEvent.click(canvas.getByRole("tab", { name: "Categorías" }));
    const panel = within(canvas.getByRole("tabpanel", { name: "Categorías" }));
    await userEvent.click(await panel.findByRole("button", { name: /^Ocio/ }));
    await expect(await canvas.findByRole("heading", { level: 1, name: "Ocio" })).toBeVisible();
    await expect(screen.queryByRole("dialog")).toBeNull();
    await expect(await canvas.findByRole("region", { name: "Presupuesto" })).toHaveTextContent(
      /Quedan/,
    );
    // And back to the tab it came from.
    await userEvent.click(canvas.getByRole("link", { name: "Volver a Categorías" }));
    await hero(canvas);
    await expect(canvas.getByRole("tab", { name: "Categorías" })).toHaveAttribute(
      "aria-selected",
      "true",
    );
  },
};

/** Wide screens: the sidebar instead of the bottom bar, and both lists side by side. */
export const Desktop: Story = {
  globals: { viewport: { value: "desktop", isRotated: false } },
  render: (args) => <HomeStage onRequest={args.onRequest} />,
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await hero(canvas);
    await expect(canvas.queryByRole("tab", { name: "Movimientos" })).toBeNull();
    const budgets = canvas.getByRole("tabpanel", { name: "Categorías" });
    const transactions = canvas.getByRole("tabpanel", { name: "Movimientos" });
    await expect(budgets).toBeVisible();
    await expect(transactions).toBeVisible();
    // Movimientos first: on the left.
    await expect(transactions.getBoundingClientRect().left).toBeLessThan(
      budgets.getBoundingClientRect().left,
    );
    const nav = within(canvas.getByRole("navigation", { name: "Navegación principal" }));
    await expect(nav.getByRole("link", { name: "Inicio" })).toHaveAttribute("aria-current", "page");
    // Categories are managed in home's Categorías list, beside Movimientos.
    await expect(nav.getByRole("link", { name: "Categorías" })).toHaveAttribute("href", "/app");
    await expect(nav.getByRole("link", { name: "Recurrentes" })).toHaveAttribute(
      "href",
      "/app/recurring",
    );
    await expect(nav.getByRole("link", { name: "Análisis" })).toHaveAttribute(
      "href",
      "/app/insights",
    );
    await expect(nav.getByRole("link", { name: "Ajustes" })).toHaveAttribute(
      "href",
      "/app/settings",
    );
    await expect(nav.queryByText("Pronto")).toBeNull();
    await userEvent.click(nav.getByRole("button", { name: "Agregar" }));
    await expect(await screen.findByRole("dialog", { name: "Nuevo gasto" })).toBeVisible();
  },
};

/** Opens the Categorías tab and returns its panel. */
async function categoriesPanel(canvas: Canvas) {
  await hero(canvas);
  await userEvent.click(canvas.getByRole("tab", { name: "Categorías" }));
  return within(canvas.getByRole("tabpanel", { name: "Categorías" }));
}

/** Ingresos: the income categories, each with "Ingreso" and no bar; the spending ones are gone. */
export const CategoriesIncome: Story = {
  render: (args) => <HomeStage onRequest={args.onRequest} />,
  play: async ({ canvasElement }) => {
    const panel = await categoriesPanel(within(canvasElement));
    await userEvent.click(panel.getByRole("tab", { name: "Ingresos" }));
    await expect(panel.getByRole("tab", { name: "Ingresos" })).toHaveAttribute(
      "aria-selected",
      "true",
    );
    await expect(await panel.findByRole("button", { name: "Salario Ingreso" })).toBeVisible();
    await expect(panel.queryByRole("button", { name: /^Supermercado/ })).toBeNull();
    await expect(panel.queryByRole("meter")).toBeNull();
    await expectTarget(panel.getByRole("button", { name: "Nueva categoría" }));
  },
};

/**
 * Archivadas: folded at the end of its kind's list, with "Restaurar" on each; restoring one
 * brings it back among the others.
 */
export const CategoriesArchived: Story = {
  render: (args) => <HomeStage onRequest={args.onRequest} archivedUnused />,
  play: async ({ canvasElement, args }) => {
    const panel = await categoriesPanel(within(canvasElement));
    const fold = await panel.findByRole("button", { name: "Archivadas (1)" });
    await expect(fold).toHaveAttribute("aria-expanded", "false");
    await expectTarget(fold);
    await expect(panel.queryByRole("region", { name: "Archivadas" })).toBeNull();
    await userEvent.click(fold);
    await expect(fold).toHaveAttribute("aria-expanded", "true");
    const archived = within(panel.getByRole("region", { name: "Archivadas" }));
    await expect(archived.getByRole("button", { name: "Transporte Archivada" })).toBeVisible();
    await expectTarget(archived.getByRole("button", { name: "Restaurar Transporte" }));
    await userEvent.click(archived.getByRole("button", { name: "Restaurar Transporte" }));
    await waitFor(() =>
      expect(calls(args.onRequest).map(([line]) => line)).toContainEqual(
        'PATCH /api/v1/categories/cat-transport {"archived":false}',
      ),
    );
    await expect(
      await panel.findByRole("button", { name: /^Transporte Sin presupuesto/ }),
    ).toBeVisible();
    await waitFor(() => expect(panel.queryByRole("button", { name: /^Archivadas/ })).toBeNull());
    await toastSaying("Transporte está de vuelta.");
  },
};

/**
 * Ingresos with every income category archived: nothing active to list, and the archived one
 * unfolded, as they rest (the mobile parity picture of the fold).
 */
export const CategoriesArchivedOpen: Story = {
  render: (args) => <HomeStage onRequest={args.onRequest} archivedIncome />,
  play: async ({ canvasElement }) => {
    const panel = await categoriesPanel(within(canvasElement));
    await userEvent.click(panel.getByRole("tab", { name: "Ingresos" }));
    await expect(await panel.findByText("Aún no tienes categorías de este tipo.")).toBeVisible();
    await userEvent.click(await panel.findByRole("button", { name: "Archivadas (1)" }));
    await expect(
      within(await panel.findByRole("region", { name: "Archivadas" })).getByRole("button", {
        name: "Salario Archivada",
      }),
    ).toBeVisible();
  },
};

/**
 * A category archived this month that still has spending in the month on screen stays among the
 * month's rows, with its "archivada" note, so the rows add up to what home says was spent. It does
 * not wait in "Archivadas".
 */
export const CategoriesArchivedWithSpending: Story = {
  render: (args) => <HomeStage onRequest={args.onRequest} archivedCategory />,
  play: async ({ canvasElement }) => {
    const panel = await categoriesPanel(within(canvasElement));
    const row = await panel.findByRole("button", {
      name: "Transporte · archivada Sin presupuesto",
    });
    await expect(row).toBeVisible();
    // Its spending is on the row, as the old budget list showed it.
    await expect(row.closest(".lk-row")).toHaveTextContent(`Gastado ${eur("15,00")}`);
    // Nothing else is archived: no fold.
    await expect(panel.queryByRole("button", { name: /^Archivadas/ })).toBeNull();
  },
};

/**
 * The old `/app/categories` address (bookmarks, history, older links) is not a 404: it opens home
 * on its Categorías tab.
 */
export const OldCategoriesAddress: Story = {
  render: (args) => <HomeStage onRequest={args.onRequest} path="/app/categories" />,
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await hero(canvas);
    await expect(canvas.getByRole("tab", { name: "Categorías" })).toHaveAttribute(
      "aria-selected",
      "true",
    );
    await expect(canvas.getByRole("tabpanel", { name: "Categorías" })).toBeVisible();
  },
};

/** "Nueva categoría": name, kind, emoji and tint; it joins the list. */
export const CreateCategory: Story = {
  render: (args) => <HomeStage onRequest={args.onRequest} />,
  play: async ({ canvasElement, args }) => {
    const panel = await categoriesPanel(within(canvasElement));
    await userEvent.click(panel.getByRole("button", { name: "Nueva categoría" }));
    const sheet = within(await screen.findByRole("dialog", { name: "Nueva categoría" }));
    // Nothing to type yet: a name is asked for.
    await userEvent.click(sheet.getByRole("button", { name: "Guardar categoría" }));
    await expect(await sheet.findByRole("alert")).toHaveTextContent(
      "Escribe un nombre para la categoría.",
    );
    await userEvent.type(sheet.getByRole("textbox", { name: "Nombre" }), "Mascotas");
    await userEvent.click(sheet.getByRole("radio", { name: "🐶" }));
    await userEvent.click(sheet.getByRole("button", { name: "Guardar categoría" }));
    await dialogGone();
    await waitFor(() =>
      expect(calls(args.onRequest).map(([line]) => line)).toContainEqual(
        expect.stringMatching(/^POST \/api\/v1\/categories .*"name":"Mascotas"/),
      ),
    );
    await expect(
      await panel.findByRole("button", { name: /^Mascotas Sin presupuesto/ }),
    ).toBeVisible();
    await toastSaying("Listo: creaste Mascotas.");
  },
};

/** A name already in use is refused in the sheet, which stays open. */
export const CreateCategoryNameTaken: Story = {
  render: (args) => <HomeStage onRequest={args.onRequest} />,
  play: async ({ canvasElement }) => {
    const panel = await categoriesPanel(within(canvasElement));
    await userEvent.click(panel.getByRole("button", { name: "Nueva categoría" }));
    const sheet = within(await screen.findByRole("dialog", { name: "Nueva categoría" }));
    await userEvent.type(sheet.getByRole("textbox", { name: "Nombre" }), "Ocio");
    await userEvent.click(sheet.getByRole("button", { name: "Guardar categoría" }));
    await expect(await sheet.findByRole("alert")).toBeVisible();
    await expect(screen.getByRole("dialog", { name: "Nueva categoría" })).toBeVisible();
  },
};

/** The new-category sheet, as it opens (the mobile parity picture of it). */
export const NewCategorySheet: Story = {
  render: (args) => <HomeStage onRequest={args.onRequest} />,
  play: async ({ canvasElement }) => {
    const panel = await categoriesPanel(within(canvasElement));
    await userEvent.click(panel.getByRole("button", { name: "Nueva categoría" }));
    const sheet = within(await screen.findByRole("dialog", { name: "Nueva categoría" }));
    await expect(sheet.getByRole("textbox", { name: "Nombre" })).toHaveValue("");
    await expect(sheet.getByRole("radio", { name: "Gasto" })).toBeChecked();
    await expect(sheet.queryByRole("button", { name: "Archivar categoría" })).toBeNull();
  },
};

/**
 * Already on home, wide: both lists are in view, so the sidebar's "Categorías" cannot switch to
 * anything. It moves focus to the Categorías panel and scrolls it to the top instead.
 */
export const SidebarCategoriesFocusesPanel: Story = {
  globals: { viewport: { value: "desktop", isRotated: false } },
  render: (args) => <HomeStage onRequest={args.onRequest} data="october" />,
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await hero(canvas);
    const panel = canvas.getByRole("tabpanel", { name: "Categorías" });
    // A long month: the page scrolls, and the panel starts below the summary.
    await expect(panel.getBoundingClientRect().top).toBeGreaterThan(200);
    await expect(panel).not.toHaveFocus();
    const nav = within(canvas.getByRole("navigation", { name: "Navegación principal" }));
    await userEvent.click(nav.getByRole("link", { name: "Categorías" }));
    await waitFor(() => expect(panel).toHaveFocus());
    await waitFor(() => expect(panel.getBoundingClientRect().top).toBeLessThan(40), {
      timeout: 5000,
    });
    // Both lists stay side by side, and the link is still the way back after scrolling away.
    await expect(canvas.getByRole("tabpanel", { name: "Movimientos" })).toBeVisible();
  },
};

/** Wide screens, by day: the sidebar and both lists, with the archived ones unfolded. */
export const CategoriesDesktopDay: Story = {
  globals: { viewport: { value: "desktop", isRotated: false }, theme: "day" },
  render: (args) => <HomeStage onRequest={args.onRequest} archivedUnused />,
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await hero(canvas);
    const panel = within(canvas.getByRole("tabpanel", { name: "Categorías" }));
    await userEvent.click(await panel.findByRole("button", { name: "Archivadas (1)" }));
    await expect(await panel.findByRole("region", { name: "Archivadas" })).toBeVisible();
  },
};

// -- Fix round 1 -----------------------------------------------------------------------------------

/**
 * A transaction in an archived category keeps its category everywhere: named in its row, a
 * budget row while it has spending, and selected (marked "archivada") when edited. Editing only
 * the note never moves it; new transactions are offered only active categories.
 */
export const ArchivedCategory: Story = {
  render: (args) => <HomeStage onRequest={args.onRequest} archivedCategory />,
  play: async ({ canvasElement, args }) => {
    const canvas = within(canvasElement);
    await hero(canvas);
    await userEvent.click(canvas.getByRole("tab", { name: "Categorías" }));
    const budgets = within(canvas.getByRole("tabpanel", { name: "Categorías" }));
    // Archived with spending this month, it stays among the month's rows, noted "archivada".
    await budgets.findByRole("button", { name: /^Restaurante/ });
    await expect(await budgets.findByRole("button", { name: /^Transporte/ })).toHaveAccessibleName(
      "Transporte · archivada Sin presupuesto",
    );
    await expect(budgets.queryByRole("button", { name: /^Archivadas/ })).toBeNull();

    await userEvent.click(canvas.getByRole("tab", { name: "Movimientos" }));
    const panel = within(canvas.getByRole("tabpanel", { name: "Movimientos" }));
    const taxi = await panel.findByRole("button", { name: /^taxi −15,00\s€ Transporte$/ });
    await userEvent.click(taxi);
    const edit = within(await screen.findByRole("dialog", { name: "Editar movimiento" }));
    const chips = within(edit.getByRole("group", { name: "Categoría" }));
    await expect(chips.getByRole("button", { name: "Transporte archivada" })).toHaveAttribute(
      "aria-pressed",
      "true",
    );
    await userEvent.click(edit.getByRole("button", { name: /^Más opciones/ }));
    await userEvent.type(edit.getByRole("textbox", { name: "Nota (opcional)" }), "aeropuerto");
    await userEvent.click(edit.getByRole("button", { name: "Guardar cambios" }));
    await dialogGone();
    await waitFor(() =>
      expect(calls(args.onRequest).map(([line]) => line)).toContainEqual(
        expect.stringMatching(/^PATCH \/api\/v1\/transactions\/\S+ \{"note":"aeropuerto"\}$/),
      ),
    );
    // The toast fully in before the a11y run: half-faded text fails contrast on a slow machine.
    await toastSaying("Cambios guardados: taxi");

    // A new transaction is never put in an archived category.
    const sheet = await openAdd(canvas);
    await expect(
      within(sheet.getByRole("group", { name: "Categoría" })).queryByRole("button", {
        name: /Transporte/,
      }),
    ).toBeNull();
    // Opening the sheet fades the toast out: let it finish before the a11y run, or a half-faded
    // toast fails its contrast check on a slow machine.
    await waitFor(
      () =>
        expect(
          [...document.querySelectorAll<HTMLElement>(".lk-toast")].every(
            (toast) => getComputedStyle(toast).opacity === "1",
          ),
        ).toBe(true),
      { timeout: 5000 },
    );
  },
};

/** Pesos from a keyboard: "." is a thousands separator, there is no decimal key, and a paste works. */
export const PesosKeyboardAndPaste: Story = {
  render: (args) => <HomeStage onRequest={args.onRequest} currency="COP" />,
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await hero(canvas);
    const sheet = await openAdd(canvas);
    await expect(sheet.queryByRole("button", { name: "Coma decimal" })).toBeNull();
    await userEvent.keyboard("15.000,5");
    const amount = sheet.getByTestId("amount");
    // The comma ends a peso amount: the 5 after it does not count.
    await expect(amount).toHaveTextContent("$15.000 (15 lukas)");
    // Screen readers hear the amount once typing pauses.
    await waitFor(() =>
      expect(
        sheet.getByText("−$15.000 (15 lukas)", { selector: "[aria-live]" }),
      ).toBeInTheDocument(),
    );
    for (let i = 0; i < 6; i += 1) await userEvent.keyboard("{Backspace}");
    const clipboard = new DataTransfer();
    clipboard.setData("text/plain", "$4.300.000");
    document.body.dispatchEvent(
      new ClipboardEvent("paste", { clipboardData: clipboard, bubbles: true, cancelable: true }),
    );
    await waitFor(() => expect(amount).toHaveTextContent("$4.300.000 (4,3 palos)"));
    // Ten million pesos and more fit.
    await userEvent.keyboard("0");
    await expect(amount).toHaveTextContent("$43.000.000");
  },
};

/** Guardar stays in view on short phones, with the amount; the content scrolls between them. */
export const ShortPhone: Story = {
  globals: { viewport: { value: "short", isRotated: false } },
  render: (args) => <HomeStage onRequest={args.onRequest} />,
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await hero(canvas);
    const sheet = await openAdd(canvas);
    await typeAmount(sheet, "6");
    const save = sheet.getByRole("button", { name: "Guardar" });
    const inView = (element: HTMLElement) => {
      const box = element.getBoundingClientRect();
      return box.top >= 0 && box.bottom <= window.innerHeight;
    };
    await waitFor(() => expect(inView(save)).toBe(true));
    // Scrolled to the top (the amount) or to the bottom (the keypad), Guardar is still there.
    const dialog = screen.getByRole("dialog");
    dialog.scrollTop = dialog.scrollHeight;
    await waitFor(() => expect(inView(save)).toBe(true));
    await expect(inView(sheet.getByRole("button", { name: "0" }))).toBe(true);
    // Tab order still ends on Guardar, then wraps to the first control.
    save.focus();
    await userEvent.tab();
    await expect(sheet.getByRole("button", { name: "Cerrar" })).toHaveFocus();
  },
};

/** The same on a 375×667 phone. */
export const SmallPhone: Story = {
  ...ShortPhone,
  globals: { viewport: { value: "se", isRotated: false } },
};

/** Sign-out that fails stays here with an error; one that works goes to sign-in. */
export const SignOut: Story = {
  render: (args) => {
    let attempts = 0;
    return (
      <HomeStage
        onRequest={args.onRequest}
        signOut={async () => {
          attempts += 1;
          return { error: attempts === 1 ? { status: 500 } : null };
        }}
      />
    );
  },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await hero(canvas);
    await userEvent.click(canvas.getByRole("button", { name: "Tu cuenta" }));
    await userEvent.click(canvas.getByRole("button", { name: "Cerrar sesión" }));
    await toastSaying("No pudimos cerrar tu sesión. Inténtalo de nuevo.", "alert");
    await expect(canvas.queryByText("Sign-in (stand-in)")).toBeNull();
    await expect(canvas.getByRole("region", { name: "Te quedan este mes" })).toBeVisible();
    await userEvent.click(canvas.getByRole("button", { name: "Cerrar sesión" }));
    await expect(await canvas.findByText("Sign-in (stand-in)")).toBeVisible();
  },
};
