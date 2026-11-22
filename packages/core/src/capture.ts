import { z } from "zod";
import { CAPTURE_SOURCES } from "./capture-sources.ts";
import { transactionDto } from "./schemas.ts";

export { CAPTURE_SOURCES, type CaptureSource, isCaptureSource } from "./capture-sources.ts";

// One pattern, not a union with the supported-currency enum: every supported code matches it,
// and the OpenAPI anyOf a union produces breaks the generated Dart client.
const captureCurrencySchema = z
  .string()
  .regex(/^[A-Z]{3}$/, "Expected a 3-letter uppercase ISO currency code");

export const createCaptureSchema = z.object({
  kind: z.enum(["expense", "income"]),
  amount: z.number().int().positive().refine(Number.isSafeInteger, "Amount is too large"),
  currency: captureCurrencySchema,
  merchant: z.string().trim().min(1).max(120),
  capturedAt: z.iso.datetime(),
  source: z.enum(CAPTURE_SOURCES),
});
export type CreateCapture = z.infer<typeof createCaptureSchema>;

export const captureResultDto = z.object({
  result: z.enum(["created", "merged"]),
  transaction: transactionDto,
  category: z.object({ name: z.string(), fallback: z.boolean() }),
});
export type CaptureResult = z.infer<typeof captureResultDto>;

export const reviewTransactionsSchema = z.object({ ids: z.array(z.uuid()).min(1).max(50) });
export type ReviewTransactions = z.infer<typeof reviewTransactionsSchema>;

export const FALLBACK_CATEGORY_NAMES: Record<
  "es" | "en" | "it" | "pt",
  { expense: string; income: string }
> = {
  es: { expense: "Otros gastos", income: "Otros ingresos" },
  en: { expense: "Other expenses", income: "Other income" },
  it: { expense: "Altre spese", income: "Altre entrate" },
  pt: { expense: "Outras despesas", income: "Outras receitas" },
};

/** Normalized merchant name used to match a merchant against past ones. */
export function merchantKey(merchant: string): string {
  const key = merchant
    .normalize("NFD")
    .replace(/\p{M}/gu, "")
    .toLowerCase()
    .replace(/[^\p{L}\p{N}]+/gu, " ")
    .split(" ")
    .filter((token) => token !== "" && !/^\d+$/.test(token))
    .join(" ");
  if (key === "") throw new Error("Merchant has no letters");
  return key;
}

/**
 * The shorter keys a learned merchant may have been saved under, longest first: the leading words
 * of [key] ("lidl casal ribeiro" -> "lidl casal", "lidl"), so a chain named with its branch still
 * matches the chain. None when the first word is under 3 letters, where a short word ("el", "la")
 * would catch unrelated merchants.
 */
export function merchantKeyPrefixes(key: string): string[] {
  const words = key.split(" ");
  if ((words[0]?.length ?? 0) < 3) return [];
  const prefixes: string[] = [];
  for (let n = words.length - 1; n >= 1; n--) prefixes.push(words.slice(0, n).join(" "));
  return prefixes;
}
