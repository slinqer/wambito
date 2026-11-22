import { useEffect, useState, useSyncExternalStore } from "react";
import { useTranslations } from "use-intl";
import type { MigrationGate as Gate } from "../../auth/encryption.ts";
import { liveMigrationDeps } from "../../local/migration.ts";
import { forgetVault, rememberPreviewAccount } from "../../local/vault-session.ts";
import { PressButton } from "../../ui/PressButton.tsx";
import { useSignOut } from "../home/use-sign-out.ts";
import { ScreenTitle, SignInScreen } from "../sign-in/SignInScreen.tsx";
import { RecoveryKeySetup } from "../vault/RecoveryKeySetup.tsx";
import { Unlock, type UnlockError } from "../vault/Unlock.tsx";
import { createMigrationFlow, type MigrationFlow, type MigrationState } from "./migration-flow.ts";

export interface MigrationScreenProps {
  state: MigrationState;
  onBegin(): void;
  onConfirmKey(): void;
  onUnlock(text: string): Promise<UnlockError | null>;
  onRetry(): void;
  onRestart(): void;
  onContinue(): void;
  /** Signs out (and wipes this browser's vault): the plaintext stays on the server until done. */
  onSignOut(): void;
  /** The recovery key's four positions to type back; random unless a story pins them. */
  positions?: number[];
}

/** One screen per state of the switch day's flow (`migration-flow.ts`). Pure UI. */
export function MigrationScreen({
  state,
  onBegin,
  onConfirmKey,
  onUnlock,
  onRetry,
  onRestart,
  onContinue,
  onSignOut,
  positions,
}: MigrationScreenProps) {
  const t = useTranslations("migration");
  const tVault = useTranslations("vault");
  const signOut = (
    <PressButton variant="ghost" className="w-full" onClick={onSignOut}>
      {tVault("sign_out")}
    </PressButton>
  );

  switch (state.status) {
    case "intro":
      return (
        <SignInScreen>
          <ScreenTitle>{t("intro_title")}</ScreenTitle>
          <p className="text-center text-ink-muted">{t("intro_body")}</p>
          <PressButton className="w-full" onClick={onBegin}>
            {t("intro_start")}
          </PressButton>
          {signOut}
        </SignInScreen>
      );
    case "keys":
      return (
        <RecoveryKeySetup
          recoveryKey={state.recoveryKey}
          busy={state.busy}
          onContinue={onConfirmKey}
          onSignOut={onSignOut}
          {...(positions ? { positions } : {})}
        />
      );
    case "unlock":
      return <Unlock onUnlock={onUnlock} lead={t("unlock_lead")} onSignOut={onSignOut} />;
    case "copying": {
      const share = state.total > 0 ? Math.min(state.done / state.total, 1) : 0;
      return (
        <SignInScreen>
          <ScreenTitle>{t("copying", { done: state.done, total: state.total })}</ScreenTitle>
          <div
            role="progressbar"
            aria-label={t("copying_label")}
            aria-valuemin={0}
            aria-valuemax={state.total}
            aria-valuenow={state.done}
            className="lk-bar w-full"
          >
            <span
              className="transition-[width] duration-(--count-up) ease-out motion-reduce:transition-none"
              style={{ width: `${Math.round(share * 1000) / 10}%` }}
            />
          </div>
        </SignInScreen>
      );
    }
    case "finishing":
      return (
        <SignInScreen>
          <ScreenTitle>{t("finishing")}</ScreenTitle>
          <div aria-busy="true" />
        </SignInScreen>
      );
    case "done":
      return (
        <SignInScreen mood="celebrating">
          <ScreenTitle>{t("done_title")}</ScreenTitle>
          <p className="text-center text-ink-muted">{t("done_lead")}</p>
          <PressButton className="w-full" onClick={onContinue}>
            {t("continue")}
          </PressButton>
        </SignInScreen>
      );
    case "failed": {
      const label = state.problem === "taken_over" ? t("continue_here") : t("retry");
      return (
        <SignInScreen mood="worried">
          <ScreenTitle>{t("failed_title")}</ScreenTitle>
          <p className="text-center text-ink-muted">{t(state.problem)}</p>
          <PressButton className="w-full" disabled={state.retrying} onClick={onRetry}>
            {state.retrying ? t("retrying") : label}
          </PressButton>
          {signOut}
        </SignInScreen>
      );
    }
    case "noLocalVault":
      return (
        <SignInScreen mood="worried">
          <ScreenTitle>{t("no_local_title")}</ScreenTitle>
          <p className="text-center text-ink-muted">{t("no_local_body")}</p>
          <PressButton className="w-full" disabled={state.busy} onClick={onRestart}>
            {t("restart")}
          </PressButton>
          {signOut}
        </SignInScreen>
      );
    default:
      return (
        <SignInScreen>
          <ScreenTitle>{t("checking")}</ScreenTitle>
          <div aria-busy="true" />
        </SignInScreen>
      );
  }
}

/** The session ended under the flow (a 401): wipe this browser's vault, then sign in again. */
function signInAgain() {
  void forgetVault()
    .catch(() => {
      // Sign-in still has to happen; the next sign-out tries the wipe again.
    })
    .finally(() => window.location.reload());
}

function flowFor(gate: Gate): MigrationFlow {
  return createMigrationFlow(
    liveMigrationDeps({
      userId: gate.profile.id,
      migration: gate.migration,
      onUnauthorized: signInAgain,
    }),
  );
}

/**
 * The switch day (E2E stage 5): a plain account's move to end-to-end encryption, before the app
 * (`/app` and `/welcome` render it when `GET /v1/me` has `migration`). Done reloads the page: the
 * account is encrypted now, and the vault gate opens the keys this flow kept.
 */
export function MigrationGate({ gate }: { gate: Gate }) {
  const [flow] = useState(() => flowFor(gate));
  useEffect(() => {
    // Sign-out wipes this browser's vault, as for any encrypted account.
    rememberPreviewAccount(gate.profile.id);
    flow.start();
  }, [flow, gate.profile.id]);
  const state = useSyncExternalStore(flow.subscribe, flow.getState, flow.getState);
  const signOut = useSignOut();
  return (
    <MigrationScreen
      state={state}
      onBegin={() => void flow.begin()}
      onConfirmKey={() => void flow.confirmKey()}
      onUnlock={flow.unlock}
      onRetry={flow.retry}
      onRestart={() => void flow.restart()}
      onContinue={flow.continue}
      onSignOut={() => void signOut()}
    />
  );
}
