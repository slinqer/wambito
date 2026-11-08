import AxeBuilder from "@axe-core/playwright";
import { expect, type Page, test } from "@playwright/test";

/** The Android download: the arm64 APK of the mobile release, and the release page. */
const ANDROID_APK_HREF =
  "https://github.com/slinqer/wambito/releases/download/mobile-v1.0.1/wambito-1.0.1-arm64-v8a.apk";
const ANDROID_RELEASE_HREF = "https://github.com/slinqer/wambito/releases/tag/mobile-v1.0.1";

/**
 * The landing page as shipped: prerendered HTML served statically (playwright.built.config.ts,
 * `pnpm e2e:landing`), read with JavaScript off unless a test turns it on. Everything a visitor or
 * a crawler needs must already be in the HTML.
 */

const ORIGIN = "https://wambito.test";
const GITHUB = "https://github.com/slinqer/wambito";

const LOCALES = [
  {
    locale: "es",
    path: "/",
    headline: "Tus lukas, por fin claras.",
    highlight: "lukas🇨🇴",
    annotation: "¡Gratis, y siempre lo será!",
    lead: "Wambi te acompaña para que cuidar tu plata dé gusto.",
    removedDescription: "Anota un gasto en segundos y mira en qué se va cada luka.",
    newTab: "(se abre en una pestaña nueva)",
    perks: "Gratis para siempre · Código abierto · Sin contraseñas",
    openSourcePerk: "Código abierto",
    removedQuestions: ["¿En qué se me va la plata?", "¿Cuánto me cuesta vivir?"],
    cta: "Empieza ahora",
    demoCta: "Pruébalo sin cuenta",
    webCta: "Empezar",
    soon: "Pronto",
    ways: ["En la web", "App para Android y iOS", "Con tu IA"],
    android: { cta: "Descargar para Android", other: "Otras versiones", ios: "En iOS, pronto." },
    importStep: "Trae tu historial",
    importQuestion: "¿Puedo traer mi historial de otras apps?",
    freeQuestion: "¿Es gratis?",
    freeAnswer: "Sí, y lo será siempre.",
    openSource: { title: "Código abierto", cta: "Ver el código en GitHub" },
    metaDescription: [/Gratis para siempre/, /código abierto/],
    banned: [/mejor amigo/i, /\bjueg(o|a)\b/i, /Empieza gratis/i],
    // Privacy copy claims only what Wambito does today: no "can't leak", no end-to-end encryption,
    // no encryption at rest.
    overclaims: [/se pueda filtrar/i, /extremo a extremo/i, /no podemos ver/i, /en reposo/i],
    privacyAnswer:
      "Tus datos viajan cifrados y nunca los vendemos ni los compartimos con anunciantes.",
    faq: "Preguntas frecuentes",
    signIn: "Entrar",
    toggleToDay: "Cambiar a modo día",
    toggleToNight: "Cambiar a modo noche",
    name: "Español",
    how: "Cómo funciona",
    questions: "Preguntas",
    other: { name: "English", path: "/en", lang: "en" },
    titlePart: "Tus lukas, por fin claras",
  },
  {
    locale: "en",
    path: "/en",
    headline: "Your money, finally clear.",
    highlight: "money",
    annotation: "Free, and it always will be!",
    lead: "Wambi keeps you company, so looking after your money feels good.",
    removedDescription: "Log an expense in seconds and see where every buck goes.",
    newTab: "(opens in a new tab)",
    perks: "Free forever · Open source · No passwords",
    openSourcePerk: "Open source",
    removedQuestions: ["Where does all my money go?", "How much does living cost me?"],
    cta: "Get started",
    demoCta: "Try it without an account",
    webCta: "Start",
    soon: "Soon",
    ways: ["On the web", "Android & iOS app", "With your AI"],
    android: { cta: "Download for Android", other: "Other versions", ios: "On iOS, soon." },
    importStep: "Bring your history",
    importQuestion: "Can I bring my history from other apps?",
    freeQuestion: "Is it free?",
    freeAnswer: "Yes, and it always will be.",
    openSource: { title: "Open source", cta: "View the code on GitHub" },
    metaDescription: [/Free forever/, /open source/],
    banned: [/best friend/i, /\bgames?\b/i, /Start free/i],
    overclaims: [/nothing to leak/i, /end-to-end/i, /can(no|')t see/i, /at rest/i],
    privacyAnswer:
      "Your data travels encrypted, and we never sell it or share it with advertisers.",
    faq: "Frequently asked questions",
    signIn: "Sign in",
    toggleToDay: "Switch to day mode",
    toggleToNight: "Switch to night mode",
    name: "English",
    how: "How it works",
    questions: "Questions",
    other: { name: "Español", path: "/", lang: "es" },
    titlePart: "Your money, finally clear",
  },
  {
    locale: "it",
    path: "/it",
    headline: "I tuoi soldi, finalmente chiari.",
    highlight: "soldi",
    annotation: "Gratis, e lo sarà sempre!",
    lead: "Wambi ti fa compagnia, così prenderti cura dei tuoi soldi è un piacere.",
    removedDescription: "Annota una spesa in pochi secondi e guarda dove va ogni centesimo.",
    newTab: "(si apre in una nuova scheda)",
    perks: "Gratis per sempre · Open source · Senza password",
    openSourcePerk: "Open source",
    removedQuestions: ["Dove se ne vanno tutti i miei soldi?", "Quanto mi costa vivere?"],
    cta: "Inizia ora",
    demoCta: "Provala senza account",
    webCta: "Inizia",
    soon: "Presto",
    ways: ["Sul web", "App per Android e iOS", "Con la tua IA"],
    android: { cta: "Scarica per Android", other: "Altre versioni", ios: "Su iOS, presto." },
    importStep: "Porta il tuo storico",
    importQuestion: "Posso portare il mio storico da altre app?",
    freeQuestion: "È gratis?",
    freeAnswer: "Sì, e lo sarà sempre.",
    openSource: { title: "Open source", cta: "Vedi il codice su GitHub" },
    metaDescription: [/Gratis per sempre/, /open source/],
    banned: [/migliore amico/i, /\bgioc(o|hi)\b/i, /Inizia gratis/i],
    overclaims: [
      /non possa trapelare/i,
      /end-to-end|da un capo all'altro/i,
      /non possiamo vedere/i,
      /a riposo/i,
    ],
    privacyAnswer:
      "I tuoi dati viaggiano cifrati e non li vendiamo né li condividiamo mai con gli inserzionisti.",
    faq: "Domande frequenti",
    signIn: "Entra",
    toggleToDay: "Passa alla modalità giorno",
    toggleToNight: "Passa alla modalità notte",
    name: "Italiano",
    how: "Come funziona",
    questions: "Domande",
    other: { name: "Português", path: "/pt", lang: "pt" },
    titlePart: "I tuoi soldi, finalmente chiari",
  },
  {
    locale: "pt",
    path: "/pt",
    headline: "O teu dinheiro, finalmente claro.",
    highlight: "dinheiro",
    annotation: "Grátis, e vai ser sempre!",
    lead: "O Wambi faz-te companhia para que cuidar do teu dinheiro seja um prazer.",
    removedDescription: "Regista uma despesa em segundos e vê para onde vai cada cêntimo.",
    newTab: "(abre num novo separador)",
    perks: "Grátis para sempre · Código aberto · Sem palavras-passe",
    openSourcePerk: "Código aberto",
    removedQuestions: ["Para onde vai todo o meu dinheiro?", "Quanto me custa viver?"],
    cta: "Começa agora",
    demoCta: "Experimenta sem conta",
    webCta: "Começar",
    soon: "Em breve",
    ways: ["Na web", "App para Android e iOS", "Com a tua IA"],
    android: { cta: "Descarregar para Android", other: "Outras versões", ios: "No iOS, em breve." },
    importStep: "Traz o teu histórico",
    importQuestion: "Posso trazer o meu histórico de outras apps?",
    freeQuestion: "É grátis?",
    freeAnswer: "Sim, e vai ser sempre.",
    openSource: { title: "Código aberto", cta: "Ver o código no GitHub" },
    metaDescription: [/Grátis para sempre/, /código aberto/],
    banned: [/melhor amigo/i, /\bjogos?\b/i, /Começa grátis/i],
    overclaims: [/não possa vazar/i, /ponta a ponta/i, /não podemos ver/i, /em repouso/i],
    privacyAnswer:
      "Os teus dados viajam cifrados e nunca os vendemos nem os partilhamos com anunciantes.",
    faq: "Perguntas frequentes",
    signIn: "Entrar",
    toggleToDay: "Mudar para o modo dia",
    toggleToNight: "Mudar para o modo noite",
    name: "Português",
    how: "Como funciona",
    questions: "Perguntas",
    other: { name: "Italiano", path: "/it", lang: "it" },
    titlePart: "O teu dinheiro, finalmente claro",
  },
] as const;

/** The privacy policy and account deletion pages, per language: path, heading and footer link. */
const LEGAL = {
  es: {
    privacy: { path: "/privacy", title: "Política de privacidad", link: "Privacidad" },
    deleteAccount: { path: "/delete-account", title: "Borrar tu cuenta", link: "Borrar cuenta" },
    otherPrivacy: "/en/privacy",
    faqLink: "política de privacidad",
  },
  en: {
    privacy: { path: "/en/privacy", title: "Privacy policy", link: "Privacy" },
    deleteAccount: {
      path: "/en/delete-account",
      title: "Delete your account",
      link: "Delete account",
    },
    otherPrivacy: "/privacy",
    faqLink: "privacy policy",
  },
  it: {
    privacy: { path: "/it/privacy", title: "Informativa sulla privacy", link: "Privacy" },
    deleteAccount: {
      path: "/it/delete-account",
      title: "Elimina il tuo account",
      link: "Elimina account",
    },
    otherPrivacy: "/pt/privacy",
    faqLink: "informativa sulla privacy",
  },
  pt: {
    privacy: { path: "/pt/privacy", title: "Política de privacidade", link: "Privacidade" },
    deleteAccount: {
      path: "/pt/delete-account",
      title: "Apagar a tua conta",
      link: "Apagar conta",
    },
    otherPrivacy: "/it/privacy",
    faqLink: "política de privacidade",
  },
} as const;

/** The roadmap page and the landing's what's-next section, per language. */
const ROADMAP = {
  es: {
    path: "/roadmap",
    otherPath: "/en/roadmap",
    title: "Lo que viene",
    titlePart: "Lo que viene",
    intro: "Esto es lo que tenemos planeado. Puede cambiar con el tiempo.",
    columns: [
      {
        label: "En construcción",
        items: [
          "Captura automática de las notificaciones de tu banco",
          "En F-Droid y Google Play",
          "Importa desde Buddy y otras apps",
        ],
      },
      {
        label: "Próximo",
        items: [
          "App para iPhone",
          "Cifrado de punta a punta",
          "Conecta tu IA en un clic",
          "Apoya a Wambito",
        ],
      },
      {
        label: "Más adelante",
        items: [
          "Sin servidor central",
          "Anota por WhatsApp",
          "Tu resumen del mes con IA en tu teléfono",
        ],
      },
      {
        label: "Ya está",
        items: [
          "App web",
          "Pruébalo sin cuenta",
          "App para Android",
          "Android: widget con micrófono",
          "Importa tu historial de Budge",
          "Funciona sin conexión",
          "Sin contraseñas",
          "Pagos recurrentes con avisos",
          "En cuatro idiomas",
          "Instálalo en tu propio servidor",
          "Conecta tu IA",
        ],
      },
    ],
    navLink: "Lo que viene",
    description: /Lo que tenemos planeado para Wambito/,
    logo: "Wambito, inicio",
  },
  en: {
    path: "/en/roadmap",
    otherPath: "/roadmap",
    title: "What's next",
    titlePart: "What's next",
    intro: "This is what we have planned. It may change over time.",
    columns: [
      {
        label: "Being built",
        items: [
          "Automatic capture of your bank's notifications",
          "On F-Droid and Google Play",
          "Import from Buddy and other apps",
        ],
      },
      {
        label: "Next",
        items: [
          "iPhone app",
          "End-to-end encryption",
          "Connect your AI in one click",
          "Support Wambito",
        ],
      },
      {
        label: "Later",
        items: [
          "No central server",
          "Log it on WhatsApp",
          "Your monthly recap with AI on your phone",
        ],
      },
      {
        label: "Live",
        items: [
          "Web app",
          "Try it without an account",
          "Android app",
          "Android: widget with a microphone",
          "Import your history from Budge",
          "Works offline",
          "No passwords",
          "Recurring payments with reminders",
          "In four languages",
          "Run it on your own server",
          "Connect your AI",
        ],
      },
    ],
    navLink: "What's next",
    description: /What we have planned for Wambito/,
    logo: "Wambito, home",
  },
  it: {
    path: "/it/roadmap",
    otherPath: "/pt/roadmap",
    title: "In arrivo",
    titlePart: "In arrivo",
    intro: "Questo è quello che abbiamo in programma. Può cambiare nel tempo.",
    columns: [
      {
        label: "In costruzione",
        items: [
          "Cattura automatica delle notifiche della tua banca",
          "Su F-Droid e Google Play",
          "Importa da Buddy e da altre app",
        ],
      },
      {
        label: "Prossimo",
        items: [
          "App per iPhone",
          "Crittografia end-to-end",
          "Collega la tua IA in un clic",
          "Sostieni Wambito",
        ],
      },
      {
        label: "Più avanti",
        items: [
          "Senza server centrale",
          "Annota su WhatsApp",
          "Il riepilogo del mese con l'IA sul telefono",
        ],
      },
      {
        label: "Fatto",
        items: [
          "App web",
          "Provala senza account",
          "App per Android",
          "Android: widget con microfono",
          "Importa il tuo storico da Budge",
          "Funziona offline",
          "Senza password",
          "Pagamenti ricorrenti con avvisi",
          "In quattro lingue",
          "Installalo sul tuo server",
          "Collega la tua IA",
        ],
      },
    ],
    navLink: "In arrivo",
    description: /Cosa abbiamo in programma per Wambito/,
    logo: "Wambito, home",
  },
  pt: {
    path: "/pt/roadmap",
    otherPath: "/it/roadmap",
    title: "O que vem aí",
    titlePart: "O que vem aí",
    intro: "Isto é o que temos planeado. Pode mudar com o tempo.",
    columns: [
      {
        label: "Em construção",
        items: [
          "Captura automática das notificações do teu banco",
          "No F-Droid e no Google Play",
          "Importa do Buddy e de outras apps",
        ],
      },
      {
        label: "A seguir",
        items: [
          "App para iPhone",
          "Encriptação ponta a ponta",
          "Liga a tua IA num clique",
          "Apoia o Wambito",
        ],
      },
      {
        label: "Mais à frente",
        items: [
          "Sem servidor central",
          "Regista pelo WhatsApp",
          "O resumo do mês com IA no teu telemóvel",
        ],
      },
      {
        label: "Já está",
        items: [
          "App web",
          "Experimenta sem conta",
          "App para Android",
          "Android: widget com microfone",
          "Importa o teu histórico do Budge",
          "Funciona sem ligação",
          "Sem palavras-passe",
          "Pagamentos recorrentes com avisos",
          "Em quatro línguas",
          "Instala-o no teu próprio servidor",
          "Liga a tua IA",
        ],
      },
    ],
    navLink: "O que vem aí",
    description: /O que temos planeado para Wambito/,
    logo: "Wambito, início",
  },
} as const;

type Rgba = { rgb: [number, number, number]; alpha: number };

/** A computed color: `rgb(…)`, `rgba(…)` or `color(srgb r g b / a)` (what `color-mix` gives). */
function parseColor(color: string): Rgba {
  const numbers = (color.match(/[\d.]+/g) ?? []).map(Number);
  const srgb = color.startsWith("color(srgb");
  const [r = 0, g = 0, b = 0, alpha = 1] = numbers;
  const scale = srgb ? 255 : 1;
  return { rgb: [r * scale, g * scale, b * scale], alpha };
}

/** `top` painted over the opaque `bottom`. */
function over(top: Rgba, bottom: Rgba): Rgba {
  const rgb = top.rgb.map((c, i) => c * top.alpha + (bottom.rgb[i] ?? 0) * (1 - top.alpha));
  return { rgb: rgb as [number, number, number], alpha: 1 };
}

/** WCAG contrast ratio of two opaque colors. */
function contrast(a: Rgba, b: Rgba): number {
  const luminance = ({ rgb }: Rgba) => {
    const [r, g, b] = rgb.map((channel) => {
      const c = channel / 255;
      return c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4;
    }) as [number, number, number];
    return 0.2126 * r + 0.7152 * g + 0.0722 * b;
  };
  const [hi, lo] = [luminance(a), luminance(b)].sort((x, y) => y - x) as [number, number];
  return (hi + 0.05) / (lo + 0.05);
}

/**
 * Contrast in the hero, which axe can't measure there (the page background is a gradient, so it
 * reports the hero's text as "incomplete"): the highlighted word is dark ink on solid gold, AA
 * for normal text.
 */
async function expectHeroContrast(page: Page) {
  const colors = await page.locator("#hero").evaluate((hero) => {
    const read = (selector: string) => {
      const style = getComputedStyle(hero.querySelector(selector) as Element);
      return { color: style.color, background: style.backgroundColor };
    };
    const token = (name: string) => {
      const probe = document.createElement("span");
      probe.style.color = `var(${name})`;
      hero.append(probe);
      const value = getComputedStyle(probe).color;
      probe.remove();
      return value;
    };
    return {
      marker: read("h1 .lk-landing-marker"),
    };
  });
  const marker = parseColor(colors.marker.background);
  expect(marker.alpha).toBe(1);
  expect(contrast(parseColor(colors.marker.color), marker)).toBeGreaterThanOrEqual(4.5);
}

/** A text in the hero, as `expectHeroTextContrast` measures it. */
interface HeroText {
  text: string;
  color: string;
  /** Translucent backgrounds between the text and what is behind them, innermost first. */
  layers: string[];
  /** The first opaque background behind the text, or null when it sits on the page's gradient. */
  opaque: string | null;
  large: boolean;
}

/**
 * Every text in the hero, measured, since axe can't (it reports them "incomplete": the page's
 * background is a gradient). Each visible text's color is checked against what is behind it: an
 * opaque background where an element has one (a button), translucent ones composited over it, and
 * otherwise the gradient at both ends, `bg-glow` and `bg` (its lightest and darkest points). AA:
 * 4.5:1, or 3:1 for large text (24px, or 18.66px bold). A failure lists each text with its ratio.
 */
async function expectHeroTextContrast(page: Page) {
  const { texts, gradient } = await page.locator("#hero").evaluate((hero) => {
    const token = (name: string) => {
      const probe = document.createElement("span");
      probe.style.color = `var(${name})`;
      hero.append(probe);
      const value = getComputedStyle(probe).color;
      probe.remove();
      return value;
    };
    const alphaOf = (color: string) => {
      const match = /\/\s*([\d.]+)\)$|rgba\([^,]+,[^,]+,[^,]+,\s*([\d.]+)\)$/.exec(color);
      return match ? Number(match[1] ?? match[2]) : 1;
    };
    const texts: HeroText[] = [];
    for (const element of hero.querySelectorAll<HTMLElement>("*")) {
      const own = [...element.childNodes]
        .filter((node) => node.nodeType === Node.TEXT_NODE)
        .map((node) => node.textContent?.trim() ?? "")
        .join(" ")
        .trim();
      const box = element.getBoundingClientRect();
      // Visually hidden text (the new-tab hint for screen readers) is not on screen.
      if (!own || box.width <= 1 || box.height <= 1) continue;
      const style = getComputedStyle(element);
      if (style.visibility === "hidden" || Number(style.opacity) === 0) continue;
      const layers: string[] = [];
      let behind: string | null = null;
      for (let node: HTMLElement | null = element; node; node = node.parentElement) {
        if (node.classList.contains("lk-screen")) break;
        const background = getComputedStyle(node).backgroundColor;
        const alpha = alphaOf(background);
        if (alpha === 0) continue;
        if (alpha === 1) {
          behind = background;
          break;
        }
        layers.push(background);
      }
      const size = Number.parseFloat(style.fontSize);
      const bold = Number(style.fontWeight) >= 700;
      texts.push({
        text: own,
        color: style.color,
        layers,
        opaque: behind,
        large: size >= 24 || (bold && size >= 18.66),
      });
    }
    return { texts, gradient: [token("--bg-glow"), token("--bg")] };
  });
  expect(texts.length).toBeGreaterThan(5);
  const measured = texts.flatMap((t) =>
    (t.opaque ? [t.opaque] : gradient).map((behind) => {
      const background = t.layers.reduceRight(
        (under, layer) => over(parseColor(layer), under),
        parseColor(behind),
      );
      const ratio = contrast(over(parseColor(t.color), background), background);
      return { text: t.text, ratio: Math.round(ratio * 100) / 100, min: t.large ? 3 : 4.5 };
    }),
  );
  expect(measured.filter((m) => m.ratio < m.min)).toEqual([]);
}

/** Axe with the WCAG A/AA rule sets (2.0 to 2.2) plus best practices. */
async function expectNoA11yViolations(page: Page) {
  const results = await new AxeBuilder({ page })
    .withTags(["wcag2a", "wcag2aa", "wcag21a", "wcag21aa", "wcag22aa", "best-practice"])
    .analyze();
  expect(
    results.violations.map((v) => ({ id: v.id, nodes: v.nodes.map((n) => n.target.join(" ")) })),
  ).toEqual([]);
}

/**
 * Nothing sticks out of the viewport and every target is at least 44px. `.lk-landing` clips
 * horizontal overflow, so the document never scrolls sideways: check every rendered element
 * instead, so content that would be cut off fails here. Nothing on the page is meant to be
 * clipped (no exceptions).
 */
async function expectFitsTheViewport(page: Page) {
  const overflowing = await page.evaluate(() => {
    const width = document.documentElement.clientWidth;
    return [...document.querySelectorAll(".lk-landing *")]
      .filter((el) => {
        const box = el.getBoundingClientRect();
        if (box.width === 0 && box.height === 0) return false;
        return box.left < -0.5 || box.right > width + 0.5;
      })
      .map((el) => `${el.tagName.toLowerCase()}.${el.className} "${el.textContent?.slice(0, 30)}"`);
  });
  expect(overflowing).toEqual([]);
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth - document.documentElement.clientWidth,
    ),
  ).toBeLessThanOrEqual(0);
  for (const target of await page.locator("a:visible, button:visible, summary").all()) {
    const box = await target.boundingBox();
    expect(box?.height, await target.innerText()).toBeGreaterThanOrEqual(44);
    expect(box?.width, await target.innerText()).toBeGreaterThanOrEqual(44);
  }
}

/**
 * The header at one width and theme: the wordmark on one line, the CTA and the ☾ switch on the
 * same row, and nothing sticking out of the viewport.
 */
async function expectHeaderFits(
  page: Page,
  path: string,
  width: number,
  theme: "night" | "day",
  cta: string,
) {
  await page.setViewportSize({ width, height: 800 });
  await page.addInitScript((value) => localStorage.setItem("wambito.theme", value), theme);
  await page.goto(path);
  await expect(page.locator("html")).toHaveAttribute("data-theme", theme);
  const header = page.getByRole("banner");
  const logo = header.locator(".lk-logo");
  const nav = header.getByRole("navigation");
  const link = nav.getByRole("link", { name: cta });
  // The day/night switch, last in the row (after the language switch).
  const toggle = nav.getByRole("button").last();
  await expect(nav.getByRole("button", { name: /:/ })).toBeVisible();
  await expect(logo).toBeVisible();
  await expect(link).toBeVisible();
  await expect(toggle).toBeVisible();
  const [logoBox, linkBox, toggleBox] = [
    await logo.boundingBox(),
    await link.boundingBox(),
    await toggle.boundingBox(),
  ];
  // One line of the 28px wordmark, not two.
  expect(logoBox?.height).toBeLessThan(40);
  // One row: the three share a vertical band.
  const rowTop = Math.min(logoBox?.y ?? 0, linkBox?.y ?? 0, toggleBox?.y ?? 0);
  const rowBottom = Math.max(
    (logoBox?.y ?? 0) + (logoBox?.height ?? 0),
    (linkBox?.y ?? 0) + (linkBox?.height ?? 0),
    (toggleBox?.y ?? 0) + (toggleBox?.height ?? 0),
  );
  expect(rowBottom - rowTop).toBeLessThan(80);
  // The wordmark clears the CTA, and the switch ends inside the viewport.
  expect((logoBox?.x ?? 0) + (logoBox?.width ?? 0)).toBeLessThanOrEqual(linkBox?.x ?? 0);
  expect((toggleBox?.x ?? 0) + (toggleBox?.width ?? 0)).toBeLessThanOrEqual(width);
  expect(linkBox?.height).toBeGreaterThanOrEqual(44);
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth - document.documentElement.clientWidth,
    ),
  ).toBeLessThanOrEqual(0);
}

test("the tab and home-screen icons are the Wambito coin, none named after the mascot", async ({
  page,
  request,
}) => {
  await page.goto("/");
  const links = await page
    .locator("head link[rel='icon'], head link[rel='apple-touch-icon']")
    .evaluateAll((els) => els.map((el) => [el.getAttribute("rel"), el.getAttribute("href")]));
  expect(links).toEqual([
    ["icon", "/favicon.ico"],
    ["icon", "/favicon.svg"],
    ["apple-touch-icon", "/apple-touch-icon.png"],
  ]);
  const types = { ico: "image/", svg: "image/svg+xml", png: "image/png" } as const;
  for (const [, href] of links) {
    const response = await request.get(href ?? "");
    expect(response.status(), href ?? "").toBe(200);
    const ext = (href ?? "").split(".").pop() as keyof typeof types;
    expect(response.headers()["content-type"]).toContain(types[ext]);
  }
  // The landing never links a file named after the mascot module (see vite.config.ts).
  const hrefs = await page
    .locator("head link[href]")
    .evaluateAll((els) => els.map((el) => el.getAttribute("href") ?? ""));
  expect(hrefs.filter((href) => /wambi/i.test(href.split("/").pop() ?? ""))).toEqual([]);
});

for (const l of LOCALES) {
  test.describe(`landing (${l.locale})`, () => {
    test("the prerendered HTML carries the copy, without JavaScript", async ({ page, request }) => {
      // React escapes apostrophes in text ("you'll" → "you&#x27;ll").
      const html = (await (await request.get(l.path)).text()).replaceAll("&#x27;", "'");
      expect(html).toContain(l.lead);
      expect(html).toContain(`<html lang="${l.locale}"`);

      await page.goto(l.path);
      // The words on show take turns; the message itself is the screen-reader text.
      const headline = page.getByRole("heading", { level: 1 });
      await expect(headline.locator(".sr-only")).toHaveText(l.headline);
      await expect(headline).toHaveAccessibleName(l.headline);
      await expect(page).toHaveTitle(new RegExp(l.titlePart));
    });

    test("the hero is simple: no crossed-out questions, the headline comes first", async ({
      page,
      request,
    }) => {
      // The old crossed-out questions are gone, from the copy and from the markup.
      const html = (await (await request.get(l.path)).text()).replaceAll("&#x27;", "'");
      for (const question of l.removedQuestions) expect(html).not.toContain(question);
      await page.goto(l.path);
      const hero = page.locator("#hero");
      await expect(hero.locator("s")).toHaveCount(0);
      // Nor is there a handwritten note above the headline any more.
      await expect(hero).not.toContainText(l.annotation);
      // Headline → description → actions.
      expect(
        await hero
          .locator(".lk-landing-hero-text > *")
          .evaluateAll((nodes) => nodes.map((node) => node.classList[0])),
      ).toEqual(["lk-landing-headline", "lk-landing-description", "lk-landing-cta"]);
    });

    test("the hero: the highlighted word, the lead and the perks", async ({ page }) => {
      await page.goto(l.path);
      const hero = page.locator("#hero");
      const headline = hero.getByRole("heading", { level: 1 });
      await expect(headline.locator("[aria-hidden='true'] .lk-landing-marker")).toHaveText(
        l.highlight,
      );

      const description = hero.locator(".lk-landing-description");
      // One sentence that introduces Wambi; the old second sentence is gone.
      await expect(description).toHaveText(l.lead);
      await expect(description.locator(".lk-landing-lead")).toHaveText(l.lead);
      await expect(hero).not.toContainText(l.removedDescription);

      // The visible text is the perks; the link to GitHub adds a hidden "opens in a new tab".
      await expect(hero.locator(".lk-landing-perks")).toHaveText(
        l.perks.replace(l.openSourcePerk, `${l.openSourcePerk} ${l.newTab}`),
      );
      const github = hero.getByRole("link", { name: l.openSourcePerk });
      await expect(github.locator(".sr-only")).toHaveText(l.newTab);
      await expect(github).toHaveAttribute("href", GITHUB);
      await expect(github).toHaveAttribute("target", "_blank");
      await expect(github).toHaveAttribute("rel", "noopener");

      // Beside it, the demo without an account, in this language, as the secondary action.
      const demo = hero.getByRole("link", { name: l.demoCta });
      await expect(demo).toHaveAttribute("href", `/demo?lang=${l.locale}`);
      await expect(demo).toHaveClass(/lk-btn-secondary/);
      expect((await demo.boundingBox())?.height).toBeGreaterThanOrEqual(44);
    });

    test("says nothing about games, best friends or paying later", async ({ page, request }) => {
      const html = await (await request.get(l.path)).text();
      const withoutScripts = html.replace(/<script[\s\S]*?<\/script>/g, "");
      await page.goto(l.path);
      const text = (await page.locator("body").textContent()) ?? "";
      for (const pattern of l.banned) {
        expect(withoutScripts).not.toMatch(pattern);
        expect(text).not.toMatch(pattern);
      }
    });

    test("names the product Wambito everywhere a person or a crawler reads it", async ({
      page,
      request,
    }) => {
      // The product is Wambito, the mascot Wambi; the old names are gone. The
      // slang word "lukas" (money, in lowercase) stays in the Spanish copy, so only the
      // capitalized old names are banned.
      await page.goto(l.path);
      const seen = await page.evaluate(() => {
        const attributes = [...document.querySelectorAll("[aria-label], [alt], [title]")].flatMap(
          (element) =>
            ["aria-label", "alt", "title"].map((name) => element.getAttribute(name) ?? ""),
        );
        const meta = [...document.querySelectorAll("head meta[content]")].map(
          (element) => element.getAttribute("content") ?? "",
        );
        const body = document.body.cloneNode(true) as HTMLElement;
        for (const script of body.querySelectorAll("script, style")) script.remove();
        return {
          body: body.textContent ?? "",
          title: document.title,
          attributes,
          meta,
        };
      });
      expect(seen.body).toContain("Wambito");
      expect(seen.title).toContain("Wambito");
      const everything = [seen.body, seen.title, ...seen.attributes, ...seen.meta].join("\n");
      expect(everything).not.toMatch(/Luk(?:itas)|\bLuk(?:as)\b/);
      const html = await (await request.get(l.path)).text();
      expect(html.replace(/<script[\s\S]*?<\/script>/g, "")).not.toMatch(
        /Luk(?:itas)|\bLuk(?:as)\b/,
      );
      await expect(page.locator('meta[property="og:site_name"]')).toHaveAttribute(
        "content",
        "Wambito",
      );
    });

    test("privacy copy promises only what Wambito does today", async ({ page, request }) => {
      // React escapes apostrophes in text ("can't" → "can&#x27;t"): decode before matching.
      const html = (await (await request.get(l.path)).text()).replaceAll("&#x27;", "'");
      const withoutScripts = html.replace(/<script[\s\S]*?<\/script>/g, "");
      await page.goto(l.path);
      const text = (await page.locator("body").textContent()) ?? "";
      for (const pattern of l.overclaims) {
        expect(withoutScripts).not.toMatch(pattern);
        expect(text).not.toMatch(pattern);
      }
      const privacyAnswer = page.locator("#faq details").filter({ hasText: l.privacyAnswer });
      await expect(privacyAnswer).toHaveCount(1);
      // The answer links to the policy page.
      // (Closed `<details>` content is out of the accessibility tree, so find it by text.)
      await expect(
        privacyAnswer.locator("a", { hasText: LEGAL[l.locale].faqLink }),
      ).toHaveAttribute("href", LEGAL[l.locale].privacy.path);
    });

    test("has its SEO tags: description, Open Graph, canonical and hreflang", async ({ page }) => {
      await page.goto(l.path);
      const head = page.locator("head");
      const self = `${ORIGIN}${l.path === "/" ? "/" : l.path}`;
      const description = head.locator('meta[name="description"]');
      await expect(description).toHaveAttribute("content", /.{60,}/);
      for (const pattern of l.metaDescription) {
        await expect(description).toHaveAttribute("content", pattern);
      }
      await expect(head.locator('link[rel="canonical"]')).toHaveAttribute("href", self);
      await expect(head.locator('link[rel="alternate"][hreflang="es"]')).toHaveAttribute(
        "href",
        `${ORIGIN}/`,
      );
      await expect(head.locator('link[rel="alternate"][hreflang="en"]')).toHaveAttribute(
        "href",
        `${ORIGIN}/en`,
      );
      await expect(head.locator('link[rel="alternate"][hreflang="it"]')).toHaveAttribute(
        "href",
        `${ORIGIN}/it`,
      );
      await expect(head.locator('link[rel="alternate"][hreflang="pt"]')).toHaveAttribute(
        "href",
        `${ORIGIN}/pt`,
      );
      await expect(head.locator('link[rel="alternate"][hreflang="x-default"]')).toHaveAttribute(
        "href",
        `${ORIGIN}/`,
      );
      await expect(head.locator('meta[property="og:title"]')).toHaveAttribute(
        "content",
        new RegExp(l.titlePart),
      );
      await expect(head.locator('meta[property="og:description"]')).toHaveAttribute(
        "content",
        /.{60,}/,
      );
      await expect(head.locator('meta[property="og:url"]')).toHaveAttribute("content", self);
      await expect(head.locator('meta[property="og:type"]')).toHaveAttribute("content", "website");
      await expect(head.locator('meta[property="og:image"]')).toHaveAttribute(
        "content",
        `${ORIGIN}/og-${l.locale}.png`,
      );
      await expect(head.locator('meta[name="twitter:card"]')).toHaveAttribute(
        "content",
        "summary_large_image",
      );
    });

    test("one primary action: get started → sign-in in this language", async ({ page }) => {
      await page.goto(l.path);
      const hero = page.locator("#hero");
      const cta = hero.getByRole("link", { name: l.cta });
      await expect(cta).toHaveAttribute("href", `/sign-in?lang=${l.locale}`);
      await expect(cta).toHaveClass(/lk-btn-primary/);
      const box = await cta.boundingBox();
      expect(box?.height).toBeGreaterThanOrEqual(44);
    });

    test("use it your way: web is live, Android downloads the APK, AI is coming soon", async ({
      page,
    }) => {
      await page.goto(l.path);
      const [web, mobile, ai] = l.ways.map((name) =>
        page.getByRole("listitem").filter({ has: page.getByRole("heading", { name }) }),
      ) as [ReturnType<Page["locator"]>, ReturnType<Page["locator"]>, ReturnType<Page["locator"]>];
      await expect(web.getByRole("link", { name: l.webCta, exact: true })).toHaveAttribute(
        "href",
        `/sign-in?lang=${l.locale}`,
      );
      await expect(web.getByText(l.soon, { exact: true })).toHaveCount(0);
      await expect(mobile.getByRole("link", { name: l.android.cta, exact: true })).toHaveAttribute(
        "href",
        ANDROID_APK_HREF,
      );
      const other = mobile.getByRole("link", { name: new RegExp(`^${l.android.other}`) });
      await expect(other).toHaveAttribute("href", ANDROID_RELEASE_HREF);
      await expect(other).toHaveAttribute("target", "_blank");
      await expect(mobile.getByText(l.android.ios, { exact: true })).toBeVisible();
      await expect(mobile.getByText(l.soon, { exact: true })).toHaveCount(0);
      await expect(ai.getByText(l.soon, { exact: true })).toBeVisible();
      await expect(ai.getByRole("link")).toHaveCount(0);
      await expect(ai).toContainText("Claude");
      await expect(ai).toContainText("ChatGPT");
    });

    test("imports come from other apps: Budge today, Buddy soon", async ({ page }) => {
      await page.goto(l.path);
      const step = page
        .locator("#how")
        .getByRole("listitem")
        .filter({ has: page.getByRole("heading", { name: l.importStep }) });
      await expect(step).toContainText("Budge");
      await expect(step).toContainText("Buddy");
      const answer = page
        .locator("#faq details")
        .filter({ has: page.getByText(l.importQuestion, { exact: true }) });
      await expect(answer).toContainText("Budge");
      await expect(answer).toContainText("Buddy");
    });

    test("free forever and open source: the FAQ and the section link to the code", async ({
      page,
    }) => {
      await page.goto(l.path);
      const free = page
        .locator("#faq details")
        .filter({ has: page.getByText(l.freeQuestion, { exact: true }) });
      await free.locator("summary").click();
      await expect(free).toContainText(l.freeAnswer);
      await expect(free.getByRole("link", { name: "GitHub" })).toHaveAttribute("href", GITHUB);

      const section = page.locator("#open-source");
      await expect(section.getByRole("heading", { level: 2 })).toHaveText(l.openSource.title);
      await expect(section).toContainText("AGPL-3.0");
      const code = section.getByRole("link", { name: l.openSource.cta });
      await expect(code).toHaveAttribute("href", GITHUB);
      await expect(code).toHaveAttribute("target", "_blank");
      await expect(code).toHaveAttribute("rel", "noopener");
      await expect(code.locator(".sr-only")).toHaveText(l.newTab);
      // Then the FAQ: no "what's next" section between them.
      expect(await section.evaluate((el) => el.nextElementSibling?.id)).toBe("faq");
    });

    test("no what's next section: the header and the footer lead to the roadmap", async ({
      page,
    }) => {
      await page.goto(l.path);
      await expect(page.locator("#whats-next")).toHaveCount(0);
      await expect(page.locator("main")).not.toContainText(ROADMAP[l.locale].intro);
    });

    test("the footer links to the roadmap, and the header does on a wide screen", async ({
      page,
    }) => {
      const r = ROADMAP[l.locale];
      await page.goto(l.path);
      const footerLink = page.getByRole("contentinfo").getByRole("link", { name: r.navLink });
      await expect(footerLink).toHaveAttribute("href", r.path);
      await expect(footerLink).not.toHaveAttribute("aria-current", /.+/);
      // The active language is marked the same way on the landing.
      await expect(
        page.getByRole("contentinfo").getByRole("link", { name: l.name }),
      ).toHaveAttribute("aria-current", "true");
      const headerLink = page.getByRole("banner").getByRole("link", { name: r.navLink });
      // The phone header has no room for it (hidden, so not in the accessibility tree); from
      // 900px it sits among the section links.
      if ((page.viewportSize()?.width ?? 0) >= 900) {
        await expect(headerLink).toHaveAttribute("href", r.path);
        await expect(headerLink).toBeVisible();
        const names = await page
          .getByRole("banner")
          .getByRole("navigation")
          .getByRole("link")
          .allInnerTexts();
        expect(names.slice(0, 3)).toEqual([l.how, r.navLink, l.questions]);
      } else {
        await expect(headerLink).toHaveCount(0);
        await expect(page.locator("header a[href='" + r.path + "']")).toBeHidden();
      }
    });

    test("the FAQ opens without JavaScript", async ({ page }) => {
      await page.goto(l.path);
      const faq = page.locator("#faq");
      await expect(faq.getByRole("heading", { level: 2 })).toHaveText(l.faq);
      const questions = faq.locator("details");
      expect(await questions.count()).toBeGreaterThanOrEqual(6);
      const first = questions.first();
      await expect(first).not.toHaveAttribute("open");
      await first.locator("summary").click();
      await expect(first).toHaveAttribute("open");
      await expect(first.locator("summary + *")).toBeVisible();
    });

    test("the footer switches language on the same page and links to the legal pages", async ({
      page,
    }) => {
      await page.goto(l.path);
      const footer = page.getByRole("contentinfo");
      const switchLink = footer.getByRole("link", { name: l.other.name });
      await expect(switchLink).toHaveAttribute("href", l.other.path);
      await expect(switchLink).toHaveAttribute("hreflang", l.other.lang);
      await expect(
        footer.getByRole("link", { name: LEGAL[l.locale].privacy.link }),
      ).toHaveAttribute("href", LEGAL[l.locale].privacy.path);
      await expect(
        footer.getByRole("link", { name: LEGAL[l.locale].deleteAccount.link }),
      ).toHaveAttribute("href", LEGAL[l.locale].deleteAccount.path);
      await expect(footer).toContainText("© 2026 Wambito");

      await switchLink.click();
      await expect(page).toHaveURL(new RegExp(`${l.other.path}$`));
      await expect(page.locator("html")).toHaveAttribute("lang", l.other.lang);
    });

    test.describe(() => {
      // Axe runs asynchronously, so it needs JavaScript: keep it on but block the app's own
      // scripts, which leaves exactly the prerendered page (the inline theme script still picks
      // night from the dark color scheme).
      test.use({ javaScriptEnabled: true, colorScheme: "dark" });

      test("the prerendered page is accessible (axe, night theme)", async ({ page }) => {
        await page.route("**/assets/*.js", (route) => route.abort());
        await page.goto(l.path);
        await expect(page.locator("html")).toHaveAttribute("data-theme", "night");
        await expectNoA11yViolations(page);
        await expectHeroContrast(page);
        await expectHeroTextContrast(page);
      });
    });

    test.describe(() => {
      // The inline theme script alone (the app's scripts are blocked): with nothing stored the page
      // is night even when the OS prefers light; only a stored "auto" follows the OS.
      test.use({ javaScriptEnabled: true, colorScheme: "light" });

      test("is night by default, even on a light OS", async ({ page }) => {
        await page.route("**/assets/*.js", (route) => route.abort());
        await page.goto(l.path);
        await expect(page.locator("html")).toHaveAttribute("data-theme", "night");
      });

      test("follows the OS when the stored preference is auto", async ({ page }) => {
        await page.route("**/assets/*.js", (route) => route.abort());
        await page.addInitScript(() => localStorage.setItem("wambito.theme", "auto"));
        await page.goto(l.path);
        await expect(page.locator("html")).toHaveAttribute("data-theme", "day");
      });
    });

    test("the header has the day/night switch next to sign-in", async ({ page }) => {
      await page.goto(l.path);
      const nav = page.getByRole("banner").getByRole("navigation");
      const toggle = nav.getByRole("button", { name: l.toggleToDay });
      await expect(toggle).toBeVisible();
      await expect(toggle).not.toHaveAttribute("aria-pressed");
      const signIn = nav.getByRole("link", { name: l.signIn });
      const [toggleBox, signInBox] = [await toggle.boundingBox(), await signIn.boundingBox()];
      expect(toggleBox?.width).toBeGreaterThanOrEqual(44);
      expect(toggleBox?.height).toBeGreaterThanOrEqual(44);
      // Same row, to the right of "Sign in".
      expect(Math.abs((toggleBox?.y ?? 0) - (signInBox?.y ?? 0))).toBeLessThan(24);
      expect(toggleBox?.x).toBeGreaterThan((signInBox?.x ?? 0) + (signInBox?.width ?? 0));
    });

    test.describe(() => {
      test.use({ javaScriptEnabled: true });

      for (const width of [320, 390, 1280]) {
        for (const theme of ["night", "day"] as const) {
          test(`the header fits at ${width}px, ${theme} theme`, async ({ page }) => {
            await expectHeaderFits(page, l.path, width, theme, l.signIn);
          });
        }
      }
    });

    test("fits the viewport and keeps every target at 44px", async ({ page }) => {
      await page.goto(l.path);
      await expectFitsTheViewport(page);
    });

    test("shows Wambi waving, and still under reduced motion", async ({ page }) => {
      await page.goto(l.path);
      const mascot = page.locator("#hero [data-slot='hero-mascot']");
      await expect(mascot).toHaveAttribute("role", "img");
      await expect(mascot).toHaveAttribute("aria-label", /Wambi/);
      const sprite = mascot.locator(".lk-wambi-sprite");
      await expect(sprite).toHaveCSS("background-image", /\/wambi\/wave\.webp/);
      expect(await sprite.evaluate((el) => el.getAnimations().length)).toBeGreaterThan(0);
      // He waves once, then rests on his first frame: one pass of the sheet, not a loop.
      await expect(sprite).toHaveClass(/is-once/);
      expect(await sprite.evaluate((el) => getComputedStyle(el).animationIterationCount)).toBe(
        "2, 1",
      );
      await expect
        .poll(() => sprite.evaluate((el) => el.getAnimations().length), { timeout: 5000 })
        .toBe(0);
      await expect(sprite).toHaveCSS("background-position", "0% 0%");

      await page.emulateMedia({ reducedMotion: "reduce" });
      expect(await sprite.evaluate((el) => el.getAnimations().length)).toBe(0);
    });

    test("keeps Wambi only in the hero and the closing, where he celebrates once", async ({
      page,
    }) => {
      await page.goto(l.path);
      // Two spots, and no other Wambi anywhere in the page (not even in the demo chips).
      expect(
        await page
          .locator("[data-wambi-spot]")
          .evaluateAll((spots) => spots.map((spot) => (spot as HTMLElement).dataset.wambiSpot)),
      ).toEqual(["hero", "closing"]);
      await expect(page.locator("main .lk-wambi")).toHaveCount(2);
      await expect(page.locator("#how .lk-landing-saved")).toBeVisible();
      // The closing celebrates in one pass, then rests on frame 4 (fists up): nothing loops.
      const closing = page.locator("[data-wambi-spot='closing'] .lk-wambi-sprite");
      await expect(closing).toHaveClass(/is-once/);
      await expect
        .poll(() => closing.evaluate((el) => el.getAnimations().length), { timeout: 5000 })
        .toBe(0);
      await expect(closing).toHaveCSS("background-position", "0% 100%");
    });
  });
}

test.describe("landing with JavaScript", () => {
  test.use({ javaScriptEnabled: true });

  test("the header's language switch opens the same page in another language", async ({ page }) => {
    await page.goto("/");
    const header = page.getByRole("banner");
    const button = header.getByRole("button", { name: "ES, Idioma: Español", exact: true });
    await expect(button).toHaveText("ES");
    await expect(button).toHaveAttribute("aria-expanded", "false");

    // Escape closes it and gives focus back to the button.
    await button.click();
    await expect(button).toHaveAttribute("aria-expanded", "true");
    const options = header.getByRole("link", { name: /^(Español|English|Italiano|Português)$/ });
    await expect(options).toHaveCount(4);
    await expect(header.getByRole("link", { name: "Español" })).toHaveAttribute(
      "aria-current",
      "true",
    );
    await page.keyboard.press("Escape");
    await expect(button).toHaveAttribute("aria-expanded", "false");
    await expect(button).toBeFocused();
    await expect(options).toHaveCount(0);

    await button.click();
    await header.getByRole("link", { name: "English" }).click();
    await expect(page).toHaveURL(/\/en$/);
    await expect(page.locator("html")).toHaveAttribute("lang", "en");
    const english = header.getByRole("button", { name: "EN, Language: English", exact: true });
    await expect(english).toHaveText("EN");
    await expect(english).toHaveAttribute("aria-expanded", "false");
  });

  for (const turn of [
    {
      path: "/",
      first: "lukas🇨🇴",
      next: "lana🇲🇽",
      flag: "🇲🇽",
      shown: "Tu lana🇲🇽, por fin clara.",
      message: "Tus lukas, por fin claras.",
    },
    {
      path: "/en",
      first: "money",
      next: "bucks🇺🇸",
      flag: "🇺🇸",
      shown: "Your bucks🇺🇸, finally clear.",
      message: "Your money, finally clear.",
    },
    {
      path: "/pt",
      first: "dinheiro",
      next: "grana🇧🇷",
      flag: "🇧🇷",
      shown: "A tua grana🇧🇷, finalmente clara.",
      message: "O teu dinheiro, finalmente claro.",
    },
    {
      path: "/it",
      first: "soldi",
      next: "grana🇮🇹",
      flag: "🇮🇹",
      shown: "La tua grana🇮🇹, finalmente chiara.",
      message: "I tuoi soldi, finalmente chiari.",
    },
  ]) {
    test(`the marker takes turns with what money is called elsewhere (${turn.path})`, async ({
      page,
    }) => {
      await page.goto(turn.path);
      const headline = page.getByRole("heading", { level: 1 });
      const shown = headline.locator("[aria-hidden='true']");
      const marker = shown.locator(".lk-landing-marker");
      await expect(marker).toHaveText(turn.first);

      await expect(marker).toHaveText(turn.next, { timeout: 5000 });
      await expect(shown.locator(".lk-landing-flag")).toHaveText(turn.flag);
      await expect(shown).toHaveText(turn.shown);
      // Assistive technology and search engines keep the message as it is.
      await expect(headline).toHaveAccessibleName(turn.message);
    });

    test(`the marker holds still under reduced motion (${turn.path})`, async ({ page }) => {
      await page.emulateMedia({ reducedMotion: "reduce" });
      await page.goto(turn.path);
      await page.waitForTimeout(3500);
      await expect(page.locator("h1 [aria-hidden='true'] .lk-landing-marker")).toHaveText(
        turn.first,
      );
    });
  }

  test.describe("at 320px", () => {
    test.use({ viewport: { width: 320, height: 700 } });

    test("a longer word never moves the page: the headline keeps its height", async ({ page }) => {
      // "Le tue palanche🇮🇹, finalmente chiare." takes two lines more than the soldi one here.
      await page.goto("/it");
      const headline = page.getByRole("heading", { level: 1 });
      const height = async () => (await headline.boundingBox())?.height;
      const first = await height();
      await expect(headline.locator("[aria-hidden='true'] .lk-landing-marker")).toHaveText(
        "palanche🇮🇹",
        { timeout: 12_000 },
      );
      expect(await height()).toBe(first);
    });
  });

  test("hydrates cleanly and keeps the page when switching language", async ({ page }) => {
    const errors: string[] = [];
    page.on("console", (message) => {
      if (message.type() === "error") errors.push(message.text());
    });
    page.on("pageerror", (error) => errors.push(error.message));

    await page.goto("/");
    await page.waitForLoadState("networkidle");
    await expect(page.getByRole("heading", { level: 1 })).toHaveAccessibleName(
      "Tus lukas, por fin claras.",
    );

    await page.getByRole("contentinfo").getByRole("link", { name: "English" }).click();
    await expect(page).toHaveURL(/\/en$/);
    await expect(page.getByRole("heading", { level: 1 })).toHaveAccessibleName(
      "Your money, finally clear.",
    );
    await expect(page).toHaveTitle(/Your money, finally clear/);
    await expect(page.locator("html")).toHaveAttribute("lang", "en");
    await expect(page.locator('link[rel="canonical"]')).toHaveAttribute("href", `${ORIGIN}/en`);
    expect(errors).toEqual([]);
  });

  test("lists the four languages, each in its own name, and switches between them", async ({
    page,
  }) => {
    const errors: string[] = [];
    page.on("console", (message) => {
      if (message.type() === "error") errors.push(message.text());
    });
    page.on("pageerror", (error) => errors.push(error.message));

    await page.goto("/it");
    await page.waitForLoadState("networkidle");
    const footer = page.getByRole("contentinfo");
    await expect(footer.locator(".lk-landing-langs a")).toHaveText([
      "Español",
      "English",
      "Italiano",
      "Português",
    ]);
    for (const [name, code] of [
      ["Español", "es"],
      ["English", "en"],
      ["Italiano", "it"],
      ["Português", "pt"],
    ] as const) {
      await expect(footer.getByRole("link", { name })).toHaveAttribute("hreflang", code);
    }
    await expect(page.getByRole("heading", { level: 1 })).toHaveAccessibleName(
      "I tuoi soldi, finalmente chiari.",
    );

    await footer.getByRole("link", { name: "Português" }).click();
    await expect(page).toHaveURL(/\/pt$/);
    await expect(page.getByRole("heading", { level: 1 })).toHaveAccessibleName(
      "O teu dinheiro, finalmente claro.",
    );
    await expect(page.locator("html")).toHaveAttribute("lang", "pt");

    await footer.getByRole("link", { name: "Español" }).click();
    await expect(page).toHaveURL(/\/$/);
    await expect(page.getByRole("heading", { level: 1 })).toHaveAccessibleName(
      "Tus lukas, por fin claras.",
    );
    expect(errors).toEqual([]);
  });

  for (const l of LOCALES) {
    test(`is accessible in the day theme (${l.locale})`, async ({ page }) => {
      // Night is the default: day comes from the stored choice (what the switch saves).
      await page.addInitScript(() => localStorage.setItem("wambito.theme", "day"));
      await page.goto(l.path);
      await expect(page.locator("html")).toHaveAttribute("data-theme", "day");
      await expect(
        page.getByRole("banner").getByRole("button", { name: l.toggleToNight }),
      ).toBeVisible();
      await expectNoA11yViolations(page);
      await expectHeroContrast(page);
      await expectHeroTextContrast(page);
    });

    test(`the switch changes the theme and it persists after a reload (${l.locale})`, async ({
      page,
    }) => {
      await page.goto(l.path);
      await page.waitForLoadState("networkidle");
      const html = page.locator("html");
      await expect(html).toHaveAttribute("data-theme", "night");

      const header = page.getByRole("banner");
      await header.getByRole("button", { name: l.toggleToDay }).click();
      await expect(html).toHaveAttribute("data-theme", "day");
      expect(await page.evaluate(() => localStorage.getItem("wambito.theme"))).toBe("day");

      // The bootstrap script applies it before paint; the switch then offers the way back.
      await page.reload();
      await expect(html).toHaveAttribute("data-theme", "day");
      await page.waitForLoadState("networkidle");
      await header.getByRole("button", { name: l.toggleToNight }).click();
      await expect(html).toHaveAttribute("data-theme", "night");
      expect(await page.evaluate(() => localStorage.getItem("wambito.theme"))).toBe("night");
    });
  }
});

for (const l of LOCALES) {
  const r = ROADMAP[l.locale];
  const self = `${ORIGIN}${r.path}`;

  test.describe(`roadmap (${l.locale})`, () => {
    test("the prerendered HTML carries the plan, without JavaScript", async ({ page, request }) => {
      const html = (await (await request.get(r.path)).text()).replaceAll("&#x27;", "'");
      expect(html).toContain(`<html lang="${l.locale}"`);
      expect(html).toContain(r.intro);
      for (const column of r.columns) {
        expect(html).toContain(column.label);
        for (const item of column.items) expect(html).toContain(item);
      }

      await page.goto(r.path);
      await expect(page.getByRole("heading", { level: 1 })).toHaveText(r.title);
      await expect(page.getByRole("main")).toContainText(r.intro);
      await expect(page).toHaveTitle(new RegExp(r.titlePart));
    });

    test("shows a column per status that has items, with its items", async ({ page }) => {
      await page.goto(r.path);
      const main = page.getByRole("main");
      // Only the columns with items render (every status has some since the demo went live).
      await expect(main.getByRole("heading", { level: 2 })).toHaveText(
        r.columns.map((column) => column.label),
      );
      for (const column of r.columns) {
        const section = main.getByRole("region", { name: column.label });
        await expect(section.getByRole("heading", { level: 3 })).toHaveText(column.items);
        await expect(section.getByRole("listitem")).toHaveCount(column.items.length);
        // Each item: a glyph, its title and one line.
        for (const card of await section.getByRole("listitem").all()) {
          expect(await card.locator("p").count()).toBe(1);
          expect(((await card.locator("p").innerText()) ?? "").trim().length).toBeGreaterThan(8);
          await expect(card.locator(".lk-landing-icon")).toHaveAttribute("aria-hidden", "true");
          expect(
            (await card.locator(".lk-landing-icon").innerText()).trim().length,
          ).toBeGreaterThan(0);
        }
      }
    });

    test("is one column on a phone and side by side on a desktop", async ({ page }) => {
      await page.goto(r.path);
      const sections = page.getByRole("main").getByRole("region");
      await expect(sections).toHaveCount(r.columns.length);
      const boxes = await sections.evaluateAll((nodes) =>
        nodes.map((node) => {
          const box = node.getBoundingClientRect();
          return { left: box.left, top: box.top };
        }),
      );
      const wide = (page.viewportSize()?.width ?? 0) >= 900;
      const tops = new Set(boxes.map((box) => Math.round(box.top)));
      const lefts = new Set(boxes.map((box) => Math.round(box.left)));
      if (wide) {
        expect(tops.size).toBe(1);
        expect(lefts.size).toBe(boxes.length);
      } else {
        expect(tops.size).toBe(boxes.length);
        expect(lefts.size).toBe(1);
      }
    });

    test("promises no dates, asks for no proposals or votes and is not a game", async ({
      page,
      request,
    }) => {
      const html = (await (await request.get(r.path)).text()).replaceAll("&#x27;", "'");
      // The page's words as a crawler reads them: no scripts, no tags (asset names have hashes).
      const withoutScripts = html
        .replace(/<script[\s\S]*?<\/script>/g, "")
        .replace(/<[^>]+>/g, " ")
        // The copyright year is the one year on the page.
        .replace(/©\s*\d{4}/, "©");
      await page.goto(r.path);
      const text = await page.getByRole("main").evaluate((main) => main.textContent ?? "");
      const forbidden = [
        ...l.banned,
        /\b(20\d\d|Q[1-4])\b/,
        /discussions/i,
        /\bvot(a|o|e|ar|ing|es)\b/i,
        /\bpropon(e|er|ga)\b|\bpropose\b/i,
      ];
      for (const pattern of forbidden) {
        expect(text).not.toMatch(pattern);
        expect(withoutScripts).not.toMatch(pattern);
      }
      // The only links in the content are the header's and the footer's: none leads out.
      await expect(page.getByRole("main").getByRole("link")).toHaveCount(0);
      expect(
        await page
          .locator("a[href]")
          .evaluateAll((nodes) =>
            nodes
              .map((node) => node.getAttribute("href") ?? "")
              .filter((href) => /github/i.test(href)),
          ),
      ).toEqual([]);
    });

    test("names the product Wambito in the text, the title and the share tags", async ({
      page,
      request,
    }) => {
      await page.goto(r.path);
      const seen = await page.evaluate(() => {
        const attributes = [...document.querySelectorAll("[aria-label], [alt], [title]")].flatMap(
          (element) =>
            ["aria-label", "alt", "title"].map((name) => element.getAttribute(name) ?? ""),
        );
        const meta = [...document.querySelectorAll("head meta[content]")].map(
          (element) => element.getAttribute("content") ?? "",
        );
        const body = document.body.cloneNode(true) as HTMLElement;
        for (const script of body.querySelectorAll("script, style")) script.remove();
        return { body: body.textContent ?? "", title: document.title, attributes, meta };
      });
      expect(seen.body).toContain("Wambito");
      expect(seen.title).toContain("Wambito");
      const everything = [seen.body, seen.title, ...seen.attributes, ...seen.meta].join("\n");
      expect(everything).not.toMatch(/Luk(?:itas)|\bLuk(?:as)\b/);
      const html = await (await request.get(r.path)).text();
      expect(html.replace(/<script[\s\S]*?<\/script>/g, "")).not.toMatch(
        /Luk(?:itas)|\bLuk(?:as)\b/,
      );
      await expect(page.locator('meta[property="og:site_name"]')).toHaveAttribute(
        "content",
        "Wambito",
      );
    });

    test("has its own SEO tags: title, description, Open Graph, canonical and hreflang", async ({
      page,
    }) => {
      await page.goto(r.path);
      const head = page.locator("head");
      const description = head.locator('meta[name="description"]');
      await expect(description).toHaveAttribute("content", /.{60,}/);
      await expect(description).toHaveAttribute("content", r.description);
      await expect(head.locator('link[rel="canonical"]')).toHaveAttribute("href", self);
      await expect(head.locator('link[rel="alternate"][hreflang="es"]')).toHaveAttribute(
        "href",
        `${ORIGIN}/roadmap`,
      );
      await expect(head.locator('link[rel="alternate"][hreflang="en"]')).toHaveAttribute(
        "href",
        `${ORIGIN}/en/roadmap`,
      );
      await expect(head.locator('link[rel="alternate"][hreflang="it"]')).toHaveAttribute(
        "href",
        `${ORIGIN}/it/roadmap`,
      );
      await expect(head.locator('link[rel="alternate"][hreflang="pt"]')).toHaveAttribute(
        "href",
        `${ORIGIN}/pt/roadmap`,
      );
      await expect(head.locator('link[rel="alternate"][hreflang="x-default"]')).toHaveAttribute(
        "href",
        `${ORIGIN}/roadmap`,
      );
      await expect(head.locator('meta[property="og:title"]')).toHaveAttribute(
        "content",
        new RegExp(r.titlePart),
      );
      await expect(head.locator('meta[property="og:description"]')).toHaveAttribute(
        "content",
        r.description,
      );
      await expect(head.locator('meta[property="og:url"]')).toHaveAttribute("content", self);
      await expect(head.locator('meta[property="og:type"]')).toHaveAttribute("content", "website");
      await expect(head.locator('meta[property="og:image"]')).toHaveAttribute(
        "content",
        `${ORIGIN}/og-${l.locale}.png`,
      );
      await expect(head.locator('meta[name="twitter:card"]')).toHaveAttribute(
        "content",
        "summary_large_image",
      );
    });

    test("has the landing's header and footer: logo home, sign-in, theme switch, language", async ({
      page,
    }) => {
      await page.goto(r.path);
      const header = page.getByRole("banner");
      await expect(header.getByRole("link", { name: r.logo })).toHaveAttribute("href", l.path);
      await expect(header.getByRole("link", { name: l.signIn })).toHaveAttribute(
        "href",
        `/sign-in?lang=${l.locale}`,
      );
      await expect(header.getByRole("button", { name: l.toggleToDay })).toBeVisible();
      if ((page.viewportSize()?.width ?? 0) >= 900) {
        const link = header.getByRole("link", { name: r.navLink });
        await expect(link).toHaveAttribute("aria-current", "page");
        // The section links lead back to the landing's sections.
        await expect(header.getByRole("link", { name: l.how })).toHaveAttribute(
          "href",
          `${l.path}#how`,
        );
      }
      const footer = page.getByRole("contentinfo");
      await expect(footer.getByRole("link", { name: r.navLink })).toHaveAttribute(
        "aria-current",
        "page",
      );
      // Only the page link is "current": the active language is marked another way.
      await expect(footer.locator('a[aria-current="page"]')).toHaveCount(1);
      await expect(footer.getByRole("link", { name: l.name })).toHaveAttribute(
        "aria-current",
        "true",
      );
      await expect(
        footer.getByRole("link", { name: LEGAL[l.locale].privacy.link }),
      ).toHaveAttribute("href", LEGAL[l.locale].privacy.path);
      await expect(footer).toContainText("© 2026 Wambito");

      // The language switch keeps the page.
      const switchLink = footer.getByRole("link", { name: l.other.name });
      await expect(switchLink).toHaveAttribute("href", r.otherPath);
      await switchLink.click();
      await expect(page).toHaveURL(new RegExp(`${r.otherPath}$`));
      await expect(page.locator("html")).toHaveAttribute("lang", l.other.lang);
    });

    test("fits the viewport and keeps every target at 44px", async ({ page }) => {
      await page.goto(r.path);
      await expectFitsTheViewport(page);
    });

    test.describe("at 320px", () => {
      test.use({ viewport: { width: 320, height: 700 } });

      test("nothing overflows", async ({ page }) => {
        await page.goto(r.path);
        await expectFitsTheViewport(page);
      });

      test("the landing does not overflow either", async ({ page }) => {
        await page.goto(l.path);
        await expectFitsTheViewport(page);
      });
    });

    test.describe(() => {
      test.use({ javaScriptEnabled: true, colorScheme: "dark" });

      test("the prerendered page is accessible (axe, night theme)", async ({ page }) => {
        await page.route("**/assets/*.js", (route) => route.abort());
        await page.goto(r.path);
        await expect(page.locator("html")).toHaveAttribute("data-theme", "night");
        await expectNoA11yViolations(page);
      });
    });

    test.describe(() => {
      test.use({ javaScriptEnabled: true });

      test("is accessible in the day theme and hydrates cleanly", async ({ page }) => {
        const errors: string[] = [];
        page.on("console", (message) => {
          if (message.type() === "error") errors.push(message.text());
        });
        page.on("pageerror", (error) => errors.push(error.message));
        await page.addInitScript(() => localStorage.setItem("wambito.theme", "day"));
        await page.goto(r.path);
        await page.waitForLoadState("networkidle");
        await expect(page.locator("html")).toHaveAttribute("data-theme", "day");
        await expectNoA11yViolations(page);
        expect(errors).toEqual([]);
      });

      test("the landing's footer opens the roadmap and the logo comes back", async ({ page }) => {
        const errors: string[] = [];
        page.on("pageerror", (error) => errors.push(error.message));
        await page.goto(l.path);
        await page.waitForLoadState("networkidle");
        await page.getByRole("contentinfo").getByRole("link", { name: r.navLink }).click();
        await expect(page).toHaveURL(new RegExp(`${r.path}$`));
        await expect(page.getByRole("heading", { level: 1 })).toHaveText(r.title);
        await expect(page.locator("html")).toHaveAttribute("lang", l.locale);
        await page.getByRole("banner").getByRole("link", { name: r.logo }).click();
        await expect(page).toHaveURL(new RegExp(`${l.path === "/" ? "/" : l.path}$`));
        expect(errors).toEqual([]);
      });
    });
  });
}

for (const l of LOCALES) {
  const legal = LEGAL[l.locale];

  test.describe(`legal pages (${l.locale})`, () => {
    for (const key of ["privacy", "deleteAccount"] as const) {
      const page_ = legal[key];

      test(`${page_.path} is prerendered, 200, with its heading, and the footer leads to it`, async ({
        page,
        request,
      }) => {
        const response = await request.get(page_.path);
        expect(response.status()).toBe(200);
        expect(await response.text()).toContain(`<html lang="${l.locale}"`);

        await page.goto(l.path);
        await page
          .getByRole("contentinfo")
          .getByRole("link", { name: page_.link, exact: true })
          .click();
        await expect(page).toHaveURL(new RegExp(`${page_.path}$`));
        await expect(page.getByRole("heading", { level: 1 })).toHaveText(page_.title);
        // The page's own footer marks it as the current one.
        await expect(
          page.getByRole("contentinfo").getByRole("link", { name: page_.link, exact: true }),
        ).toHaveAttribute("aria-current", "page");
      });
    }
  });
}

/** Automatic capture: the landing's card and its "how it works" page, per language. */
const CAPTURE = {
  es: {
    path: "/automatic-capture",
    card: "¡Wambi anota los gastos por ti!",
    badge: "Pronto · Solo en Android",
    link: "¿Cómo funciona?",
    title: "¿Cómo funciona la captura automática?",
    soon: "Pronto en la app de Android.",
  },
  en: {
    path: "/en/automatic-capture",
    card: "Wambi logs your expenses for you!",
    badge: "Soon · Android only",
    link: "How does it work?",
    title: "How does automatic capture work?",
    soon: "Soon in the Android app.",
  },
  it: {
    path: "/it/automatic-capture",
    card: "Wambi annota le spese per te!",
    badge: "Presto · Solo su Android",
    link: "Come funziona?",
    title: "Come funziona la cattura automatica?",
    soon: "Presto nell’app Android.",
  },
  pt: {
    path: "/pt/automatic-capture",
    card: "O Wambi regista as despesas por ti!",
    badge: "Em breve · Só no Android",
    link: "Como funciona?",
    title: "Como funciona a captura automática?",
    soon: "Em breve na app Android.",
  },
} as const;

for (const l of LOCALES) {
  const c = CAPTURE[l.locale];

  test.describe(`automatic capture (${l.locale})`, () => {
    test("the landing's #how holds the card as its fifth item, with a real link to the page", async ({
      page,
    }) => {
      await page.goto(l.path);
      const items = page.locator("#how ul.is-how > li");
      await expect(items).toHaveCount(5);
      const card = items.nth(4);
      await expect(card.getByRole("heading", { name: c.card })).toBeVisible();
      await expect(card.getByText(c.badge, { exact: true })).toBeVisible();
      await expect(card.getByRole("link", { name: c.link })).toHaveAttribute("href", c.path);
    });

    test("the page works without JavaScript: five steps, five scenes, the soon line", async ({
      page,
      request,
    }) => {
      const response = await request.get(c.path);
      expect(response.status()).toBe(200);
      expect(await response.text()).toContain(`<html lang="${l.locale}"`);
      await page.goto(c.path);
      await expect(page.getByRole("heading", { level: 1 })).toHaveText(c.title);
      await expect(page.getByRole("heading", { level: 2 })).toHaveCount(5);
      await expect(page.locator("img.lk-capture-scene")).toHaveCount(5);
      await expect(page.getByText(c.soon, { exact: true })).toBeVisible();
      await expect(
        page.getByRole("contentinfo").getByRole("link", { name: l.other.name }),
      ).toHaveAttribute("href", CAPTURE[l.other.lang].path);
    });

    test.describe("at 320px", () => {
      test.use({ viewport: { width: 320, height: 700 } });

      test("nothing overflows on the page nor on #how", async ({ page }) => {
        await page.goto(c.path);
        await expectFitsTheViewport(page);
        await page.goto(l.path);
        await expectFitsTheViewport(page);
      });
    });
  });
}

test("the language switch on the privacy policy keeps the page", async ({ page }) => {
  await page.goto("/it/privacy");
  const pt = page.getByRole("contentinfo").getByRole("link", { name: "Português" });
  await expect(pt).toHaveAttribute("href", "/pt/privacy");
  await pt.click();
  await expect(page).toHaveURL(/\/pt\/privacy$/);
  await expect(page.getByRole("heading", { level: 1 })).toHaveText(LEGAL.pt.privacy.title);
});

test.describe("static files", () => {
  test("robots.txt, sitemap.xml and the Open Graph images are served", async ({ request }) => {
    const robots = await (await request.get("/robots.txt")).text();
    expect(robots).toContain("Sitemap: https://wambito.test/sitemap.xml");
    expect(robots).toContain("Disallow: /app");

    const sitemap = await (await request.get("/sitemap.xml")).text();
    expect(sitemap).toContain("<loc>https://wambito.test/</loc>");
    expect(sitemap).toContain("<loc>https://wambito.test/en</loc>");
    expect(sitemap).toContain('hreflang="x-default"');
    expect(sitemap).toContain("<loc>https://wambito.test/roadmap</loc>");
    expect(sitemap).toContain("<loc>https://wambito.test/en/roadmap</loc>");
    for (const path of ["/it", "/pt", "/it/roadmap", "/pt/roadmap"]) {
      expect(sitemap).toContain(`<loc>https://wambito.test${path}</loc>`);
    }
    for (const entry of Object.values(LEGAL)) {
      for (const key of ["privacy", "deleteAccount"] as const) {
        expect(sitemap).toContain(`<loc>https://wambito.test${entry[key].path}</loc>`);
      }
    }

    for (const locale of ["es", "en", "it", "pt"]) {
      const image = await request.get(`/og-${locale}.png`);
      expect(image.headers()["content-type"]).toBe("image/png");
      const bytes = await image.body();
      // PNG IHDR: width and height are big-endian at bytes 16 and 20.
      expect([bytes.readUInt32BE(16), bytes.readUInt32BE(20)]).toEqual([1200, 630]);
    }
  });
});
