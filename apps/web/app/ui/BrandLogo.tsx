import source from "../../../../docs/design/system/project/icons/brands.json";

/** One filled path of a logo, with the even-odd rule when `evenOdd`. */
interface BrandPath {
  d: string;
  evenOdd?: boolean;
}

interface BrandSource {
  viewBox: string;
  paths: BrandPath[];
}

/** The AI assistants and payment apps whose logos Settings shows (brands.json; the phone reads the same). */
export type BrandName =
  | "chatgpt"
  | "claude"
  | "lumo"
  | "grok"
  | "revolut"
  | "google-wallet"
  | "activobank";

const LOGOS: Record<BrandName, BrandSource> = source.logos;

export interface BrandLogoProps {
  name: BrandName;
  /** Width and height in px (default 22). */
  size?: number;
  className?: string;
}

/**
 * A brand's logo in one colour (`currentColor`), hidden from assistive technology: the text beside
 * it names the brand. Each logo keeps its own viewBox.
 */
export function BrandLogo({ name, size = 22, className }: BrandLogoProps) {
  const logo = LOGOS[name];
  return (
    <svg
      width={size}
      height={size}
      viewBox={logo.viewBox}
      fill="none"
      aria-hidden="true"
      focusable="false"
      className={className}
      data-brand={name}
    >
      {logo.paths.map((path) => (
        <path
          key={path.d}
          d={path.d}
          fill="currentColor"
          fillRule={path.evenOdd ? "evenodd" : undefined}
          clipRule={path.evenOdd ? "evenodd" : undefined}
        />
      ))}
    </svg>
  );
}
