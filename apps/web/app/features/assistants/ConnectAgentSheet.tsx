import { type ReactNode, useId } from "react";
import { useTranslations } from "use-intl";
import { PressButton } from "../../ui/PressButton.tsx";
import { Sheet } from "../../ui/Sheet.tsx";
import type { Agent, AgentId } from "./agents.ts";

/** Whose help centre the guide is in ("la ayuda de <company>"). */
const COMPANY: Record<AgentId, string> = {
  claude: "Claude",
  chatgpt: "OpenAI",
  lumo: "Proton",
  grok: "xAI",
};

const bold = (chunks: ReactNode) => <b className="text-ink">{chunks}</b>;

const BUTTON =
  "lk-btn lk-btn-ghost lk-btn-sm inline-flex min-h-11 min-w-11 items-center no-underline";

/** The connector's address, read-only, with "Copiar". */
export function AddressField({ url, onCopy }: { url: string; onCopy(): void }) {
  const t = useTranslations("settings.assistants");
  const id = useId();
  return (
    <div className="flex min-w-0 gap-(--space-2)">
      <input
        id={id}
        readOnly
        value={url}
        aria-label={t("url_label")}
        onFocus={(event) => event.currentTarget.select()}
        className="lk-input min-h-11 min-w-0 flex-1 font-text text-ink"
      />
      <PressButton
        variant="secondary"
        className="flex-none"
        aria-label={t("copy_label")}
        onClick={onCopy}
      >
        {t("copy")}
      </PressButton>
    </div>
  );
}

/**
 * "Conectar <app>": Wambi shaking hands with the app, then three steps (copy the address, paste it
 * in the app, sign in with the Wambito account), the guide's link and things to ask. Closes with
 * "Listo".
 */
export function ConnectAgentSheet({
  agent,
  open,
  url,
  onCopy,
  onClose,
}: {
  /** The app being connected; kept after closing so the content stays while the sheet leaves. */
  agent: Agent | null;
  open: boolean;
  url: string;
  onCopy(): void;
  onClose(): void;
}) {
  const t = useTranslations("settings.agents");
  const a = useTranslations("settings.assistants");
  return (
    <Sheet
      open={open && agent !== null}
      onClose={onClose}
      title={agent ? t("connect_title", { name: agent.name }) : ""}
    >
      {agent && (
        <div className="flex flex-col gap-(--space-4) pt-(--space-3)">
          <img
            src={agent.scene}
            alt=""
            className="mx-auto block h-auto w-full max-w-[280px] select-none"
          />
          {agent.note && (
            <p className="m-0 rounded-md bg-surface-sunken px-(--space-3) py-(--space-2) text-[14px] text-ink">
              {t(`note_${agent.note}`)}
            </p>
          )}
          <ol className="m-0 flex list-none flex-col gap-(--space-4) p-0">
            <li className="flex gap-(--space-3)">
              <Step n={1} />
              <div className="flex min-w-0 flex-1 flex-col gap-(--space-2)">
                <p className="m-0 text-[15px] text-ink">{t("step1")}</p>
                <AddressField url={url} onCopy={onCopy} />
              </div>
            </li>
            <li className="flex gap-(--space-3)">
              <Step n={2} />
              <div className="flex min-w-0 flex-1 flex-col items-start gap-(--space-2)">
                <p className="m-0 text-[15px] text-ink">
                  {t.rich(`step2_${agent.id}`, { b: bold })}
                </p>
                <a href={agent.connectorsUrl} target="_blank" rel="noreferrer" className={BUTTON}>
                  {t(`open_${agent.id}`)}
                </a>
              </div>
            </li>
            <li className="flex gap-(--space-3)">
              <Step n={3} />
              <p className="m-0 text-[15px] text-ink">{t("step3", { name: agent.name })}</p>
            </li>
          </ol>
          <p className="m-0 text-[13px] font-bold text-ink-muted">
            {t.rich("help", {
              company: COMPANY[agent.id],
              link: (chunks) => (
                <a
                  href={agent.helpUrl}
                  target="_blank"
                  rel="noreferrer"
                  className="text-ink underline decoration-2 underline-offset-[3px]"
                >
                  {chunks}
                </a>
              ),
            })}
          </p>
          <div className="flex flex-col gap-(--space-2)">
            <span className="text-[15px] font-bold text-ink">{a("examples_title")}</span>
            <ul className="m-0 flex list-none flex-wrap gap-(--space-2) p-0">
              {[a("example_add"), a("example_month")].map((example) => (
                <li
                  key={example}
                  className="rounded-md border-2 border-stroke bg-surface-row px-(--space-3) py-(--space-1) text-[14px] text-ink"
                >
                  {example}
                </li>
              ))}
            </ul>
          </div>
          <PressButton onClick={onClose}>{t("done")}</PressButton>
        </div>
      )}
    </Sheet>
  );
}

function Step({ n }: { n: number }) {
  return (
    <span
      aria-hidden="true"
      className="flex size-7 flex-none items-center justify-center rounded-full bg-surface-sunken font-display text-[14px] font-bold text-ink"
    >
      {n}
    </span>
  );
}
