import { describe, expect, it } from "vitest";
import { analyticsConfig, siteAnalyticsConfig } from "./config";

describe("siteAnalyticsConfig", () => {
  it("is off in a build that is not landing-only, even with a key", () => {
    expect(siteAnalyticsConfig({ VITE_POSTHOG_KEY: "phc_test" })).toBeNull();
    expect(
      siteAnalyticsConfig({ VITE_LANDING_ONLY: "false", VITE_POSTHOG_KEY: "phc_test" }),
    ).toBeNull();
  });

  it("is on in a landing-only build with a key", () => {
    expect(
      siteAnalyticsConfig({ VITE_LANDING_ONLY: "true", VITE_POSTHOG_KEY: "phc_test" }),
    ).toEqual({ key: "phc_test", host: "https://eu.i.posthog.com" });
  });

  it("is off in a landing-only build without a key", () => {
    expect(siteAnalyticsConfig({ VITE_LANDING_ONLY: "true" })).toBeNull();
  });
});

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
