import { describe, expect, it } from "vitest";
import { analyticsConfig } from "./config";

describe("analyticsConfig", () => {
  it("is off without a key", () => {
    expect(analyticsConfig({})).toBeNull();
    expect(analyticsConfig({ VITE_POSTHOG_KEY: " " })).toBeNull();
  });

  it("defaults the host to the EU cloud", () => {
    expect(analyticsConfig({ VITE_POSTHOG_KEY: "phc_test" })).toEqual({
      key: "phc_test",
      host: "https://eu.i.posthog.com",
    });
  });

  it("drops a trailing slash from the host", () => {
    expect(
      analyticsConfig({
        VITE_POSTHOG_KEY: "phc_test",
        VITE_POSTHOG_HOST: "https://eu.i.posthog.com/",
      }),
    ).toEqual({ key: "phc_test", host: "https://eu.i.posthog.com" });
  });
});
