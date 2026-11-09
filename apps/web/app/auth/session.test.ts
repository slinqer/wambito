import { describe, expect, it } from "vitest";
import { ApiProblem } from "../api/errors.ts";
import {
  createGuards,
  DEMO_USER,
  demoGuards,
  type GuardDeps,
  type SessionUser,
  sessionUserFrom,
} from "./session.ts";

const user = (onboardingCompletedAt: string | null): SessionUser => ({
  id: "u1",
  email: "ana@example.com",
  onboardingCompletedAt,
});

function guards(session: SessionUser | null, mode: "live" | "demo" = "live") {
  const deps: GuardDeps = { getSession: async () => session, mode: () => mode };
  return createGuards(deps);
}

/** What a guard threw, as a redirect: its status and Location. */
async function redirectOf(run: () => Promise<unknown>) {
  try {
    await run();
  } catch (thrown) {
    if (thrown instanceof Response) {
      return { status: thrown.status, location: thrown.headers.get("Location") };
    }
    throw thrown;
  }
  return null;
}

describe("requireSession", () => {
  it("redirects a visitor without a session to sign-in, remembering the page", async () => {
    const { requireSession } = guards(null);
    expect(await redirectOf(() => requireSession("/app/insights"))).toEqual({
      status: 302,
      location: "/sign-in?next=%2Fapp%2Finsights",
    });
  });

  it("never lets next point off-site", async () => {
    const { requireSession } = guards(null);
    expect(await redirectOf(() => requireSession("https://evil.example"))).toEqual({
      status: 302,
      location: "/sign-in?next=%2Fapp",
    });
  });

  it("brings a visitor back to the consent screen with its whole signed query", async () => {
    const consent =
      "/oauth/consent?client_id=https%3A%2F%2Fclaude.ai%2Fmeta&scope=finance%3Aread" +
      "&redirect_uri=https%3A%2F%2Fclaude.ai%2Fcb&state=s&exp=1&sig=a%2Bb";
    const { requireSession } = guards(null);
    const redirect = await redirectOf(() => requireSession(consent));
    expect(redirect?.status).toBe(302);
    const next = new URL(redirect?.location ?? "", "http://x").searchParams.get("next");
    expect(next).toBe(consent);
  });

  it("returns the user when signed in", async () => {
    const { requireSession } = guards(user(null));
    expect(await requireSession("/app")).toMatchObject({ id: "u1" });
  });

  it("treats the demo as signed in", async () => {
    const { requireSession } = guards(null, "demo");
    expect(await requireSession("/app")).toEqual(DEMO_USER);
  });
});

describe("requireOnboarded", () => {
  it("sends a user who has not finished onboarding to /welcome", async () => {
    const { requireOnboarded } = guards(user(null));
    expect(await redirectOf(() => requireOnboarded())).toEqual({
      status: 302,
      location: "/welcome",
    });
  });

  it("lets an onboarded user through", async () => {
    const { requireOnboarded } = guards(user("2026-10-01T10:00:00.000Z"));
    expect(await requireOnboarded()).toMatchObject({ id: "u1" });
  });

  it("sends a visitor without a session to sign-in", async () => {
    const { requireOnboarded } = guards(null);
    expect(await redirectOf(() => requireOnboarded("/app/insights"))).toEqual({
      status: 302,
      location: "/sign-in?next=%2Fapp%2Finsights",
    });
  });

  it("treats the demo as onboarded", async () => {
    const { requireOnboarded } = guards(null, "demo");
    expect(await requireOnboarded()).toEqual(DEMO_USER);
  });
});

describe("redirectIfSignedIn", () => {
  const request = (url: string) => ({ request: new Request(`http://localhost${url}`) });

  it("lets a signed-out visitor see the page", async () => {
    const { redirectIfSignedIn } = guards(null);
    expect(await redirectIfSignedIn(request("/sign-in"))).toBeNull();
  });

  it("sends an onboarded user to the app", async () => {
    const { redirectIfSignedIn } = guards(user("2026-10-01T10:00:00.000Z"));
    expect(await redirectOf(() => redirectIfSignedIn(request("/sign-in")))).toEqual({
      status: 302,
      location: "/app",
    });
  });

  it("sends a user still onboarding to /welcome", async () => {
    const { redirectIfSignedIn } = guards(user(null));
    expect((await redirectOf(() => redirectIfSignedIn(request("/sign-in"))))?.location).toBe(
      "/welcome",
    );
  });

  it.each([
    "/.//evil.example",
    "/..//evil.example",
    "/%2e%2e//evil.example",
    "/\\evil.example",
    "%2F%2Fevil.example",
    "javascript:alert(1)",
  ])("never redirects to %j", async (next) => {
    const { redirectIfSignedIn } = guards(user("2026-10-01T10:00:00.000Z"));
    const result = await redirectOf(() =>
      redirectIfSignedIn(request(`/sign-in?next=${encodeURIComponent(next)}`)),
    );
    expect(result?.location).toBe("/app");
  });

  it("honours a same-origin next and ignores an off-site one", async () => {
    const { redirectIfSignedIn } = guards(user("2026-10-01T10:00:00.000Z"));
    expect(
      (await redirectOf(() => redirectIfSignedIn(request("/sign-in?next=%2Fapp%2Finsights"))))
        ?.location,
    ).toBe("/app/insights");
    expect(
      (
        await redirectOf(() =>
          redirectIfSignedIn(request("/sign-in?next=https%3A%2F%2Fevil.example")),
        )
      )?.location,
    ).toBe("/app");
  });
});

describe("sessionUserFrom", () => {
  const ana = user(null);

  it("returns the user, or null for a clean signed-out answer", () => {
    expect(sessionUserFrom({ data: { user: ana }, error: null })).toEqual(ana);
    expect(sessionUserFrom({ data: null, error: null })).toBeNull();
  });

  it("treats 401 and 403 as signed out", () => {
    expect(
      sessionUserFrom({ data: null, error: { status: 401, statusText: "Unauthorized" } }),
    ).toBeNull();
    expect(
      sessionUserFrom({ data: null, error: { status: 403, statusText: "Forbidden" } }),
    ).toBeNull();
  });

  it("throws on a server error, so a blip never signs anyone out", () => {
    expect(() =>
      sessionUserFrom({ data: null, error: { status: 503, statusText: "Unavailable" } }),
    ).toThrowError(expect.objectContaining({ status: 503, code: "internal_error" }));
  });

  it("throws network_error when there was no response", () => {
    expect(() =>
      sessionUserFrom({ data: null, error: { status: 0, statusText: "" } }),
    ).toThrowError(expect.objectContaining({ status: 0, code: "network_error" }));
  });
});

describe("a failed session lookup", () => {
  const failing = createGuards({
    getSession: async () => {
      throw new ApiProblem({ status: 0, code: "network_error" });
    },
    mode: () => "live",
  });

  it("surfaces as an error from every guard, never as a redirect to sign-in", async () => {
    for (const run of [
      () => failing.requireSession("/app"),
      () => failing.requireOnboarded(),
      () => failing.redirectIfSignedIn({ request: new Request("http://localhost/sign-in") }),
    ]) {
      const thrown = await run().catch((e: unknown) => e);
      expect(thrown).toBeInstanceOf(ApiProblem);
      expect(thrown).not.toBeInstanceOf(Response);
    }
  });
});

describe("demoGuards", () => {
  it("sign the demo in without asking for a session", async () => {
    expect(await demoGuards.requireSession("/demo")).toEqual(DEMO_USER);
    expect(await demoGuards.requireOnboarded()).toEqual(DEMO_USER);
  });
});

describe("signed-out loads", () => {
  it("tell onSignedOut, so the browser's leftover vaults go", async () => {
    let calls = 0;
    const { requireSession, redirectIfSignedIn } = createGuards({
      getSession: async () => null,
      mode: () => "live",
      onSignedOut: async () => {
        calls += 1;
      },
    });
    await redirectOf(() => requireSession("/app"));
    await redirectIfSignedIn({ request: new Request("http://x/sign-in") });
    expect(calls).toBe(2);
  });

  it("a signed-in load does not", async () => {
    let calls = 0;
    const { requireSession } = createGuards({
      getSession: async () => user("2026-01-01"),
      mode: () => "live",
      onSignedOut: () => {
        calls += 1;
      },
    });
    await requireSession("/app");
    expect(calls).toBe(0);
  });

  it("a failing cleanup never blocks the guard", async () => {
    const { redirectIfSignedIn } = createGuards({
      getSession: async () => null,
      mode: () => "live",
      onSignedOut: async () => {
        throw new Error("blocked");
      },
    });
    await expect(redirectIfSignedIn({ request: new Request("http://x/sign-in") })).resolves.toBe(
      null,
    );
  });
});
