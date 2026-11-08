import type { Profile } from "./wambito.ts";

type Locale = Profile["locale"];
type State = "ok" | "near" | "over";

/** The sentences of the tools' text summaries, in the person's language. Amounts come formatted. */
interface Phrases {
  overview(p: {
    month: string;
    income: string;
    spent: string;
    budget: string;
    remaining: string;
  }): string;
  budgetLine(p: { name: string; spent: string; budget: string; state: State }): string;
  transactions(count: number, more: boolean): string;
  totals(p: { count: number; expense: string; income: string }): string;
  byCategory(p: { from: string; to: string; total: string; income: boolean }): string;
  trend(p: { month: string; income: string; expenses: string }): string;
  categories(count: number): string;
  archived: string;
  budget(amount: string): string;
  recurring(count: number): string;
  monthly(day: number): string;
  yearly(day: number, month: number): string;
  saved(count: number): string;
  alreadySaved(count: number): string;
  partlySaved(saved: number, already: number): string;
  updated: string;
  deleted(count: number): string;
  restored(count: number): string;
  budgetSet(p: { name: string; amount: string; from: string }): string;
  categoryCreated(name: string): string;
  categoryUpdated(name: string): string;
  categoryArchived(name: string): string;
  recurringCreated(name: string): string;
  recurringUpdated(name: string): string;
  recurringStopped(name: string): string;
  pending: string;
  toReview: string;
  fromSource(source: "revolut" | "google_wallet"): string;
}

const STATES: Record<Locale, Record<State, string>> = {
  es: { ok: "bien", near: "cerca del límite", over: "pasado" },
  en: { ok: "on track", near: "near the limit", over: "over" },
  it: { ok: "in linea", near: "vicino al limite", over: "superato" },
  pt: { ok: "dentro", near: "perto do limite", over: "ultrapassado" },
};

const SOURCES = { revolut: "Revolut", google_wallet: "Google Wallet" } as const;

const plural = (n: number, one: string, many: string) => `${n} ${n === 1 ? one : many}`;

const PHRASES: Record<Locale, Phrases> = {
  es: {
    overview: (p) =>
      `${p.month}: ingresos ${p.income}, gastos ${p.spent}, presupuesto ${p.budget}, quedan ${p.remaining}.`,
    budgetLine: (p) => `${p.name}: ${p.spent} de ${p.budget} (${STATES.es[p.state]})`,
    transactions: (n, more) =>
      `${plural(n, "movimiento", "movimientos")}${more ? " (hay más: pasa nextCursor)" : ""}.`,
    totals: (p) =>
      `${plural(p.count, "movimiento", "movimientos")} · gastos ${p.expense} · ingresos ${p.income}`,
    byCategory: (p) =>
      `${p.income ? "Ingresos" : "Gastos"} de ${p.from} a ${p.to}: ${p.total} en total.`,
    trend: (p) => `${p.month}: ingresos ${p.income}, gastos ${p.expenses}`,
    categories: (n) => `${plural(n, "categoría", "categorías")}.`,
    archived: "archivada",
    budget: (a) => `presupuesto ${a}`,
    recurring: (n) => `${plural(n, "movimiento recurrente", "movimientos recurrentes")}.`,
    monthly: (d) => `cada mes el día ${d}`,
    yearly: (d, m) => `cada año el ${d}/${m}`,
    saved: (n) => `Guardé ${plural(n, "movimiento", "movimientos")}.`,
    alreadySaved: (n) =>
      `Ya estaba guardado: ${plural(n, "movimiento", "movimientos")}, no se guardó dos veces.`,
    partlySaved: (s, a) =>
      `Guardé ${plural(s, "movimiento", "movimientos")}; ${a} ya estaban guardados.`,
    updated: "Actualizado:",
    deleted: (n) =>
      `Borré ${plural(n, "movimiento", "movimientos")}. Se pueden recuperar con restore_transactions.`,
    restored: (n) => `Recuperé ${plural(n, "movimiento", "movimientos")}.`,
    budgetSet: (p) => `Presupuesto de ${p.name}: ${p.amount} desde ${p.from}.`,
    categoryCreated: (n) => `Creé la categoría ${n}.`,
    categoryUpdated: (n) => `Actualicé la categoría ${n}.`,
    categoryArchived: (n) => `Archivé la categoría ${n}.`,
    recurringCreated: (n) => `Creé el recurrente ${n}.`,
    recurringUpdated: (n) => `Actualicé el recurrente ${n}.`,
    recurringStopped: (n) => `Detuve el recurrente ${n}.`,
    pending: "pendiente",
    toReview: "por revisar",
    fromSource: (s) => `de ${SOURCES[s]}`,
  },
  en: {
    overview: (p) =>
      `${p.month}: income ${p.income}, spent ${p.spent}, budget ${p.budget}, ${p.remaining} left.`,
    budgetLine: (p) => `${p.name}: ${p.spent} of ${p.budget} (${STATES.en[p.state]})`,
    transactions: (n, more) =>
      `${plural(n, "transaction", "transactions")}${more ? " (more: pass nextCursor)" : ""}.`,
    totals: (p) =>
      `${plural(p.count, "transaction", "transactions")} · spent ${p.expense} · income ${p.income}`,
    byCategory: (p) =>
      `${p.income ? "Income" : "Spending"} from ${p.from} to ${p.to}: ${p.total} in total.`,
    trend: (p) => `${p.month}: income ${p.income}, spent ${p.expenses}`,
    categories: (n) => `${plural(n, "category", "categories")}.`,
    archived: "archived",
    budget: (a) => `budget ${a}`,
    recurring: (n) => `${plural(n, "recurring transaction", "recurring transactions")}.`,
    monthly: (d) => `monthly on day ${d}`,
    yearly: (d, m) => `yearly on ${m}/${d}`,
    saved: (n) => `Saved ${plural(n, "transaction", "transactions")}.`,
    alreadySaved: (n) =>
      `Already saved: ${plural(n, "transaction", "transactions")}, nothing saved twice.`,
    partlySaved: (s, a) =>
      `Saved ${plural(s, "transaction", "transactions")}; ${a} were already saved.`,
    updated: "Updated:",
    deleted: (n) =>
      `Deleted ${plural(n, "transaction", "transactions")}. They can be brought back with restore_transactions.`,
    restored: (n) => `Restored ${plural(n, "transaction", "transactions")}.`,
    budgetSet: (p) => `Budget for ${p.name}: ${p.amount} from ${p.from}.`,
    categoryCreated: (n) => `Created the category ${n}.`,
    categoryUpdated: (n) => `Updated the category ${n}.`,
    categoryArchived: (n) => `Archived the category ${n}.`,
    recurringCreated: (n) => `Created the recurring transaction ${n}.`,
    recurringUpdated: (n) => `Updated the recurring transaction ${n}.`,
    recurringStopped: (n) => `Stopped the recurring transaction ${n}.`,
    pending: "pending",
    toReview: "to review",
    fromSource: (s) => `from ${SOURCES[s]}`,
  },
  it: {
    overview: (p) =>
      `${p.month}: entrate ${p.income}, spese ${p.spent}, budget ${p.budget}, restano ${p.remaining}.`,
    budgetLine: (p) => `${p.name}: ${p.spent} su ${p.budget} (${STATES.it[p.state]})`,
    transactions: (n, more) =>
      `${plural(n, "movimento", "movimenti")}${more ? " (ce ne sono altri: passa nextCursor)" : ""}.`,
    totals: (p) =>
      `${plural(p.count, "movimento", "movimenti")} · spese ${p.expense} · entrate ${p.income}`,
    byCategory: (p) =>
      `${p.income ? "Entrate" : "Spese"} da ${p.from} a ${p.to}: ${p.total} in totale.`,
    trend: (p) => `${p.month}: entrate ${p.income}, spese ${p.expenses}`,
    categories: (n) => `${plural(n, "categoria", "categorie")}.`,
    archived: "archiviata",
    budget: (a) => `budget ${a}`,
    recurring: (n) => `${plural(n, "movimento ricorrente", "movimenti ricorrenti")}.`,
    monthly: (d) => `ogni mese il giorno ${d}`,
    yearly: (d, m) => `ogni anno il ${d}/${m}`,
    saved: (n) => `Ho salvato ${plural(n, "movimento", "movimenti")}.`,
    alreadySaved: (n) =>
      `Era già salvato: ${plural(n, "movimento", "movimenti")}, niente salvato due volte.`,
    partlySaved: (s, a) =>
      `Ho salvato ${plural(s, "movimento", "movimenti")}; ${a} erano già salvati.`,
    updated: "Aggiornato:",
    deleted: (n) =>
      `Ho eliminato ${plural(n, "movimento", "movimenti")}. Si possono recuperare con restore_transactions.`,
    restored: (n) => `Ho recuperato ${plural(n, "movimento", "movimenti")}.`,
    budgetSet: (p) => `Budget di ${p.name}: ${p.amount} da ${p.from}.`,
    categoryCreated: (n) => `Ho creato la categoria ${n}.`,
    categoryUpdated: (n) => `Ho aggiornato la categoria ${n}.`,
    categoryArchived: (n) => `Ho archiviato la categoria ${n}.`,
    recurringCreated: (n) => `Ho creato il ricorrente ${n}.`,
    recurringUpdated: (n) => `Ho aggiornato il ricorrente ${n}.`,
    recurringStopped: (n) => `Ho fermato il ricorrente ${n}.`,
    pending: "in sospeso",
    toReview: "da rivedere",
    fromSource: (s) => `da ${SOURCES[s]}`,
  },
  pt: {
    overview: (p) =>
      `${p.month}: receitas ${p.income}, despesas ${p.spent}, orçamento ${p.budget}, faltam ${p.remaining}.`,
    budgetLine: (p) => `${p.name}: ${p.spent} de ${p.budget} (${STATES.pt[p.state]})`,
    transactions: (n, more) =>
      `${plural(n, "movimento", "movimentos")}${more ? " (há mais: passa nextCursor)" : ""}.`,
    totals: (p) =>
      `${plural(p.count, "movimento", "movimentos")} · despesas ${p.expense} · receitas ${p.income}`,
    byCategory: (p) =>
      `${p.income ? "Receitas" : "Despesas"} de ${p.from} a ${p.to}: ${p.total} no total.`,
    trend: (p) => `${p.month}: receitas ${p.income}, despesas ${p.expenses}`,
    categories: (n) => `${plural(n, "categoria", "categorias")}.`,
    archived: "arquivada",
    budget: (a) => `orçamento ${a}`,
    recurring: (n) => `${plural(n, "movimento recorrente", "movimentos recorrentes")}.`,
    monthly: (d) => `todos os meses no dia ${d}`,
    yearly: (d, m) => `todos os anos a ${d}/${m}`,
    saved: (n) => `Guardei ${plural(n, "movimento", "movimentos")}.`,
    alreadySaved: (n) =>
      `Já estava guardado: ${plural(n, "movimento", "movimentos")}, nada foi guardado duas vezes.`,
    partlySaved: (s, a) =>
      `Guardei ${plural(s, "movimento", "movimentos")}; ${a} já estavam guardados.`,
    updated: "Atualizado:",
    deleted: (n) =>
      `Apaguei ${plural(n, "movimento", "movimentos")}. Podem ser recuperados com restore_transactions.`,
    restored: (n) => `Recuperei ${plural(n, "movimento", "movimentos")}.`,
    budgetSet: (p) => `Orçamento de ${p.name}: ${p.amount} a partir de ${p.from}.`,
    categoryCreated: (n) => `Criei a categoria ${n}.`,
    categoryUpdated: (n) => `Atualizei a categoria ${n}.`,
    categoryArchived: (n) => `Arquivei a categoria ${n}.`,
    recurringCreated: (n) => `Criei o recorrente ${n}.`,
    recurringUpdated: (n) => `Atualizei o recorrente ${n}.`,
    recurringStopped: (n) => `Parei o recorrente ${n}.`,
    pending: "pendente",
    toReview: "por rever",
    fromSource: (s) => `do ${SOURCES[s]}`,
  },
};

export function phrases(locale: Locale): Phrases {
  return PHRASES[locale] ?? PHRASES.es;
}

/**
 * Text the person (or an import) wrote, marked as data for the model: inside «», on one line, and
 * with any « or » of its own removed so it cannot close the quote and pose as tool text.
 */
export function quote(text: string): string {
  return `«${text.replace(/[«»]/g, "").replace(/\s+/g, " ").trim()}»`;
}
