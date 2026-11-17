import { fromBase64Url, generateDataKey, unwrapDataKey } from "@wambito/crypto";
import { renderToString } from "react-dom/server";
import { MemoryRouter } from "react-router";
import { IntlProvider } from "use-intl";
import { describe, expect, it, vi } from "vitest";
import { CATALOGS } from "../../i18n/catalog.ts";
import { ThemeProvider } from "../../theme/ThemeProvider.tsx";
import { ConsentUnlock, ConsentWrapFailed } from "./Consent.tsx";
import { createConsentApi } from "./consent-api.ts";
import { AssistantWrapError, allowAssistant, firstKeySource } from "./consent-model.ts";

const CLIENT = "https://claude.ai/oauth/mcp-oauth-client-metadata";
const QUERY = `client_id=${encodeURIComponent(CLIENT)}&scope=finance%3Aread&exp=1793450000&sig=s1g`;
const USER = "u_consent";
const REDIRECT = "https://claude.ai/api/mcp/auth_callback?code=c0de&state=st";

/** Better Auth's consent, `/v2/keys` and the assistants route, recording every request. */
function fakeServer(options: { failPut?: boolean } = {}) {
  const calls: Array<{ method: string; path: string; body: Record<string, unknown> | null }> = [];
  /** `sessionChanged`: the cookie is another account's, so calls naming USER get 409. */
  const state = { failPut: options.failPut ?? false, sessionChanged: false };
  const fetchImpl = vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
    const method = init?.method ?? "GET";
    const path = String(input);
    calls.push({ method, path, body: init?.body ? JSON.parse(String(init.body)) : null });
    if (state.sessionChanged && new Headers(init?.headers).get("x-wambito-user") === USER) {
      return Response.json({ code: "session_changed" }, { status: 409 });
    }
    if (path === "/api/auth/oauth2/consent")
      return Response.json({ redirect: true, url: REDIRECT });
    if (path.startsWith("/api/v2/keys/")) {
      return state.failPut
        ? Response.json({ code: "unavailable" }, { status: 503 })
        : Response.json({});
    }
    if (path.startsWith("/api/v1/me/assistants/")) return new Response(null, { status: 204 });
    return new Response(null, { status: 404 });
  });
  const api = createConsentApi(fetchImpl, { userId: USER });
  return { api, calls, state };
}

/** A vault that hands out `dk` at `keyV`, as `withDataKeyFrom` does, recording the source asked. */
function vaultWith(dk: Uint8Array, keyV: number) {
  const sources: unknown[] = [];
  const handed: Uint8Array[] = [];
  return {
    sources,
    handed,
    keys: {
      userId: USER,
      device: true,
      open: async <T,>(source: unknown, fn: (dk: Uint8Array, keyV: number) => Promise<T>) => {
        sources.push(source);
        const copy = dk.slice();
        handed.push(copy);
        try {
          return await fn(copy, keyV);
        } finally {
          copy.fill(0);
        }
      },
      touchPasskey: async () => null,
    },
  };
}

const render = (node: React.ReactNode) =>
  renderToString(
    <MemoryRouter>
      <ThemeProvider>
        <IntlProvider locale="en" messages={CATALOGS.en} timeZone="UTC">
          {node}
        </IntlProvider>
      </ThemeProvider>
    </MemoryRouter>,
  );

describe("Consent for an encrypted account", () => {
  it("a plain account posts no wk and no wrap", async () => {
    const server = fakeServer();
    const url = await allowAssistant({ api: server.api, clientId: CLIENT, oauthQuery: QUERY });
    expect(url).toBe(REDIRECT);
    expect(server.calls).toEqual([
      {
        method: "POST",
        path: "/api/auth/oauth2/consent",
        body: { accept: true, oauth_query: QUERY },
      },
    ]);
  });

  it("an encrypted account with the vault open: consent with wk, then the assistant wrap under S", async () => {
    const server = fakeServer();
    const dk = generateDataKey();
    const vault = vaultWith(dk, 3);
    // The vault is open here: no touch, DK from this browser's device wrap.
    const source = firstKeySource(vault.keys);
    expect(source).toEqual({ device: true });

    const url = await allowAssistant({
      api: server.api,
      clientId: CLIENT,
      oauthQuery: QUERY,
      key: { userId: USER, open: (fn) => vault.keys.open(source, fn) },
    });
    expect(url).toBe(REDIRECT);
    expect(vault.sources).toEqual([{ device: true }]);
    // consent first, then the wrap (the server accepts it only for a client consented to)
    expect(
      server.calls.map((c) => `${c.method} ${c.path.replace(/[0-9a-f-]{36}$/, "{id}")}`),
    ).toEqual(["POST /api/auth/oauth2/consent", "PUT /api/v2/keys/{id}"]);
    const [consent, put] = server.calls;
    const wk = consent?.body?.wk as string;
    expect(wk).toMatch(/^[A-Za-z0-9_-]{43}$/);
    expect(put?.body).toMatchObject({ kind: "assistant", ref: CLIENT, keyV: 3 });
    const opened = await unwrapDataKey(
      fromBase64Url(wk),
      { kind: "assistant", userId: USER, keyV: 3 },
      fromBase64Url(put?.body?.wrapped as string),
    );
    expect(opened).toEqual(dk);
    // DK is forgotten once done
    expect(vault.handed[0]?.every((b) => b === 0)).toBe(true);
  });

  it("an encrypted account without the vault offers the passkey and the recovery key", async () => {
    expect(firstKeySource({ device: false })).toBeNull();
    const html = render(
      <ConsentUnlock
        onRecovery={async () => null}
        onPasskey={async () => null}
        onCancel={() => undefined}
        passkeysSupported={() => true}
      />,
    );
    expect(html).toContain("Open your data to connect it");
    expect(html).toContain("Recovery key");
    expect(html).toContain("Use a passkey");
    // nothing about this browser keeping the data: it is opened only to connect
    expect(html).not.toContain("in this browser");
  });

  it("a failed wrap PUT says so; Try again revokes and consents again with a new S", async () => {
    const server = fakeServer({ failPut: true });
    const vault = vaultWith(generateDataKey(), 1);
    const key = { userId: USER, open: vault.keys.open.bind(null, { device: true }) };
    const first = await allowAssistant({
      api: server.api,
      clientId: CLIENT,
      oauthQuery: QUERY,
      key,
    }).catch((e) => e);
    expect(first).toBeInstanceOf(AssistantWrapError);

    const html = render(<ConsentWrapFailed busy={false} onTryAgain={() => undefined} />);
    expect(html).toContain("It was allowed but its key wasn&#x27;t saved");
    expect(html).toContain("Try again");

    const firstWk = server.calls[0]?.body?.wk as string;
    server.state.failPut = false;
    server.calls.length = 0;
    const url = await allowAssistant({
      api: server.api,
      clientId: CLIENT,
      oauthQuery: QUERY,
      key,
      again: true,
    });
    expect(url).toBe(REDIRECT);
    expect(
      server.calls.map((c) => `${c.method} ${c.path.replace(/[0-9a-f-]{36}$/, "{id}")}`),
    ).toEqual([
      `DELETE /api/v1/me/assistants/${encodeURIComponent(CLIENT)}`,
      "POST /api/auth/oauth2/consent",
      "PUT /api/v2/keys/{id}",
    ]);
    const secondWk = server.calls[1]?.body?.wk as string;
    expect(secondWk).toMatch(/^[A-Za-z0-9_-]{43}$/);
    expect(secondWk).not.toBe(firstWk);
  });

  it("a cookie that now belongs to another account is no failed wrap: nothing is revoked", async () => {
    const server = fakeServer();
    server.state.sessionChanged = true;
    const vault = vaultWith(generateDataKey(), 1);
    const key = { userId: USER, open: vault.keys.open.bind(null, { device: true }) };
    const first = await allowAssistant({
      api: server.api,
      clientId: CLIENT,
      oauthQuery: QUERY,
      key,
    }).catch((e) => e);
    expect(first).not.toBeInstanceOf(AssistantWrapError);
    expect(first).toMatchObject({ problem: "session_changed" });
    // The consent names the account too: refused, so no consent and no wrap for the other one.
    expect(server.calls.map((c) => c.method)).toEqual(["POST"]);

    // a retry after a real wrap failure, with the cookie switched since: the revoke names the
    // account, gets 409, and nothing else is sent
    server.calls.length = 0;
    const again = await allowAssistant({
      api: server.api,
      clientId: CLIENT,
      oauthQuery: QUERY,
      key,
      again: true,
    }).catch((e) => e);
    expect(again).toMatchObject({ problem: "session_changed" });
    expect(server.calls.map((c) => c.method)).toEqual(["DELETE"]);
  });
});
