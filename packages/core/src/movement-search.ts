/** Accented letters the text search folds, and what they fold to (Spanish, Italian, Portuguese). */
export const FOLD_FROM = "áàâãäéèêëíìîïóòôõöúùûüñç";
export const FOLD_TO = "aaaaaeeeeiiiiooooouuuunc";

/** Lower case without accents, so "almuerzo" finds "Almuérzo". */
export const foldText = (text: string): string =>
  [...text.toLowerCase()].map((ch) => FOLD_TO[FOLD_FROM.indexOf(ch)] ?? ch).join("");

export type MovementKind = "expense" | "income";

export interface MovementSearch {
  terms?: string[];
  categoryIds?: string[];
  kind?: MovementKind;
  status?: "paid" | "pending";
  /** How terms and categories combine; kind and status always apply. Default "all". */
  match?: "all" | "any";
}

export interface SearchableMovement {
  name: string;
  note: string | null;
  categoryId: string;
  amount: number;
  status: "paid" | "pending";
}

export function matchesMovementSearch(tx: SearchableMovement, s: MovementSearch): boolean {
  if (s.kind === "expense" && !(tx.amount < 0)) return false;
  if (s.kind === "income" && !(tx.amount > 0)) return false;
  if (s.status && tx.status !== s.status) return false;

  const terms = (s.terms ?? []).map((t) => foldText(t.trim())).filter((t) => t !== "");
  const categoryIds = s.categoryIds ?? [];
  const checks: boolean[] = [];
  if (terms.length > 0) {
    const haystack = `${foldText(tx.name)}\n${foldText(tx.note ?? "")}`;
    checks.push(terms.some((t) => haystack.includes(t)));
  }
  if (categoryIds.length > 0) checks.push(categoryIds.includes(tx.categoryId));
  if (checks.length === 0) return true;
  return s.match === "any" ? checks.some(Boolean) : checks.every(Boolean);
}

export interface MovementTotals {
  count: number;
  expense: number;
  income: number;
}

export function movementTotals(rows: { amount: number }[]): MovementTotals {
  let expense = 0;
  let income = 0;
  for (const { amount } of rows) {
    if (amount < 0) expense += -amount;
    else income += amount;
  }
  return { count: rows.length, expense, income };
}
