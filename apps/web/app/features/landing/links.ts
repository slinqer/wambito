import type { Locale } from "../../i18n/format.ts";
import { APP_ORIGIN, LANDING_ONLY } from "../../site/config.ts";

/** The demo without an account ("Pruébalo sin cuenta"): part of the app, not of the landing. */
export const DEMO_PATH = "/demo";

/** The source code: Wambito is open source (AGPL-3.0). Opened in a new tab. */
export const GITHUB_HREF = "https://github.com/slinqer/wambito";

/**
 * The Android app the landing offers: the latest `mobile-v*` release on GitHub. Raised after each
 * Android release is published there, never before (the link would 404); `release.md`.
 */
export const ANDROID_VERSION = "1.0.1";

/** "Descargar para Android": the arm64 APK, which nearly every phone in use runs. */
export const ANDROID_APK_HREF = `${GITHUB_HREF}/releases/download/mobile-v${ANDROID_VERSION}/wambito-${ANDROID_VERSION}-arm64-v8a.apk`;

/** The release page: the 32-bit APK, the checksums and the signing certificate. */
export const ANDROID_RELEASE_HREF = `${GITHUB_HREF}/releases/tag/mobile-v${ANDROID_VERSION}`;

/** Google Play listing; null until the app is published there (the install offer hides its button). */
export const PLAY_HREF: string | null = null;

/** F-Droid listing; null until the app is published there. */
export const FDROID_HREF: string | null = null;

/** App Store listing; null until the app is published there. */
export const APP_STORE_HREF: string | null = null;

/** Where each way to get the phone app lives; a button shows only for a non-null link. */
export interface StoreLinks {
  apk: string | null;
  release: string | null;
  play: string | null;
  fdroid: string | null;
  appStore: string | null;
}

export const STORE_LINKS: StoreLinks = {
  apk: ANDROID_APK_HREF,
  release: ANDROID_RELEASE_HREF,
  play: PLAY_HREF,
  fdroid: FDROID_HREF,
  appStore: APP_STORE_HREF,
};

/** The account creation page (the email code form): the landing's "Crear cuenta" door. */
export const CREATE_ACCOUNT_PATH = "/create-account";

/** The sign-in page (the QR beside the other ways): the header's "Entrar" door. */
export const SIGN_IN_PATH = "/sign-in";

/** Which door of the app a landing link opens. */
export type Door = "sign-in" | "create";

/**
 * Where "Crear cuenta" (`create`) and "Entrar" (`sign-in`) go, told which language the visitor
 * came from (spread onto a `PressLink`). In the landing-only release the app lives on another
 * origin: with `VITE_APP_URL` they open that door there; without it there is no app to open yet,
 * so both lead to the GitHub repo in a new tab.
 */
export function appLinkProps(
  locale: Locale,
  door: Door,
  landingOnly: boolean = LANDING_ONLY,
  appOrigin: string | undefined = APP_ORIGIN,
): { to: string; target?: "_blank"; rel?: string } {
  const path = `${door === "create" ? CREATE_ACCOUNT_PATH : SIGN_IN_PATH}?lang=${locale}`;
  if (!landingOnly) return { to: path };
  if (appOrigin) return { to: `${appOrigin}${path}` };
  return { to: GITHUB_HREF, target: "_blank", rel: "noopener" };
}

/**
 * Where "Pruébalo sin cuenta" goes: the demo, in the visitor's language. The demo is part of the
 * app, so the landing-only release opens it on the app's origin (`VITE_APP_URL`), like sign-in;
 * without an app to open there is no demo either, and the link is left out (null).
 */
export function demoLinkProps(
  locale: Locale,
  landingOnly: boolean = LANDING_ONLY,
  appOrigin: string | undefined = APP_ORIGIN,
): { to: string } | null {
  const demo = `${DEMO_PATH}?lang=${locale}`;
  if (!landingOnly) return { to: demo };
  return appOrigin ? { to: `${appOrigin}${demo}` } : null;
}

/** The copyright year: the landing page's first publication. */
export const COPYRIGHT_YEAR = 2026;
