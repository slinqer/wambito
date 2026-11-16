import { type IconName, type IconVariant, iconShapes } from "./icon-shapes.ts";

export interface IconProps {
  name: IconName;
  /** `outline` for an inactive tab; the default `filled` everywhere else. */
  variant?: IconVariant;
  /** Width and height in px (default 24). */
  size?: number;
  className?: string;
}

/**
 * An interface icon in `currentColor`, hidden from assistive technology: the button or link around
 * it carries the name. Emoji stay for categories only (docs/design/system/project/README.md).
 */
export function Icon({ name, variant = "filled", size = 24, className }: IconProps) {
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 48 48"
      fill="none"
      aria-hidden="true"
      focusable="false"
      className={className}
      data-icon={name}
      data-variant={variant}
    >
      {iconShapes(name, variant).map((shape) =>
        shape.fill ? (
          <path
            key={shape.d}
            d={shape.d}
            fill="currentColor"
            fillRule={shape.evenOdd ? "evenodd" : undefined}
            clipRule={shape.evenOdd ? "evenodd" : undefined}
          />
        ) : (
          <path
            key={shape.d}
            d={shape.d}
            stroke="currentColor"
            strokeWidth={shape.stroke}
            strokeLinecap="round"
            strokeLinejoin="round"
          />
        ),
      )}
    </svg>
  );
}
