import { toBase64Url, wrapDataKey } from "@wambito/crypto";
import { uuidv7 } from "@wambito/vault";
import type { DataKeySource, PasskeySecret } from "../../local/keys.ts";
import type { ConsentApi } from "./consent-api.ts";

/**
 * The consent screen's rules (spec §6.1), apart from React: what the signed query asks for, where
 * the assistant comes from, what a refusal from Better Auth means for the person, and how an
 * encrypted account's "Allow" gives the assistant its key (spec 2026-11-16 section 5).
 */

/** The scopes the API offers (apps/api/src/auth.ts, OAUTH_SCOPES). */
export type Permission = "finance:read" | "finance:write" | "offline_access";

const PERMISSIONS: readonly Permission[] = ["finance:read", "finance:write", "offline_access"];

/** What Better Auth's signed redirect to `/oauth/consent` says, as far as the screen needs it. */
export interface ConsentRequest {
  clientId: string;
  /** The requested scopes we know, in a fixed order (read, write, offline); unknown ones dropped. */
  permissions: Permission[];
  /** When the signature stops being valid (`exp`, seconds), or null when it has none. */
  expiresAt: Date | null;
}

/** The request in the page's query, or null when it has no client_id or no signature. */
export function parseConsentQuery(search: string): ConsentRequest | null {
  const params = new URLSearchParams(search);
  const clientId = params.get("client_id");
  if (!clientId || !params.get("sig")) return null;
  const asked = new Set((params.get("scope") ?? "").split(" ").filter(Boolean));
  const exp = Number(params.get("exp"));
  return {
    clientId,
    permissions: PERMISSIONS.filter((p) => asked.has(p)),
    expiresAt: Number.isFinite(exp) && exp > 0 ? new Date(exp * 1000) : null,
  };
}

/** The query Better Auth signed, as `oauth_query` wants it: the page's search without the `?`. */
export const oauthQueryOf = (search: string) => (search.startsWith("?") ? search.slice(1) : search);

const hostOf = (url: string | null | undefined, https: boolean): string | null => {
  if (!url) return null;
  try {
    const parsed = new URL(url);
    if (parsed.protocol === "https:") return parsed.host;
    return !https && parsed.protocol === "http:" ? parsed.host : null;
  } catch {
    return null;
  }
};

/**
 * Where the assistant comes from: the host its client_id lives on when the id is an https URL
 * (a Client ID Metadata Document, which only that host can publish), else its website's host.
 * This is what tells a real Claude from a copy that calls itself Claude. Same rule as the API's
 * `GET /v1/me/assistants` (routes/assistants.ts).
 */
export function clientDomain(clientId: string, clientUri?: string | null): string | null {
  return hostOf(clientId, true) ?? hostOf(clientUri, false);
}

/** The public fields of an OAuth client (`GET /api/auth/oauth2/public-client`). */
export interface PublicClient {
  name: string;
  /** Its logo, when it gave an https one. */
  icon: string | null;
  domain: string | null;
}

/** Reads Better Auth's answer (`client_name`, `logo_uri`, `client_uri`, RFC 7591 names). */
export function publicClientFrom(clientId: string, body: unknown): PublicClient {
  const fields = typeof body === "object" && body !== null ? (body as Record<string, unknown>) : {};
  const text = (key: string) => (typeof fields[key] === "string" ? (fields[key] as string) : null);
  const logo = text("logo_uri");
  return {
    name: text("client_name")?.trim() || clientId,
    icon: logo && hostOf(logo, true) ? logo : null,
    domain: clientDomain(clientId, text("client_uri")),
  };
}

/**
 * Why consent can't go on, as the screen says it: `expired` (the signed link ran out or was
 * tampered with, or the assistant is unknown: start again from the assistant), `guest` (save
 * the progress first), `network` (no connection), `session_changed` (a call naming the account
 * got 409: the cookie now belongs to another one; reload the page), or `generic`.
 */
export type ConsentProblem = "expired" | "guest" | "network" | "session_changed" | "generic";

/** A refusal, already read into what the consent screen says about it. */
export class ConsentError extends Error {
  readonly problem: ConsentProblem;
  constructor(problem: ConsentProblem) {
    super(problem);
    this.name = "ConsentError";
    this.problem = problem;
  }
}

const START_AGAIN = new Set([
  "invalid_signature",
  "invalid_request",
  "invalid_client",
  "not_found",
  "access_denied",
]);

/**
 * A refusal from Better Auth, read from its status and body. Its errors come as `{ code }`
 * (ours: `guest_cannot_authorize`) or as OAuth's `{ error }` (`invalid_signature`).
 */
export function consentProblemFrom(status: number, body: unknown): ConsentProblem {
  if (status === 0) return "network";
  const fields = typeof body === "object" && body !== null ? (body as Record<string, unknown>) : {};
  const code = [fields.code, fields.error].find((v): v is string => typeof v === "string");
  if (code === "guest_cannot_authorize") return "guest";
  if (status === 409 && code === "session_changed") return "session_changed";
  if (code && START_AGAIN.has(code.toLowerCase())) return "expired";
  if (status === 404) return "expired";
  return "generic";
}

/** What the consent screen needs for an encrypted account (absent for a plain one). */
export interface ConsentKeys {
  /** The signed-in account. */
  userId: string;
  /** This browser holds the account's vault: DK from its own device wrap, no touch. */
  device: boolean;
  /** Opens DK from `source` for one operation (`withDataKeyFrom`); DK is zeroed after. */
  open<T>(source: DataKeySource, fn: (dk: Uint8Array, keyV: number) => Promise<T>): Promise<T>;
  /** A touch of one of the person's passkeys for its PRF (`evaluatePrf`); null when cancelled. */
  touchPasskey(): Promise<PasskeySecret | null>;
}

/**
 * Where "Allow" first takes DK from: this browser's open vault (its device wrap), else nothing
 * yet (null: the screen asks for a passkey or the recovery key).
 */
export const firstKeySource = (keys: Pick<ConsentKeys, "device">): DataKeySource | null =>
  keys.device ? { device: true } : null;

/**
 * The consent was given but its wrap was not saved: the assistant would have a code and nothing
 * to open. The screen says so and offers "Try again" (`allowAssistant` with `again`).
 */
export class AssistantWrapError extends Error {
  /** Why the PUT failed: no connection, or anything else. */
  readonly problem: "network" | "generic";
  constructor(problem: "network" | "generic") {
    super("assistant_wrap_not_saved");
    this.name = "AssistantWrapError";
    this.problem = problem;
  }
}

export interface AllowOptions {
  api: Pick<ConsentApi, "decide" | "putAssistantWrap" | "revoke">;
  clientId: string;
  /** The page's signed query (`oauthQueryOf`). */
  oauthQuery: string;
  /** An encrypted account: its id and DK for one operation from the chosen source. */
  key?: {
    userId: string;
    open<T>(fn: (dk: Uint8Array, keyV: number) => Promise<T>): Promise<T>;
  };
  /**
   * "Try again" after an `AssistantWrapError`: the code already issued carries the old `S`, so the
   * consent is revoked first, then given again with a new one.
   */
  again?: boolean;
  /** The wrap's id; UUID v7 by default (the server replaces the client's earlier wrap). */
  newId?: () => string;
}

/**
 * "Allow": resolves to where the browser goes next. A plain account only posts the consent. An
 * encrypted account (spec 2026-11-16 section 5), with DK open: makes `S` (32 random bytes) and the
 * `assistant` wrap of DK under `S` (ref: the client, the wrap's `keyV`), revokes the earlier
 * consent when `again`, posts the consent with `wk` = `S`, then PUTs the wrap; `S` is zeroed and
 * DK forgotten whatever happens. A refused consent throws its `ConsentError`; a refused wrap after
 * the consent, `AssistantWrapError`, except a 409 `session_changed` (the cookie is another
 * account's now), thrown as its `ConsentError`: nothing to retry, the page must reload.
 */
export async function allowAssistant(options: AllowOptions): Promise<string> {
  const { api, clientId, oauthQuery, key, again = false, newId = uuidv7 } = options;
  if (!key) return api.decide(true, oauthQuery);
  return key.open(async (dk, keyV) => {
    const secret = crypto.getRandomValues(new Uint8Array(32));
    try {
      const wrapped = await wrapDataKey(
        secret,
        { kind: "assistant", userId: key.userId, keyV },
        dk,
      );
      if (again) await api.revoke(clientId);
      const url = await api.decide(true, oauthQuery, toBase64Url(secret));
      try {
        await api.putAssistantWrap({
          id: newId(),
          keyV,
          ref: clientId,
          wrap: toBase64Url(wrapped),
        });
      } catch (error) {
        // The cookie is another account's now (409): no failed wrap to retry, and a retry's
        // revoke would hit that account. The screen asks to reload instead.
        if (error instanceof ConsentError && error.problem === "session_changed") throw error;
        const network = error instanceof ConsentError && error.problem === "network";
        throw new AssistantWrapError(network ? "network" : "generic");
      }
      return url;
    } finally {
      secret.fill(0);
    }
  });
}
