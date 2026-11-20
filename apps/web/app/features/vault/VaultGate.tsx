import { useQueryClient } from "@tanstack/react-query";
import { type ReactNode, useEffect, useState, useSyncExternalStore } from "react";
import { Navigate } from "react-router";
import { useTranslations } from "use-intl";
import { ApiProvider } from "../../api/ApiProvider.tsx";
import { api, unauthorizedRedirect } from "../../api/client.ts";
import { ApiProblem } from "../../api/errors.ts";
import { useMe } from "../../api/queries.ts";
import { authClient } from "../../auth/auth-client.ts";
import { accountPasskeyIds } from "../../auth/passkey.ts";
import {
  addPasskeyWrap,
  hasPasskeyWrap,
  KeysError,
  type LocalKeys,
  loadLocalKeys,
  prepareAccount,
  unlockWithPasskey,
  unlockWithRecovery,
} from "../../local/keys.ts";
import { startPairing } from "../../local/pairing.ts";
import { clearSignInPrf, evaluatePrf, takeSignInPrf } from "../../local/prf.ts";
import {
  notePasskeyOpened,
  notePasskeyWithoutPrf,
  passkeyGaveNoPrf,
} from "../../local/unlock-hint.ts";
import {
  forgetVault,
  openVaultSession,
  rememberPreviewAccount,
  type VaultProfile,
  type VaultSession,
} from "../../local/vault-session.ts";
import { useSignOut } from "../home/use-sign-out.ts";
import { ScreenTitle, SignInScreen } from "../sign-in/SignInScreen.tsx";
import { InstallApp } from "./InstallApp.tsx";
import { Locked } from "./Locked.tsx";
import { PairNewDevice } from "./PairNewDevice.tsx";
import { RecoveryKeySetup } from "./RecoveryKeySetup.tsx";
import { Unlock } from "./Unlock.tsx";
import { VaultSessionContext } from "./vault-context.ts";
import { createVaultGate, type VaultGate as Gate } from "./vault-gate.ts";

/** The session ended under the vault (a 401 from sync): wipe it, then sign in again. */
function signInAgain() {
  void forgetVault()
    .catch(() => {
      // Sign-in still has to happen; the next sign-out tries the wipe again.
    })
    .finally(() => {
      const target = unauthorizedRedirect(window.location);
      if (target) window.location.assign(target);
    });
}

/** A 401 from `/v2/keys` (signed out in another tab, say): sign in again, the gate stays put. */
function signInAgainOn401<T>(promise: Promise<T>): Promise<T> {
  return promise.catch((error: unknown) => {
    if (error instanceof KeysError && error.status === 401) signInAgain();
    throw error;
  });
}

/** Who is signed in now (the live `GET /v1/me`): null when no one; throws when it cannot tell. */
async function sessionUserId(): Promise<string | null> {
  try {
    const { data } = await api.GET("/v1/me");
    if (!data) throw new Error("no profile");
    return data.id;
  } catch (error) {
    // Signed out (the client already heads for sign-in); anything else: cannot tell.
    if (error instanceof ApiProblem && error.status === 401) return null;
    throw error;
  }
}

/**
 * The id of the session signed in now (Better Auth's `get-session`): a kept vault links its device
 * wrap to it, so a removal ends this session. Null when it cannot tell.
 */
async function liveSessionId(): Promise<string | null> {
  const { data } = await authClient.getSession();
  return data?.session?.id ?? null;
}

/** Another account signed in under this page: load the app again, for them (never the old vault). */
function reloadApp() {
  window.location.assign("/app");
}

/** The live gate of `profile`'s account (exported for its wiring tests). */
export function gateFor(profile: VaultProfile): Gate<VaultSession, LocalKeys> {
  const userId = profile.id;
  // Set below: the open session's sync tells the gate when the cookie changed hands.
  let gate: Gate<VaultSession, LocalKeys> | undefined;
  gate = createVaultGate({
    loadLocalKeys: () => loadLocalKeys(userId),
    prepareAccount: () => signInAgainOn401(prepareAccount({ userId, guest: profile.isAnonymous })),
    unlockWithRecovery: (text) => signInAgainOn401(unlockWithRecovery({ userId, text })),
    // The passkey the person signed in (or registered) with, then Unlock's "Use a passkey".
    takeSignInPrf: () => takeSignInPrf(userId),
    unlockWithPasskey: (passkey) => signInAgainOn401(unlockWithPasskey({ userId, ...passkey })),
    addPasskeyWrap: (passkey) => addPasskeyWrap({ userId, ...passkey }),
    evaluatePrf: (ids) => evaluatePrf(ids),
    accountPasskeyIds,
    // What can open the data on this device: the "no PRF here" hint and the account's wraps.
    passkeyGaveNoPrf: () => passkeyGaveNoPrf(userId),
    notePasskeyWithoutPrf: () => notePasskeyWithoutPrf(userId),
    notePasskeyOpened: () => notePasskeyOpened(userId),
    // Never a reason to sign in again: a removal ends the session, and its notice must show.
    // Any failure (a 401 included) counts as a wrap.
    hasPasskeyWrap: () => hasPasskeyWrap({ userId }),
    // "From another device": a device that has the data approves this one.
    startPairing: () => signInAgainOn401(startPairing({ userId })),
    open: (keys, fresh) =>
      openVaultSession({
        profile,
        keys,
        fresh,
        onUnauthorized: signInAgain,
        onSessionChanged: () => gate?.sessionChanged(),
        sessionId: liveSessionId,
      }),
    userId,
    sessionUserId,
    reload: reloadApp,
  });
  return gate;
}

/** While the vault opens or syncs for the first time. */
export function VaultLoading() {
  const t = useTranslations("vault");
  return (
    <SignInScreen>
      <ScreenTitle>{t("loading")}</ScreenTitle>
      <div aria-busy="true" />
    </SignInScreen>
  );
}

/**
 * A preview account's way in (stage 2a): set up the recovery key, unlock with it, or open the keys
 * this browser kept; then the screens run on the local backend (`<ApiProvider mode="local">`),
 * refetching after every commit to the vault (a sync that brought something in, say).
 */
export function VaultGate({ profile, children }: { profile: VaultProfile; children: ReactNode }) {
  const [gate] = useState(() => gateFor(profile));
  useEffect(() => {
    rememberPreviewAccount(profile.id);
    gate.start();
  }, [gate, profile.id]);
  const state = useSyncExternalStore(gate.subscribe, gate.getState, gate.getState);
  const session = state.status === "ready" ? state.session : null;
  useEffect(() => session?.onClosed(() => gate.closed()), [session, gate]);
  // Removed from the account by another device: the vault is gone, Unlock says so.
  useEffect(() => session?.onRemoved(() => gate.removed()), [session, gate]);
  // A new key version did not verify: the vault is kept, Unlock asks for a passkey or the key.
  useEffect(() => session?.onUnverified(() => gate.unverified()), [session, gate]);
  // The open app needs no passkey PRF: whatever is still kept is zeroed.
  useEffect(() => {
    if (session) clearSignInPrf();
  }, [session]);
  // The live sign-out: it wipes this browser's vault (the gate remembered the account).
  const signOut = useSignOut();

  switch (state.status) {
    case "setup":
      return (
        <RecoveryKeySetup
          recoveryKey={state.recoveryKey}
          onContinue={() => void gate.confirmSetup()}
          onSignOut={() => void signOut()}
        />
      );
    case "install":
      return <InstallApp onContinue={() => void gate.installDone()} />;
    case "unlock":
      return (
        <Unlock
          notice={state.notice}
          means={state.means}
          onUnlock={gate.unlock}
          onPasskey={gate.unlockWithPasskey}
          onPair={() => void gate.pair()}
          onSignOut={() => void signOut()}
        />
      );
    case "pairing":
      return (
        <PairNewDevice
          start={gate.startPairing}
          onBack={gate.leavePairing}
          timeZone={profile.timezone}
        />
      );
    case "locked":
      return (
        <Locked
          kind={state.kind}
          retrying={state.retrying}
          onRetry={gate.retry}
          onSignOut={() => void signOut()}
        />
      );
    case "ready":
      return (
        <ApiProvider mode="local" fetch={state.session.fetch}>
          <VaultSessionContext.Provider value={state.session}>
            <RefetchOnCommit session={state.session} />
            {children}
          </VaultSessionContext.Provider>
        </ApiProvider>
      );
    default:
      return <VaultLoading />;
  }
}

/** Every commit to the vault (the person's or the sync's) marks the cached reads stale. */
function RefetchOnCommit({ session }: { session: VaultSession }) {
  const queryClient = useQueryClient();
  useEffect(() => {
    let pending = false;
    return session.subscribe(() => {
      if (pending) return;
      pending = true;
      queueMicrotask(() => {
        pending = false;
        void queryClient.invalidateQueries();
      });
    });
  }, [session, queryClient]);
  return null;
}

/**
 * The welcome and the app decide on the vault's own onboarding flag (the server's stays empty for a
 * preview account): `/app` sends one not onboarded to `/welcome`, `/welcome` an onboarded one to
 * `/app`.
 */
export function LocalOnboardingRoute({
  onboarded,
  to,
  children,
}: {
  /** Which state stays on this route. */
  onboarded: boolean;
  to: string;
  children: ReactNode;
}) {
  const me = useMe();
  if (me.error && !me.data) throw me.error;
  if (!me.data) return <div className="lk-screen min-h-dvh" aria-busy="true" />;
  if ((me.data.onboardingCompletedAt != null) !== onboarded) return <Navigate to={to} replace />;
  return children;
}
