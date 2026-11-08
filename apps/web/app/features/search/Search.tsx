import { type CategoryDto, todayIn } from "@wambito/core";
import { useEffect, useMemo, useRef, useState } from "react";
import { useSearchParams } from "react-router";
import { useTranslations } from "use-intl";
import { ApiProblem, problemMessage, type Translator } from "../../api/errors.ts";
import { useAllCategories, useMe, useTransactionSearch } from "../../api/queries.ts";
import { formatMoney } from "../../i18n/format.ts";
import { useLocale } from "../../i18n/IntlProvider.tsx";
import { CategoryChip } from "../../ui/CategoryChip.tsx";
import { categoryLook } from "../../ui/category-look.ts";
import { PageHeader } from "../../ui/PageHeader.tsx";
import { PressButton } from "../../ui/PressButton.tsx";
import { SegmentedControl } from "../../ui/SegmentedControl.tsx";
import { Sheet } from "../../ui/Sheet.tsx";
import { WambiBubble } from "../../ui/WambiBubble.tsx";
import { ManageFrame } from "../categories/CategoryDetail.tsx";
import { useAppPath } from "../home/app-path.ts";
import { Day, ShowMore } from "../home/Home.tsx";
import { groupNewestFirst } from "../home/home-model.ts";
import {
  filtersFromParams,
  filtersToParams,
  isSearching,
  type SearchFilters,
} from "./search-model.ts";

/** The longest text the API accepts for one search word, and the most categories it takes. */
const MAX_TEXT = 100;
const MAX_CATEGORIES = 20;
const DEBOUNCE_MS = 300;
const FILTER_KEYS = ["q", "kind", "category", "status"] as const;

/** The filters in the URL, kept inside what the API accepts. */
function readFilters(params: URLSearchParams): SearchFilters {
  const f = filtersFromParams(params);
  return {
    ...f,
    text: f.text.slice(0, MAX_TEXT),
    categoryIds: f.categoryIds.slice(0, MAX_CATEGORIES),
  };
}

/**
 * The search screen (`/app/search`): movements across every month, by name or note, kind, category
 * and status. The filters live in the URL (replaced on each change, so back leaves the screen
 * instead of undoing keystrokes); the text reaches it 300 ms after the last key. Results are
 * home's days and rows, with the server's totals over every match above them.
 */
export function Search() {
  const t = useTranslations("search");
  const tRoot = useTranslations() as unknown as Translator;
  const tManage = useTranslations("manage");
  const appPath = useAppPath();
  const { locale } = useLocale();
  const me = useMe().data;
  if (!me) throw new Error("Search renders inside AppShell, which waits for the profile");
  const [params, setParams] = useSearchParams();
  const filters = useMemo(() => readFilters(params), [params]);
  const categories = useAllCategories();
  const [sheetOpen, setSheetOpen] = useState(false);
  const [text, setText] = useState(filters.text);
  const written = useRef(filters.text);

  const update = (next: Partial<SearchFilters>) => {
    setParams(
      (current) => {
        const merged = { ...readFilters(current), ...next };
        const out = new URLSearchParams(current);
        for (const key of FILTER_KEYS) out.delete(key);
        for (const [key, value] of filtersToParams(merged)) out.append(key, value);
        return out;
      },
      { replace: true },
    );
  };

  // The URL changed by itself (back, forward): show its text, unless it is what was just written.
  useEffect(() => {
    if (filters.text === written.current) return;
    written.current = filters.text;
    setText(filters.text);
  }, [filters.text]);

  // The text reaches the URL (and so the API) once typing pauses.
  useEffect(() => {
    if (text === written.current) return;
    const timer = setTimeout(() => {
      written.current = text;
      update({ text });
    }, DEBOUNCE_MS);
    return () => clearTimeout(timer);
  });

  const search = useTransactionSearch(filters);
  const byId = new Map((categories.data ?? []).map((c) => [c.id, c]));
  const searching = isSearching(filters);

  return (
    <ManageFrame busy={searching && search.isPending}>
      <PageHeader back={{ to: appPath(), label: tManage("back"), short: tManage("back_short") }} />
      <main className="flex flex-col gap-(--space-3)">
        <h1 className="m-0 font-display text-[28px] font-bold text-ink">{t("title")}</h1>
        <div className="lk-input min-h-11">
          <span aria-hidden="true">🔍</span>
          <input
            type="search"
            value={text}
            maxLength={MAX_TEXT}
            placeholder={t("placeholder")}
            aria-label={t("placeholder")}
            autoComplete="off"
            enterKeyHint="search"
            onChange={(event) => setText(event.target.value)}
            className="min-w-0 flex-1 border-0 bg-transparent p-0 font-text text-ink outline-none placeholder:text-ink-muted placeholder:italic"
          />
        </div>
        <SegmentedControl<SearchFilters["kind"]>
          label={t("kind")}
          value={filters.kind}
          options={[
            { value: "all", label: t("kind_all") },
            { value: "expense", label: t("kind_expense") },
            { value: "income", label: t("kind_income") },
          ]}
          onChange={(kind) => update({ kind })}
        />
        <div className="flex flex-wrap items-center gap-(--space-2)">
          <PressButton
            variant="secondary"
            size="sm"
            aria-haspopup="dialog"
            disabled={!categories.data}
            onClick={() => setSheetOpen(true)}
          >
            {filters.categoryIds.length > 0
              ? t("category_count", { count: filters.categoryIds.length })
              : t("category")}
          </PressButton>
        </div>
        <SegmentedControl<SearchFilters["status"]>
          label={t("status")}
          value={filters.status}
          options={[
            { value: "all", label: t("status_all") },
            { value: "paid", label: t("status_paid") },
            { value: "pending", label: t("status_pending") },
          ]}
          onChange={(status) => update({ status })}
        />

        {!searching ? (
          <WambiBubble message={t("hint")} mood="happy" />
        ) : search.error && !search.data ? (
          <div role="alert" className="flex flex-col items-start gap-(--space-2)">
            <p className="m-0 text-[14px] font-bold text-ink">
              {search.error instanceof ApiProblem
                ? problemMessage(search.error, tRoot)
                : tRoot("errors.generic")}
            </p>
            <PressButton variant="secondary" onClick={() => void search.refetch()}>
              {tRoot("common.retry")}
            </PressButton>
          </div>
        ) : !search.data || !categories.data ? (
          <div className="min-h-[120px]" aria-busy="true" />
        ) : search.data.items.length === 0 ? (
          <WambiBubble
            message={
              filters.text.trim() !== ""
                ? t("none", { text: filters.text.trim() })
                : t("none_filters")
            }
            mood="worried"
          />
        ) : (
          <>
            <h2 className="sr-only">{t("results")}</h2>
            {search.data.totals && (
              <p
                data-testid="search-totals"
                className="m-0 text-[14px] font-bold text-ink-muted"
                aria-live="polite"
              >
                {t("totals", {
                  count: search.data.totals.count,
                  expense: formatMoney(search.data.totals.expense, me.currency, locale),
                  income: formatMoney(search.data.totals.income, me.currency, locale),
                })}
              </p>
            )}
            {groupNewestFirst(search.data.items, todayIn(me.timezone)).map((group) => (
              <Day key={group.date} group={group} byId={byId} currency={me.currency} />
            ))}
            <ShowMore pages={search} />
          </>
        )}
      </main>
      <CategorySheet
        open={sheetOpen}
        onClose={() => setSheetOpen(false)}
        categories={categories.data ?? []}
        selected={filters.categoryIds}
        onChange={(categoryIds) => update({ categoryIds })}
      />
    </ManageFrame>
  );
}

/** Every category (archived ones last, marked): any number can be on at once. */
function CategorySheet({
  open,
  onClose,
  categories,
  selected,
  onChange,
}: {
  open: boolean;
  onClose(): void;
  categories: CategoryDto[];
  selected: string[];
  onChange(ids: string[]): void;
}) {
  const t = useTranslations("search");
  const tTx = useTranslations("transaction");
  const ordered = [...categories].sort(
    (a, b) => Number(a.archived) - Number(b.archived) || a.sortOrder - b.sortOrder,
  );
  const toggle = (id: string) => {
    if (selected.includes(id)) onChange(selected.filter((s) => s !== id));
    else if (selected.length < MAX_CATEGORIES) onChange([...selected, id]);
  };
  return (
    <Sheet
      open={open}
      onClose={onClose}
      title={t("category")}
      footer={<PressButton onClick={onClose}>{t("done")}</PressButton>}
    >
      <div role="group" aria-label={t("category")} className="lk-chips">
        {ordered.map((c) => (
          <CategoryChip
            key={c.id}
            glyph={categoryLook(c).glyph}
            label={c.name}
            {...(c.archived ? { note: tTx("archived") } : {})}
            selected={selected.includes(c.id)}
            onSelect={() => toggle(c.id)}
          />
        ))}
      </div>
    </Sheet>
  );
}
