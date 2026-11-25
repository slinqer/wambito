import type { ReactNode } from "react";
import { cx } from "../../ui/cx.ts";

/** The section with the downloads ("Úsalo como prefieras"). */
export const DOWNLOADS_HASH = "#ways";

/**
 * A link down to the downloads that looks and presses like `PressLink` (`lk-btn`): the hero's
 * "Descargar la app", the agent's "Conecta tu agente" and the closing's big button. A plain anchor,
 * so it scrolls without JavaScript.
 */
export function DownloadLink({
  variant = "primary",
  size = "md",
  className,
  children,
}: {
  variant?: "primary" | "secondary";
  size?: "md" | "sm";
  className?: string;
  children: ReactNode;
}) {
  return (
    <a
      href={DOWNLOADS_HASH}
      className={cx(
        "lk-btn",
        `lk-btn-${variant}`,
        size === "sm" && "lk-btn-sm",
        "inline-flex min-h-11 min-w-11 items-center justify-center gap-(--space-2) no-underline",
        className,
      )}
    >
      {children}
    </a>
  );
}
