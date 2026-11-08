import { type ReactNode, useId, useState } from "react";
import { useTranslations } from "use-intl";
import { intlTag, type Locale } from "../../i18n/format.ts";
import { useLocale } from "../../i18n/IntlProvider.tsx";
import { ConfirmSheet } from "../../ui/ConfirmSheet.tsx";
import { PressButton } from "../../ui/PressButton.tsx";
import { useToast } from "../../ui/Toast.tsx";
import { SettingLabel, SettingsSection } from "../settings/parts.tsx";
import { type Assistant, useAssistants, useRevokeAssistant } from "./queries.ts";

/** Copies text; the browser's clipboard by default (stories stand in for it). */
export type CopyText = (text: string) => Promise<void>;

const clipboardCopy: CopyText = (text) => navigator.clipboard.writeText(text);

/** The MCP's address: the same for everyone (OAuth tells who it is), on the web's own origin. */
export const mcpUrl = (origin: string) => `${origin}/mcp`;

/** A day as `2 oct 2026` (es) or `Oct 2, 2026` (en), in the person's time zone. */
function formatDay(iso: string, locale: Locale, timeZone: string): string {
  try {
    return new Intl.DateTimeFormat(intlTag(locale), { dateStyle: "medium", timeZone })
      .format(new Date(iso))
      .replace(/\./g, "");
  } catch {
    return iso.slice(0, 10);
  }
}

/**
 * "Conecta tu asistente" in settings (spec §6.2): the MCP's address with "Copiar", short steps
 * for Claude and ChatGPT (their menus are in English and change: checked when this was built),
 * two things to ask, and the assistants already connected, each with where it comes from, when
 * it was connected and last used, and "Revocar" after asking. In the demo there is no account
 * to connect, so the list is left out and nothing is asked of the API.
 */
export function AssistantsSection({
  timeZone,
  off = false,
  offNote,
  copy = clipboardCopy,
  origin = typeof window === "undefined" ? "" : window.location.origin,
}: {
  timeZone: string;
  /** The demo (and a preview account): the address and the steps only. */
  off?: boolean;
  /** Shown instead of the list when `off` (a preview account says why). */
  offNote?: ReactNode;
  copy?: CopyText;
  /** Where the web is served; the page's own origin by default. */
  origin?: string;
}) {
  const t = useTranslations("settings.assistants");
  const urlId = useId();
  const toast = useToast();
  const url = mcpUrl(origin);

  const copyUrl = async () => {
    try {
      await copy(url);
      toast.show({ message: t("copied") });
    } catch {
      toast.show({ tone: "error", message: t("copy_failed") });
    }
  };

  return (
    <SettingsSection title={t("title")} lead={t("lead")}>
      <div className="flex flex-col gap-(--space-2)">
        <label htmlFor={urlId} className="text-[15px] font-bold text-ink">
          {t("url_label")}
        </label>
        <div className="flex min-w-0 gap-(--space-2)">
          <input
            id={urlId}
            readOnly
            value={url}
            onFocus={(event) => event.currentTarget.select()}
            className="lk-input min-h-11 min-w-0 flex-1 font-text text-ink"
          />
          <PressButton
            variant="secondary"
            className="flex-none"
            aria-label={t("copy_label")}
            onClick={() => void copyUrl()}
          >
            {t("copy")}
          </PressButton>
        </div>
      </div>
      <div className="flex flex-col gap-(--space-3)">
        <SettingLabel label={t("claude_title")} hint={t("claude_steps")} />
        <SettingLabel label={t("chatgpt_title")} hint={t("chatgpt_steps")} />
      </div>
      <div className="flex flex-col gap-(--space-2)">
        <SettingLabel label={t("examples_title")} />
        <ul className="m-0 flex list-none flex-wrap gap-(--space-2) p-0">
          {[t("example_add"), t("example_month")].map((example) => (
            <li
              key={example}
              className="rounded-md border-2 border-stroke bg-surface-row px-(--space-3) py-(--space-1) text-[14px] text-ink"
            >
              {example}
            </li>
          ))}
        </ul>
      </div>
      {off ? offNote : <ConnectedAssistants timeZone={timeZone} />}
    </SettingsSection>
  );
}

/** The assistants the person let in, each with "Revocar". */
function ConnectedAssistants({ timeZone }: { timeZone: string }) {
  const t = useTranslations("settings.assistants");
  const { locale } = useLocale();
  const toast = useToast();
  const list = useAssistants();
  const revoke = useRevokeAssistant();
  const [revoking, setRevoking] = useState<Assistant | null>(null);
  const [confirmOpen, setConfirmOpen] = useState(false);
  const day = (iso: string) => formatDay(iso, locale, timeZone);

  const confirm = async () => {
    if (!revoking) return;
    try {
      await revoke.mutateAsync(revoking.clientId);
    } catch (problem) {
      toast.show({ tone: "error", message: t("revoke_failed") });
      throw problem;
    }
    toast.show({ message: t("revoked", { name: revoking.name }) });
  };

  return (
    <div className="flex flex-col gap-(--space-2)" aria-busy={list.isPending || undefined}>
      <SettingLabel label={t("connected_title")} />
      {list.isError && <p className="m-0 text-[14px] text-ink-muted">{t("list_failed")}</p>}
      {list.data?.length === 0 && <p className="m-0 text-[14px] text-ink">{t("empty")}</p>}
      {list.data && list.data.length > 0 && (
        <ul className="m-0 flex list-none flex-col gap-(--space-2) p-0">
          {list.data.map((item) => (
            <li key={item.clientId} className="lk-rowcard justify-between">
              <span className="flex min-w-0 items-center gap-(--space-3)">
                {item.icon?.startsWith("https://") ? (
                  <img
                    src={item.icon}
                    alt=""
                    width={32}
                    height={32}
                    referrerPolicy="no-referrer"
                    className="size-8 flex-none rounded-sm object-contain"
                  />
                ) : (
                  <span
                    aria-hidden="true"
                    className="flex size-8 flex-none items-center justify-center rounded-sm bg-surface-sunken font-display text-[16px] font-bold text-ink"
                  >
                    {item.name.slice(0, 1).toUpperCase()}
                  </span>
                )}
                <span className="flex min-w-0 flex-col">
                  <span className="truncate text-[15px] font-bold text-ink">{item.name}</span>
                  {item.domain && (
                    <span className="truncate text-[13px] font-bold text-ink-muted">
                      {t("from", { domain: item.domain })}
                    </span>
                  )}
                  <span className="flex flex-wrap gap-x-(--space-2) text-[13px] text-ink-muted">
                    <span>{t("connected_at", { date: day(item.connectedAt) })}</span>
                    <span>
                      {item.lastUsedAt
                        ? t("last_used", { date: day(item.lastUsedAt) })
                        : t("never_used")}
                    </span>
                  </span>
                </span>
              </span>
              <PressButton
                variant="ghost"
                size="sm"
                className="flex-none"
                aria-label={t("revoke_label", { name: item.name })}
                onClick={() => {
                  setRevoking(item);
                  setConfirmOpen(true);
                }}
              >
                {t("revoke")}
              </PressButton>
            </li>
          ))}
        </ul>
      )}
      <ConfirmSheet
        open={confirmOpen}
        onClose={() => setConfirmOpen(false)}
        title={t("revoke_title", { name: revoking?.name ?? "" })}
        body={t("revoke_body")}
        confirmLabel={t("revoke_confirm")}
        onConfirm={confirm}
      />
    </div>
  );
}
