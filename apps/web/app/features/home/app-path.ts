import { useApiMode } from "../../api/ApiProvider.tsx";
import type { ApiMode } from "../../api/scope.ts";

/**
 * Where the app's screens live: the live app (and a preview account's local one) under /app, the
 * demo's copy of them under /demo.
 */
export const APP_BASE: Record<ApiMode, string> = { live: "/app", demo: "/demo", local: "/app" };

/**
 * Builds paths inside the app for the current mode: `appPath("/insights")` is `/app/insights` in
 * the live app and `/demo/insights` in the demo, so a link never leaves the demo for the signed-in
 * app (whose guard would send the visitor to sign-in). `appPath()` is home.
 */
export function useAppPath(): (sub?: string) => string {
  const base = APP_BASE[useApiMode()];
  return (sub = "") => `${base}${sub}`;
}
