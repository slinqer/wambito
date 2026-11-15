import { describe, expect, it } from "vitest";
import {
  createCaptureSchema,
  merchantKey,
  merchantKeyPrefixes,
  reviewTransactionsSchema,
} from "./capture.ts";
import { updateTransactionSchema } from "./schemas.ts";

describe("merchantKey", () => {
  it.each([
    ["MERCADONA 1234", "mercadona"],
    ["Mercadona", "mercadona"],
    ["Café  Central", "cafe central"],
    ["UBER *TRIP", "uber trip"],
    ["Lidl 0042 Madrid", "lidl madrid"],
  ])("%s -> %s", (input, expected) => {
    expect(merchantKey(input)).toBe(expected);
  });

  it("throws when nothing is left", () => {
    expect(() => merchantKey("   ")).toThrow();
    expect(() => merchantKey("1234 *")).toThrow();
  });
});

describe("merchantKeyPrefixes", () => {
  it("lists the shorter leading words, longest first", () => {
    expect(merchantKeyPrefixes("lidl casal ribeiro")).toEqual(["lidl casal", "lidl"]);
  });

  it("has none for one word", () => {
    expect(merchantKeyPrefixes("lidl")).toEqual([]);
  });

  it("has none when the first word is shorter than 3 letters", () => {
    expect(merchantKeyPrefixes("el corte ingles")).toEqual([]);
    expect(merchantKeyPrefixes("la tagliatella madrid")).toEqual([]);
  });

  it("keeps a first word of exactly 3 letters", () => {
    expect(merchantKeyPrefixes("bar pepe")).toEqual(["bar"]);
  });
});

describe("createCaptureSchema", () => {
  const valid = {
    kind: "expense",
    amount: 1250,
    currency: "EUR",
    merchant: "  Mercadona ",
    capturedAt: "2026-11-04T10:15:00Z",
    source: "revolut",
  };

  it("accepts a valid body and trims the merchant", () => {
    expect(createCaptureSchema.parse(valid).merchant).toBe("Mercadona");
  });

  it("accepts any 3-letter uppercase currency", () => {
    expect(createCaptureSchema.parse({ ...valid, currency: "GBP" }).currency).toBe("GBP");
    expect(() => createCaptureSchema.parse({ ...valid, currency: "eur" })).toThrow();
  });

  it.each([0, -5, 1.5])("rejects amount %s", (amount) => {
    expect(() => createCaptureSchema.parse({ ...valid, amount })).toThrow();
  });

  it("rejects an unknown source", () => {
    expect(() => createCaptureSchema.parse({ ...valid, source: "sms" })).toThrow();
  });

  it("rejects a non-instant capturedAt", () => {
    expect(() => createCaptureSchema.parse({ ...valid, capturedAt: "yesterday" })).toThrow();
  });
});

describe("reviewTransactionsSchema", () => {
  const id = "00000000-0000-4000-8000-000000000000";

  it("needs 1 to 50 uuids", () => {
    expect(() => reviewTransactionsSchema.parse({ ids: [] })).toThrow();
    expect(() =>
      reviewTransactionsSchema.parse({ ids: Array.from({ length: 51 }, () => id) }),
    ).toThrow();
    expect(reviewTransactionsSchema.parse({ ids: [id] }).ids).toHaveLength(1);
  });
});

describe("updateTransactionSchema needsReview", () => {
  it("only allows confirming", () => {
    expect(() => updateTransactionSchema.parse({ needsReview: true })).toThrow();
    expect(updateTransactionSchema.parse({ needsReview: false })).toEqual({ needsReview: false });
  });
});
