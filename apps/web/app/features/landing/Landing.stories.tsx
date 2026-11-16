import type { Meta, StoryObj } from "@storybook/react-vite";
import { MemoryRouter } from "react-router";
import { expect, userEvent, waitFor, within } from "storybook/test";
import { expectEdge, expectFocusRing, expectTarget } from "../../../.storybook/story-utils.ts";
import { AgentDemo } from "./AgentDemo.tsx";
import { AutomaticCapture } from "./AutomaticCapture.tsx";
import { Faq } from "./Faq.tsx";
import { Footer } from "./Footer.tsx";
import { Hero } from "./Hero.tsx";
import { HowItWorks } from "./HowItWorks.tsx";
import { Landing } from "./Landing.tsx";
import { ANDROID_APK_HREF } from "./links.ts";
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
 * on its edge, no perks line under it, and Wambi standing still.
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
    // No perks line under the actions any more (free, open source, no passwords).
    await expect(canvasElement.querySelector(".lk-landing-perks")).toBeNull();
    await expect(canvas.queryByRole("link", { name: /Código abierto/ })).toBeNull();
    // Two app-icon tiles inside the headline, decorative.
    const tiles = [...headline.querySelectorAll("[aria-hidden='true'] [data-tile]")];
    await expect(tiles.map((tile) => tile.getAttribute("data-tile"))).toEqual(["app", "notice"]);
    await expect(canvas.getByRole("link", { name: "Pruébalo sin cuenta" })).toHaveAttribute(
      "href",
      "/demo?lang=es",
    );
    const cta = canvas.getByRole("link", { name: "Empieza ahora" });
    await expectEdge(cta, 6);
    await expectTarget(cta);
    await userEvent.tab();
    await expectFocusRing(cta);
    // No Wambi in the hero any more: he jumps further down, by the feature grid's title.
    await expect(canvasElement.querySelector(".lk-wambi")).toBeNull();
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

/**
 * Android downloads the APK from GitHub (Google Play coming soon), iOS is coming soon on the App
 * Store; no web card, and no agent card (the agent has its own section).
 */
export const UseItYourWaySection: Story = {
  render: () => <UseItYourWay />,
  globals: { theme: "day" },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await expect(canvas.getAllByRole("heading", { level: 3 }).map((h) => h.textContent)).toEqual([
      "App para Android",
      "App para iOS",
    ]);
    await expect(canvas.queryByRole("link", { name: "Empezar" })).toBeNull();
    await expect(canvas.getAllByText("Pronto")).toHaveLength(2);
    await expect(canvas.getByText("Google Play").parentElement).toHaveTextContent(
      "Google PlayPronto",
    );
    await expect(canvas.getByText("App Store").parentElement).toHaveTextContent("App StorePronto");
    const apk = canvas.getByRole("link", { name: "Desde GitHub" });
    await expect(apk).toHaveAttribute("href", ANDROID_APK_HREF);
    await expect(apk).not.toHaveAttribute("target");
    // No "other versions" link: the stores are button-shaped, not links.
    await expect(canvas.queryByRole("link", { name: /Otras versiones/ })).toBeNull();
    await expect(canvas.getAllByRole("link")).toHaveLength(1);
    await expect(canvas.queryByText("Claude / ChatGPT")).toBeNull();
    // Each card shows its brands' logos, decorative: the heading already names them.
    const logos = [...canvasElement.querySelectorAll("#ways li")].map((card) =>
      [...card.querySelectorAll("[data-logo]")].map((logo) => logo.getAttribute("data-logo")),
    );
    await expect(logos).toEqual([
      ["android", "github", "googleplay"],
      ["apple", "appstore"],
    ]);
    for (const logo of canvasElement.querySelectorAll("[data-logo]")) {
      await expect(logo.closest("[aria-hidden='true']")).not.toBeNull();
      await expect(logo.querySelector("path")?.getAttribute("d")).toMatch(/^[Mm]/);
    }
  },
};

/**
 * Automatic capture, under the hero: its heading, the line naming Revolut and Google Wallet, a
 * real link to its page, and the notification turning into an expense, decorative.
 */
export const AutomaticCaptureSection: Story = {
  render: () => <AutomaticCapture pace={0.2} />,
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await expect(canvas.getByRole("heading", { level: 2 })).toHaveTextContent(
      "¡Wambi anota los gastos por ti!",
    );
    await expect(canvasElement).toHaveTextContent("Revolut");
    await expect(canvasElement).toHaveTextContent("Google Wallet");
    await expect(canvas.getByRole("link", { name: "¿Cómo funciona?" })).toHaveAttribute(
      "href",
      "/automatic-capture",
    );
    await expect(canvasElement.querySelector(".lk-landing-panel")).toHaveAttribute(
      "aria-hidden",
      "true",
    );
    // No "soon" badge: the capture is in the Android app today.
    await expect(canvasElement.querySelector(".lk-landing-soon")).toBeNull();
    // Google Wallet's notification, in pesos in Spanish (the demo currency per language).
    const panel = canvasElement.querySelector<HTMLElement>(".lk-landing-capture-play");
    if (!panel) throw new Error("no panel");
    await expect(panel.querySelector(".lk-capture-notif")).toHaveAttribute(
      "data-source",
      "googlewallet",
    );
    await expect(panel.querySelector(".lk-capture-notif")).toHaveTextContent("Google Wallet");
    await expect(panel.querySelector(".lk-capture-notif")).toHaveTextContent("$50.000");
    // On a loop while on screen: the notification drops in, the arrow, then "logged", and again.
    const seen = new Set<string>();
    await waitFor(
      () => {
        seen.add(panel.dataset.phase ?? "");
        expect([...seen]).toEqual(expect.arrayContaining(["notify", "arrow", "logged"]));
      },
      { timeout: 4000, interval: 20 },
    );
    await waitFor(() => expect(panel.dataset.phase).toBe("notify"), {
      timeout: 2000,
      interval: 20,
    });
  },
};

/**
 * Your agent: the heading, the way in and the two assistants' logos, and a chat whose three
 * examples take turns while it is on screen: Uber this month, the budgets, where the money went.
 */
export const AgentDemoSection: Story = {
  render: () => <AgentDemo pace={0.1} />,
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await expect(canvas.getByRole("heading", { level: 2 })).toHaveTextContent(
      "Tu agente analiza tus gastos.",
    );
    await expect(canvas.getByRole("link", { name: /Conecta tu agente/ })).toHaveAttribute(
      "href",
      "/sign-in?lang=es",
    );
    const logos = [...canvasElement.querySelectorAll("[data-logo]")].map((logo) =>
      logo.getAttribute("data-logo"),
    );
    await expect(logos).toEqual(["claude", "openai"]);
    const chat = canvasElement.querySelector<HTMLElement>(".lk-landing-chat");
    if (!chat) throw new Error("no chat");
    await expect(chat).toHaveAttribute("aria-hidden", "true");
    // In view, three examples take turns, each with its question, Wambito thinking, then its answer.
    const answer = (example: string) =>
      waitFor(
        () => {
          expect(chat.dataset.example).toBe(example);
          expect(chat.dataset.phase).toBe("answer");
        },
        { timeout: 2000, interval: 20 },
      );
    await answer("uber");
    await expect(chat).toHaveTextContent("¿Cuánto me gasté en Uber este mes?");
    // Pesos in Spanish (the demo currency per language).
    await expect(chat).toHaveTextContent("Este mes llevas $345.600 en Uber, en 7 viajes");
    await expect(chat.querySelectorAll(".lk-landing-chat-card li")).toHaveLength(3);
    await expect(chat.querySelector(".lk-landing-shimmer")).toBeNull();
    await expect(chat.querySelectorAll(".lk-landing-chat-dots > .is-on")).toHaveLength(1);
    await answer("budgets");
    await expect(chat).toHaveTextContent("¿Cómo van mis presupuestos?");
    await expect(chat.querySelectorAll(".lk-landing-chat-card .lk-bar")).toHaveLength(3);
    // Near its limit (85%), restaurants' bar is yellow.
    await expect(chat.querySelector(".lk-landing-budget .lk-bar")).toHaveClass("is-near");
    await answer("top");
    await expect(chat).toHaveTextContent("¿En qué se me fue más plata este mes?");
    await expect(chat.querySelectorAll(".lk-landing-column")).toHaveLength(4);
    // Then round again.
    await answer("uber");
  },
};

/** Six features, each with its name, a line and a decorative illustration, money in the locale's format. */
export const HowItWorksSection: Story = {
  render: () => <HowItWorks />,
  globals: { locale: "en" },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    const title = canvas.getByRole("heading", { level: 2 });
    await expect(title).toHaveAccessibleName("Your whole month, in one app.");
    // Wambi jumps for joy after the title: one still frame, decorative.
    const wambi = title.querySelector("[data-wambi-spot='how']");
    await expect(wambi).toHaveAttribute("aria-hidden", "true");
    const sprite = wambi?.querySelector<HTMLElement>(".lk-wambi-sprite");
    await expect(sprite).not.toHaveClass("is-playing");
    await expect(sprite?.getAnimations() ?? []).toHaveLength(0);
    // Each card's name (the badge aside).
    const names = canvas
      .getAllByRole("heading", { level: 3 })
      .map((h) => h.firstChild?.textContent);
    await expect(names).toEqual([
      "See where it goes",
      "Budgets that give you a heads-up",
      "Fixed payments, no surprises",
      "Only you can read your data",
      "Bring your history",
      "Sign in without passwords",
    ]);
    const demos = canvasElement.querySelectorAll(".lk-landing-demo");
    await expect(demos).toHaveLength(6);
    for (const demo of demos) {
      await expect(demo).toHaveAttribute("aria-hidden", "true");
    }
    // Automatic capture has its own section now, and the voice and month cards are gone.
    await expect(canvasElement).not.toHaveTextContent("Wambi logs your expenses for you!");
    await expect(canvasElement).not.toHaveTextContent("I spent 3 euros on coffee");
    await expect(canvasElement).not.toHaveTextContent("Your month at a glance");
    await expect(canvasElement).toHaveTextContent("Due in 3 days");
    await expect(canvasElement).toHaveTextContent("Due in 9 days");
    // End-to-end encryption, live (no "soon"): not even Wambito reads it; the expense on the phone,
    // scrambled on the server.
    const vault = canvas
      .getByRole("heading", { name: "Only you can read your data" })
      .closest("li");
    await expect(vault).toHaveTextContent("not even Wambito");
    await expect(vault).not.toHaveTextContent("Soon");
    await expect(vault).toHaveTextContent("On your phone");
    await expect(vault).toHaveTextContent("What the server sees");
    // Dollars in English (the demo currency per language).
    await expect(vault).toHaveTextContent("−$4.50");
    await expect(canvasElement).toHaveTextContent("482 913");
    await expect(canvasElement).toHaveTextContent("$46.33 left");
    await expect(canvasElement).toHaveTextContent("1,248 transactions ready");
    await expect(canvasElement).toHaveTextContent("Budge today, Buddy and others soon.");
  },
};

/**
 * The cards play by themselves once on screen, no pointer needed, and again every few seconds
 * while they stay there: the donut sweeps in clockwise from the top as in the app's insights; the
 * budget bars fill up; the file pushes the arrow; the expense is locked and leaves scrambled.
 * Nothing waits for a hover any more. `pace` runs it fast here.
 */
export const HowItWorksPlays: Story = {
  render: () => <HowItWorks pace={0.1} />,
  play: async ({ canvasElement }) => {
    const playing = new Map<string, string>();
    const hovered: string[] = [];
    for (const sheet of document.styleSheets) {
      let rules: CSSRuleList;
      try {
        rules = sheet.cssRules;
      } catch {
        continue;
      }
      const walk = (list: CSSRuleList) => {
        for (const rule of list) {
          if (rule instanceof CSSStyleRule && rule.selectorText.includes(".lk-landing-card")) {
            // With var() in the shorthand the longhands read empty, so take the whole declaration.
            const animation = rule.style.getPropertyValue("animation");
            if (rule.selectorText.includes("[data-play]"))
              playing.set(rule.selectorText, animation);
            if (/:hover|:active/.test(rule.selectorText) && animation)
              hovered.push(rule.selectorText);
          }
          if ("cssRules" in rule) walk((rule as CSSGroupingRule).cssRules);
        }
      };
      walk(rules);
    }
    const animated = (part: string) =>
      [...playing].some(([selector, name]) => selector.includes(part) && /lk-landing-/.test(name));
    for (const part of [
      ".lk-landing-donut",
      ".lk-landing-legend",
      ".lk-bar",
      ".lk-landing-arrow",
      ".lk-landing-lock",
      ".lk-landing-sealed",
    ]) {
      await expect(animated(part), part).toBe(true);
    }
    await expect(hovered).toEqual([]);

    // Each card on screen plays, then plays again while it stays there.
    const cards = [...canvasElement.querySelectorAll<HTMLElement>(".lk-landing-cards.is-how > li")];
    await expect(cards).toHaveLength(6);
    for (const card of cards) {
      card.scrollIntoView({ block: "center" });
      await waitFor(() => expect(card).toHaveAttribute("data-play"));
      const first = Number(card.dataset.play);
      await waitFor(() => expect(Number(card.dataset.play)).toBeGreaterThan(first), {
        timeout: 2000,
      });
    }
  },
};

/**
 * "Bring your history": once on screen the count runs from 0 up to 1248 transactions, then a check
 * pops to confirm. Without JavaScript it shows the final count, confirmed. The budget card's near
 * bar turns from green to yellow as it fills.
 */
export const HowItWorksImportCount: Story = {
  render: () => <HowItWorks pace={0.5} />,
  play: async ({ canvasElement }) => {
    const card = canvasElement.querySelector<HTMLElement>(".lk-landing-imported")?.closest("li");
    if (!card) throw new Error("no import card");
    const imported = () => card.querySelector<HTMLElement>(".lk-landing-imported");
    card.scrollIntoView({ block: "center" });
    await waitFor(() => expect(imported()).toHaveAttribute("data-state", "counting"));
    const midway = Number(imported()?.textContent?.replace(/\D/g, ""));
    await expect(midway).toBeLessThan(1248);
    await waitFor(
      () => {
        expect(imported()).toHaveAttribute("data-state", "done");
        expect(imported()).toHaveTextContent("1248 movimientos listos");
      },
      { timeout: 4000 },
    );
    await expect(imported()?.querySelector(".lk-landing-imported-check")).not.toBeNull();

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
 * Scroll reveals: cards, section headings and FAQ questions rise into place
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
    ]) {
      await expect(scrollDriven(canvasElement.querySelector(selector)), selector).toHaveLength(1);
    }
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
