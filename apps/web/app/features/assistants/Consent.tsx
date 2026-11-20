import { useQuery } from "@tanstack/react-query";
import { KeysError } from "@wambito/vault";
import { useEffect, useRef, useState } from "react";
import { useLocation } from "react-router";
import { useTranslations } from "use-intl";
import type { DataKeySource } from "../../local/keys.ts";
import { PressButton } from "../../ui/PressButton.tsx";
import { FieldError, ScreenTitle, SignInScreen } from "../sign-in/SignInScreen.tsx";
import { Unlock, type UnlockError } from "../vault/Unlock.tsx";
import type { UnlockMeans } from "../vault/vault-gate.ts";
import { type ConsentApi, ConsentError } from "./consent-api.ts";
import {
  AssistantWrapError,
  allowAssistant,
  type ConsentKeys,
  type ConsentProblem,
  firstKeySource,
  oauthQueryOf,
  type Permission,
  parseConsentQuery,
} from "./consent-model.ts";

const PERMISSION_KEY = {
  "finance:read": "permissions.read",
  "finance:write": "permissions.write",
  offline_access: "permissions.offline",
} as const satisfies Record<Permission, string>;

/** Where the browser goes once the person answers: away from Wambito, to the assistant. */
const leaveTo = (url: string) => window.location.assign(url);

export interface ConsentProps {
  /** Better Auth's oauth-provider by default; stories stand in for it. */
  api: ConsentApi;
  /** A guest (no email yet): the API refuses them, so they are asked to add one first. */
  guest: boolean;
  /** Follows the URL the answer returns; a full page load by default. */
  go?: (url: string) => void;
  /** Now, to tell an expired link before asking anything; the clock by default. */
  now?: () => Date;
  /** An encrypted account: "Allow" gives the assistant its key (spec 2026-11-16 section 5). */
  keys?: ConsentKeys;
  /** Whether this browser can use passkeys (WebAuthn); stories stand in for it. */
  passkeysSupported?: () => boolean;
}

const problemOf = (error: unknown): ConsentProblem =>
  error instanceof ConsentError
    ? error.problem
    : error instanceof KeysError && error.code === "offline"
      ? "network"
      : "generic";

const UNLOCK_ERRORS: ReadonlySet<string> = new Set<UnlockError>([
  "bad_recovery_key",
  "wrong_recovery_key",
  "no_prf",
  "no_passkey_wrap",
  "offline",
  "server",
]);

/** A failure while the unlock step shows, as Unlock says it under its field or button. */
function unlockErrorOf(error: unknown): UnlockError {
  if (error instanceof KeysError && UNLOCK_ERRORS.has(error.code)) return error.code as UnlockError;
  return problemOf(error) === "network" ? "offline" : "server";
}

/**
 * An encrypted account without its vault in this browser: the passkey (its PRF) or the recovery
 * key opens the data key, only to connect the assistant (nothing is kept, no device is enrolled).
 * Unlock's pieces, under the consent's title; Cancel goes back to the request.
 */
export function ConsentUnlock({
  onRecovery,
  onPasskey,
  onCancel,
  passkeysSupported,
  means,
}: {
  onRecovery(text: string): Promise<UnlockError | null>;
  onPasskey(): Promise<UnlockError | null>;
  onCancel(): void;
  passkeysSupported?: () => boolean;
  /** What can open the data here (no pairing on this page): picks Unlock's layout. */
  means?: UnlockMeans | undefined;
}) {
  const t = useTranslations("consent");
  return (
    <Unlock
      title={t("unlock_title")}
      lead={null}
      onUnlock={onRecovery}
      onPasskey={onPasskey}
      {...(passkeysSupported ? { passkeysSupported } : {})}
      {...(means ? { means } : {})}
      onSignOut={onCancel}
      exitLabel={t("cancel")}
    />
  );
}

/**
 * The consent went through but the assistant's key was not saved: it could read nothing, so the
 * browser does not go back to it. "Try again" revokes that consent and gives it again with a new
 * secret (`allowAssistant` with `again`).
 */
export function ConsentWrapFailed({
  busy,
  failure,
  onTryAgain,
}: {
  busy: boolean;
  /** Why the last try failed, when it did before reaching the wrap. */
  failure?: string | null;
  onTryAgain(): void;
}) {
  const t = useTranslations("consent");
  return (
    <SignInScreen mood="worried">
      <p role="alert" className="m-0 text-center text-[17px] font-bold text-ink">
        {t("wrap_failed")}
      </p>
      {failure && <FieldError id="consent-error">{failure}</FieldError>}
      <PressButton
        className="w-full"
        disabled={busy}
        aria-busy={busy || undefined}
        onClick={onTryAgain}
      >
        {busy ? t("allowing") : t("try_again")}
      </PressButton>
    </SignInScreen>
  );
}

/**
 * `/oauth/consent` (spec §6.1): Better Auth sends the browser here, with a signed query, when an
 * assistant (Claude, ChatGPT) asks to connect. "<Name> quiere acceder a tus finanzas", its logo,
 * and the domain its client_id lives on, which is what tells a real Claude from a copy; then
 * what it could do, in plain words per scope. Permitir and Cancelar post the signed query back
 * and follow where Better Auth says (the assistant, with a code or `access_denied`).
 *
 * A guest gets "Primero agrega un email" (Settings → Protect your data → add an email, in the
 * app or on the web) instead of Permitir. A link that ran out (ten minutes) or was
 * changed says to start again from the assistant. The heading takes the focus on arrival.
 */
export function Consent({
  api,
  guest,
  go = leaveTo,
  now = () => new Date(),
  keys,
  passkeysSupported,
}: ConsentProps) {
  const t = useTranslations("consent");
  const tErrors = useTranslations("errors");
  const tCommon = useTranslations("common");
  const { search } = useLocation();
  const [request] = useState(() => parseConsentQuery(search));
  const [expiredOnArrival] = useState(
    () => !request || (request.expiresAt !== null && request.expiresAt < now()),
  );
  const client = useQuery({
    queryKey: ["oauth-client", request?.clientId],
    queryFn: () => api.client(request?.clientId ?? ""),
    enabled: !expiredOnArrival,
    retry: false,
    staleTime: Number.POSITIVE_INFINITY,
  });
  const [busy, setBusy] = useState<"allow" | "cancel" | null>(null);
  const [problem, setProblem] = useState<ConsentProblem | null>(null);
  // A ref, not state: two quick taps must not post twice.
  const inFlight = useRef(false);
  const heading = useRef<HTMLHeadingElement>(null);
  /**
   * An encrypted account's steps after "Allow": `unlock` (no vault here: a passkey or the
   * recovery key), `wrap_failed` (consented, key not saved), `leaving` (on the way back).
   */
  const [step, setStep] = useState<"ask" | "unlock" | "wrap_failed" | "leaving">("ask");
  // After a wrap that was not saved, every later try revokes the consent first.
  const again = useRef(false);

  const clientProblem = client.isError ? problemOf(client.error) : null;
  const expired = expiredOnArrival || clientProblem === "expired" || problem === "expired";
  const asGuest = guest || problem === "guest";
  const ready = client.data !== undefined;

  // The screen appears without a tap on a link: a screen reader starts at its heading.
  useEffect(() => {
    if (expired || ready) heading.current?.focus();
  }, [expired, ready]);

  async function answer(accept: boolean) {
    if (inFlight.current) return;
    if (accept && keys) {
      const source = firstKeySource(keys);
      if (source) await giveKey(source);
      else setStep("unlock");
      return;
    }
    inFlight.current = true;
    setBusy(accept ? "allow" : "cancel");
    setProblem(null);
    try {
      const oauthQuery = oauthQueryOf(search);
      go(
        accept && request
          ? await allowAssistant({ api, clientId: request.clientId, oauthQuery })
          : await api.decide(accept, oauthQuery),
      );
      // Busy until the page is gone: the assistant's address is loading.
    } catch (error) {
      inFlight.current = false;
      setBusy(null);
      setProblem(problemOf(error));
    }
  }

  /**
   * An encrypted account's "Allow" with DK from `source` (spec 2026-11-16 section 5). Resolves to
   * the error the unlock step shows, or null: it went (`leaving`), or moved to another step. The
   * vault here failing to open (removed, tampered) asks for a passkey or the recovery key instead.
   */
  async function giveKey(source: DataKeySource): Promise<UnlockError | null> {
    if (!keys || !request || inFlight.current) return null;
    inFlight.current = true;
    setBusy("allow");
    setProblem(null);
    try {
      const url = await allowAssistant({
        api,
        clientId: request.clientId,
        oauthQuery: oauthQueryOf(search),
        key: { userId: keys.userId, open: (fn) => keys.open(source, fn) },
        again: again.current,
      });
      setStep("leaving");
      go(url);
      return null;
    } catch (error) {
      inFlight.current = false;
      setBusy(null);
      if (error instanceof AssistantWrapError) {
        again.current = true;
        setProblem(error.problem === "network" ? "network" : null);
        setStep("wrap_failed");
        return null;
      }
      const unopened =
        error instanceof KeysError &&
        (error.code === "device_removed" || error.code === "tampered");
      if ("device" in source && unopened) {
        setStep("unlock");
        return null;
      }
      const consentProblem = error instanceof ConsentError ? error.problem : null;
      if (
        consentProblem === "expired" ||
        consentProblem === "guest" ||
        consentProblem === "session_changed"
      ) {
        setProblem(consentProblem);
        setStep("ask");
        return null;
      }
      if (step === "unlock" && !("device" in source)) return unlockErrorOf(error);
      setProblem(problemOf(error));
      return null;
    }
  }

  /** The unlock step's passkey: a touch for its PRF, which opens DK; the PRF is zeroed after. */
  async function passkeyKey(): Promise<UnlockError | null> {
    if (!keys) return null;
    let touched: Awaited<ReturnType<ConsentKeys["touchPasskey"]>>;
    try {
      touched = await keys.touchPasskey();
    } catch (error) {
      return unlockErrorOf(error);
    }
    if (!touched) return null;
    try {
      return await giveKey(touched);
    } finally {
      touched.prf.fill(0);
    }
  }

  /** "Try again" after a wrap that was not saved: the same way in as the first time. */
  function tryAgain() {
    if (!keys) return;
    const source = firstKeySource(keys);
    if (source) void giveKey(source);
    else setStep("unlock");
  }

  if (step === "leaving") {
    return (
      <SignInScreen>
        <p role="status" className="m-0 text-ink-muted">
          {t("allowing")}
        </p>
      </SignInScreen>
    );
  }

  // The cookie now belongs to another account: nothing here may go on for this one.
  if (problem === "session_changed") {
    return (
      <SignInScreen mood="worried">
        <p role="alert" className="m-0 text-center text-[17px] font-bold text-ink">
          {tErrors("session_changed")}
        </p>
      </SignInScreen>
    );
  }

  if (expired) {
    return (
      <SignInScreen mood="worried">
        <ScreenTitle ref={heading} focusable>
          {t("expired.title")}
        </ScreenTitle>
        <p className="m-0 text-center text-ink-muted">{t("expired.body")}</p>
      </SignInScreen>
    );
  }

  if (!client.data) {
    return (
      <SignInScreen>
        {clientProblem ? (
          <>
            <FieldError id="consent-error">
              {clientProblem === "network" ? tErrors("network_error") : t("failed")}
            </FieldError>
            <PressButton variant="secondary" onClick={() => void client.refetch()}>
              {tCommon("retry")}
            </PressButton>
          </>
        ) : (
          <p role="status" className="m-0 text-ink-muted">
            {t("loading")}
          </p>
        )}
      </SignInScreen>
    );
  }

  const { name, icon, domain } = client.data;
  const failure =
    problem === "network" ? tErrors("network_error") : problem === "generic" ? t("failed") : null;

  if (step === "unlock") {
    return (
      <ConsentUnlock
        onRecovery={(text) => giveKey({ recovery: text })}
        onPasskey={passkeyKey}
        onCancel={() => setStep(again.current ? "wrap_failed" : "ask")}
        {...(passkeysSupported ? { passkeysSupported } : {})}
        means={keys?.means}
      />
    );
  }

  if (step === "wrap_failed") {
    return <ConsentWrapFailed busy={busy !== null} failure={failure} onTryAgain={tryAgain} />;
  }

  return (
    <SignInScreen>
      {icon && (
        <img
          src={icon}
          alt={t("logo_alt", { name })}
          width={56}
          height={56}
          referrerPolicy="no-referrer"
          className="size-14 rounded-lg border-2 border-stroke bg-surface-row object-contain"
        />
      )}
      <ScreenTitle ref={heading} focusable>
        {t("title", { name })}
      </ScreenTitle>
      <div className="flex w-full flex-col items-center gap-(--space-1) rounded-md border-2 border-stroke bg-surface-row p-(--space-3) text-center">
        {domain ? (
          <>
            <p className="m-0 break-all text-[17px] font-bold text-ink">{t("from", { domain })}</p>
            <p className="m-0 text-[14px] text-ink-muted">{t("domain_hint")}</p>
          </>
        ) : (
          <p className="m-0 text-[15px] font-bold text-ink">{t("no_domain")}</p>
        )}
      </div>
      {request && request.permissions.length > 0 && (
        <div className="flex w-full flex-col gap-(--space-2)">
          <h2 className="m-0 text-[15px] font-bold text-ink">{t("permissions_title")}</h2>
          <ul className="m-0 flex list-disc flex-col gap-(--space-2) pl-(--space-5) text-ink marker:text-ink-muted">
            {request.permissions.map((permission) => (
              <li
                key={permission}
                className={permission === "offline_access" ? "text-[14px] text-ink-muted" : ""}
              >
                {t(PERMISSION_KEY[permission])}
              </li>
            ))}
          </ul>
          <p className="m-0 text-[14px] text-ink-muted">{t("revoke_hint")}</p>
        </div>
      )}
      {keys && !asGuest && <p className="m-0 w-full text-[14px] text-ink">{t("encrypted_note")}</p>}
      {asGuest && (
        <section
          aria-labelledby="consent-guest"
          className="flex w-full flex-col gap-(--space-1) rounded-md border-2 border-gold p-(--space-3)"
        >
          <h2 id="consent-guest" className="m-0 font-display text-[20px] font-bold text-ink">
            {t("guest.title")}
          </h2>
          <p className="m-0 text-[15px] text-ink">{t("guest.body")}</p>
        </section>
      )}
      {failure && <FieldError id="consent-error">{failure}</FieldError>}
      <div className="flex w-full flex-col gap-(--space-2)">
        {!asGuest && (
          <PressButton
            className="w-full"
            disabled={busy !== null}
            aria-busy={busy === "allow" || undefined}
            aria-describedby={failure ? "consent-error" : undefined}
            onClick={() => void answer(true)}
          >
            {busy === "allow" ? t("allowing") : t("allow")}
          </PressButton>
        )}
        <PressButton
          variant={asGuest ? "secondary" : "ghost"}
          className="w-full"
          disabled={busy !== null}
          aria-busy={busy === "cancel" || undefined}
          onClick={() => void answer(false)}
        >
          {t("cancel")}
        </PressButton>
      </div>
    </SignInScreen>
  );
}
