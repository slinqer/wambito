import { Link, type LinkProps } from "react-router";
import { cx } from "./cx.ts";

export type PressLinkProps = {
  variant?: "primary" | "secondary";
  size?: "md" | "sm";
} & LinkProps;

/**
 * A link that looks and presses like `PressButton` (`lk-btn`): for actions that go somewhere,
 * such as "Crear cuenta" → `/create-account`. Same solid edge, focus ring and 44px minimum.
 */
export function PressLink({
  variant = "primary",
  size = "md",
  className,
  ...rest
}: PressLinkProps) {
  return (
    <Link
      className={cx(
        "lk-btn",
        `lk-btn-${variant}`,
        size === "sm" && "lk-btn-sm",
        "inline-flex min-h-11 min-w-11 items-center justify-center gap-(--space-2) no-underline",
        className,
      )}
      {...rest}
    />
  );
}
