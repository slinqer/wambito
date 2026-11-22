import { type ReactNode, useId } from "react";
import { Link } from "react-router";
import { useTranslations } from "use-intl";
import { cx } from "../../ui/cx.ts";
import { Icon } from "../../ui/Icon.tsx";

/** A card of settings named by its heading (so it is a landmark region). */
export function SettingsSection({
  title,
  lead,
  tone,
  children,
}: {
  title: string;
  lead?: string;
  /** "danger": deleting the account. */
  tone?: "danger";
  children: ReactNode;
}) {
  const id = useId();
  return (
    <section
      aria-labelledby={id}
      className={cx(
        "lk-hero flex min-w-0 flex-col gap-(--space-4)",
        tone === "danger" && "lk-danger-zone",
      )}
    >
      <div className="flex flex-col gap-(--space-1)">
        <h2
          id={id}
          className={cx(
            "m-0 font-display text-[20px] font-bold leading-tight",
            tone === "danger" ? "text-over" : "text-ink",
          )}
        >
          {title}
        </h2>
        {lead && <p className="m-0 text-[14px] text-ink-muted">{lead}</p>}
      </div>
      {children}
    </section>
  );
}

/**
 * In the demo, under a setting that can't work there (export, deleting the account, passkeys,
 * import): why its controls are off. With `local`, the same for a preview account's encrypted
 * vault (export, import, assistants: not available yet). Give the controls `aria-describedby={id}`.
 */
export function DemoOffNote({ id, local = false }: { id: string; local?: boolean }) {
  const t = useTranslations("settings");
  return (
    <p id={id} className="m-0 text-[14px] text-ink-muted">
      {t(local ? "local_off" : "demo_off")}
    </p>
  );
}

/** The name of one setting and, under it, a muted line on what it does. */
export function SettingLabel({
  label,
  hint,
  hintId,
}: {
  label: string;
  hint?: string;
  hintId?: string;
}) {
  return (
    <div className="flex flex-col gap-(--space-1)">
      <span className="text-[15px] font-bold text-ink">{label}</span>
      {hint && (
        <span id={hintId} className="text-[13px] text-ink-muted">
          {hint}
        </span>
      )}
    </div>
  );
}

const OPTION =
  "relative flex min-h-11 min-w-11 cursor-pointer items-center justify-center rounded-md border-2 border-stroke bg-surface-row px-(--space-2) text-center text-[14px] font-bold text-ink-muted shadow-edge-sm has-checked:border-brand-glow has-checked:text-ink has-checked:outline-3 has-checked:outline-gold has-checked:outline-offset-1 has-focus-visible:outline-3 has-focus-visible:outline-focus has-focus-visible:outline-offset-2 has-disabled:cursor-not-allowed has-disabled:opacity-60";

/**
 * One choice among a few (language, theme), as native radios in a fieldset named by `legend`:
 * the arrow keys move between them, and the chosen one is outlined in gold.
 */
export function Choices<T extends string>({
  legend,
  hint,
  name,
  value,
  options,
  onChange,
  disabled = false,
}: {
  legend: string;
  hint?: string;
  name: string;
  value: T;
  options: readonly { value: T; label: string; lang?: string }[];
  onChange(value: T): void;
  disabled?: boolean;
}) {
  const hintId = useId();
  return (
    <fieldset
      className="m-0 flex min-w-0 flex-col gap-(--space-2) border-0 p-0"
      disabled={disabled}
      aria-describedby={hint ? hintId : undefined}
    >
      <legend className="contents">
        <SettingLabel label={legend} />
      </legend>
      <div
        className="grid gap-(--space-2)"
        style={{ gridTemplateColumns: `repeat(${options.length}, minmax(0, 1fr))` }}
      >
        {options.map((option) => (
          <label key={option.value} className={OPTION} lang={option.lang}>
            <input
              type="radio"
              name={name}
              value={option.value}
              checked={value === option.value}
              onChange={() => onChange(option.value)}
              className="absolute inset-0 m-0 cursor-pointer appearance-none opacity-0"
            />
            {option.label}
          </label>
        ))}
      </div>
      {hint && (
        <p id={hintId} className="m-0 text-[13px] text-ink-muted">
          {hint}
        </p>
      )}
    </fieldset>
  );
}

/** An on/off setting: the whole row is one switch, named by its label. */
export function SettingSwitch({
  label,
  hint,
  checked,
  onChange,
}: {
  label: string;
  hint?: string;
  checked: boolean;
  onChange(checked: boolean): void;
}) {
  const labelId = useId();
  const hintId = useId();
  return (
    <button
      type="button"
      role="switch"
      aria-checked={checked}
      aria-labelledby={labelId}
      aria-describedby={hint ? hintId : undefined}
      onClick={() => onChange(!checked)}
      className="lk-switch-row flex min-h-11 w-full items-center justify-between gap-(--space-3) rounded-md border-0 bg-transparent p-0 text-left"
    >
      <span className="flex flex-col gap-(--space-1)">
        <span id={labelId} className="text-[15px] font-bold text-ink">
          {label}
        </span>
        {hint && (
          <span id={hintId} className="text-[13px] font-normal text-ink-muted">
            {hint}
          </span>
        )}
      </span>
      <span className="lk-switch" aria-hidden="true">
        <span className="lk-switch-thumb" />
      </span>
    </button>
  );
}

/** What a [SettingsRow] shows at its end. */
export type Trailing =
  | { kind: "chevron"; value?: ReactNode }
  | { kind: "switch"; checked: boolean; onChange(value: boolean): void }
  | { kind: "chip"; text: string }
  | { kind: "trash"; label: string; onPress(): void }
  | { kind: "none" };

/**
 * The head of a [SettingsGroup]: a 40 px icon tile, the group's title and one muted line. `id` is
 * what the group's `aria-labelledby` points at.
 */
export function SettingsGroupHead({
  icon,
  title,
  line,
  id,
}: {
  icon: ReactNode;
  title: string;
  line?: string;
  id?: string;
}) {
  return (
    <div className="lk-group-head">
      <span className="lk-menutile" aria-hidden="true">
        {icon}
      </span>
      <span className="lk-row-text">
        <span id={id} className="lk-group-head-title">
          {title}
        </span>
        {line && <span className="lk-row-line text-ink-muted">{line}</span>}
      </span>
    </div>
  );
}

/**
 * A light group of rows (a settings category's list): `surface-row` with a 2px stroke, an optional
 * small uppercase label or a [SettingsGroupHead] (`head`), rows divided by a 2px line. Named by
 * its label or head title when it has one.
 */
export function SettingsGroup({
  label,
  head,
  children,
}: {
  label?: string;
  head?: { icon: ReactNode; title: string; line?: string };
  children: ReactNode;
}) {
  const id = useId();
  return (
    <div role="group" aria-labelledby={label || head ? id : undefined} className="lk-group">
      {label && (
        <div id={id} className="lk-group-label">
          {label}
        </div>
      )}
      {head && <SettingsGroupHead id={id} {...head} />}
      {children}
    </div>
  );
}

/**
 * One row of a [SettingsGroup]: an icon, a title with an optional muted line, and a trailing part.
 * A `switch` row is one switch named by its title; a `trash` row has its own button; `onPress` or
 * `href` make the rest of the row a button or a link (http(s) opens in a new tab).
 */
export function SettingsRow({
  icon,
  title,
  line,
  trailing,
  onPress,
  href,
  tone,
  description,
}: {
  icon: ReactNode;
  title: string;
  line?: string;
  /**
   * A longer explanation the one-line row cannot hold, read out with the row (its accessible
   * description) but not drawn.
   */
  description?: string;
  trailing: Trailing;
  onPress?: () => void;
  href?: string;
  tone?: "danger";
}) {
  const titleId = useId();
  const lineId = useId();
  const descriptionId = useId();
  const danger = tone === "danger";
  const describedBy = [line ? lineId : null, description ? descriptionId : null]
    .filter(Boolean)
    .join(" ");
  const lead = (
    <>
      <span
        className={cx("lk-row-icon", danger ? "text-over" : "text-ink-muted")}
        aria-hidden="true"
      >
        {icon}
      </span>
      <span className="lk-row-text">
        <span id={titleId} className={cx("lk-row-title", danger ? "text-over" : "text-ink")}>
          {title}
        </span>
        {line && (
          <span id={lineId} className="lk-row-line text-ink-muted">
            {line}
          </span>
        )}
        {description && (
          <span id={descriptionId} hidden>
            {description}
          </span>
        )}
      </span>
    </>
  );

  if (trailing.kind === "switch") {
    return (
      <button
        type="button"
        role="switch"
        aria-checked={trailing.checked}
        aria-labelledby={titleId}
        aria-describedby={describedBy || undefined}
        onClick={() => trailing.onChange(!trailing.checked)}
        className="lk-row lk-switch-row"
      >
        {lead}
        <span className="lk-switch lk-row-switch" aria-hidden="true">
          <span className="lk-switch-thumb" />
        </span>
      </button>
    );
  }

  const press = (children: ReactNode) => {
    if (href !== undefined) {
      return /^https?:\/\//.test(href) ? (
        <a
          href={href}
          target="_blank"
          rel="noreferrer"
          aria-describedby={description ? descriptionId : undefined}
          className="lk-row lk-row-press"
        >
          {children}
        </a>
      ) : (
        <Link
          to={href}
          aria-describedby={description ? descriptionId : undefined}
          className="lk-row lk-row-press"
        >
          {children}
        </Link>
      );
    }
    if (onPress) {
      return (
        <button
          type="button"
          onClick={onPress}
          aria-describedby={description ? descriptionId : undefined}
          className="lk-row lk-row-press"
        >
          {children}
        </button>
      );
    }
    return <div className="lk-row">{children}</div>;
  };

  if (trailing.kind === "trash") {
    return (
      <div className="lk-row-split">
        <div className="lk-row-split-main">{press(lead)}</div>
        <button
          type="button"
          aria-label={trailing.label}
          onClick={trailing.onPress}
          className="lk-row-trash text-over"
        >
          <span className="lk-row-trash-box">
            <Icon name="trash" size={18} />
          </span>
        </button>
      </div>
    );
  }

  const end =
    trailing.kind === "chevron" ? (
      <span className="lk-row-end text-ink-muted">
        {trailing.value !== undefined && <span className="lk-row-value">{trailing.value}</span>}
        <Icon name="chevron-right" size={16} />
      </span>
    ) : trailing.kind === "chip" ? (
      <span className="lk-row-chip text-ink-muted">{trailing.text}</span>
    ) : null;

  return press(
    <>
      {lead}
      {end}
    </>,
  );
}
