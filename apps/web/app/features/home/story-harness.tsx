import {
  addMonths,
  costOfLiving,
  firstDay,
  lastDay,
  type MonthSummary,
  matchesMovementSearch,
  monthOf,
  monthSummary,
  monthsBetween,
  movementTotals,
  type TransactionDto,
  todayIn,
} from "@wambito/core";
import { type ReactNode, useState } from "react";
import { MemoryRouter, Route, Routes } from "react-router";
import { OCTOBER_2026 } from "../../../../../packages/core/test/fixtures/october-2026.ts";
import { exposeStoryFetch } from "../../../.storybook/parity.ts";
import { ApiProvider } from "../../api/ApiProvider.tsx";
import type { ApiMode } from "../../api/scope.ts";
import type { PasskeyOutcome } from "../../auth/passkey.ts";
import { AppMessages } from "../../i18n/AppMessages.tsx";
import type { Locale } from "../../i18n/format.ts";
import { IntlProvider, useLocale } from "../../i18n/IntlProvider.tsx";
import { ToastProvider } from "../../ui/Toast.tsx";
import type { Assistant } from "../assistants/queries.ts";
import { CategoriesRedirect } from "../categories/CategoriesRedirect.tsx";
import { CategoryDetail } from "../categories/CategoryDetail.tsx";
import { Insights } from "../insights/Insights.tsx";
import { RecurringPage } from "../recurring/RecurringPage.tsx";
import { Search } from "../search/Search.tsx";
import type { PasskeyItem, PasskeysApi } from "../settings/passkeys.ts";
import { Settings } from "../settings/Settings.tsx";
import type { SecurityApi } from "../settings/security.ts";
import { AppShell } from "./AppShell.tsx";
import { Home } from "./Home.tsx";
import { clearHomeStorage } from "./home-storage.ts";
import type { SignOutRequest } from "./use-sign-out.ts";

/** The time zone of the made-up person: "today" and the month are theirs. */
export const STORY_TIMEZONE = "Europe/Madrid";
export const STORY_TODAY = todayIn(STORY_TIMEZONE);
const MONTH = monthOf(STORY_TODAY);
/** Who the fake API says is signed in. */
export const STORY_USER_ID = "u-ana";

interface FakeCategory {
  id: string;
  name: string;
  kind: "expense" | "income";
  icon: string;
  color: string;
  sortOrder: number;
  archived: boolean;
  currentBudget: number | null;
}

const category = (
  id: string,
  name: string,
  icon: string,
  color: string,
  sortOrder: number,
  currentBudget: number | null,
  kind: "expense" | "income" = "expense",
): FakeCategory => ({ id, name, kind, icon, color, sortOrder, archived: false, currentBudget });

const CATEGORIES: FakeCategory[] = [
  category("cat-groceries", "Supermercado", "🛒", "#ff9f1c", 0, 18000),
  category("cat-restaurant", "Restaurante", "🍽️", "#ff5c7a", 1, 30000),
  category("cat-fun", "Ocio", "⭐", "#a66bff", 2, 65000),
  category("cat-transport", "Transporte", "🚗", "#3fa7ff", 3, 9000),
  category("cat-salary", "Salario", "💰", "#2fd388", 7, null, "income"),
];

const PESO_CATEGORIES: FakeCategory[] = [
  category("cat-food", "Comida", "🍽️", "#ff5c7a", 0, 80000000),
  category("cat-home", "Casa", "🏠", "#3fa7ff", 1, 150000000),
  category("cat-salary", "Salario", "💰", "#2fd388", 7, null, "income"),
];

/** A day of this month `days` from today, kept inside the month. */
function dayFromToday(days: number): string {
  const [year, month, day] = STORY_TODAY.split("-").map(Number) as [number, number, number];
  const date = new Date(Date.UTC(year, month - 1, day + days)).toISOString().slice(0, 10);
  if (date > lastDay(MONTH)) return lastDay(MONTH);
  if (date < `${MONTH}-01`) return `${MONTH}-01`;
  return date;
}

let ids = 0;
function transaction(
  name: string,
  categoryId: string,
  amount: number,
  date: string,
  status: "paid" | "pending" = "paid",
  currency = "EUR",
): TransactionDto {
  ids += 1;
  return {
    id: `00000000-0000-4000-8000-${String(ids).padStart(12, "0")}`,
    name,
    amount,
    currency,
    date,
    status,
    note: null,
    categoryId,
    recurrenceId: null,
    importId: null,
    source: "web",
    needsReview: false,
    captureSource: null,
    createdAt: `${date}T09:00:00.000Z`,
    updatedAt: `${date}T09:00:00.000Z`,
  };
}

/**
 * This month, invented: groceries over budget (194,12 of 180 €), the restaurant near its limit,
 * a pending subscription a couple of days ahead, and the salary. 501,13 € left of 1.220 €.
 */
function sampleTransactions(): TransactionDto[] {
  const first = `${MONTH}-01`;
  return [
    transaction("desayuno", "cat-restaurant", -475, STORY_TODAY),
    transaction("pingo doce", "cat-groceries", -19412, first),
    transaction("cena", "cat-restaurant", -25367, first),
    transaction("cine", "cat-fun", -26280, first),
    transaction("Salario", "cat-salary", 250000, first),
    transaction("Spotify", "cat-fun", -353, dayFromToday(2), "pending"),
  ];
}

interface FakeRecurrence {
  id: string;
  name: string;
  amount: number;
  categoryId: string;
  frequency: "monthly" | "yearly";
  dayOfMonth: number;
  monthOfYear: number | null;
  startDate: string;
  endDate: string | null;
}

/**
 * Fixed costs: Spotify (the pending one above) and a film club in Ocio, the salary, and a yearly
 * car insurance in Transporte.
 */
function sampleRecurrences(): FakeRecurrence[] {
  const spotifyDay = Number(dayFromToday(2).slice(8, 10));
  return [
    {
      id: "rec-spotify",
      name: "Spotify",
      amount: -353,
      categoryId: "cat-fun",
      frequency: "monthly",
      dayOfMonth: spotifyDay,
      monthOfYear: null,
      startDate: "2026-01-01",
      endDate: null,
    },
    {
      id: "rec-cineclub",
      name: "Cine club",
      amount: -1500,
      categoryId: "cat-fun",
      frequency: "monthly",
      dayOfMonth: 12,
      monthOfYear: null,
      startDate: "2026-01-01",
      endDate: null,
    },
    {
      id: "rec-salary",
      name: "Salario",
      amount: 250000,
      categoryId: "cat-salary",
      frequency: "monthly",
      dayOfMonth: 1,
      monthOfYear: null,
      startDate: "2026-01-01",
      endDate: null,
    },
    {
      id: "rec-insurance",
      name: "Seguro del carro",
      amount: -42000,
      categoryId: "cat-transport",
      frequency: "yearly",
      dayOfMonth: 15,
      monthOfYear: 3,
      startDate: "2025-03-01",
      endDate: null,
    },
  ];
}

/** How the October 2026 fixture's categories look in the app. */
const OCTOBER_LOOKS: Record<string, { icon: string; color: string }> = {
  supermercado: { icon: "🛒", color: "#ff9f1c" },
  restaurante: { icon: "🍽️", color: "#ff5c7a" },
  ocio: { icon: "⭐", color: "#a66bff" },
  casa: { icon: "🏠", color: "#3fa7ff" },
  transporte: { icon: "🚗", color: "#5ac8fa" },
  suscripciones: { icon: "📱", color: "#ff8fd8" },
  vida: { icon: "❤️", color: "#2fd388" },
  taxes: { icon: "🧾", color: "#8e87b8" },
  salario: { icon: "💰", color: "#2fd388" },
};

/** The October 2026 fixture's categories (packages/core), with their budgets. */
function octoberCategories(): FakeCategory[] {
  const look = (key: string) => OCTOBER_LOOKS[key] as { icon: string; color: string };
  return [
    ...OCTOBER_2026.expense.map((c, i) =>
      category(`cat-${c.key}`, c.name, look(c.key).icon, look(c.key).color, i, c.budget),
    ),
    ...OCTOBER_2026.income.map((c, i) =>
      category(`cat-${c.key}`, c.name, look(c.key).icon, look(c.key).color, 20 + i, null, "income"),
    ),
  ];
}

/**
 * The October 2026 fixture's spending (2.237,08 € in all, Casa 1.329,78 € of it) and salary in
 * this month and each of the six before it. Casa is the rent (a recurrence) plus the
 * electricity; this month's subscriptions are still pending.
 */
function octoberTransactions(): TransactionDto[] {
  const all: TransactionDto[] = [];
  for (let back = 6; back >= 0; back--) {
    const month = addMonths(MONTH, -back);
    const status = (key: string) => (back === 0 && key === "suscripciones" ? "pending" : "paid");
    for (const c of OCTOBER_2026.expense) {
      if (c.spent === 0) continue;
      if (c.key === "casa") {
        all.push(transaction("arriendo", "cat-casa", -120000, `${month}-01`));
        all.push(transaction("luz", "cat-casa", -(c.spent - 120000), `${month}-03`));
        continue;
      }
      all.push(
        transaction(c.name.toLowerCase(), `cat-${c.key}`, -c.spent, `${month}-02`, status(c.key)),
      );
    }
    for (const c of OCTOBER_2026.income) {
      all.push(transaction(c.name, `cat-${c.key}`, c.received, `${month}-01`));
    }
  }
  return all;
}

/** The fixture's fixed costs: the rent (Casa), Spotify (suscripciones) and the salary. */
function octoberRecurrences(): FakeRecurrence[] {
  const monthly = (id: string, name: string, amount: number, categoryId: string, day: number) => ({
    id,
    name,
    amount,
    categoryId,
    frequency: "monthly" as const,
    dayOfMonth: day,
    monthOfYear: null,
    startDate: `${addMonths(MONTH, -12)}-01`,
    endDate: null,
  });
  return [
    monthly("rec-rent", "arriendo", -120000, "cat-casa", 1),
    monthly("rec-spotify", "suscripciones", -3689, "cat-suscripciones", 2),
    monthly("rec-salary", "Salário", 620000, "cat-salario", 1),
  ];
}

const SUGGESTIONS = [
  { name: "continente", categoryId: "cat-groceries" },
  { name: "pingo doce", categoryId: "cat-groceries" },
  { name: "desayuno", categoryId: "cat-restaurant" },
  { name: "cine", categoryId: "cat-fun" },
];

export interface HomeApiOptions {
  /** Every write, as `METHOD /path {json body}`, with its headers. */
  onRequest(line: string, headers: Record<string, string>): void;
  currency?: "EUR" | "COP";
  /**
   * "sample": this month as above; "empty": categories without budgets and no transactions;
   * "october": the October 2026 fixture (packages/core) in this month and the six before it.
   */
  data?: "sample" | "empty" | "no-categories" | "october";
  /** Creating a transaction answers 503 (after `createDelayMs`). */
  failCreate?: boolean;
  /** A search (any filter on the transactions list) answers 503. */
  failSearch?: boolean;
  /** How long a create takes, in ms. */
  createDelayMs?: number;
  /** Transporte is archived, with a taxi ride in it today (sample data only). */
  archivedCategory?: boolean;
  /** Transporte is archived and has no movement this month: it waits in "Archivadas" (sample data only). */
  archivedUnused?: boolean;
  /** Salario, the only income category, is archived (sample data only). */
  archivedIncome?: boolean;
  /** This category is archived, with its budget and its movements. */
  archivedId?: string;
  /** No recurrences (the sample has Spotify, the salary and a yearly insurance). */
  noRecurrences?: boolean;
  /** How long each report (insights) takes to answer, in ms. */
  reportDelayMs?: number;
  /** How long listing the recurrences takes to answer, in ms. */
  recurrencesDelayMs?: number;
  /** Budgets start this many months before this one (12 by default); earlier months have none. */
  budgetsSince?: number;
  /** The profile's language (the story's locale by default). */
  locale?: Locale;
  /** Two transactions detected from notifications, still to review (sample data only). */
  detected?: boolean;
  /**
   * The currency stays locked (409 `currency_locked`) even with no transactions or recurrences
   * in sight, as when only deleted transactions remain.
   */
  currencyLocked?: boolean;
  /** Exporting answers 503. */
  failExport?: boolean;
  /** Deleting the account answers 503. */
  failDelete?: boolean;
  /** The assistants connected to the account (`GET /v1/me/assistants`); none by default. */
  assistants?: Assistant[];
  /** Revoking an assistant answers 503. */
  failRevoke?: boolean;
  /** The profile is a guest's (`isAnonymous`). */
  guest?: boolean;
}

/** One budget amount, from its month on (until a later one), as the API keeps them. */
interface FakeBudget {
  categoryId: string;
  amount: number;
  effectiveFrom: string;
}

/** The budget in force in `month`: the latest one starting on or before it. */
function budgetIn(budgets: FakeBudget[], categoryId: string, month: string): number | null {
  const found = budgets
    .filter((b) => b.categoryId === categoryId && b.effectiveFrom <= month)
    .sort((a, b) => (a.effectiveFrom < b.effectiveFrom ? 1 : -1))[0];
  return found ? found.amount : null;
}

function summaryOf(
  categories: FakeCategory[],
  budgets: FakeBudget[],
  transactions: TransactionDto[],
  month: string,
): MonthSummary {
  const inMonth = transactions.filter((t) => monthOf(t.date) === month);
  // Like the API: an archived category stays while it has spending that month.
  const used = new Set(inMonth.map((t) => t.categoryId));
  return monthSummary({
    month,
    categories: categories
      .filter((c) => !c.archived || used.has(c.id))
      .map((c) => ({ id: c.id, kind: c.kind })),
    budgets: categories.flatMap((c) => {
      const amount = budgetIn(budgets, c.id, month);
      return amount === null ? [] : [{ categoryId: c.id, amount, effectiveFrom: month }];
    }),
    transactions: inMonth,
  });
}

const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

function homeFetch({
  onRequest,
  currency = "EUR",
  data = "sample",
  failCreate = false,
  failSearch = false,
  createDelayMs = 0,
  archivedCategory = false,
  archivedUnused = false,
  archivedIncome = false,
  archivedId,
  noRecurrences = false,
  reportDelayMs = 0,
  recurrencesDelayMs = 0,
  budgetsSince = 12,
  locale = "es",
  detected = false,
  currencyLocked = false,
  failExport = false,
  failDelete = false,
  assistants: initialAssistants = [],
  failRevoke = false,
  guest = false,
}: HomeApiOptions): typeof fetch {
  let assistants = [...initialAssistants];
  let categories: FakeCategory[] =
    data === "no-categories"
      ? []
      : data === "october"
        ? octoberCategories()
        : currency === "COP"
          ? structuredClone(PESO_CATEGORIES)
          : structuredClone(CATEGORIES);
  if (data === "empty") categories = categories.map((c) => ({ ...c, currentBudget: null }));
  let transactions: TransactionDto[] =
    data === "october"
      ? octoberTransactions()
      : data === "sample" && currency === "EUR"
        ? sampleTransactions()
        : [];
  if (detected) {
    transactions = [
      ...transactions,
      {
        ...transaction("Mercadona", "cat-groceries", -2350, STORY_TODAY),
        source: "capture",
        needsReview: true,
        captureSource: "revolut",
      },
      {
        ...transaction("Zara", "cat-fun", -4990, STORY_TODAY),
        source: "capture",
        needsReview: true,
        captureSource: "google_wallet",
      },
    ];
  }
  if (archivedCategory) {
    categories = categories.map((c) =>
      c.id === "cat-transport" ? { ...c, archived: true, currentBudget: null } : c,
    );
    transactions = [...transactions, transaction("taxi", "cat-transport", -1500, STORY_TODAY)];
  }
  if (archivedUnused) {
    categories = categories.map((c) =>
      c.id === "cat-transport" ? { ...c, archived: true, currentBudget: null } : c,
    );
  }
  if (archivedId) {
    categories = categories.map((c) => (c.id === archivedId ? { ...c, archived: true } : c));
  }
  if (archivedIncome) {
    categories = categories.map((c) => (c.id === "cat-salary" ? { ...c, archived: true } : c));
  }
  let budgets: FakeBudget[] = categories.flatMap((c) =>
    c.currentBudget === null
      ? []
      : [
          {
            categoryId: c.id,
            amount: c.currentBudget,
            effectiveFrom: addMonths(MONTH, -budgetsSince),
          },
        ],
  );
  const withBudget = (c: FakeCategory): FakeCategory => ({
    ...c,
    currentBudget: budgetIn(budgets, c.id, MONTH),
  });
  let recurrences: FakeRecurrence[] = noRecurrences
    ? []
    : data === "october"
      ? octoberRecurrences()
      : data === "sample" && currency === "EUR"
        ? sampleRecurrences()
        : [];
  let recurrenceIds = 0;
  const deleted = new Map<string, TransactionDto>();
  let profile = {
    id: STORY_USER_ID,
    email: "ana@example.com",
    timezone: STORY_TIMEZONE,
    locale: locale as string,
    onboardingCompletedAt: "2026-10-01T10:00:00.000Z",
    currency: currency as string,
    isAnonymous: guest,
  };
  const newestFirst = (a: TransactionDto, b: TransactionDto) =>
    a.date === b.date ? (a.id < b.id ? 1 : -1) : a.date < b.date ? 1 : -1;

  return async (input) => {
    const request = input instanceof Request ? input : new Request(input);
    const url = new URL(request.url);
    const path = url.pathname;
    const isJson = request.headers.get("content-type")?.includes("application/json");
    const body = isJson ? await request.json() : undefined;
    if (request.method !== "GET") {
      onRequest(
        `${request.method} ${path}${body === undefined ? "" : ` ${JSON.stringify(body)}`}`,
        Object.fromEntries(request.headers.entries()),
      );
    }

    if (path === "/api/v1/me" && request.method === "PATCH") {
      const patch = body as Partial<typeof profile>;
      // Like the API: the currency changes only while the account has no transactions or recurrences.
      if (
        patch.currency &&
        patch.currency !== profile.currency &&
        (currencyLocked || transactions.length > 0 || recurrences.length > 0)
      ) {
        return Response.json({ code: "currency_locked" }, { status: 409 });
      }
      profile = { ...profile, ...patch };
      return Response.json(profile);
    }
    if (path === "/api/v1/me" && request.method === "DELETE") {
      if (failDelete) return Response.json({ code: "internal_error" }, { status: 503 });
      return new Response(null, { status: 204 });
    }
    if (path === "/api/v1/me") return Response.json(profile);
    if (path === "/api/v1/me/assistants") return Response.json({ items: assistants });
    const oneAssistant = /^\/api\/v1\/me\/assistants\/(.+)$/.exec(path);
    if (oneAssistant && request.method === "DELETE") {
      if (failRevoke) return Response.json({ code: "internal_error" }, { status: 503 });
      const clientId = decodeURIComponent(oneAssistant[1] as string);
      if (!assistants.some((a) => a.clientId === clientId)) {
        return Response.json({ code: "not_found" }, { status: 404 });
      }
      assistants = assistants.filter((a) => a.clientId !== clientId);
      return new Response(null, { status: 204 });
    }
    if (path === "/api/v1/me/export") {
      if (failExport) return Response.json({ code: "internal_error" }, { status: 503 });
      const csv = url.searchParams.get("format") === "csv";
      return new Response(
        csv
          ? "date,name,amount,currency,category,status,note\n"
          : JSON.stringify({ user: profile }),
        {
          headers: {
            "content-type": csv ? "text/csv; charset=utf-8" : "application/json",
            "content-disposition": `attachment; filename="wambito-export-${STORY_TODAY}.${csv ? "csv" : "json"}"`,
          },
        },
      );
    }
    if (path === "/api/v1/categories" && request.method === "GET") {
      const all = url.searchParams.get("includeArchived") === "true";
      return Response.json(categories.filter((c) => all || !c.archived).map(withBudget));
    }
    if (path === "/api/v1/categories" && request.method === "POST") {
      const asked = (body as { name?: string }).name?.toLowerCase();
      if (categories.some((c) => c.name.toLowerCase() === asked)) {
        return Response.json({ code: "category_name_taken" }, { status: 409 });
      }
      const created = {
        ...(body as Omit<FakeCategory, "id" | "archived" | "currentBudget">),
        id: `cat-new-${categories.length}`,
        archived: false,
        currentBudget: null,
      } as FakeCategory;
      categories = [...categories, created];
      return Response.json(created, { status: 201 });
    }
    const categoryBudget = /^\/api\/v1\/categories\/([^/]+)\/budget$/.exec(path);
    if (categoryBudget && request.method === "PUT") {
      const id = categoryBudget[1] as string;
      const { amount, effectiveFrom } = body as { amount: number; effectiveFrom: string };
      if (!Number.isInteger(amount) || amount < 0) {
        return Response.json({ code: "validation_failed" }, { status: 422 });
      }
      budgets = [
        ...budgets.filter((b) => !(b.categoryId === id && b.effectiveFrom === effectiveFrom)),
        { categoryId: id, amount, effectiveFrom },
      ];
      return Response.json(withBudget(categories.find((c) => c.id === id) as FakeCategory));
    }
    const oneCategory = /^\/api\/v1\/categories\/([^/]+)$/.exec(path);
    if (oneCategory && request.method === "PATCH") {
      const id = oneCategory[1] as string;
      const patch = body as Partial<FakeCategory> & { archived?: boolean };
      const existing = categories.find((c) => c.id === id);
      if (!existing) return Response.json({ code: "not_found" }, { status: 404 });
      if (
        patch.kind &&
        patch.kind !== existing.kind &&
        transactions.some((t) => t.categoryId === id)
      ) {
        return Response.json({ code: "category_has_transactions" }, { status: 409 });
      }
      if (
        patch.name &&
        categories.some((c) => c.id !== id && c.name.toLowerCase() === patch.name?.toLowerCase())
      ) {
        return Response.json({ code: "category_name_taken" }, { status: 409 });
      }
      categories = categories.map((c) => (c.id === id ? { ...c, ...patch } : c));
      // Like the API: archiving ends the category's active recurrences today.
      if (patch.archived && !existing.archived) {
        recurrences = recurrences.map((r) =>
          r.categoryId === id && (r.endDate === null || r.endDate >= STORY_TODAY)
            ? { ...r, endDate: STORY_TODAY }
            : r,
        );
      }
      return Response.json(withBudget(categories.find((c) => c.id === id) as FakeCategory));
    }
    if (path === "/api/v1/recurrences" && request.method === "GET") {
      if (recurrencesDelayMs) await sleep(recurrencesDelayMs);
      return Response.json(recurrences);
    }
    if (path === "/api/v1/recurrences" && request.method === "POST") {
      const input = body as Omit<FakeRecurrence, "id">;
      if (input.frequency === "yearly" && input.monthOfYear == null) {
        return Response.json({ code: "validation_failed" }, { status: 422 });
      }
      recurrenceIds += 1;
      const created: FakeRecurrence = {
        ...input,
        id: `rec-new-${recurrenceIds}`,
        monthOfYear: input.monthOfYear ?? null,
        endDate: input.endDate ?? null,
      };
      recurrences = [...recurrences, created];
      return Response.json(created, { status: 201 });
    }
    const oneRecurrence = /^\/api\/v1\/recurrences\/([^/]+)$/.exec(path);
    if (oneRecurrence && request.method === "PATCH") {
      const id = oneRecurrence[1] as string;
      recurrences = recurrences.map((r) =>
        r.id === id ? { ...r, ...(body as Partial<FakeRecurrence>) } : r,
      );
      return Response.json(recurrences.find((r) => r.id === id));
    }
    if (oneRecurrence && request.method === "DELETE") {
      recurrences = recurrences.filter((r) => r.id !== oneRecurrence[1]);
      return new Response(null, { status: 204 });
    }
    if (path === "/api/v1/summary") {
      return Response.json(
        summaryOf(categories, budgets, transactions, url.searchParams.get("month") ?? MONTH),
      );
    }
    // Reports, computed like the API (apps/api/src/routes/reports.ts).
    if (path.startsWith("/api/v1/reports/") && reportDelayMs) await sleep(reportDelayMs);
    if (path === "/api/v1/reports/by-category") {
      const from = url.searchParams.get("from") ?? MONTH;
      const to = url.searchParams.get("to") ?? MONTH;
      const kind = url.searchParams.get("kind") ?? "expense";
      const status = url.searchParams.get("status");
      const sign = kind === "expense" ? -1 : 1;
      const items = categories
        .filter((c) => c.kind === kind)
        .map((c) => ({
          categoryId: c.id,
          name: c.name,
          icon: c.icon,
          color: c.color,
          total:
            sign *
            transactions
              .filter((t) => t.categoryId === c.id && (!status || t.status === status))
              .filter((t) => monthOf(t.date) >= from && monthOf(t.date) <= to)
              .reduce((sum, t) => sum + t.amount, 0),
        }))
        .filter((i) => i.total !== 0)
        .sort((x, y) => y.total - x.total);
      const total = items.reduce((sum, i) => sum + i.total, 0);
      return Response.json({
        total,
        items: items.map((i) => ({
          ...i,
          share: total === 0 ? 0 : Math.round((i.total / total) * 10_000) / 10_000,
        })),
      });
    }
    if (path === "/api/v1/reports/trend") {
      const months = monthsBetween(
        url.searchParams.get("from") ?? MONTH,
        url.searchParams.get("to") ?? MONTH,
      );
      const kindOf = new Map(categories.map((c) => [c.id, c.kind]));
      return Response.json({
        months: months.map((month) => {
          const summary = summaryOf(categories, budgets, transactions, month);
          const inMonth = transactions.filter((t) => monthOf(t.date) === month);
          const sum = (kind: "expense" | "income") =>
            inMonth
              .filter((t) => kindOf.get(t.categoryId) === kind)
              .reduce((acc, t) => acc + t.amount, 0);
          return {
            month,
            income: sum("income"),
            expenses: -sum("expense"),
            budget: summary.budgetTotal,
          };
        }),
      });
    }
    if (path === "/api/v1/reports/cost-of-living") {
      const count = Number(url.searchParams.get("months") ?? 6);
      const to = addMonths(MONTH, -1);
      const from = addMonths(to, 1 - count);
      return Response.json(
        costOfLiving({
          months: monthsBetween(from, to),
          categories: categories.map((c) => ({ id: c.id, kind: c.kind })),
          fixedCategoryIds: recurrences
            .filter((r) => r.endDate === null || r.endDate >= firstDay(from))
            .map((r) => r.categoryId),
          transactions: transactions.map((t) => ({
            categoryId: t.categoryId,
            amount: t.amount,
            date: t.date,
          })),
        }),
      );
    }
    if (path === "/api/v1/transactions/suggestions") {
      const q = (url.searchParams.get("q") ?? "").toLowerCase();
      return Response.json({ items: SUGGESTIONS.filter((s) => s.name.includes(q)) });
    }
    if (path === "/api/v1/transactions" && request.method === "GET") {
      const month = url.searchParams.get("month");
      const sp = url.searchParams;
      if (failSearch && sp.get("totals") === "true") {
        return Response.json({ code: "internal_error" }, { status: 503 });
      }
      const terms = sp.getAll("q");
      const categoryIds = sp.getAll("category");
      const kind = sp.get("kind");
      const match = sp.get("match");
      const status = sp.get("status");
      if (
        terms.length > 10 ||
        terms.some((t) => t.length > 100) ||
        categoryIds.length > 20 ||
        (kind !== null && kind !== "expense" && kind !== "income") ||
        (match !== null && match !== "all" && match !== "any")
      ) {
        return Response.json({ code: "validation_failed" }, { status: 422 });
      }
      const rows = transactions
        .filter((t) => !month || monthOf(t.date) === month)
        .filter((t) => sp.get("needsReview") !== "true" || t.needsReview)
        .filter((t) =>
          matchesMovementSearch(t, {
            ...(terms.length > 0 ? { terms } : {}),
            ...(categoryIds.length > 0 ? { categoryIds } : {}),
            ...(kind ? { kind } : {}),
            ...(status === "paid" || status === "pending" ? { status } : {}),
            ...(match ? { match } : {}),
          }),
        )
        .sort(newestFirst);
      const items = rows.slice(0, Number(sp.get("limit") ?? 50));
      return Response.json({
        items,
        nextCursor: null,
        ...(sp.get("totals") === "true" ? { totals: movementTotals(rows) } : {}),
      });
    }
    if (path === "/api/v1/transactions" && request.method === "POST") {
      if (createDelayMs) await sleep(createDelayMs);
      if (failCreate) return Response.json({ code: "internal_error" }, { status: 503 });
      const input = body as Pick<
        TransactionDto,
        "name" | "amount" | "categoryId" | "date" | "status" | "note"
      >;
      const created = {
        ...transaction(input.name, input.categoryId, input.amount, input.date, input.status),
        note: input.note ?? null,
        currency,
      };
      transactions = [...transactions, created];
      return Response.json(created, { status: 201 });
    }
    if (path === "/api/v1/transactions/review" && request.method === "POST") {
      const { ids } = body as { ids: string[] };
      transactions = transactions.map((t) =>
        ids.includes(t.id) ? { ...t, needsReview: false } : t,
      );
      return Response.json({
        items: transactions.filter((t) => ids.includes(t.id)),
        nextCursor: null,
      });
    }
    const restore = /^\/api\/v1\/transactions\/([^/]+)\/restore$/.exec(path);
    if (restore) {
      const back = deleted.get(restore[1] as string);
      if (!back) return Response.json({ code: "not_found" }, { status: 404 });
      transactions = [...transactions, back];
      return Response.json(back);
    }
    const one = /^\/api\/v1\/transactions\/([^/]+)$/.exec(path);
    if (one && request.method === "PATCH") {
      transactions = transactions.map((t) =>
        t.id === one[1] ? { ...t, ...(body as Partial<TransactionDto>) } : t,
      );
      return Response.json(transactions.find((t) => t.id === one[1]));
    }
    if (one && request.method === "DELETE") {
      const gone = transactions.find((t) => t.id === one[1]);
      if (gone) deleted.set(gone.id, gone);
      transactions = transactions.filter((t) => t.id !== one[1]);
      return new Response(null, { status: 204 });
    }
    return new Response(null, { status: 404 });
  };
}

/**
 * Passkeys kept in memory, standing in for Better Auth and the browser's prompt: `outcome` is what
 * adding one comes to (a new passkey when "added").
 */
export function storyPasskeys({
  initial = [],
  supported = true,
  outcome = "added",
  failList = false,
}: {
  initial?: PasskeyItem[];
  supported?: boolean;
  outcome?: PasskeyOutcome;
  failList?: boolean;
} = {}): PasskeysApi {
  let items = [...initial];
  return {
    supported: () => supported,
    list: async () => {
      if (failList) throw new Error("passkeys_unavailable");
      return [...items];
    },
    add: async () => {
      if (outcome === "added") {
        items = [
          ...items,
          {
            id: `pk-${items.length + 1}`,
            credentialId: `cred-${items.length + 1}`,
            name: null,
            createdAt: `${STORY_TODAY}T10:00:00.000Z`,
            synced: true,
          },
        ];
      }
      return outcome;
    },
    remove: async (id) => {
      items = items.filter((item) => item.id !== id);
    },
  };
}

export interface HomeStageProps extends HomeApiOptions {
  /** Stands in for Better Auth's sign-out; by default it succeeds. */
  signOut?: SignOutRequest;
  /** Where the story starts (`/app` by default): any screen of the signed-in app. */
  path?: string;
  /** Stands in for Better Auth's passkeys in settings; by default none, and the browser can add one. */
  passkeys?: PasskeysApi;
  /** Receives settings' downloads instead of the browser. */
  onSave?(filename: string, blob: Blob): void;
  /** Receives what settings copies (the assistants' address) instead of the clipboard. */
  onCopy?(text: string): Promise<void>;
  /** The provider's mode; `local` shows a preview account's app. Default `live`. */
  mode?: ApiMode;
  /** Stands in for the open vault's keys in settings (Security, mode `local`). */
  security?: SecurityApi;
}

/**
 * The signed-in app (the shell with its bottom bar or sidebar and the add sheet; home, the
 * categories, a category's detail, the recurring ones, insights and settings) in a memory router,
 * against the fake API above, with the toasts. It speaks the story's language until settings
 * switches it. Each story starts with no remembered choices; "Recargar" remounts everything as a
 * reload would, keeping what the browser stored.
 */
export function HomeStage({
  signOut = async () => ({ error: null }),
  path = "/app",
  passkeys: passkeysProp,
  onSave = () => {},
  onCopy = async () => {},
  mode,
  security,
  ...api
}: HomeStageProps) {
  // The toolbar's language, held here so settings can switch it (the toolbar's provider can't).
  const storyLocale = useLocale().locale;
  const [locale, setLocale] = useState(storyLocale);
  const [passkeys] = useState(() => passkeysProp ?? storyPasskeys());
  const [fetchImpl] = useState(() => {
    clearHomeStorage(STORY_USER_ID);
    return exposeStoryFetch(homeFetch({ locale: storyLocale, ...api }));
  });
  const [reloads, setReloads] = useState(0);
  const shell = (screen: ReactNode) => <AppShell>{screen}</AppShell>;
  return (
    <IntlProvider locale={locale} onLocaleChange={setLocale}>
      <AppMessages>
        <MemoryRouter initialEntries={[path]}>
          <button
            type="button"
            className="sr-only focus:not-sr-only"
            onClick={() => setReloads((n) => n + 1)}
          >
            Recargar (stand-in)
          </button>
          <ApiProvider key={reloads} fetch={fetchImpl} {...(mode ? { mode } : {})}>
            <ToastProvider>
              <Routes>
                <Route path="/app" element={shell(<Home signOut={signOut} />)} />
                <Route path="/app/categories" element={<CategoriesRedirect />} />
                <Route path="/app/categories/:id" element={shell(<CategoryDetail />)} />
                <Route path="/app/recurring" element={shell(<RecurringPage />)} />
                <Route path="/app/insights" element={shell(<Insights />)} />
                <Route path="/app/search" element={shell(<Search />)} />
                <Route
                  path="/app/settings"
                  element={shell(
                    <Settings
                      passkeys={passkeys}
                      signOut={signOut}
                      save={(blob, filename) => onSave(filename, blob)}
                      copy={onCopy}
                      {...(security ? { security } : {})}
                    />,
                  )}
                />
                <Route
                  path="/sign-in"
                  element={<p className="p-(--space-4) text-ink">Sign-in (stand-in)</p>}
                />
                <Route
                  path="/"
                  element={<p className="p-(--space-4) text-ink">Landing (stand-in)</p>}
                />
              </Routes>
            </ToastProvider>
          </ApiProvider>
        </MemoryRouter>
      </AppMessages>
    </IntlProvider>
  );
}
