import { useState } from "react";
import { MemoryRouter, Route, Routes, useLocation } from "react-router";
import { fn } from "storybook/test";
import { exposeStoryFetch } from "../../../.storybook/parity.ts";
import { ApiProvider } from "../../api/ApiProvider.tsx";
import type { PasskeyOutcome } from "../../auth/passkey.ts";
import { realClock } from "../../local/relay.ts";
import type { WebSignin } from "../../local/signin.ts";
import { ToastProvider } from "../../ui/Toast.tsx";
import type {
  AuthFailure,
  AuthResult,
  AuthUser,
  CodeHints,
  RecoveryResult,
  SignInAuth,
} from "./auth.ts";
import { PasskeyOffer, type PasskeyOfferApi } from "./PasskeyOffer.tsx";
import { type QrFactory, type QrPage, SignIn } from "./SignIn.tsx";
import { createQrSignin, type QrSignin } from "./signin-model.ts";
import { Verify } from "./Verify.tsx";

/** The code the fake backend accepts. */
export const GOOD_CODE = "424242";

export const NEW_USER: AuthUser = {
  id: "u-new",
  email: "ana@example.com",
  onboardingCompletedAt: null,
};

export const ONBOARDED_USER: AuthUser = {
  id: "u-old",
  email: "ana@example.com",
  onboardingCompletedAt: "2026-10-01T10:00:00.000Z",
};

export const ok = <T,>(data: T): AuthResult<T> => ({ data, error: null });
export const fail = (error: AuthFailure): AuthResult<never> => ({ data: null, error });

const never = <T,>() => new Promise<T>(() => {});

/** A sign-in request no phone answers: code `ABCDEFGH`. */
export function unansweredRequest(): WebSignin {
  return {
    id: "0190a1b2-c3d4-7e5f-8a9b-0c1d2e3f4a5b",
    code: "ABCDEFGH",
    qr: "wambito://signin?id=0190a1b2-c3d4-7e5f-8a9b-0c1d2e3f4a5b&key=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
    expiresAt: new Date(Date.now() + 2 * 60 * 1000).toISOString(),
    number: never,
    ready: never,
    finish: never,
    cancel: () => {},
  };
}

/** The real QR model over a fake `startSignin` whose request no phone answers. */
export function liveQr(page?: QrPage): QrSignin {
  return createQrSignin({
    start: async () => unansweredRequest(),
    label: "Firefox on macOS",
    clock: realClock,
    visible: page?.visible ?? (() => true),
    onVisibility: page?.onVisibility ?? (() => () => {}),
  });
}

/**
 * A stand-in for Better Auth: `sendCode` always works, `verifyCode` accepts `GOOD_CODE` (and says
 * INVALID_OTP otherwise), passkeys are off unless a story turns them on, no passkey has been used
 * in this browser, the autofill request never ends (nobody picks a passkey) and no passkey offer
 * is due; the recovery key is never one the server knows, and no phone answers the QR. Every
 * method is a spy.
 */
export function fakeAuth(overrides: Partial<SignInAuth> & { user?: AuthUser } = {}): SignInAuth {
  const { user = NEW_USER, ...rest } = overrides;
  return {
    sendCode: fn(async (_email: string, _hints: CodeHints) => ok(true as const)),
    verifyCode: fn(async (_email: string, code: string, _hints: CodeHints) =>
      code === GOOD_CODE ? ok(user) : fail({ code: "INVALID_OTP", status: 400 }),
    ),
    passkeysAvailable: () => false,
    passkeyUsedHere: () => false,
    signInWithPasskey: fn(async () => ok(user)),
    autofillPasskey: fn(() => new Promise<AuthResult<AuthUser>>(() => {})),
    shouldOfferPasskey: fn(async (_userId: string) => false),
    signInWithRecoveryKey: fn(
      async (_text: string): Promise<RecoveryResult> => ({ error: "recovery_key_invalid" }),
    ),
    startQrSignin: fn(async () => unansweredRequest()),
    ...rest,
  };
}

/** A stand-in for the passkey offer's browser side: WebAuthn works and creating a passkey works. */
export function fakeOffer(overrides: Partial<PasskeyOfferApi> = {}): PasskeyOfferApi {
  return {
    supported: () => true,
    add: fn(async (): Promise<PasskeyOutcome> => "added"),
    decide: fn((_userId: string) => {}),
    ...overrides,
  };
}

/** `GET/PATCH /api/v1/me` for the given profile; PATCH bodies go to `onPatch`. */
function profileFetch(user: AuthUser, onPatch: (body: unknown) => void): typeof fetch {
  let profile = {
    id: user.id,
    email: user.email,
    timezone: "Europe/Lisbon",
    locale: "es",
    onboardingCompletedAt: (user.onboardingCompletedAt as string | null | undefined) ?? null,
  };
  return async (input) => {
    const request = input instanceof Request ? input : new Request(input);
    const path = new URL(request.url).pathname;
    if (path !== "/api/v1/me") return new Response(null, { status: 404 });
    if (request.method === "PATCH") {
      const body = (await request.json()) as Partial<typeof profile>;
      onPatch(body);
      profile = { ...profile, ...body };
    }
    return Response.json(profile);
  };
}

/** Shows where the router ended up, so a play test can read it. */
function WhereAmI() {
  const location = useLocation();
  return (
    <output aria-label="Current page" className="sr-only">
      {location.pathname}
    </output>
  );
}

function Landed({ label }: { label: string }) {
  return <p className="p-(--space-4) text-ink">{label}</p>;
}

export interface SignInStageProps {
  auth: SignInAuth;
  /** The passkey offer's browser side; a working one unless a story says otherwise. */
  offer?: PasskeyOfferApi;
  /** Where the router starts: a path, or a location with `state` (e.g. the code step). */
  initialEntry: string | { pathname: string; search?: string; state?: unknown };
  /** The signed-in user's profile, as `GET /v1/me` returns it. */
  profileUser?: AuthUser;
  onPatchMe?: (body: unknown) => void;
  resendDelayMs?: number;
  /** The browser's user agent, for the screens that differ on Android; the real one by default. */
  userAgent?: string;
  /** The QR panel's model; `liveQr` (no phone answers) by default. */
  qr?: QrFactory;
}

/**
 * The sign-in screens inside a memory router, an API provider with a fake `/v1/me` and the
 * toasts, with stand-in pages for where sign-in leads (`/welcome`, `/app/*`).
 */
export function SignInStage({
  auth,
  offer,
  initialEntry,
  profileUser = NEW_USER,
  onPatchMe = () => {},
  resendDelayMs,
  userAgent,
  qr = liveQr,
}: SignInStageProps) {
  const [fetchImpl] = useState(() => exposeStoryFetch(profileFetch(profileUser, onPatchMe)));
  const [fallbackOffer] = useState(() => fakeOffer());
  return (
    <MemoryRouter initialEntries={[initialEntry]}>
      <ApiProvider fetch={fetchImpl}>
        <ToastProvider>
          <Routes>
            <Route
              path="/sign-in"
              element={
                <SignIn
                  auth={auth}
                  qr={qr}
                  {...(resendDelayMs !== undefined ? { resendDelayMs } : {})}
                />
              }
            />
            <Route path="/create-account" element={<SignIn auth={auth} mode="create" qr={qr} />} />
            <Route
              path="/auth/verify"
              element={<Verify auth={auth} {...(userAgent !== undefined ? { userAgent } : {})} />}
            />
            <Route
              path="/passkey-offer"
              element={<PasskeyOffer offer={offer ?? fallbackOffer} userId={profileUser.id} />}
            />
            <Route path="/welcome" element={<Landed label="Welcome (stand-in)" />} />
            <Route path="/app/*" element={<Landed label="App (stand-in)" />} />
          </Routes>
          <WhereAmI />
        </ToastProvider>
      </ApiProvider>
    </MemoryRouter>
  );
}
