import { redirect } from "react-router";
import { ApiProblem } from "../api/errors.ts";
import { deleteStaleVaults } from "../local/stale-vaults.ts";
import { authClient } from "./auth-client.ts";
import { DEFAULT_NEXT, safeNext, signInPath } from "./next.ts";

/** What the guards need to know about the signed-in user. */
export interface SessionUser {
  id: string;
  email: string;
  /** When they finished onboarding; null until then. */
  onboardingCompletedAt: string | Date | null;
  /** A guest (Better Auth's anonymous plugin): no email yet. Missing on older sessions. */
  isAnonymous?: boolean | null;
}

/** Who the demo is "signed in" as. */
export const DEMO_USER: SessionUser = {
  id: "demo",
  email: "demo@wambito.test",
  onboardingCompletedAt: "2026-01-01T00:00:00.000Z",
};

export interface GuardDeps {
  /** The current user, or null when signed out. */
  getSession(): Promise<SessionUser | null>;
  mode(): "live" | "demo";
  /**
   * A load found nobody signed in: the live guards delete every vault left in the browser (a
   * session that ended outside the sign-out leaves its vault behind). Failures are ignored.
   */
  onSignedOut?(): Promise<void> | void;
}

interface SessionResult {
  data: { user: unknown } | null;
  error: { status: number; statusText: string } | null;
}

/**
 * The user in a `getSession` answer. Signed out is an answer with no user (or a 401/403); a failure
 * to get an answer at all (no connection, a 5xx) throws, so the route's error boundary offers a
 * retry instead of the guards taking a blip for a sign-out and sending the person to sign-in.
 */
export function sessionUserFrom({ data, error }: SessionResult): SessionUser | null {
  if (error && error.status !== 401 && error.status !== 403) {
    throw new ApiProblem({
      status: error.status,
      code:
        error.status >= 500
          ? "internal_error"
          : error.status === 0
            ? "network_error"
            : "http_error",
    });
  }
  // Better Auth returns the extra user fields the API declares (see apps/api/src/auth.ts).
  return (data?.user as SessionUser | undefined) ?? null;
}

const liveDeps: GuardDeps = {
  getSession: async () => sessionUserFrom(await authClient.getSession()),
  mode: () => "live",
  onSignedOut: () => deleteStaleVaults(null),
};

const isOnboarded = (user: SessionUser) => user.onboardingCompletedAt != null;

/**
 * Route guards, written as `clientLoader` helpers: they return what the loader may use, or throw a
 * redirect (React Router sends the browser there). The app is a client-side SPA, so the session
 * is read in the browser; the API still checks every request.
 *
 *   export const clientLoader = () => requireOnboarded("/app/insights");
 *
 * Loaders run outside React and cannot read `<ApiProvider mode>`, so the guards exported here are
 * the live ones. The demo's routes use `demoGuards`, which sign the made-up user in.
 */
export function createGuards(deps: GuardDeps) {
  /** The signed-in user, or null (the demo always has one). */
  async function currentUser(): Promise<SessionUser | null> {
    if (deps.mode() === "demo") return DEMO_USER;
    const user = await deps.getSession();
    if (!user) {
      try {
        await deps.onSignedOut?.();
      } catch {
        // Next time.
      }
    }
    return user;
  }

  /** Signed in: returns the user. Signed out: sends them to sign-in, and back to `next` after. */
  async function requireSession(next: string): Promise<SessionUser> {
    const user = await currentUser();
    if (!user) throw redirect(signInPath(next));
    return user;
  }

  /** Signed in and done with onboarding. Not onboarded yet: /welcome. */
  async function requireOnboarded(next: string = DEFAULT_NEXT): Promise<SessionUser> {
    const user = await requireSession(next);
    if (!isOnboarded(user)) throw redirect("/welcome");
    return user;
  }

  /**
   * For sign-in and sign-up pages: a visitor who is already signed in goes on to `?next=` (when
   * it is a same-origin path), to the app, or to /welcome if onboarding is unfinished.
   */
  async function redirectIfSignedIn({ request }: { request: Request }): Promise<null> {
    const user = await currentUser();
    if (!user) return null;
    if (!isOnboarded(user)) throw redirect("/welcome");
    throw redirect(safeNext(new URL(request.url).searchParams.get("next")));
  }

  return { requireSession, requireOnboarded, redirectIfSignedIn };
}

export const { requireSession, requireOnboarded, redirectIfSignedIn } = createGuards(liveDeps);

/** The guards for the demo's routes: always signed in and onboarded as `DEMO_USER`. */
export const demoGuards = createGuards({ getSession: async () => DEMO_USER, mode: () => "demo" });
