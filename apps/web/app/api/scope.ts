import type { QueryClient } from "@tanstack/react-query";
import { type ApiClient, createApiClient } from "./client.ts";
import { createQueryClient } from "./query-client.ts";

/**
 * `live` talks to the real API; `demo` runs on an in-memory backend, signed in as a made-up user;
 * `local` is a preview account's end-to-end encrypted vault (the local backend over IndexedDB,
 * synced through `/v2`). Demo-only behaviour checks `=== "demo"`; live-only behaviour `=== "live"`.
 */
export type ApiMode = "live" | "demo" | "local";

/** Everything one backend needs, kept together so two backends never share a cache. */
export interface ApiScope {
  mode: ApiMode;
  client: ApiClient;
  queryClient: QueryClient;
  /** Forget everything fetched so far. Call it on sign-in and sign-out. */
  clearSession(): void;
}

export interface ApiScopeOptions {
  mode?: ApiMode;
  /** The backend: defaults to the browser's `fetch`; the demo passes an in-memory one. */
  fetch?: typeof globalThis.fetch;
  baseUrl?: string;
}

/** A client and the cache of what it fetched, for one mode. */
export function createApiScope({ mode = "live", fetch, baseUrl }: ApiScopeOptions = {}): ApiScope {
  const queryClient = createQueryClient();
  const client = createApiClient({
    ...(fetch ? { fetch } : {}),
    ...(baseUrl ? { baseUrl } : {}),
  });
  return { mode, client, queryClient, clearSession: () => queryClient.clear() };
}
