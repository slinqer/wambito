import { SUGGESTED_CATEGORIES } from "@wambito/core";
import { isLocale, type Locale } from "../i18n/format.ts";
import { createLocalBackend, type UnavailableRoute } from "./backend.ts";
import { createEncryptedStore, type EncryptedStore } from "./encrypted-store.ts";
import { uuidv5 } from "./ids.ts";
import { forgetDevice, type LocalKeys } from "./keys.ts";
import { createSyncEngine, type SyncProblemCode } from "./sync.ts";

/**
 * A preview account's open vault in this tab (stage 2a): the encrypted store, the local backend the
 * screens' `fetch` goes to, and the sync engine. One per tab, shared by `/welcome` and `/app` (so
 * moving between them neither reopens nor resyncs), until sign-out or a 401 ends it.
 */

/** What the server says about the account; the vault's profile and its first settings. */
export interface VaultProfile {
  id: string;
  email: string;
  isAnonymous: boolean;
  locale: string;
  timezone: string;
}

export interface VaultSession {
  userId: string;
  /** The `/api/v1/*` the screens use: the local backend, plus the account routes kept live. */
  fetch: typeof globalThis.fetch;
  /** Called after every commit to the store (the screens refetch). */
  subscribe(listener: () => void): () => void;
  /**
   * Called once if the vault closes under the session (another tab deleted or upgraded it): the
   * sync has stopped and the session is gone; the gate checks again (reopen, or Unlock).
   */
  onClosed(listener: () => void): () => void;
  close(): void;
}

/** What a preview account cannot do yet: answered with 403, the screens show "not available yet". */
export const LOCAL_UNAVAILABLE: readonly UnavailableRoute[] = [
  { method: "*", path: "/v1/me/export" },
  { method: "*", path: "/v1/imports", prefix: true },
  { method: "*", path: "/v1/me/assistants", prefix: true },
];

/** The account itself, not its finances: these go to the real API. */
const LIVE_ROUTES: readonly { method: string; path: string }[] = [
  // Deleting the account; its records and key wraps cascade from the user on the server.
  { method: "DELETE", path: "/v1/me" },
];

/** Opening failed; `code` says why (`offline` gets the offline copy). */
export class VaultOpenError extends Error {
  constructor(readonly code: SyncProblemCode | "server") {
    super(code);
    this.name = "VaultOpenError";
  }
}

export interface OpenVaultOptions {
  profile: VaultProfile;
  keys: LocalKeys;
  /** The keys were just made or unlocked: the first full sync must succeed. */
  fresh: boolean;
  /** The network, for `/v2/sync` and the live routes. Defaults to the global `fetch`. */
  fetch?: typeof globalThis.fetch;
  now?: () => Date;
  /** The session is gone (a 401 from sync): the caller wipes the vault and goes to sign-in. */
  onUnauthorized?: () => void;
  /**
   * The cookie now belongs to another account (409 `session_changed` from sync): the session has
   * stopped and closed; the caller checks who is signed in (and reloads the app for them).
   */
  onSessionChanged?: () => void;
  /** The store; tests pass their own. */
  openStore?: (userId: string) => Promise<EncryptedStore>;
}

interface Active {
  userId: string;
  session?: VaultSession;
  /** An open in flight, shared by a second caller. */
  opening?: Promise<VaultSession>;
}

/** This tab's preview account, and its session once open. */
let active: Active | null = null;

/** The gate is showing for this preview account: sign-out must wipe its vault even if it never opened. */
export function rememberPreviewAccount(userId: string): void {
  if (active?.userId === userId) return;
  active?.session?.close();
  active = { userId };
}

const isLive = (method: string, pathname: string) =>
  LIVE_ROUTES.some((r) => r.method === method && pathname.endsWith(`/api${r.path}`));

/** The namespace of the seeded records' ids; the account's own namespace is made from it. */
const SEED_NAMESPACE = "6f1f7a4e-0c5b-5e0a-9a3e-2b1d6c8f4a10";

/**
 * Creates the account's first records when it has none after the first sync: the settings (from
 * the server's profile, the web's default currency EUR) and the suggested categories in the
 * person's language, as sign-up does on the server for a plain account. The welcome then works as
 * for anyone.
 *
 * Two devices can seed at once (both see an empty account), so the ids are UUID v5 of the account
 * and the record's name, and the content comes from the server's profile only (no clock, no
 * browser zone): both devices write the same records, and the sync keeps one copy of each.
 */
async function seedIfEmpty(store: EncryptedStore, profile: VaultProfile): Promise<void> {
  if ((await store.list("settings")).length > 0) return;
  const locale: Locale = isLocale(profile.locale) ? profile.locale : "es";
  const namespace = await uuidv5(SEED_NAMESPACE, profile.id);
  const settingsId = await uuidv5(namespace, "settings");
  const categories = await Promise.all(
    SUGGESTED_CATEGORIES.map(async (suggestion, sortOrder) => ({
      id: await uuidv5(namespace, `category:${suggestion.key}`),
      body: {
        s: 1 as const,
        name: suggestion.names[locale],
        kind: suggestion.kind,
        icon: suggestion.glyph,
        color: suggestion.tint,
        sortOrder,
        archivedAt: null,
        systemKey: null,
      },
    })),
  );
  await store.transaction(async (tx) => {
    await tx.put("settings", settingsId, {
      s: 1,
      name: null,
      currency: "EUR",
      locale,
      timezone: profile.timezone,
      onboardingCompletedAt: null,
    });
    for (const { id, body } of categories) await tx.put("category", id, body);
  });
}

/**
 * Opens (or reuses) this tab's vault session: the store, a full sync (required when `fresh`; a
 * known browser opens on its local data when offline), the first records if the account has none,
 * then the sync engine's triggers.
 */
export function openVaultSession(options: OpenVaultOptions): Promise<VaultSession> {
  const { profile } = options;
  if (active?.userId === profile.id && active.session) return Promise.resolve(active.session);
  if (active?.userId === profile.id && active.opening) return active.opening;
  rememberPreviewAccount(profile.id);
  const mine = active as Active;
  const opening = open(options).finally(() => {
    if (mine.opening === opening) mine.opening = undefined;
  });
  mine.opening = opening;
  return opening;
}

async function open(options: OpenVaultOptions): Promise<VaultSession> {
  const { profile, keys, fresh } = options;
  const network = options.fetch ?? ((input, init) => globalThis.fetch(input, init));
  const store = await (options.openStore ?? createEncryptedStore)(profile.id);
  try {
    const backend = createLocalBackend({
      store,
      now: options.now ?? (() => new Date()),
      profile: {
        id: profile.id,
        email: profile.email,
        isAnonymous: profile.isAnonymous,
        encryption: "preview",
      },
      unavailable: LOCAL_UNAVAILABLE,
    });
    /** Set once open: a later 409 `session_changed` closes it. */
    let opened: VaultSession | undefined;
    const engine = createSyncEngine({
      store,
      fetch: network,
      userId: profile.id,
      keys: keys.keys,
      keyV: keys.keyV,
      onError: (problem) => {
        if (problem.code === "unauthorized") options.onUnauthorized?.();
        if (problem.code === "session_changed" && opened) {
          opened.close();
          options.onSessionChanged?.();
        }
      },
    });
    const first = await engine.run();
    const fatal = first.error === "unauthorized" || first.error === "session_changed";
    if (!first.ok && (fresh || fatal)) {
      throw new VaultOpenError(first.error ?? "server");
    }
    // Only on a complete first sync: an empty-looking vault may just be one not downloaded yet
    // (offline, or a resync whose set-aside changes still wait for their download).
    const waiting = (await store.readOutbox(Number.MAX_SAFE_INTEGER)).some((e) => e.setAside);
    if (first.ok && !waiting) await seedIfEmpty(store, profile);
    const stop = engine.start();
    const routed = (async (input: RequestInfo | URL, init?: RequestInit) => {
      const request = input instanceof Request ? input : null;
      const method = (init?.method ?? request?.method ?? "GET").toUpperCase();
      const url = request?.url ?? String(input);
      const pathname = new URL(url, "http://vault").pathname;
      return isLive(method, pathname) ? network(input, init) : backend.fetch(input, init);
    }) as typeof globalThis.fetch;
    const closedListeners = new Set<() => void>();
    let closing = false;
    const drop = () => {
      stop();
      if (active?.session === session) active.session = undefined;
    };
    const session: VaultSession = {
      userId: profile.id,
      fetch: routed,
      subscribe: (listener) => store.subscribe(listener),
      onClosed(listener) {
        closedListeners.add(listener);
        return () => closedListeners.delete(listener);
      },
      close() {
        closing = true;
        drop();
        store.close();
      },
    };
    // Every store op now rejects with `VaultClosedError`: stop, forget the session, tell the gate.
    store.onClosed(() => {
      if (closing) return;
      drop();
      for (const listener of closedListeners) listener();
    });
    if (active?.userId === profile.id) active.session = session;
    opened = session;
    return session;
  } catch (error) {
    store.close();
    throw error;
  }
}

/**
 * Sign-out (and a lost session): stops the sync, closes the store and deletes this browser's vault
 * of the preview account the tab showed. Nothing for a plain account.
 */
export async function forgetVault(): Promise<void> {
  const current = active;
  if (!current) return;
  active = null;
  current.session?.close();
  await forgetDevice(current.userId);
}
