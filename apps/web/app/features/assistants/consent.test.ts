import { describe, expect, it, vi } from "vitest";
import { ConsentError, createConsentApi } from "./consent-api.ts";
import {
  clientDomain,
  consentProblemFrom,
  oauthQueryOf,
  parseConsentQuery,
  publicClientFrom,
} from "./consent-model.ts";

const SIGNED =
  "?response_type=code&client_id=https%3A%2F%2Fclaude.ai%2Foauth%2Fmcp-oauth-client-metadata" +
  "&scope=finance%3Aread+finance%3Awrite+offline_access&state=s&exp=1793450000&sig=abc";

describe("parseConsentQuery", () => {
  it("reads the client, the known scopes in a fixed order, and when the link expires", () => {
    expect(parseConsentQuery(SIGNED)).toEqual({
      clientId: "https://claude.ai/oauth/mcp-oauth-client-metadata",
      permissions: ["finance:read", "finance:write", "offline_access"],
      expiresAt: new Date(1793450000 * 1000),
    });
    expect(
      parseConsentQuery("client_id=c1&scope=openid+finance%3Awrite+finance%3Aread&sig=x")
        ?.permissions,
    ).toEqual(["finance:read", "finance:write"]);
  });

  it("is null without a client or a signature, so nothing unsigned is offered", () => {
    expect(parseConsentQuery("")).toBeNull();
    expect(parseConsentQuery("?client_id=c1&scope=finance%3Aread")).toBeNull();
    expect(parseConsentQuery("?sig=abc")).toBeNull();
  });
});

describe("oauthQueryOf", () => {
  it("is the search without its question mark, untouched", () => {
    expect(oauthQueryOf(SIGNED)).toBe(SIGNED.slice(1));
    expect(oauthQueryOf("a=1")).toBe("a=1");
  });
});

describe("clientDomain", () => {
  it("is the host of an https client_id (a metadata document)", () => {
    expect(clientDomain("https://claude.ai/oauth/meta", "https://fake.example")).toBe("claude.ai");
  });

  it("is the website's host for a registered client, and null when there is neither", () => {
    expect(clientDomain("xYz123", "https://chatgpt.com/")).toBe("chatgpt.com");
    expect(clientDomain("http://claude.ai/meta", "https://chatgpt.com")).toBe("chatgpt.com");
    expect(clientDomain("xYz123", "javascript:alert(1)")).toBeNull();
    expect(clientDomain("xYz123", null)).toBeNull();
  });
});

describe("publicClientFrom", () => {
  it("reads Better Auth's RFC 7591 fields", () => {
    expect(
      publicClientFrom("c1", {
        client_id: "c1",
        client_name: "Claude",
        client_uri: "https://claude.ai",
        logo_uri: "https://claude.ai/logo.png",
      }),
    ).toEqual({ name: "Claude", icon: "https://claude.ai/logo.png", domain: "claude.ai" });
  });

  it("falls back to the client_id for a name, and drops a logo that is not https", () => {
    expect(
      publicClientFrom("c1", { client_name: " ", logo_uri: "data:image/png;base64,x" }),
    ).toEqual({ name: "c1", icon: null, domain: null });
  });
});

describe("consentProblemFrom", () => {
  it("asks a guest to save their progress", () => {
    expect(consentProblemFrom(403, { code: "guest_cannot_authorize", message: "…" })).toBe("guest");
  });

  it("sends an expired, tampered or unknown request back to the assistant", () => {
    expect(consentProblemFrom(400, { error: "invalid_signature" })).toBe("expired");
    expect(consentProblemFrom(400, { error: "invalid_request" })).toBe("expired");
    expect(consentProblemFrom(404, { error: "not_found" })).toBe("expired");
    expect(consentProblemFrom(404, undefined)).toBe("expired");
  });

  it("tells that the cookie now belongs to another account", () => {
    expect(consentProblemFrom(409, { code: "session_changed" })).toBe("session_changed");
  });

  it("tells a lost connection from anything else", () => {
    expect(consentProblemFrom(0, undefined)).toBe("network");
    expect(consentProblemFrom(500, "<html>")).toBe("generic");
  });
});

describe("createConsentApi", () => {
  const answer = (status: number, body: unknown) =>
    vi.fn(async (_input: RequestInfo | URL, _init?: RequestInit) =>
      Response.json(body, { status }),
    );

  it("Permitir posts accept: true with the signed query and resolves to the returned url", async () => {
    const fetchImpl = answer(200, { redirect: true, url: "https://claude.ai/cb?code=1&state=s" });
    const url = await createConsentApi(fetchImpl).decide(true, oauthQueryOf(SIGNED));
    expect(url).toBe("https://claude.ai/cb?code=1&state=s");
    const [input, init] = fetchImpl.mock.calls[0] ?? [];
    expect(input).toBe("/api/auth/oauth2/consent");
    expect(init?.method).toBe("POST");
    expect(init?.credentials).toBe("include");
    expect(JSON.parse(String(init?.body))).toEqual({ accept: true, oauth_query: SIGNED.slice(1) });
  });

  it("Cancelar posts accept: false", async () => {
    const fetchImpl = answer(200, {
      redirect: true,
      url: "https://claude.ai/cb?error=access_denied",
    });
    await createConsentApi(fetchImpl).decide(false, "client_id=c1&sig=x");
    expect(JSON.parse(String(fetchImpl.mock.calls[0]?.[1]?.body))).toEqual({
      accept: false,
      oauth_query: "client_id=c1&sig=x",
    });
  });

  it("throws what the refusal means", async () => {
    const guest = createConsentApi(answer(403, { code: "guest_cannot_authorize" }));
    await expect(guest.decide(true, "q")).rejects.toEqual(new ConsentError("guest"));
    const offline = createConsentApi(async () => {
      throw new TypeError("Failed to fetch");
    });
    await expect(offline.decide(true, "q")).rejects.toMatchObject({ problem: "network" });
  });

  it("an encrypted account's Permitir carries wk, the assistant secret", async () => {
    const fetchImpl = answer(200, { redirect: true, url: "https://claude.ai/cb?code=1" });
    await createConsentApi(fetchImpl).decide(true, "client_id=c1&sig=x", "c2VjcmV0");
    expect(JSON.parse(String(fetchImpl.mock.calls[0]?.[1]?.body))).toEqual({
      accept: true,
      oauth_query: "client_id=c1&sig=x",
      wk: "c2VjcmV0",
    });
  });

  it("puts the assistant wrap under /v2/keys, naming the account", async () => {
    const fetchImpl = answer(200, {});
    const id = "01930000-0000-7000-8000-0000000000a1";
    await createConsentApi(fetchImpl, { userId: "u1" }).putAssistantWrap({
      id,
      keyV: 2,
      ref: "https://claude.ai/meta",
      wrap: "d3JhcA",
    });
    const [input, init] = fetchImpl.mock.calls[0] ?? [];
    expect(input).toBe(`/api/v2/keys/${id}`);
    expect(init?.method).toBe("PUT");
    expect(init?.credentials).toBe("include");
    expect(new Headers(init?.headers).get("x-wambito-user")).toBe("u1");
    expect(JSON.parse(String(init?.body))).toEqual({
      kind: "assistant",
      ref: "https://claude.ai/meta",
      keyV: 2,
      wrapped: "d3JhcA",
    });
    const refused = createConsentApi(answer(422, { code: "unknown_assistant" }));
    await expect(
      refused.putAssistantWrap({ id, keyV: 1, ref: "c1", wrap: "x" }),
    ).rejects.toBeInstanceOf(ConsentError);
  });

  it("revokes through the assistants route; one already gone counts as done", async () => {
    const fetchImpl = vi.fn(
      async (_input: RequestInfo | URL, _init?: RequestInit) => new Response(null, { status: 204 }),
    );
    await createConsentApi(fetchImpl, { userId: "u1" }).revoke("https://claude.ai/meta");
    const [input, init] = fetchImpl.mock.calls[0] ?? [];
    expect(input).toBe("/api/v1/me/assistants/https%3A%2F%2Fclaude.ai%2Fmeta");
    expect(init?.method).toBe("DELETE");
    // names the account: a cookie switched to someone else gets 409, never revokes theirs
    expect(new Headers(init?.headers).get("x-wambito-user")).toBe("u1");
    await createConsentApi(answer(404, { code: "not_found" })).revoke("c1");
    await expect(createConsentApi(answer(500, {})).revoke("c1")).rejects.toBeInstanceOf(
      ConsentError,
    );
  });

  it("asks for the public client by its client_id", async () => {
    const fetchImpl = answer(200, { client_name: "Claude", client_uri: "https://claude.ai" });
    const client = await createConsentApi(fetchImpl).client("https://claude.ai/meta");
    expect(fetchImpl.mock.calls[0]?.[0]).toBe(
      "/api/auth/oauth2/public-client?client_id=https%3A%2F%2Fclaude.ai%2Fmeta",
    );
    expect(client).toEqual({ name: "Claude", icon: null, domain: "claude.ai" });
  });
});
