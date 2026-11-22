import { useEffect, useRef, useState } from "react";
import { useTranslations } from "use-intl";
import { useApiMode } from "../../api/ApiProvider.tsx";
import { useMe } from "../../api/queries.ts";
import { intlTag, type Locale } from "../../i18n/format.ts";
import { useLocale } from "../../i18n/IntlProvider.tsx";
import { BrandLogo } from "../../ui/BrandLogo.tsx";
import { ConfirmSheet } from "../../ui/ConfirmSheet.tsx";
import { Icon } from "../../ui/Icon.tsx";
import { PressButton } from "../../ui/PressButton.tsx";
import { useToast } from "../../ui/Toast.tsx";
import { SettingsGroup, SettingsSection } from "../settings/parts.tsx";
import { AGENTS, type Agent, agentFor } from "./agents.ts";
import { AddressField, ConnectAgentSheet } from "./ConnectAgentSheet.tsx";
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

/** The calendar day (`2026-10-02`) of an instant in a time zone, for "today" and "yesterday". */
function dayKey(date: Date, timeZone: string): string {
  try {
    return new Intl.DateTimeFormat("en-CA", { timeZone }).format(date);
  } catch {
    return date.toISOString().slice(0, 10);
  }
}

const DAY_MS = 24 * 60 * 60 * 1000;

/** The newest grant of a group (the one whose dates the row shows; "Revocar" ends every grant of the app). */
const newest = (grants: Assistant[]): Assistant | undefined =>
  [...grants].sort((a, b) => b.connectedAt.localeCompare(a.connectedAt))[0];

/**
 * "Mis agentes" in settings (spec 2026-11-22): the four AI apps with their state, each with
 * "Conectar" (a sheet with Wambi's handshake and the steps) or, once connected, when it was
 * connected and last used with "Revocar"; any other client that was let in after them; and the
 * connector's address. When the tab regains focus the list is read again, and a new grant of one
 * of the four shows a toast. The demo has no account to connect (nothing is asked of the API);
 * a guest is told to add an email first.
 */
export function AgentsScreen({
  timeZone,
  copy = clipboardCopy,
  origin = typeof window === "undefined" ? "" : window.location.origin,
}: {
  timeZone: string;
  copy?: CopyText;
  /** Where the web is served; the page's own origin by default. */
  origin?: string;
}) {
  const t = useTranslations("settings.agents");
  const a = useTranslations("settings.assistants");
  const { locale } = useLocale();
  const toast = useToast();
  const demo = useApiMode() === "demo";
  const guest = useMe().data?.isAnonymous === true;
  const list = useAssistants({ enabled: !demo && !guest });
  const revoke = useRevokeAssistant();
  const url = mcpUrl(origin);
  const [connecting, setConnecting] = useState<Agent | null>(null);
  const [sheetOpen, setSheetOpen] = useState(false);
  const [revoking, setRevoking] = useState<{ name: string; ids: string[] } | null>(null);
  const [confirmOpen, setConfirmOpen] = useState(false);

  // The grant ids already seen: null until the first load, so that one never toasts.
  const seen = useRef<Set<string> | null>(null);
  const { data, refetch } = list;
  useEffect(() => {
    if (!data) return;
    const before = seen.current;
    seen.current = new Set(data.map((item) => item.clientId));
    if (!before) return;
    for (const item of data) {
      if (before.has(item.clientId)) continue;
      const id = agentFor(item);
      const agent = AGENTS.find((candidate) => candidate.id === id);
      if (agent) toast.show({ message: t("now_connected", { name: agent.name }) });
    }
  }, [data, toast, t]);

  // Back on this tab after connecting elsewhere.
  const listing = !demo && !guest;
  useEffect(() => {
    if (!listing) return;
    const onFocus = () => void refetch();
    window.addEventListener("focus", onFocus);
    return () => window.removeEventListener("focus", onFocus);
  }, [listing, refetch]);

  const copyUrl = async () => {
    try {
      await copy(url);
      toast.show({ message: a("copied") });
    } catch {
      toast.show({ tone: "error", message: a("copy_failed") });
    }
  };

  const confirm = async () => {
    if (!revoking) return;
    try {
      await revoke.mutateAsync(revoking.ids);
    } catch (problem) {
      toast.show({ tone: "error", message: a("revoke_failed") });
      throw problem;
    }
    toast.show({ message: a("revoked", { name: revoking.name }) });
  };

  const day = (iso: string) => formatDay(iso, locale, timeZone);
  const used = (grant: Assistant): string => {
    if (!grant.lastUsedAt) return t("never_used");
    const key = dayKey(new Date(grant.lastUsedAt), timeZone);
    if (key === dayKey(new Date(), timeZone)) return t("used_today");
    if (key === dayKey(new Date(Date.now() - DAY_MS), timeZone)) return t("used_yesterday");
    return t("used_on", { date: day(grant.lastUsedAt) });
  };
  const connectedLine = (grant: Assistant) =>
    t("connected_line", { date: day(grant.connectedAt), used: used(grant) });

  const askRevoke = (name: string, grants: Assistant[]) => {
    setRevoking({ name, ids: grants.map((item) => item.clientId) });
    setConfirmOpen(true);
  };

  if (guest) {
    return (
      <SettingsSection title={t("guest_title")}>
        <p className="m-0 text-[15px] text-ink">{t("guest_body")}</p>
      </SettingsSection>
    );
  }

  const grants = demo ? [] : (list.data ?? []);
  const others = grants.filter((grant) => agentFor(grant) === null);

  return (
    <>
      <p className="m-0 text-[14px] text-ink-muted">{t("lead")}</p>
      {list.isError && <p className="m-0 text-[14px] text-ink-muted">{a("list_failed")}</p>}
      {(demo || list.data) && (
        <SettingsGroup>
          {AGENTS.map((agent) => {
            const own = grants.filter((item) => agentFor(item) === agent.id);
            const grant = newest(own);
            return (
              <AgentRow
                key={agent.id}
                id={agent.id}
                icon={<BrandLogo name={agent.brand} size={18} />}
                name={agent.name}
                line={grant ? connectedLine(grant) : t("not_connected")}
                action={
                  grant ? (
                    <RevokeButton name={agent.name} onPress={() => askRevoke(agent.name, own)} />
                  ) : (
                    <PressButton
                      variant="secondary"
                      size="sm"
                      className="flex-none"
                      aria-label={t("connect_label", { name: agent.name })}
                      onClick={() => {
                        setConnecting(agent);
                        setSheetOpen(true);
                      }}
                    >
                      {t("connect")}
                    </PressButton>
                  )
                }
              />
            );
          })}
          {others.map((grant) => (
            <AgentRow
              key={grant.clientId}
              id={grant.clientId}
              icon={
                <span data-testid="generic-agent-icon" className="flex">
                  <Icon name="chat" size={18} />
                </span>
              }
              name={grant.name}
              line={connectedLine(grant)}
              action={
                <RevokeButton name={grant.name} onPress={() => askRevoke(grant.name, [grant])} />
              }
            />
          ))}
        </SettingsGroup>
      )}
      <SettingsSection title={t("address_title")}>
        <AddressField url={url} onCopy={() => void copyUrl()} />
      </SettingsSection>
      <ConnectAgentSheet
        agent={connecting}
        open={sheetOpen}
        url={url}
        onCopy={() => void copyUrl()}
        onClose={() => setSheetOpen(false)}
      />
      <ConfirmSheet
        open={confirmOpen}
        onClose={() => setConfirmOpen(false)}
        title={a("revoke_title", { name: revoking?.name ?? "" })}
        body={a("revoke_body")}
        confirmLabel={a("revoke_confirm")}
        onConfirm={confirm}
      />
    </>
  );
}

function RevokeButton({ name, onPress }: { name: string; onPress(): void }) {
  const a = useTranslations("settings.assistants");
  return (
    <PressButton
      variant="ghost"
      size="sm"
      className="flex-none"
      aria-label={a("revoke_label", { name })}
      onClick={onPress}
    >
      {a("revoke")}
    </PressButton>
  );
}

/** One app: its logo on a sunken tile, its name and state, and its action at the end. */
function AgentRow({
  id,
  icon,
  name,
  line,
  action,
}: {
  id: string;
  icon: React.ReactNode;
  name: string;
  line: string;
  action: React.ReactNode;
}) {
  return (
    <div className="lk-row" data-agent={id}>
      <span
        aria-hidden="true"
        className="flex size-8 flex-none items-center justify-center rounded-sm bg-surface-sunken text-ink"
      >
        {icon}
      </span>
      <span className="lk-row-text">
        <span className="lk-row-title text-ink">{name}</span>
        <span className="lk-row-line text-ink-muted">{line}</span>
      </span>
      {action}
    </div>
  );
}
