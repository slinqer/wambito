import type { Meta, StoryObj } from "@storybook/react-vite";
import { MemoryRouter } from "react-router";
import { expect, userEvent, waitFor, within } from "storybook/test";
import { expectEdge, expectFocusRing, expectTarget } from "../../../.storybook/story-utils.ts";
import { Faq } from "./Faq.tsx";
import { Footer } from "./Footer.tsx";
import { Hero } from "./Hero.tsx";
import { HowItWorks } from "./HowItWorks.tsx";
import { Landing } from "./Landing.tsx";
import { ANDROID_APK_HREF, ANDROID_RELEASE_HREF } from "./links.ts";
import { NoMoreSpreadsheet } from "./NoMoreSpreadsheet.tsx";
import { OpenSource } from "./OpenSource.tsx";
import { SiteHeader } from "./SiteHeader.tsx";
import { UseItYourWay } from "./UseItYourWay.tsx";

const meta = {
  title: "Landing/Landing",
  component: Landing,
  parameters: { layout: "fullscreen" },
  decorators: [
    (Story) => (
      <MemoryRouter>
        <div className="lk-screen lk-landing">
          <Story />
        </div>
      </MemoryRouter>
    ),
  ],
} satisfies Meta<typeof Landing>;

export default meta;
type Story = StoryObj<typeof meta>;

/** The whole page in Spanish, night theme. */
export const Page: Story = {
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await expect(canvas.getByRole("heading", { level: 1 })).toHaveAccessibleName(
      "Tus lukas, por fin claras.",
    );
    const ctas = canvas.getAllByRole("link", { name: "Empieza ahora" });
    await expect(ctas.map((link) => link.getAttribute("href"))).toEqual([
      "/sign-in?lang=es",
      "/sign-in?lang=es",
    ]);
    await expect(canvas.getByRole("link", { name: "Entrar" })).toHaveAttribute(
      "href",
      "/sign-in?lang=es",
    );
    // No "what's next" section: the header and the footer lead to the roadmap.
    await expect(canvasElement.querySelector("#whats-next")).toBeNull();
    // The day/night switch sits next to "Entrar", in the header.
    await expect(canvas.getByRole("button", { name: "Cambiar a modo día" })).toBeVisible();
  },
};

/** The whole page in English, day theme. */
export const PageDayEnglish: Story = {
  globals: { theme: "day", locale: "en" },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await expect(canvas.getByRole("heading", { level: 1 })).toHaveAccessibleName(
      "Your money, finally clear.",
    );
    await expect(canvas.getAllByRole("link", { name: "Get started" })[0]).toHaveAttribute(
      "href",
      "/sign-in?lang=en",
    );
  },
};

/**
 * Hero: no handwritten note any more, the headline with "lukas" on the gold marker (taking turns with
 * what money is called elsewhere, each with its flag), one primary action
 * on its edge with the perks (open source links to GitHub), Wambi waving.
 */
export const HeroSection: Story = {
  render: () => <Hero />,
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await expect(canvasElement.querySelectorAll("s")).toHaveLength(0);
    await expect(canvas.queryByText("¡Gratis, y siempre lo será!")).toBeNull();
    const headline = canvas.getByRole("heading", { level: 1 });
    await expect(headline).toHaveAccessibleName("Tus lukas, por fin claras.");
    await expect(headline.querySelector(".lk-landing-marker")).toHaveTextContent("lukas");
    await expect(headline.querySelector(".lk-landing-flag")).toHaveTextContent("🇨🇴");
    await expect(
      canvas.getByRole("link", { name: "Código abierto (se abre en una pestaña nueva)" }),
    ).toHaveAttribute("href", "https://github.com/slinqer/wambito");
    await expect(canvas.getByRole("link", { name: "Pruébalo sin cuenta" })).toHaveAttribute(
      "href",
      "/demo?lang=es",
    );
    const cta = canvas.getByRole("link", { name: "Empieza ahora" });
    await expectEdge(cta, 6);
    await expectTarget(cta);
    await userEvent.tab();
    await expectFocusRing(cta);
    const mascot = canvas.getByRole("img", { name: /Wambi/ });
    await expect(mascot).toHaveAttribute("data-slot", "hero-mascot");
    await expect(mascot.querySelector(".lk-wambi")).toHaveAttribute("aria-hidden", "true");
    // He waves once and rests: the hero's sprite plays its sheet a single time.
    await expect(mascot.querySelector(".lk-wambi-sprite")).toHaveClass("is-once");
  },
};

/** Hero in English by day, with the demo as the second action. */
export const HeroWithDemoDayEnglish: Story = {
  render: () => <Hero />,
  globals: { theme: "day", locale: "en" },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    const demo = canvas.getByRole("link", { name: "Try it without an account" });
    await expect(demo).toHaveAttribute("href", "/demo?lang=en");
    await expect(demo).toHaveClass("lk-btn-secondary");
    await expectTarget(demo);
  },
};

/**
 * The headline in English, Portuguese and Italian: the plain word first, with no flag, then what
 * money is called elsewhere, with its flag, and the words around it agreeing with it.
 */
function headlineTurns(first: string, next: string, flag: string, shown: string) {
  return async ({ canvasElement }: { canvasElement: HTMLElement }) => {
    const headline = within(canvasElement).getByRole("heading", { level: 1 });
    const marker = headline.querySelector(".lk-landing-marker") as HTMLElement;
    await expect(marker).toHaveTextContent(first);
    await expect(headline.querySelector(".lk-landing-flag")).toHaveTextContent("");
    await waitFor(() => expect(marker).toHaveTextContent(next), { timeout: 5000 });
    await expect(headline.querySelector(".lk-landing-flag")).toHaveTextContent(flag);
    await waitFor(() =>
      expect(headline.querySelector("[aria-hidden='true']")).toHaveTextContent(shown),
    );
  };
}

export const HeadlineEnglish: Story = {
  render: () => <Hero />,
  globals: { locale: "en" },
  play: headlineTurns("money", "bucks", "🇺🇸", "Your bucks🇺🇸, finally clear."),
};

export const HeadlinePortuguese: Story = {
  render: () => <Hero />,
  globals: { locale: "pt" },
  play: headlineTurns("dinheiro", "grana", "🇧🇷", "A tua grana🇧🇷, finalmente clara."),
};

export const HeadlineItalian: Story = {
  render: () => <Hero />,
  globals: { locale: "it" },
  play: headlineTurns("soldi", "grana", "🇮🇹", "La tua grana🇮🇹, finalmente chiara."),
};

/** Hero under reduced motion: Wambi holds still. */
export const HeroReducedMotion: Story = {
  render: () => <Hero />,
  parameters: { reducedMotion: true },
  play: async ({ canvasElement }) => {
    const wambi = canvasElement.querySelector(".lk-wambi") as HTMLElement;
    await expect(wambi.getAnimations({ subtree: true })).toHaveLength(0);
  },
};

/** Web is live; Android downloads the APK (iOS is coming); the AI assistants are coming soon. */
export const UseItYourWaySection: Story = {
  render: () => <UseItYourWay />,
  globals: { theme: "day" },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await expect(canvas.getAllByRole("listitem")).toHaveLength(3);
    const start = canvas.getByRole("link", { name: "Empezar" });
    await expect(start).toHaveAttribute("href", "/sign-in?lang=es");
    await expectTarget(start);
    await expect(canvas.getAllByText("Pronto")).toHaveLength(1);
    const apk = canvas.getByRole("link", { name: "Descargar para Android" });
    await expect(apk).toHaveAttribute("href", ANDROID_APK_HREF);
    await expect(apk).not.toHaveAttribute("target");
    const all = canvas.getByRole("link", { name: /Otras versiones/ });
    await expect(all).toHaveAttribute("href", ANDROID_RELEASE_HREF);
    await expect(all).toHaveAttribute("target", "_blank");
    await expect(canvas.getByText("En iOS, pronto.")).toBeVisible();
    await expect(canvas.getByText("Claude / ChatGPT")).toBeVisible();
    await expect(canvas.getByRole("heading", { name: "App para Android y iOS" })).toBeVisible();
  },
};

/** No more spreadsheet: a heading, Wambi shredding a spreadsheet, and three before/after rows. */
export const NoMoreSpreadsheetSection: Story = {
  render: () => <NoMoreSpreadsheet />,
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await expect(canvas.getByRole("heading", { level: 2 })).toHaveAccessibleName(
      "Chao al Excel de gastos.",
    );
    // Light: no subtitle and no column labels, only the heading, Wambi and the rows.
    await expect(canvasElement).not.toHaveTextContent("Sin fórmulas");
    await expect(canvasElement.querySelector(".lk-landing-compare-labels")).toBeNull();
    const art = canvas.getByRole("img", {
      name: "Wambi, contento, mete una hoja de cálculo en una trituradora de papel",
    });
    await expect(art).toHaveAttribute("src", "/wambi/shredder.webp");
    await expect(art).toHaveAttribute("loading", "lazy");
    // The scroll film: eight poses, from shredding the sheet to showing Wambito on a phone, decorative (the still says it).
    const poses = canvasElement.querySelectorAll<HTMLImageElement>(".lk-landing-nosheet-pose");
    await expect(poses).toHaveLength(8);
    for (const [index, pose] of [...poses].entries()) {
      await expect(pose).toHaveAttribute("src", `/wambi/shredder/${index + 1}.webp`);
      await expect(pose).toHaveAttribute("alt", "");
      await expect(pose).toHaveAttribute("loading", "lazy");
    }
    await expect(canvas.getAllByRole("img")).toHaveLength(1);
    // Three pains of a spreadsheet, each beside how Wambito solves it; screen readers hear which is which.
    const rows = canvas.getAllByRole("listitem");
    await expect(rows).toHaveLength(3);
    await expect(rows[0]).toHaveTextContent(
      "Con un Excel: Abres el computador, buscas el archivo y bajas hasta la última fila.",
    );
    await expect(rows[0]).toHaveTextContent(
      "Con Wambito: Lo anotas en segundos, también desde el celular.",
    );
    await expect(rows[2]).toHaveTextContent("Con Wambito: Tus presupuestos te avisan antes.");
  },
};

/** Four steps with decorative illustrations, money in the locale's format. */
export const HowItWorksSection: Story = {
  render: () => <HowItWorks />,
  globals: { locale: "en" },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await expect(canvas.getAllByRole("heading", { level: 3 }).map((h) => h.textContent)).toEqual([
      "Log your expenses by voice",
      "See where it goes",
      "Budgets that give you a heads-up",
      "Bring your history",
      "Wambi logs your expenses for you!",
    ]);
    for (const demo of canvasElement.querySelectorAll(".lk-landing-demo")) {
      await expect(demo).toHaveAttribute("aria-hidden", "true");
    }
    // The voice card: what you say to Wambi, then the expense it logs.
    await expect(canvasElement).toHaveTextContent("I spent 3 euros on coffee");
    await expect(canvasElement).toHaveTextContent("Coffee−€3.00");
    await expect(canvasElement).toHaveTextContent("From the Android app's widget.");
    await expect(canvasElement).toHaveTextContent("€46.33 left");
    await expect(canvasElement).toHaveTextContent("1,248 transactions ready");
    await expect(canvasElement).toHaveTextContent("Budge today, Buddy and others soon.");
  },
};

/**
 * "How it works" cards come alive on hover (and on tap, on phones): the mic pulses, what you said
 * and the expense slide in and "¡Anotado!" bounces; the donut sweeps in clockwise from the top as
 * in the app's insights; the budget bars fill up; the file pushes the arrow. Once per hover.
 */
export const HowItWorksHover: Story = {
  render: () => <HowItWorks />,
  play: async () => {
    const hovered = new Map<string, string>();
    for (const sheet of document.styleSheets) {
      let rules: CSSRuleList;
      try {
        rules = sheet.cssRules;
      } catch {
        continue;
      }
      const walk = (list: CSSRuleList) => {
        for (const rule of list) {
          if (
            rule instanceof CSSStyleRule &&
            rule.selectorText.includes(".lk-landing-card:hover")
          ) {
            // With var() in the shorthand the longhands read empty, so take the whole declaration.
            hovered.set(rule.selectorText, rule.style.getPropertyValue("animation"));
          }
          if ("cssRules" in rule) walk((rule as CSSGroupingRule).cssRules);
        }
      };
      walk(rules);
    }
    const animated = (part: string) =>
      [...hovered].some(([selector, name]) => selector.includes(part) && /lk-landing-/.test(name));
    for (const part of [
      ".lk-landing-saved",
      ".lk-landing-donut",
      ".lk-landing-legend",
      ".lk-bar",
      ".lk-landing-arrow",
      ".lk-landing-mic",
      ".lk-landing-said",
    ]) {
      await expect(animated(part), part).toBe(true);
    }
  },
};

/**
 * "Bring your history": under the pointer the count runs from 0 up to 1248 transactions, then a
 * check pops to confirm. The budget card's near bar turns from green to yellow as it fills.
 */
export const HowItWorksImportCount: Story = {
  render: () => <HowItWorks />,
  play: async ({ canvasElement }) => {
    const imported = canvasElement.querySelector<HTMLElement>(".lk-landing-imported");
    const card = imported?.closest("li");
    if (!imported || !card) throw new Error("no import card");
    // Without a hover it shows the final count, confirmed.
    await expect(imported).toHaveTextContent("1248 movimientos listos");
    await expect(imported).toHaveAttribute("data-state", "done");
    card.dispatchEvent(new PointerEvent("pointerenter", { pointerType: "mouse" }));
    await waitFor(() => expect(imported).toHaveAttribute("data-state", "counting"));
    const midway = Number(imported.textContent?.replace(/\D/g, ""));
    await expect(midway).toBeLessThan(1248);
    await waitFor(
      () => {
        expect(imported).toHaveAttribute("data-state", "done");
        expect(imported).toHaveTextContent("1248 movimientos listos");
      },
      { timeout: 4000 },
    );
    await expect(imported.querySelector(".lk-landing-imported-check")).not.toBeNull();

    // The near bar's fill changes color on the way: green first, yellow at the end.
    const fillNear = [...document.styleSheets]
      .flatMap((sheet) => {
        try {
          return [...sheet.cssRules];
        } catch {
          return [];
        }
      })
      .find((rule) => rule instanceof CSSKeyframesRule && rule.name === "lk-landing-fill-near") as
      | CSSKeyframesRule
      | undefined;
    await expect(fillNear?.cssText).toMatch(/var\(--good\)[\s\S]*var\(--near\)/);
  },
};

/** Open source: the code icon, one short paragraph and the repository, in a new tab. */
export const OpenSourceSection: Story = {
  render: () => <OpenSource />,
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await expect(canvas.getByRole("heading", { level: 2 })).toHaveTextContent("Código abierto");
    await expect(canvasElement).toHaveTextContent("AGPL-3.0");
    const code = canvas.getByRole("link", {
      name: "Ver el código en GitHub (se abre en una pestaña nueva)",
    });
    await expect(code).toHaveAttribute("href", "https://github.com/slinqer/wambito");
    await expect(code).toHaveAttribute("target", "_blank");
    await expectEdge(code, 3);
    await expectTarget(code);
  },
};

/** Questions open in place; each summary is a 44px pressable card with the focus ring. */
export const FaqSection: Story = {
  render: () => <Faq />,
  play: async ({ canvasElement }) => {
    const summaries = [...canvasElement.querySelectorAll("summary")];
    await expect(summaries).toHaveLength(6);
    const first = summaries[0] as HTMLElement;
    await expectTarget(first);
    await userEvent.click(first);
    await expect(first.parentElement).toHaveAttribute("open");
    await expect(summaries[3]?.parentElement?.querySelector("a")).toHaveAttribute(
      "href",
      "/privacy",
    );
    await userEvent.tab();
    await expectFocusRing(summaries[1] as HTMLElement);
  },
};

/** Header: the language switch open, the current language marked, each option the same page. */
export const HeaderLanguageMenu: Story = {
  render: () => <SiteHeader page="landing" />,
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    const button = canvas.getByRole("button", { name: "ES, Idioma: Español" });
    await expect(button).toHaveTextContent("ES");
    await expectTarget(button);
    await userEvent.click(button);
    await expect(button).toHaveAttribute("aria-expanded", "true");
    await expect(canvas.getByRole("link", { name: "Español" })).toHaveAttribute(
      "aria-current",
      "true",
    );
    const english = canvas.getByRole("link", { name: "English" });
    await expect(english).toHaveAttribute("href", "/en");
    await expect(english).toHaveAttribute("hreflang", "en");
    for (const option of ["Español", "English", "Italiano", "Português"]) {
      await expectTarget(canvas.getByRole("link", { name: option }));
    }
  },
};

/**
 * Scroll reveals: cards, section headings, FAQ questions and the before/after rows rise into place
 * as they scroll in, driven by the scroll itself (CSS view timelines, no JavaScript). The hero and
 * the closing hold still: the traveling Wambi lands on their spots.
 */
export const ScrollReveal: Story = {
  play: async ({ canvasElement }) => {
    const scrollDriven = (el: Element | null) =>
      (el?.getAnimations() ?? []).filter(
        (a) => typeof ViewTimeline !== "undefined" && a.timeline instanceof ViewTimeline,
      );
    if (typeof ViewTimeline === "undefined") return;
    for (const selector of [
      "#ways .lk-landing-card",
      "#how .lk-landing-section-head",
      "#faq .lk-landing-faq > li",
      "#spreadsheet .lk-landing-compare-row .is-before",
      "#spreadsheet .lk-landing-compare-row .is-after",
    ]) {
      await expect(scrollDriven(canvasElement.querySelector(selector)), selector).toHaveLength(1);
    }
    // The before/after rows slide in from opposite sides.
    const startX = (selector: string) => {
      const [animation] = scrollDriven(canvasElement.querySelector(selector));
      const from = (animation?.effect as KeyframeEffect | undefined)?.getKeyframes()[0];
      return String(from?.translate ?? "").split(" ")[0];
    };
    await expect(startX("#spreadsheet .lk-landing-compare-row .is-before")).toBe("-24px");
    await expect(startX("#spreadsheet .lk-landing-compare-row .is-after")).toBe("24px");
    // Wambi's poses cross-fade with the scroll of the spreadsheet's stage, one after the other.
    const poses = [...canvasElement.querySelectorAll("#spreadsheet .lk-landing-nosheet-pose")];
    await expect(poses).toHaveLength(8);
    for (const pose of poses) {
      await expect(scrollDriven(pose)).toHaveLength(1);
    }
    // `rangeStart` is not in TypeScript's DOM types yet.
    type Ranged = Animation & { rangeStart?: { offset?: unknown } };
    const starts = poses.map((pose) =>
      String((scrollDriven(pose)[0] as Ranged | undefined)?.rangeStart?.offset ?? ""),
    );
    await expect(new Set(starts).size).toBe(8);
    await expect(scrollDriven(canvasElement.querySelector("#hero"))).toHaveLength(0);
    await expect(scrollDriven(canvasElement.querySelector(".lk-landing-closing"))).toHaveLength(0);
  },
};

/**
 * Hover halo: with a mouse over "Empieza ahora", the light follows the pointer inside the button and
 * the halo around it leans toward that side.
 */
export const ButtonHalo: Story = {
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    const [cta] = canvas.getAllByRole("link", { name: "Empieza ahora" });
    if (!cta) throw new Error("no primary action");
    const box = cta.getBoundingClientRect();
    cta.dispatchEvent(
      new PointerEvent("pointermove", {
        bubbles: true,
        pointerType: "mouse",
        clientX: box.left + box.width - 4,
        clientY: box.top + 4,
      }),
    );
    await expect(cta.style.getPropertyValue("--lk-glow-x")).toBe(`${Math.round(box.width - 4)}px`);
    await expect(cta.style.getPropertyValue("--lk-glow-y")).toBe("4px");
    await expect(Number(cta.style.getPropertyValue("--lk-lean-x"))).toBeGreaterThan(0.9);
    await expect(Number(cta.style.getPropertyValue("--lk-lean-y"))).toBeLessThan(-0.8);
    // A finger has no hover: touch moves leave the button alone.
    const [other] = canvas.getAllByRole("link", { name: "Pruébalo sin cuenta" });
    other?.dispatchEvent(
      new PointerEvent("pointermove", {
        bubbles: true,
        pointerType: "touch",
        clientX: 1,
        clientY: 1,
      }),
    );
    await expect(other?.style.getPropertyValue("--lk-glow-x") ?? "").toBe("");
  },
};

/** Language switch (current language marked), privacy and account deletion links, copyright. */
export const FooterSection: Story = {
  render: () => <Footer />,
  globals: { locale: "en", theme: "day" },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    const english = canvas.getByRole("link", { name: "English" });
    await expect(english).toHaveAttribute("aria-current", "true");
    const spanish = canvas.getByRole("link", { name: "Español" });
    await expect(spanish).toHaveAttribute("href", "/");
    await expect(spanish).toHaveAttribute("hreflang", "es");
    await expect(canvas.getByRole("link", { name: "Privacy" })).toHaveAttribute(
      "href",
      "/en/privacy",
    );
    await expect(canvas.getByRole("link", { name: "Delete account" })).toHaveAttribute(
      "href",
      "/en/delete-account",
    );
    for (const link of canvas.getAllByRole("link")) await expectTarget(link);
    await expect(canvasElement).toHaveTextContent("© 2026 Wambito");
  },
};
