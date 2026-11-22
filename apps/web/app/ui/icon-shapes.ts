import source from "../../../../docs/design/system/project/icons/icons.json";

/**
 * One shape of an icon, on a 48 grid in `currentColor`: `d` is SVG path data, filled when `fill`
 * (with the even-odd rule when `evenOdd`), else stroked `stroke` wide with round caps and joins.
 */
export interface IconShape {
  d: string;
  fill?: boolean;
  evenOdd?: boolean;
  stroke?: number;
}

export type IconVariant = "filled" | "outline";

interface IconSource {
  filled: IconShape[];
  outline?: IconShape[];
}

const ICONS = source.icons as Record<string, IconSource>;

/** The interface icons (docs/design/system/project/icons/icons.json; the phone reads the same). */
export const ICON_NAMES = [
  "search",
  "user",
  "home",
  "chart",
  "plus",
  "close",
  "chevron-left",
  "chevron-right",
  "mic",
  "check",
  "cloud-off",
  "shield",
  "sliders",
  "bell",
  "folder",
  "info",
  "fingerprint",
  "phone",
  "laptop",
  "key",
  "trash",
  "wand",
  "calendar",
  "widget",
  "eye-off",
  "globe",
  "moon",
  "volume",
  "clock",
  "coin",
  "upload",
  "download",
  "server",
  "map",
  "chat",
] as const;

export type IconName = (typeof ICON_NAMES)[number];

/** The shapes of [name] in [variant]; an icon drawn once has the same shapes in both. */
export function iconShapes(name: IconName, variant: IconVariant): IconShape[] {
  const icon = ICONS[name];
  if (!icon) throw new Error(`No icon named ${name}`);
  return (variant === "outline" ? icon.outline : undefined) ?? icon.filled;
}
