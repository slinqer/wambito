import { useQueryClient } from "@tanstack/react-query";
import { type ReactNode, useEffect, useState, useSyncExternalStore } from "react";
import { Navigate } from "react-router";
import { useTranslations } from "use-intl";
import { ApiProvider } from "../../api/ApiProvider.tsx";
import { unauthorizedRedirect } from "../../api/client.ts";
import { useMe } from "../../api/queries.ts";
import { loadLocalKeys, prepareAccount, unlockWithRecovery } from "../../local/keys.ts";
import {
  forgetVault,
  openVaultSession,
  rememberPreviewAccount,
  type VaultProfile,
  type VaultSession,
} from "../../local/vault-session.ts";
import { ScreenTitle, SignInScreen } from "../sign-in/SignInScreen.tsx";
import { Locked } from "./Locked.tsx";
import { RecoveryKeySetup } from "./RecoveryKeySetup.tsx";
import { Unlock } from "./Unlock.tsx";
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

function gateFor(profile: VaultProfile): Gate<VaultSession> {
  const userId = profile.id;
  return createVaultGate({
    loadLocalKeys: () => loadLocalKeys(userId),
    prepareAccount: () => prepareAccount({ userId, guest: profile.isAnonymous }),
    unlockWithRecovery: (text) => unlockWithRecovery({ userId, text }),
    open: (keys, fresh) => openVaultSession({ profile, keys, fresh, onUnauthorized: signInAgain }),
  });
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

  switch (state.status) {
    case "setup":
      return (
        <RecoveryKeySetup
          recoveryKey={state.recoveryKey}
          onContinue={() => void gate.confirmSetup()}
        />
      );
    case "unlock":
      return <Unlock onUnlock={gate.unlock} />;
    case "locked":
      return <Locked kind={state.kind} retrying={state.retrying} onRetry={gate.retry} />;
    case "ready":
      return (
        <ApiProvider mode="local" fetch={state.session.fetch}>
          <RefetchOnCommit session={state.session} />
          {children}
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
