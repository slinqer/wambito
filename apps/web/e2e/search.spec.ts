import { expect, type Page, test } from "@playwright/test";

/**
 * The search screen on the demo (`/demo/search`, no API): type a name and its rows and the totals
 * line show, Ingresos hides the expenses, a row opens the edit sheet and deleting it lowers the
 * count, and leaving for Home and coming back restores the filters from the URL.
 */

test.beforeEach(async ({ page }) => {
  await page.clock.setFixedTime(new Date("2026-10-21T18:00:00Z"));
});

/** The movements count in the totals line ("12 movimientos · gastos … · ingresos …"). */
async function count(page: Page): Promise<number> {
  const totals = page.getByTestId("search-totals");
  await expect(totals).toContainText(/\d+ movimientos?/);
  return Number(/(\d+) movimientos?/.exec((await totals.textContent()) ?? "")?.[1]);
}

test("es: search by name, filter by kind, delete a row, and the URL keeps the filters", async ({
  page,
}) => {
  await page.goto("/demo/search?lang=es");
  await expect(page).toHaveTitle("Demo · Buscar · Wambito");
  await expect(page.getByRole("heading", { name: "Buscar", level: 1 })).toBeVisible();
  await expect(page.getByText("Busca por nombre, nota, categoría…")).toBeVisible();

  await page.getByRole("searchbox", { name: "Busca por nombre o nota" }).fill("Café");
  const rows = page.getByRole("button", { name: /^Café/ });
  await expect(rows.first()).toBeVisible();
  const before = await count(page);
  expect(before).toBeGreaterThan(1);
  await expect(page).toHaveURL(/[?&]q=Caf%C3%A9/);

  // Ingresos hides the expenses.
  await page.getByRole("tab", { name: "Ingresos" }).click();
  await expect(rows).toHaveCount(0);
  await expect(page.getByText("No encontré nada con «Café»")).toBeVisible();
  await page.getByRole("tab", { name: "Gastos" }).click();
  await expect(rows.first()).toBeVisible();
  await page.getByRole("tab", { name: "Todos" }).first().click();
  await expect(page).not.toHaveURL(/kind=/);
  expect(await count(page)).toBe(before);

  // A row opens the edit sheet; deleting it lowers the count by one.
  await rows.first().click();
  const sheet = page.getByRole("dialog", { name: "Editar movimiento" });
  await sheet.getByRole("button", { name: "Eliminar" }).click();
  await expect(page.getByRole("status")).toContainText("Eliminado: Café");
  await expect.poll(() => count(page)).toBe(before - 1);
});

test("es: going back to Home and forward restores the filters", async ({ page }) => {
  await page.goto("/demo?lang=es");
  await page.getByRole("banner").getByRole("link", { name: "Buscar" }).click();
  await expect(page).toHaveURL(/\/demo\/search/);
  await page.getByRole("searchbox", { name: "Busca por nombre o nota" }).fill("Taxi");
  await page.getByRole("tab", { name: "Gastos" }).click();
  await expect(page).toHaveURL(/q=Taxi/);
  await expect(page).toHaveURL(/kind=expense/);

  await page.goBack();
  await expect(page).toHaveURL(/\/demo(\?lang=es)?$/);
  await page.goForward();
  await expect(page).toHaveURL(/q=Taxi/);
  await expect(page.getByRole("searchbox", { name: "Busca por nombre o nota" })).toHaveValue(
    "Taxi",
  );
  await expect(page.getByRole("tab", { name: "Gastos" })).toHaveAttribute("aria-selected", "true");
  await expect(page.getByRole("button", { name: /^Taxi\b/ }).first()).toBeVisible();
});
