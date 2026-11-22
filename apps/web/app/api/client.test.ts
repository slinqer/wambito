import { describe, expect, it, vi } from "vitest";
import { createApiClient, unauthorizedRedirect } from "./client.ts";
import { ApiProblem } from "./errors.ts";

const BASE = "http://localhost/api";

function problemResponse(status: number, code: string) {
  return new Response(JSON.stringify({ type: "about:blank", title: "x", status, code }), {
    status,
    headers: { "content-type": "application/problem+json" },
  });
}

describe("unauthorizedRedirect", () => {
  it("sends the signed-out visitor to sign-in, remembering where they were", () => {
    expect(
      unauthorizedRedirect({ pathname: "/app/insights", search: "?m=2026-10", hash: "" }),
    ).toBe("/sign-in?next=%2Fapp%2Finsights%3Fm%3D2026-10");
  });

  it("does not loop on the sign-in page itself", () => {
    expect(
      unauthorizedRedirect({ pathname: "/sign-in", search: "?next=%2Fapp", hash: "" }),
    ).toBeNull();
    expect(unauthorizedRedirect({ pathname: "/sign-in/", search: "", hash: "" })).toBeNull();
  });

  it("is not fooled by a path that merely starts like sign-in", () => {
    expect(unauthorizedRedirect({ pathname: "/sign-inn", search: "", hash: "" })).toBe(
      "/sign-in?next=%2Fsign-inn",
    );
  });
});

describe("createApiClient", () => {
  it("throws an ApiProblem for a non-2xx response", async () => {
    const fetch = vi.fn(async () => problemResponse(409, "category_name_taken"));
    const client = createApiClient({ fetch, baseUrl: BASE, onUnauthorized: vi.fn() });
    const error = await client.GET("/v1/categories").catch((e: unknown) => e);
    expect(error).toBeInstanceOf(ApiProblem);
    expect(error).toMatchObject({ status: 409, code: "category_name_taken" });
  });

  it("a 426 is update_required, whatever its body (a proxy's page, say)", async () => {
    const fetch = vi.fn(async () => new Response("<html>Upgrade Required</html>", { status: 426 }));
    const client = createApiClient({ fetch, baseUrl: BASE, onUnauthorized: vi.fn() });
    await expect(client.GET("/v1/categories")).rejects.toMatchObject({
      status: 426,
      code: "update_required",
    });
  });

  it("returns data for a 2xx response", async () => {
    const fetch = vi.fn(
      async () => new Response("[]", { headers: { "content-type": "application/json" } }),
    );
    const client = createApiClient({ fetch, baseUrl: BASE, onUnauthorized: vi.fn() });
    const { data } = await client.GET("/v1/recurrences");
    expect(data).toEqual([]);
  });

  it("leaves the admin panel's 401 (verify with a passkey) to the panel: no sign-in", async () => {
    const onUnauthorized = vi.fn();
    const fetch = vi.fn(async () => problemResponse(401, "admin_verification_required"));
    const client = createApiClient({ fetch, baseUrl: BASE, onUnauthorized });
    await expect(client.GET("/v1/admin/me")).rejects.toMatchObject({
      status: 401,
      code: "admin_verification_required",
    });
    expect(onUnauthorized).not.toHaveBeenCalled();
  });

  it("sends no authorization header: the admin guard refuses one (cookies only)", async () => {
    const fetch = vi.fn(async (_input: RequestInfo | URL) => new Response(null, { status: 204 }));
    const client = createApiClient({ fetch, baseUrl: BASE, onUnauthorized: vi.fn() });
    await client.POST("/v1/admin/verify/options");
    const request = fetch.mock.calls[0]?.[0] as Request;
    expect(request.headers.has("authorization")).toBe(false);
    expect(request.credentials).toBe("include");
  });

  it("calls the signed-out handler on 401 and still throws", async () => {
    const onUnauthorized = vi.fn();
    const fetch = vi.fn(async () => problemResponse(401, "unauthenticated"));
    const client = createApiClient({ fetch, baseUrl: BASE, onUnauthorized });
    await expect(client.GET("/v1/me")).rejects.toMatchObject({ status: 401 });
    expect(onUnauthorized).toHaveBeenCalledOnce();
  });

  it("sends the session cookie and goes through the injected fetch", async () => {
    const fetch = vi.fn<typeof globalThis.fetch>(
      async () => new Response("[]", { headers: { "content-type": "application/json" } }),
    );
    const client = createApiClient({ fetch, baseUrl: BASE, onUnauthorized: vi.fn() });
    await client.GET("/v1/recurrences");
    const request = fetch.mock.calls[0]?.[0] as Request;
    expect(request.url).toBe(`${BASE}/v1/recurrences`);
    expect(request.credentials).toBe("include");
  });

  it("turns a lost connection into a network_error problem", async () => {
    const fetch = vi.fn(async () => {
      throw new TypeError("Failed to fetch");
    });
    const client = createApiClient({ fetch, baseUrl: BASE, onUnauthorized: vi.fn() });
    await expect(client.GET("/v1/me")).rejects.toMatchObject({ status: 0, code: "network_error" });
  });
});

describe("createApiClient errors that are not a lost connection", () => {
  it("keeps a bug behind fetch visible as itself", async () => {
    const fetch = vi.fn(async () => {
      throw new RangeError("demo backend bug");
    });
    const client = createApiClient({ fetch, baseUrl: BASE, onUnauthorized: vi.fn() });
    await expect(client.GET("/v1/me")).rejects.toThrowError("demo backend bug");
  });
});
