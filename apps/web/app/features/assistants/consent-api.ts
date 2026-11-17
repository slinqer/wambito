import {
  type ConsentProblem,
  consentProblemFrom,
  type PublicClient,
  publicClientFrom,
} from "./consent-model.ts";

/** Better Auth lives at /api/auth (auth/auth-client.ts); the API at /api. */
const AUTH_BASE = "/api/auth";
const API_BASE = "/api";

/** A refusal, already read into what the consent screen says about it. */
export class ConsentError extends Error {
  readonly problem: ConsentProblem;
  constructor(problem: ConsentProblem) {
    super(problem);
    this.name = "ConsentError";
    this.problem = problem;
  }
}

/** What the consent screen asks of Better Auth, as a prop so stories can stand in for it. */
export interface ConsentApi {
  /** The assistant's name, logo and domain; throws a `ConsentError`. */
  client(clientId: string): Promise<PublicClient>;
  /**
   * Answers the request: `oauthQuery` is the page's signed query (without `?`). Resolves to where
   * the browser goes next (the assistant's redirect_uri, with a code or `access_denied`); throws
   * a `ConsentError`. `wk`: an encrypted account's assistant secret `S` (base64url), which the API
   * puts in the assistant's tokens (spec 2026-11-16 section 4).
   */
  decide(accept: boolean, oauthQuery: string, wk?: string): Promise<string>;
  /**
   * `PUT /v2/keys/{id}`: an encrypted account's `assistant` wrap of its data key (`wrap`,
   * base64url) for the client `ref`, at `keyV`. Only after the consent: the server takes it only
   * for a client the person consented to. Throws a `ConsentError`.
   */
  putAssistantWrap(wrap: { id: string; keyV: number; ref: string; wrap: string }): Promise<void>;
  /**
   * Revokes the client's consent, tokens and wrap (`DELETE /v1/me/assistants/{clientId}`); one
   * already gone (404) counts as done. Throws a `ConsentError`.
   */
  revoke(clientId: string): Promise<void>;
}

async function bodyOf(response: Response): Promise<unknown> {
  try {
    return await response.json();
  } catch {
    return undefined;
  }
}

/**
 * Better Auth's oauth-provider endpoints and the API's wrap and revoke routes, through `fetchImpl`
 * (the browser's by default). `userId`: the signed-in account, named on `/v2` calls
 * (`x-wambito-user`), so a cookie that now belongs to someone else never gets this one's wrap.
 */
export function createConsentApi(
  fetchImpl: typeof fetch = (...args) => fetch(...args),
  { userId }: { userId?: string } = {},
): ConsentApi {
  const send = async (input: string, init?: RequestInit): Promise<Response> => {
    try {
      return await fetchImpl(input, { credentials: "include", ...init });
    } catch {
      throw new ConsentError("network");
    }
  };
  const call = async (input: string, init?: RequestInit): Promise<unknown> => {
    const response = await send(input, init);
    const body = await bodyOf(response);
    if (!response.ok) throw new ConsentError(consentProblemFrom(response.status, body));
    return body;
  };

  return {
    client: async (clientId) => {
      const query = new URLSearchParams({ client_id: clientId });
      return publicClientFrom(clientId, await call(`${AUTH_BASE}/oauth2/public-client?${query}`));
    },
    decide: async (accept, oauthQuery, wk) => {
      const body = await call(`${AUTH_BASE}/oauth2/consent`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ accept, oauth_query: oauthQuery, ...(wk ? { wk } : {}) }),
      });
      const url = (body as { url?: unknown } | undefined)?.url;
      if (typeof url !== "string" || !url) throw new ConsentError("generic");
      return url;
    },
    putAssistantWrap: async ({ id, keyV, ref, wrap }) => {
      await call(`${API_BASE}/v2/keys/${id}`, {
        method: "PUT",
        headers: {
          "content-type": "application/json",
          ...(userId ? { "x-wambito-user": userId } : {}),
        },
        body: JSON.stringify({ kind: "assistant", ref, keyV, wrapped: wrap }),
      });
    },
    revoke: async (clientId) => {
      const response = await send(`${API_BASE}/v1/me/assistants/${encodeURIComponent(clientId)}`, {
        method: "DELETE",
      });
      if (response.ok || response.status === 404) return;
      throw new ConsentError(consentProblemFrom(response.status, await bodyOf(response)));
    },
  };
}

export const liveConsentApi = createConsentApi();
