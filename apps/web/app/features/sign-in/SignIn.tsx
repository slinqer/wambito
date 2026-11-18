import {
  type FormEvent,
  useCallback,
  useEffect,
  useId,
  useLayoutEffect,
  useRef,
  useState,
} from "react";
import { Link, useLocation, useSearchParams } from "react-router";
import { useTranslations } from "use-intl";
import { useLocale } from "../../i18n/IntlProvider.tsx";
import { deviceLabel } from "../../local/device-label.ts";
import { realClock } from "../../local/relay.ts";
import { cx } from "../../ui/cx.ts";
import { FingerprintIcon } from "../../ui/FingerprintIcon.tsx";
import { PressButton } from "../../ui/PressButton.tsx";
import { useToast } from "../../ui/Toast.tsx";
import {
  type AuthErrorKey,
  type AuthFailure,
  type AuthResult,
  type AuthUser,
  authErrorKey,
  CODE_ERRORS,
  DEFAULT_SIGN_IN_WAIT_S,
  EMAIL,
  passkeyErrorKey,
  type SignInAuth,
  type SignInMethod,
  signInLocale,
} from "./auth.ts";
import { CODE_LENGTH, CodeInput, type CodeInputHandle } from "./CodeInput.tsx";
import { oneAtATime } from "./one-at-a-time.ts";
import { QrSignIn } from "./QrSignIn.tsx";
import { RecoveryKeySignIn } from "./RecoveryKeySignIn.tsx";
import { FieldError, ScreenTitle, SignInScreen } from "./SignInScreen.tsx";
import { createQrSignin, type QrSignin } from "./signin-model.ts";
import { useFinishSignIn } from "./use-finish-sign-in.ts";
import { useSecondsUntil } from "./use-seconds-until.ts";

/** How long "resend" waits after a code was sent. */
export const RESEND_DELAY_MS = 30_000;

/** What `/auth/verify` passes when it sends a new code: open at the code step for this email. */
export interface SignInState {
  email: string;
  codeSent: true;
}

function isSignInState(state: unknown): state is SignInState {
  return (
    typeof state === "object" &&
    state !== null &&
    typeof (state as SignInState).email === "string" &&
    (state as SignInState).codeSent === true
  );
}

/** What the QR panel's model sees of the page: visible means the tab is shown and the panel on screen. */
export interface QrPage {
  visible(): boolean;
  onVisibility(cb: () => void): () => void;
}

/** Makes the QR panel's model once the panel is on screen; stories pass a fake one. */
export type QrFactory = (page: QrPage) => QrSignin;

/** The live model: `createQrSignin` over `auth.startQrSignin`, this browser's label and clock. */
export const liveQrFactory =
  (auth: Pick<SignInAuth, "startQrSignin">): QrFactory =>
  (page) =>
    createQrSignin({
      start: auth.startQrSignin,
      label: deviceLabel(typeof navigator === "undefined" ? "" : navigator.userAgent),
      clock: realClock,
      ...page,
    });

/** From this width up (Tailwind's `md`), the screen is a computer's: the QR comes first (ruling 12). */
export const WIDE_PX = 768;

export interface SignInProps {
  auth: SignInAuth;
  /** `/sign-in` (every way in, the QR first) or `/create-account` (the email form only). */
  mode?: "sign-in" | "create";
  /** The QR panel's model; `liveQrFactory(auth)` by default. */
  qr?: QrFactory;
  /** Shortened by stories. */
  resendDelayMs?: number;
}

type Busy = "send" | "verify" | "passkey" | "resend" | null;

/**
 * `/sign-in`: no passwords. The QR for the phone to approve (web plan rulings 8–12), and "Other
 * ways to sign in": with a passkey used here before, "Sign in with fingerprint"; "Recovery key";
 * the email step, which sends a 6-digit code that the code step takes. On a computer the QR comes
 * first, on a phone the other ways do. `mode: "create"` (`/create-account`) is the email step
 * alone, under "Create your account".
 * The same email carries a magic link to `/auth/verify`. `?next=` is where to go afterwards (same
 * origin only) and `?lang=` (from the landing) the language of the page and of a new profile.
 */
export function SignIn({
  auth,
  mode = "sign-in",
  qr,
  resendDelayMs = RESEND_DELAY_MS,
}: SignInProps) {
  const t = useTranslations("sign_in");
  const tRoot = useTranslations();
  const toast = useToast();
  const finish = useFinishSignIn(auth);
  const location = useLocation();
  const [params] = useSearchParams();
  const next = params.get("next");
  const { locale, setLocale } = useLocale();
  // The landing's `?lang=`, else the browser's language: for these pages, the email and a new
  // profile. Read once, so a later locale switch can't change it under the person.
  const [lang] = useState(() =>
    signInLocale(
      params.get("lang"),
      typeof navigator === "undefined" ? undefined : navigator.language,
    ),
  );

  // Before paint, so a visitor from the English landing never sees a Spanish frame.
  useLayoutEffect(() => {
    if (lang !== locale) setLocale(lang);
  }, [lang, locale, setLocale]);

  const arrived = isSignInState(location.state) ? location.state : null;
  const [step, setStep] = useState<"email" | "code">(arrived ? "code" : "email");
  const [email, setEmail] = useState(arrived?.email ?? "");
  const [code, setCode] = useState("");
  const [error, setError] = useState<AuthErrorKey | null>(null);
  const [busy, setBusy] = useState<Busy>(null);
  const [resendAt, setResendAt] = useState(() => (arrived ? Date.now() + resendDelayMs : 0));
  const [passkeys] = useState(() => auth.passkeysAvailable());
  // The fingerprint button only shows once a passkey has signed in, or been registered, in this
  // browser: before that the OS would only say "no sign-in available". Read once, like `passkeys`.
  const [fingerprintButton] = useState(() => passkeys && auth.passkeyUsedHere());
  const resendIn = useSecondsUntil(resendAt);
  // After a sign-in 429: when the code may be tried again.
  const [retryAt, setRetryAt] = useState(0);
  const retryIn = useSecondsUntil(retryAt);
  // A ref, not state: Enter and the 6th digit can both submit within one render.
  const inFlight = useRef(false);
  const emailInput = useRef<HTMLInputElement>(null);
  const codeInput = useRef<CodeInputHandle>(null);
  const focusEmailOnShow = useRef(false);
  const emailId = useId();
  const errorId = useId();

  const signedIn = useCallback(
    (user: Pick<AuthUser, "id" | "onboardingCompletedAt">, method: SignInMethod = "email") =>
      finish({ user, next, lang, method }),
    [finish, next, lang],
  );
  // Another way in is finishing (the QR's enroll, a recovery key's unlock): nothing else starts.
  const [qrBusy, setQrBusy] = useState(false);
  const [recoveryBusy, setRecoveryBusy] = useState(false);
  const otherBusy = qrBusy || recoveryBusy;
  const [qrFactory] = useState(() => qr ?? liveQrFactory(auth));
  const [screen, setScreen] = useState<HTMLDivElement | null>(null);
  const wide = useWideScreen(screen);

  /**
   * Runs one auth call at a time. On failure shows `toKey(error)` (nothing when it is null) and
   * returns `{ failed }` with the key, so the caller can react; on success the data.
   */
  async function run<T>(
    kind: Exclude<Busy, null>,
    call: () => Promise<AuthResult<T>>,
    toKey: (error: AuthFailure) => AuthErrorKey | null,
  ): Promise<{ data: T } | { failed: AuthErrorKey | null } | null> {
    if (inFlight.current) return null;
    inFlight.current = true;
    setBusy(kind);
    setError(null);
    try {
      const result = await call();
      if (result.error) {
        const key = toKey(result.error);
        setError(key);
        if (key === "errors.too_many_sign_in_attempts") {
          const wait = result.error.retryAfter ?? DEFAULT_SIGN_IN_WAIT_S;
          setRetryAt(Date.now() + wait * 1000);
        }
        return { failed: key };
      }
      return { data: result.data };
    } finally {
      inFlight.current = false;
      setBusy(null);
    }
  }

  async function sendCode(event: FormEvent) {
    event.preventDefault();
    if (otherBusy) return;
    const address = email.trim().toLowerCase();
    if (!EMAIL.test(address)) {
      setError("errors.invalid_email");
      emailInput.current?.focus();
      return;
    }
    const sent = await run(
      "send",
      () => auth.sendCode(address, { locale: lang, next }),
      (e) => authErrorKey(e, "send"),
    );
    if (!sent || !("data" in sent)) {
      emailInput.current?.focus();
      return;
    }
    setEmail(address);
    setCode("");
    setResendAt(Date.now() + resendDelayMs);
    setStep("code");
  }

  async function verify(candidate: string) {
    if (candidate.length !== CODE_LENGTH || retryIn > 0) return;
    const result = await run(
      "verify",
      () => auth.verifyCode(email, candidate, { locale: lang }),
      (e) => authErrorKey(e, "sign_in"),
    );
    if (!result) return;
    if ("failed" in result) {
      // A wrong code starts over in the first box; a connection or rate-limit problem keeps the
      // code, so "Entrar" tries it again. The error stays until the next try.
      if (result.failed && CODE_ERRORS.has(result.failed)) {
        setCode("");
        codeInput.current?.focus(0);
      }
      return;
    }
    // Stays busy while the profile is read and the next page loads.
    inFlight.current = true;
    setBusy("verify");
    await signedIn(result.data, "email");
  }

  async function resend() {
    const sent = await run(
      "resend",
      () => auth.sendCode(email, { locale: lang, next }),
      (e) => authErrorKey(e, "send"),
    );
    if (!sent || !("data" in sent)) return;
    setCode("");
    setResendAt(Date.now() + resendDelayMs);
    toast.show({ message: t("resent") });
    codeInput.current?.focus(0);
  }

  async function passkey() {
    if (otherBusy) return;
    // the explicit request ends the open conditional one
    autofill.forget();
    const result = await run("passkey", () => auth.signInWithPasskey(), passkeyErrorKey);
    if (!result || !("data" in result)) {
      // The explicit request replaced the conditional one: ask for the autofill again.
      if (result) startAutofill();
      return;
    }
    inFlight.current = true;
    setBusy("passkey");
    await signedIn(result.data, "passkey");
  }

  // The conditional passkey request (WebAuthn conditional mediation): while the email field is
  // there, the browser may offer this site's passkeys in the keyboard or autofill. Picking one
  // signs in. Anything else it comes back with is no news: a newer request taking over, nothing
  // picked, no support. `generation` drops the answers of requests that were replaced; a request
  // still open is reused (`oneAtATime`), since a second one would replace its challenge.
  const generation = useRef(0);
  const [autofill] = useState(() => oneAtATime(() => auth.autofillPasskey()));
  const onAutofillResult = useRef<(user: AuthUser) => void>(() => {});
  useEffect(() => {
    onAutofillResult.current = (user) => {
      if (inFlight.current) return;
      inFlight.current = true;
      setBusy("passkey");
      void signedIn(user, "passkey");
    };
  }, [signedIn]);
  const startAutofill = useCallback(() => {
    generation.current += 1;
    const mine = generation.current;
    void autofill
      .run()
      .then((result) => {
        if (mine === generation.current && !result.error) onAutofillResult.current(result.data);
      })
      .catch(() => {});
  }, [autofill]);
  useEffect(() => {
    // `/create-account` is for someone with no passkey yet: nothing to ask the browser for
    if (step !== "email" || !passkeys || mode === "create") return;
    startAutofill();
    return () => {
      generation.current += 1;
    };
  }, [step, passkeys, mode, startAutofill]);

  function changeEmail() {
    focusEmailOnShow.current = true;
    setStep("email");
    setCode("");
    setError(null);
  }

  // Back from the code step: the email field, ready to fix. (Not on first load: on a phone the
  // keyboard would cover Wambi and the fingerprint button before anyone chose.)
  useEffect(() => {
    if (step !== "email" || !focusEmailOnShow.current) return;
    focusEmailOnShow.current = false;
    emailInput.current?.focus();
  }, [step]);

  const errorText = error ? tRoot(error) : null;

  if (step === "code") {
    return (
      <SignInScreen>
        <ScreenTitle>{t("code_title")}</ScreenTitle>
        <p className="text-center text-ink-muted">
          {t.rich("code_lead", {
            email,
            strong: (chunks) => <strong className="wrap-anywhere text-ink">{chunks}</strong>,
          })}
        </p>
        <form
          noValidate
          className="flex w-full flex-col gap-(--space-3)"
          onSubmit={(event) => {
            event.preventDefault();
            void verify(code);
          }}
        >
          <CodeInput
            ref={codeInput}
            value={code}
            onChange={(value) => {
              setCode(value);
              if (error) setError(null);
            }}
            onComplete={(value) => void verify(value)}
            invalid={error !== null && CODE_ERRORS.has(error)}
            readOnly={busy === "verify"}
            describedBy={errorText ? errorId : undefined}
            autoFocus
          />
          {errorText && <FieldError id={errorId}>{errorText}</FieldError>}
          <PressButton
            type="submit"
            className="w-full"
            disabled={busy !== null || code.length !== CODE_LENGTH || retryIn > 0}
          >
            {busy === "verify"
              ? t("verifying")
              : retryIn > 0
                ? t("wait", { seconds: retryIn })
                : t("submit_code")}
          </PressButton>
        </form>
        {/* Stacked: the countdown changes width every second and must not reflow the row. */}
        <div className="flex flex-col items-center">
          <PressButton variant="ghost" disabled={resendIn > 0 || busy !== null} onClick={resend}>
            {resendIn > 0 ? t("resend_in", { seconds: resendIn }) : t("resend")}
          </PressButton>
          <PressButton variant="ghost" disabled={busy === "verify"} onClick={changeEmail}>
            {t("change_email")}
          </PressButton>
        </div>
      </SignInScreen>
    );
  }

  // A passkey problem is shown under its button; anything else is about the email field.
  const passkeyError = error === "errors.passkey_failed";
  const signIn = mode === "sign-in";
  const emailForm = (
    <form noValidate className="flex w-full flex-col gap-(--space-3)" onSubmit={sendCode}>
      <label htmlFor={emailId} className="text-sm text-ink-muted">
        {t("email_label")}
      </label>
      <div className={cx("lk-input min-h-11", error && !passkeyError && "border-over")}>
        <input
          ref={emailInput}
          id={emailId}
          type="email"
          name="email"
          autoComplete="username webauthn"
          autoCapitalize="none"
          spellCheck={false}
          enterKeyHint="send"
          placeholder={t("email_placeholder")}
          value={email}
          onChange={(event) => {
            setEmail(event.target.value);
            if (error && !passkeyError) setError(null);
          }}
          aria-invalid={(error !== null && !passkeyError) || undefined}
          aria-describedby={error && !passkeyError ? errorId : undefined}
          className="min-h-9 min-w-0 flex-1 border-0 bg-transparent p-0 font-text text-[16px] text-ink outline-none placeholder:font-normal placeholder:text-ink-muted"
        />
      </div>
      {!passkeyError && errorText && <FieldError id={errorId}>{errorText}</FieldError>}
      <PressButton type="submit" className="w-full" disabled={busy !== null || otherBusy}>
        {busy === "send" ? t("sending") : t("send_code")}
      </PressButton>
    </form>
  );

  if (!signIn) {
    return (
      <SignInScreen>
        <ScreenTitle>{t("create.title")}</ScreenTitle>
        <p className="text-center text-ink-muted">{t("create.lead")}</p>
        {emailForm}
        <p className="text-center text-[15px] text-ink-muted">
          {t.rich("create.have_account", {
            link: (chunks) => (
              <Link
                to={{ pathname: "/sign-in", search: location.search }}
                className="font-bold text-ink underline"
              >
                {chunks}
              </Link>
            ),
          })}
        </p>
      </SignInScreen>
    );
  }

  const otherWaysTitleId = `${emailId}-other-ways`;
  const otherWays = (
    <section
      key="other-ways"
      aria-labelledby={wide ? otherWaysTitleId : undefined}
      className="flex w-full flex-col items-center gap-(--space-4)"
    >
      {wide && (
        <h2 id={otherWaysTitleId} className="m-0 text-center text-[20px] font-bold text-ink">
          {t("other_ways")}
        </h2>
      )}
      {fingerprintButton && (
        <>
          <PressButton
            variant="secondary"
            className="w-full"
            disabled={busy !== null || otherBusy}
            onClick={passkey}
          >
            <FingerprintIcon />
            {busy === "passkey" ? t("passkey_busy") : t("passkey")}
          </PressButton>
          {passkeyError && errorText && <FieldError id={errorId}>{errorText}</FieldError>}
        </>
      )}
      <RecoveryKeySignIn
        signIn={(text) => auth.signInWithRecoveryKey(text)}
        onSignedIn={(userId) => signedIn({ id: userId }, "recovery")}
        disabled={busy !== null || qrBusy}
        onBusy={setRecoveryBusy}
      />
      <p className="flex w-full items-center gap-(--space-3) text-sm text-ink-muted before:h-0.5 before:flex-1 before:bg-stroke after:h-0.5 after:flex-1 after:bg-stroke">
        {t("or_email")}
      </p>
      {emailForm}
      <p className="text-center text-[15px] text-ink-muted">{t("first_time")}</p>
    </section>
  );
  const qrArea = (
    <div key="qr" className="flex w-full flex-col items-center gap-(--space-3)">
      {!wide && <p className="m-0 text-center text-ink-muted">{t("qr_on_computer")}</p>}
      <QrArea
        factory={qrFactory}
        onBusy={setQrBusy}
        onSignedIn={(userId) => signedIn({ id: userId }, "qr")}
      />
    </div>
  );
  return (
    <SignInScreen wide={wide} rootRef={setScreen}>
      <ScreenTitle>{t("title")}</ScreenTitle>
      <p className="text-center text-ink-muted">{t("lead")}</p>
      <div
        className={cx(
          "w-full",
          wide
            ? "grid grid-cols-2 items-start gap-(--space-6)"
            : "flex flex-col items-center gap-(--space-6)",
        )}
      >
        {/* Keyed, so a change of layout moves them without remounting the QR's model. */}
        {wide ? [qrArea, otherWays] : [otherWays, qrArea]}
      </div>
    </SignInScreen>
  );
}

/**
 * Whether the screen `el` is a computer's (`WIDE_PX` or wider), measured before paint. It starts
 * from the page's width (`clientWidth`: the screen spans it), so the first render is already
 * right: moving the email field later would end the browser's passkey autofill request.
 */
function useWideScreen(el: HTMLElement | null): boolean {
  const [wide, setWide] = useState(
    // the page's width without the scrollbar: what the screen root measures below
    () => typeof document !== "undefined" && document.documentElement.clientWidth >= WIDE_PX,
  );
  useLayoutEffect(() => {
    if (!el) return;
    const measure = () => setWide(el.getBoundingClientRect().width >= WIDE_PX);
    measure();
    if (typeof ResizeObserver === "undefined") return;
    const observer = new ResizeObserver(measure);
    observer.observe(el);
    return () => observer.disconnect();
  }, [el]);
  return wide;
}

/** The browser's time zone, for the time a throttled QR tries again. */
const browserTimeZone = () => Intl.DateTimeFormat().resolvedOptions().timeZone;

/**
 * The QR panel, its model made only once the panel is on screen (`IntersectionObserver`, ruling
 * 12): every visit would otherwise open a request, and the API allows few per address. Off screen
 * (or in a hidden tab) the model counts as not visible: a shown QR runs to its end and the next
 * one opens when the panel is back. Stopped on unmount; never in between, so an enroll that
 * started (`finishing`) always completes here.
 */
function QrArea({
  factory,
  onSignedIn,
  onBusy,
}: {
  factory: QrFactory;
  onSignedIn(userId: string): void;
  onBusy(busy: boolean): void;
}) {
  const ref = useRef<HTMLDivElement>(null);
  const [model, setModel] = useState<QrSignin | null>(null);
  const [timeZone] = useState(browserTimeZone);
  const factoryRef = useRef(factory);
  factoryRef.current = factory;

  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    let onScreen = false;
    let made: QrSignin | null = null;
    const listeners = new Set<() => void>();
    const page: QrPage = {
      visible: () => onScreen && document.visibilityState === "visible",
      onVisibility(cb) {
        listeners.add(cb);
        document.addEventListener("visibilitychange", cb);
        return () => {
          listeners.delete(cb);
          document.removeEventListener("visibilitychange", cb);
        };
      },
    };
    const changed = (now: boolean) => {
      if (now === onScreen) return;
      onScreen = now;
      if (now && !made) {
        made = factoryRef.current(page);
        setModel(made);
      }
      for (const cb of [...listeners]) cb();
    };
    let observer: IntersectionObserver | null = null;
    if (typeof IntersectionObserver === "undefined") changed(true);
    else {
      observer = new IntersectionObserver((entries) =>
        changed(entries.some((entry) => entry.isIntersecting)),
      );
      observer.observe(el);
    }
    return () => {
      observer?.disconnect();
      made?.stop();
      made = null;
      setModel(null);
    };
  }, []);

  // the other ways wait while this one enrolls
  const onBusyRef = useRef(onBusy);
  onBusyRef.current = onBusy;
  useEffect(() => {
    if (!model) return;
    const report = () => {
      const status = model.state().status;
      onBusyRef.current(status === "finishing" || status === "done");
    };
    report();
    const unsubscribe = model.subscribe(report);
    return () => {
      unsubscribe();
      onBusyRef.current(false);
    };
  }, [model]);

  return (
    <div ref={ref} className="flex min-h-[208px] w-full flex-col items-center">
      {model && <QrSignIn model={model} onSignedIn={onSignedIn} timeZone={timeZone} />}
    </div>
  );
}

/**
 * The passkey offer takes the glyph from here. (Importing it from ui/ there instead makes Rollup
 * split the Spanish catalog out of the shared i18n chunk: +2 KiB gzip on every first load.)
 */
export { FingerprintIcon };
