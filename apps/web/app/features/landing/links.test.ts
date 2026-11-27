import { describe, expect, it } from "vitest";
import * as links from "./links.ts";
import {
  ANDROID_APK_HREF,
  ANDROID_RELEASE_HREF,
  appLinkProps,
  demoLinkProps,
  GITHUB_HREF,
} from "./links.ts";

const APP = "https://app.wambito.com";

describe("appLinkProps", () => {
  it("leads to create-account or sign-in in the visitor's language when the app exists", () => {
    expect(appLinkProps("es", "create", false)).toEqual({ to: "/create-account?lang=es" });
    expect(appLinkProps("en", "create", false)).toEqual({ to: "/create-account?lang=en" });
    expect(appLinkProps("es", "sign-in", false)).toEqual({ to: "/sign-in?lang=es" });
    expect(appLinkProps("en", "sign-in", false)).toEqual({ to: "/sign-in?lang=en" });
  });

  it("leads to the GitHub repo, in a new tab, for both doors in landing-only mode without an app URL", () => {
    for (const locale of ["es", "en", "it", "pt"] as const) {
      for (const door of ["create", "sign-in"] as const) {
        const github = { to: GITHUB_HREF, target: "_blank", rel: "noopener" };
        expect(appLinkProps(locale, door, true)).toEqual(github);
        expect(appLinkProps(locale, door, true, undefined)).toEqual(github);
      }
    }
  });

  it("prefixes the live app's origin in landing-only mode with an app URL", () => {
    expect(appLinkProps("es", "create", true, APP)).toEqual({
      to: `${APP}/create-account?lang=es`,
    });
    expect(appLinkProps("en", "sign-in", true, APP)).toEqual({ to: `${APP}/sign-in?lang=en` });
  });

  it("ignores the app URL outside landing-only mode: the app's own routes are used", () => {
    expect(appLinkProps("es", "create", false, APP)).toEqual({ to: "/create-account?lang=es" });
    expect(appLinkProps("es", "sign-in", false, APP)).toEqual({ to: "/sign-in?lang=es" });
  });
});

describe("demoLinkProps", () => {
  it("leads to the demo in the visitor's language when the app is on this origin", () => {
    expect(demoLinkProps("es", false)).toEqual({ to: "/demo?lang=es" });
    expect(demoLinkProps("en", false, APP)).toEqual({ to: "/demo?lang=en" });
  });

  it("opens the demo on the app's origin in landing-only mode with an app URL", () => {
    expect(demoLinkProps("es", true, APP)).toEqual({ to: `${APP}/demo?lang=es` });
    expect(demoLinkProps("en", true, APP)).toEqual({ to: `${APP}/demo?lang=en` });
  });

  it("is left out in landing-only mode without an app URL: there is no demo to open", () => {
    expect(demoLinkProps("es", true)).toBeNull();
    expect(demoLinkProps("en", true, undefined)).toBeNull();
  });
});

describe("privacy link", () => {
  it("is no longer an anchor on the landing: the policy has its own page", () => {
    expect(Object.keys(links)).not.toContain("PRIVACY_HREF");
  });
});

describe("Android download", () => {
  it("is the arm64 APK of the latest release on GitHub, so a release never needs a landing change", () => {
    expect(ANDROID_APK_HREF).toBe(`${GITHUB_HREF}/releases/latest/download/wambito-arm64-v8a.apk`);
    expect(ANDROID_RELEASE_HREF).toBe(`${GITHUB_HREF}/releases/latest`);
  });

  it("names no version", () => {
    expect(Object.keys(links)).not.toContain("ANDROID_VERSION");
    expect(ANDROID_APK_HREF).not.toMatch(/\d+\.\d+\.\d+/);
  });
});
