import type { ReactNode, Ref } from "react";
import { Link } from "react-router";
import { useTranslations } from "use-intl";
import { landingLink } from "../../site/config.ts";
import { cx } from "../../ui/cx.ts";
import { ThemeToggle } from "../../ui/ThemeToggle.tsx";
import { Wambi, type WambiMood } from "../../wambi/Wambi.tsx";

/** Wambi's size on the sign-in screens: friendly, never crowding the form. */
const MASCOT_PX = 96;

/**
 * The frame of the sign-in screens (`/sign-in`, `/auth/verify`): the wordmark (home) and the
 * day/night switch on top, then one column with Wambi above the content. On a phone the column
 * sits on the background, so the code boxes get the whole width; from `sm` up it is a raised card.
 */
const LOGO_CLASS =
  "lk-logo inline-flex min-h-11 items-center rounded-sm no-underline focus-visible:outline-3 focus-visible:outline-focus focus-visible:outline-offset-2";

export function SignInScreen({
  mood = "happy",
  wide = false,
  rootRef,
  children,
}: {
  mood?: WambiMood;
  /** A computer's `/sign-in`: the card holds two columns (the QR, the other ways). */
  wide?: boolean;
  /** The whole screen, for a page that lays itself out by the screen's width. */
  rootRef?: Ref<HTMLDivElement>;
  children: ReactNode;
}) {
  const t = useTranslations("sign_in");
  const home = landingLink();
  return (
    <div ref={rootRef} className="lk-screen flex min-h-dvh flex-col">
      <header className="mx-auto flex w-full max-w-[480px] items-center justify-between px-(--space-4) py-(--space-3)">
        {home.external ? (
          // The landing lives on its own site here: a full page load, not a route of this app.
          <a href={home.href} aria-label={t("home")} className={LOGO_CLASS}>
            Wambito
          </a>
        ) : (
          <Link to={home.href} aria-label={t("home")} className={LOGO_CLASS}>
            Wambito
          </Link>
        )}
        <ThemeToggle />
      </header>
      <main className="flex flex-1 flex-col items-center px-(--space-4) pb-(--space-6)">
        <div
          className={cx(
            "flex w-full flex-col items-center gap-(--space-4) sm:mt-(--space-5) sm:rounded-xl sm:border-2 sm:border-stroke sm:bg-surface sm:p-(--space-6) sm:shadow-edge-md",
            wide ? "max-w-[880px]" : "max-w-[420px]",
          )}
        >
          <Wambi mood={mood} size={MASCOT_PX} />
          {children}
        </div>
      </main>
    </div>
  );
}

/**
 * The screen's title: display face, centered. A screen that opens by itself (not from a tap on a
 * link) takes the focus to it with `focusable` and a `ref`, so a screen reader starts there.
 */
export function ScreenTitle({
  children,
  ref,
  focusable = false,
}: {
  children: ReactNode;
  ref?: Ref<HTMLHeadingElement>;
  focusable?: boolean;
}) {
  return (
    <h1
      ref={ref}
      tabIndex={focusable ? -1 : undefined}
      className="text-center font-display text-[28px] leading-tight font-bold text-ink outline-none"
    >
      {children}
    </h1>
  );
}

/** An error under the control it is about; `role="alert"` so it is read out when it appears. */
export function FieldError({ id, children }: { id: string; children: ReactNode }) {
  return (
    <p id={id} role="alert" className="text-[15px] text-over">
      {children}
    </p>
  );
}
