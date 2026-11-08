import { useQueryClient } from "@tanstack/react-query";
import { useId, useRef, useState } from "react";
import { useNavigate } from "react-router";
import { useTranslations } from "use-intl";
import { useApi } from "../../api/ApiProvider.tsx";
import type { Translator } from "../../api/errors.ts";
import { landingLink } from "../../site/config.ts";
import { PressButton } from "../../ui/PressButton.tsx";
import { Sheet } from "../../ui/Sheet.tsx";
import type { SignOutRequest } from "../home/use-sign-out.ts";
import { DemoOffNote, SettingsSection } from "./parts.tsx";
import { emailMatches } from "./settings-model.ts";
import type { ExportFormat } from "./use-export.ts";
import { failureMessage } from "./use-profile.ts";

/**
 * Deleting the account: a sheet that says what goes (at once; backups that hold it age out within
 * 14 days), offers the export first ("Descarga tus datos antes"), and only enables "Sí, eliminar
 * mi cuenta" once the account's email is typed (case and surrounding spaces don't matter). Then
 * `DELETE /v1/me`, sign-out, and the landing. A failed delete stays in the sheet and says why; a
 * failed sign-out afterwards does not matter (the sessions went with the account).
 */
export function DeleteAccount({
  email,
  signOut,
  onExport,
  exporting,
  off = false,
  canExport = true,
}: {
  email: string;
  signOut: SignOutRequest;
  onExport(format: ExportFormat): void;
  exporting: boolean;
  /** A preview account has no export yet: the sheet does not offer one. */
  canExport?: boolean;
  /** The demo: the button is off, with a note saying why. */
  off?: boolean;
}) {
  const t = useTranslations("settings.delete");
  const tRoot = useTranslations() as unknown as Translator;
  const api = useApi();
  const qc = useQueryClient();
  const navigate = useNavigate();
  const [open, setOpen] = useState(false);
  const [typed, setTyped] = useState("");
  const [busy, setBusy] = useState(false);
  // A ref, not state: a double tap, or Enter and a tap together, must send one DELETE.
  const inFlight = useRef(false);
  const [error, setError] = useState<string | null>(null);
  const inputId = useId();
  const hintId = useId();
  const errorId = useId();
  const offId = useId();
  const ready = emailMatches(typed, email);

  const close = () => {
    if (busy) return;
    setOpen(false);
    setTyped("");
    setError(null);
  };

  const remove = async () => {
    if (!ready || inFlight.current) return;
    inFlight.current = true;
    setBusy(true);
    setError(null);
    // Nothing should refetch with a session that is about to end.
    await qc.cancelQueries();
    try {
      await api.DELETE("/v1/me");
    } catch (problem) {
      setError(failureMessage(problem, tRoot));
      inFlight.current = false;
      setBusy(false);
      return;
    }
    try {
      await signOut();
    } catch {
      // The account and its sessions are gone already; the cookie goes with the next request.
    }
    // The landing is outside the app's layout, so the cache goes with it as the layout unmounts
    // (or with the page, when the landing lives on its own site). It is not emptied here: emptied
    // while the app's screens are still mounted, they would refetch, get a 401 and send the
    // browser to sign-in instead.
    const landing = landingLink();
    if (landing.external) window.location.replace(landing.href);
    else navigate(landing.href, { replace: true });
  };

  return (
    <SettingsSection title={t("title")} lead={t("lead")} tone="danger">
      <PressButton
        variant="secondary"
        className="self-start text-over"
        disabled={off}
        aria-describedby={off ? offId : undefined}
        onClick={() => setOpen(true)}
      >
        {t("action")}
      </PressButton>
      {off && <DemoOffNote id={offId} />}
      <Sheet open={open} onClose={close} title={t("sheet_title")}>
        <div className="flex flex-col gap-(--space-4) pt-(--space-3)">
          <p className="m-0 text-[15px] text-ink">{t("sheet_body")}</p>
          {canExport && (
            <PressButton
              variant="secondary"
              className="self-start"
              disabled={exporting}
              aria-busy={exporting || undefined}
              onClick={() => onExport("json")}
            >
              {t("export_first")}
            </PressButton>
          )}
          <div className="flex flex-col gap-(--space-1)">
            <label htmlFor={inputId} className="text-[14px] font-bold text-ink">
              {t("confirm_label")}
            </label>
            <span className="lk-input min-h-11">
              <input
                id={inputId}
                type="text"
                inputMode="email"
                autoComplete="off"
                autoCapitalize="none"
                spellCheck={false}
                value={typed}
                aria-describedby={error ? `${hintId} ${errorId}` : hintId}
                aria-invalid={error ? true : undefined}
                onChange={(event) => setTyped(event.target.value)}
                onKeyDown={(event) => {
                  if (event.key === "Enter") void remove();
                }}
                className="min-h-9 min-w-0 flex-1 border-0 bg-transparent p-0 font-text text-[16px] text-ink outline-none"
              />
            </span>
            <span id={hintId} className="text-[13px] text-ink-muted">
              {t("confirm_hint", { email })}
            </span>
          </div>
          {error && (
            <p id={errorId} role="alert" className="m-0 text-[15px] text-over">
              {error}
            </p>
          )}
          <div className="flex flex-col gap-(--space-2) min-[400px]:flex-row-reverse">
            <PressButton
              variant="secondary"
              className="flex-1 text-over"
              disabled={!ready || busy}
              aria-busy={busy || undefined}
              onClick={() => void remove()}
            >
              {busy ? t("deleting") : t("confirm")}
            </PressButton>
            <PressButton variant="ghost" className="flex-1" disabled={busy} onClick={close}>
              {tRoot("common.cancel")}
            </PressButton>
          </div>
        </div>
      </Sheet>
    </SettingsSection>
  );
}
