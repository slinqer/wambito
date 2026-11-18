import { readdirSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import * as links from "./links.ts";
import {
  ANDROID_APK_HREF,
  ANDROID_RELEASE_HREF,
  ANDROID_VERSION,
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
  it("is the arm64 APK of the mobile release on GitHub, downloaded directly", () => {
    expect(ANDROID_APK_HREF).toBe(
      `${GITHUB_HREF}/releases/download/mobile-v${ANDROID_VERSION}/wambito-${ANDROID_VERSION}-arm64-v8a.apk`,
    );
    expect(ANDROID_RELEASE_HREF).toBe(`${GITHUB_HREF}/releases/tag/mobile-v${ANDROID_VERSION}`);
  });

  it("is a released version: one with an arm64 changelog", () => {
    // Version codes are (X*10000 + Y*100 + Z)*10 + ABI, 2 for arm64 (release.md). The landing moves
    // to a version only once its GitHub release is published, so this is not always the newest.
    const [x, y, z] = ANDROID_VERSION.split(".").map(Number) as [number, number, number];
    const code = (x * 10000 + y * 100 + z) * 10 + 2;
    const dir = fileURLToPath(
      new URL("../../../../mobile/fastlane/metadata/android/en-US/changelogs/", import.meta.url),
    );
    expect(readdirSync(dir)).toContain(`${code}.txt`);
  });
});
