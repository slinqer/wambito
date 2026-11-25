import type { CategoryDto, CategoryKind, MonthSummary } from "@wambito/core";
import { useState } from "react";
import { useNavigate } from "react-router";
import { useTranslations } from "use-intl";
import { CategoryRow } from "../../ui/CategoryRow.tsx";
import { categoryLook } from "../../ui/category-look.ts";
import { Icon } from "../../ui/Icon.tsx";
import { PressButton } from "../../ui/PressButton.tsx";
import { SegmentedControl } from "../../ui/SegmentedControl.tsx";
import { useAppPath } from "../home/app-path.ts";
import type { DetailState } from "./CategoryDetail.tsx";
import { categoryLists } from "./category-lists.ts";
import { useCategorySheets } from "./use-category-sheets.tsx";

export interface CategoriesTabProps {
  /** The month on screen; its lines carry each spending category's budget and spend. */
  summary: MonthSummary | undefined;
  /** Every category, archived ones too. */
  categories: CategoryDto[] | undefined;
  currency: string;
  month: string;
}

/** What a spending category with no line in the summary (just created) shows: nothing yet. */
const NO_LINE = { budget: null, spent: 0, remaining: null, state: "ok" } as const;

/**
 * Home's Categorías tab: where categories are managed (founder decision 2026-10-24; there is no
 * separate page). A Gastos | Ingresos switch; one row per category of that kind, opening its
 * detail (a spending category with its month's budget bar, an income one with "Ingreso"); "Nueva
 * categoría", a dashed row after them (under the empty line when there are none), as on the phone;
 * and the archived ones of that kind folded at the end, each with "Restaurar". An
 * archived spending category that has spending in the month on screen is one of the rows instead,
 * noted "archivada" (`categoryLists`). Renaming,
 * the icon and colour, and archiving are in the detail.
 */
export function CategoriesTab({ summary, categories, currency, month }: CategoriesTabProps) {
  const t = useTranslations("categories");
  const tHome = useTranslations("home");
  const tTransaction = useTranslations("transaction");
  const navigate = useNavigate();
  const appPath = useAppPath();
  const sheets = useCategorySheets();
  const [kind, setKind] = useState<CategoryKind>("expense");
  const [showArchived, setShowArchived] = useState(false);
  if (!summary || !categories) return <div className="min-h-[120px]" aria-busy="true" />;

  const lines = new Map(summary.categories.map((line) => [line.categoryId, line]));
  const { rows, archived } = categoryLists(categories, lines, kind);
  // Its detail, in the month on screen, and back to this tab from it.
  const open = (category: CategoryDto) => {
    const state: DetailState = { from: "categories" };
    navigate(appPath(`/categories/${category.id}?month=${month}`), { state });
  };

  return (
    <>
      <SegmentedControl<CategoryKind>
        label={t("kind_label")}
        value={kind}
        options={[
          { value: "expense", label: t("expenses") },
          { value: "income", label: t("income") },
        ]}
        onChange={setKind}
      />
      {rows.length === 0 ? (
        <p className="m-0 text-[14px] font-bold text-ink-muted">
          {kind === "expense" ? tHome("no_expense_categories") : t("none_of_kind")}
        </p>
      ) : (
        rows.map((category) => {
          const look = categoryLook(category);
          const line = lines.get(category.id) ?? NO_LINE;
          return (
            <CategoryRow
              key={category.id}
              name={category.name}
              glyph={look.glyph}
              tint={look.tint}
              budget={line.budget}
              spent={line.spent}
              remaining={line.remaining}
              state={line.state}
              currency={currency}
              {...(kind === "income" ? { line: t("income_line") } : {})}
              // Archived this month, with spending in it: kept among the rows, noted.
              {...(category.archived ? { note: tTransaction("archived") } : {})}
              onOpen={() => open(category)}
            />
          );
        })
      )}
      {/* After the categories (and before the archived ones), as on the phone: a dashed row as
          wide as them, so the page's one purple + stays the add-a-movement button. */}
      <button type="button" className="lk-add-row" onClick={sheets.startCreate}>
        <Icon name="plus" size={20} />
        {t("add")}
      </button>
      {archived.length > 0 && (
        <div className="flex flex-col gap-(--space-2)">
          <PressButton
            variant="secondary"
            className="self-start"
            aria-expanded={showArchived}
            onClick={() => setShowArchived((shown) => !shown)}
          >
            <span aria-hidden="true">{showArchived ? "▾" : "▸"}</span>
            {t("archived_fold", { count: archived.length })}
          </PressButton>
          {showArchived && (
            <section aria-label={t("archived_title")} className="flex flex-col gap-(--space-2)">
              {archived.map((category) => {
                const look = categoryLook(category);
                return (
                  <CategoryRow
                    key={category.id}
                    name={category.name}
                    glyph={look.glyph}
                    tint={look.tint}
                    budget={null}
                    spent={0}
                    remaining={null}
                    state="ok"
                    currency={currency}
                    line={t("archived_line")}
                    onOpen={() => open(category)}
                    control={
                      <PressButton
                        variant="secondary"
                        size="sm"
                        aria-label={t("restore_named", { name: category.name })}
                        onClick={() => void sheets.restore(category)}
                      >
                        {t("restore")}
                      </PressButton>
                    }
                  />
                );
              })}
            </section>
          )}
        </div>
      )}
      {sheets.sheets}
    </>
  );
}
