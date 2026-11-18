import { describe, expect, it } from "vitest";
import { createApiClient } from "../../api/client.ts";
import appEn from "../../i18n/messages/app.en.json" with { type: "json" };
import { ClaimError, claimEmail } from "./add-email.ts";

const PROFILE = {
  id: "u-ana",
  email: "ana@example.com",
  timezone: "Europe/Madrid",
  locale: "es",
  onboardingCompletedAt: null,
  currency: "EUR",
  isAnonymous: false,
  encryption: "preview",
};

/** A claim API that answers `reply(path)` and records what it was sent. */
function setup(reply: (path: string) => Response) {
  const calls: { path: string; body: unknown }[] = [];
  const fetch: typeof globalThis.fetch = async (input) => {
    const request = input as Request;
    const path = new URL(request.url).pathname;
    calls.push({ path, body: await request.json() });
    return reply(path);
  };
  const api = createApiClient({ fetch, baseUrl: "http://x/api", onUnauthorized: () => {} });
  return { claim: claimEmail(api), calls };
}

const problem = (status: number, code: string) => Response.json({ code }, { status });
const keyOf = async (promise: Promise<unknown>) =>
  promise.then(
    () => null,
    (error: unknown) => (error instanceof ClaimError ? error.key : "other"),
  );

describe("claimEmail", () => {
  it("send then verify posts the email and the code", async () => {
    const { claim, calls } = setup((path) =>
      path.endsWith("/send") ? new Response(null, { status: 204 }) : Response.json(PROFILE),
    );
    await claim.send("ana@example.com");
    await claim.verify("ana@example.com", "123456");
    expect(calls).toEqual([
      { path: "/api/v1/me/claim-email/send", body: { email: "ana@example.com" } },
      { path: "/api/v1/me/claim-email/verify", body: { email: "ana@example.com", code: "123456" } },
    ]);
  });

  it("409 email_taken maps to the phone-merge copy (ruling 5)", async () => {
    const { claim } = setup(() => problem(409, "email_taken"));
    const key = await keyOf(claim.send("ana@example.com"));
    expect(key).toBe("settings.add_email.taken");
    expect(appEn.settings.add_email.taken).toBe(
      "This email already has a Wambito account. Open Wambito on your phone to bring this data into it.",
    );
  });

  it("a wrong code maps to the existing code error", async () => {
    const wrong = setup(() => problem(400, "invalid_code"));
    expect(await keyOf(wrong.claim.verify("ana@example.com", "000000"))).toBe(
      "errors.invalid_code",
    );
    const expired = setup(() => problem(400, "invalid_or_expired_code"));
    expect(await keyOf(expired.claim.verify("a@b.co", "000000"))).toBe(
      "errors.invalid_or_expired_code",
    );
    const tries = setup(() => problem(403, "too_many_attempts"));
    expect(await keyOf(tries.claim.verify("a@b.co", "000000"))).toBe("errors.too_many_attempts");
  });

  it("maps the send errors to the sign-in copy", async () => {
    expect(await keyOf(setup(() => problem(429, "too_many_requests")).claim.send("a@b.co"))).toBe(
      "errors.too_many_requests",
    );
    expect(await keyOf(setup(() => problem(422, "validation_error")).claim.send("a@b.co"))).toBe(
      "errors.invalid_email",
    );
    expect(await keyOf(setup(() => problem(403, "sign_in_not_allowed")).claim.send("a@b.co"))).toBe(
      "errors.sign_in_not_allowed",
    );
    expect(await keyOf(setup(() => problem(503, "internal_error")).claim.send("a@b.co"))).toBe(
      "errors.internal_error",
    );
  });
});
