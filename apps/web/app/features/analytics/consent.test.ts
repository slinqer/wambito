import { describe, expect, it } from "vitest";
import { consentState, encodeChoice, readStoredConsent, writeStoredConsent } from "./consent";

const now = new Date("2026-11-19T12:00:00Z");
const daysAgo = (days: number) => new Date(now.getTime() - days * 86_400_000).toISOString();
const stored = (v: unknown, choice: unknown, at: unknown) => JSON.stringify({ v, choice, at });

describe("consentState", () => {
  it("asks when nothing is stored", () => {
    expect(consentState(null, {}, now)).toBe("ask");
  });

  it("reads a choice it encoded", () => {
    expect(consentState(encodeChoice("granted", now), {}, now)).toBe("granted");
    expect(consentState(encodeChoice("denied", now), {}, now)).toBe("denied");
  });

  it("expires a choice after 182 days", () => {
    expect(consentState(stored(1, "granted", daysAgo(181)), {}, now)).toBe("granted");
    expect(consentState(stored(1, "granted", daysAgo(183)), {}, now)).toBe("ask");
  });

  it("asks again on an old version", () => {
    expect(consentState(stored(0, "granted", now.toISOString()), {}, now)).toBe("ask");
  });

  it("asks on malformed values", () => {
    for (const value of [
      "yes",
      "{}",
      "{",
      stored(1, "maybe", now.toISOString()),
      stored(1, "granted", "not a date"),
    ]) {
      expect(consentState(value, {}, now)).toBe("ask");
    }
  });

  it("denies when the browser says no", () => {
    expect(consentState(encodeChoice("granted", now), { globalPrivacyControl: true }, now)).toBe(
      "denied",
    );
    expect(consentState(null, { doNotTrack: "1" }, now)).toBe("denied");
    expect(consentState(encodeChoice("granted", now), { doNotTrack: "0" }, now)).toBe("granted");
  });
});

describe("storage helpers", () => {
  it("returns null when reading fails or storage is missing", () => {
    expect(
      readStoredConsent({
        getItem() {
          throw new Error("blocked");
        },
      }),
    ).toBeNull();
    expect(readStoredConsent(undefined)).toBeNull();
  });

  it("returns false when writing fails", () => {
    expect(
      writeStoredConsent(
        {
          setItem() {
            throw new Error("quota");
          },
        },
        "x",
      ),
    ).toBe(false);
  });

  it("encodes a versioned, dated choice", () => {
    expect(JSON.parse(encodeChoice("denied", now))).toEqual({
      v: 1,
      choice: "denied",
      at: "2026-11-19T12:00:00.000Z",
    });
  });
});
