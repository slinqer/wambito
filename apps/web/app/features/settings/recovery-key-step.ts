import { useQueryClient } from "@tanstack/react-query";
import { useState } from "react";
import { type Problem, problemOf } from "./RemoveDeviceSheet.tsx";
import { protectSettingsKey, SECURITY_KEY, type SecurityApi } from "./security.ts";

export type KeyStep =
  | { step: "idle"; busy: boolean; problem: Problem | null }
  | {
      step: "setup";
      recoveryKey: string;
      commit(): Promise<void>;
      saving: boolean;
      /** A commit failed: the key may be saved, so it stays on screen (no Cancel) until done. */
      failed: boolean;
    };

/**
 * "Save a recovery key" of "Protect your data", shared by Settings' checklist (step 1) and by
 * `AddEmail` (spec 2026-11-15 section 7.1: the key screen comes right after the email when none
 * was saved). No check of a current key (web ruling 16: the open vault and the session are the
 * proof): `newRecoveryKey()`, the person types four characters back, `commit()` (a failed commit may
 * be saved: the setup stays), then `markRecoveryKeySaved()`, Protect's `protectSettingsKey(userId)`
 * refetched, then `onSaved`.
 */
export function useRecoveryKeyStep(security: SecurityApi, onSaved: () => void | Promise<void>) {
  const qc = useQueryClient();
  const [key, setKey] = useState<KeyStep>({ step: "idle", busy: false, problem: null });

  const idle = (patch: Partial<Extract<KeyStep, { step: "idle" }>> = {}) =>
    setKey({ step: "idle", busy: false, problem: null, ...patch });

  async function start() {
    if (key.step !== "idle" || key.busy) return;
    idle({ busy: true });
    try {
      const prepared = await security.newRecoveryKey();
      setKey({ step: "setup", ...prepared, saving: false, failed: false });
    } catch (error) {
      idle({ problem: problemOf(error) });
    }
  }

  async function save(setup: Extract<KeyStep, { step: "setup" }>) {
    if (setup.saving) return;
    setKey({ ...setup, saving: true });
    try {
      await setup.commit();
    } catch (error) {
      if (problemOf(error) === "rotated_elsewhere") {
        // Refused for sure: the sync picks up the other device's keys, the list follows.
        void security.reloadKeys().catch(() => {});
        void qc.invalidateQueries({ queryKey: SECURITY_KEY });
        idle({ problem: "rotated_elsewhere" });
      } else {
        setKey({ ...setup, saving: false, failed: true });
      }
      return;
    }
    try {
      await security.markRecoveryKeySaved();
    } catch {
      // The key is saved on the server; only the checklist's mark is missing (the step stays open).
    }
    await qc.invalidateQueries({ queryKey: protectSettingsKey(security.pairing.userId) });
    idle();
    await onSaved();
  }

  return { key, start, save, cancel: () => idle() };
}
