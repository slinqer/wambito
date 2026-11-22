import type { BrandName } from "../../ui/BrandLogo.tsx";

/** The four AI apps "Mis agentes" knows how to connect. */
export type AgentId = "claude" | "chatgpt" | "lumo" | "grok";

export interface Agent {
  id: AgentId;
  name: string;
  brand: BrandName;
  /** Wambi's handshake scene with this app. */
  scene: string;
  /** Where the app takes a custom connector (or where to get the app). */
  connectorsUrl: string;
  /** The company's own step-by-step guide. */
  helpUrl: string;
  /** A notice the sheet shows before the steps. */
  note?: "plan" | "desktop" | "paid";
}

export const AGENTS: readonly Agent[] = [
  {
    id: "claude",
    name: "Claude",
    brand: "claude",
    scene: "/wambi/handshake-claude.webp",
    connectorsUrl: "https://claude.ai/settings/connectors",
    helpUrl:
      "https://support.claude.com/en/articles/11175166-getting-started-with-custom-connectors-using-remote-mcp",
  },
  {
    id: "chatgpt",
    name: "ChatGPT",
    brand: "chatgpt",
    scene: "/wambi/handshake-chatgpt.webp",
    connectorsUrl: "https://chatgpt.com/plugins",
    helpUrl:
      "https://help.openai.com/en/articles/12584461-connecting-custom-mcp-servers-in-chatgpt",
    note: "plan",
  },
  {
    id: "lumo",
    name: "Lumo+",
    brand: "lumo",
    scene: "/wambi/handshake-lumo.webp",
    connectorsUrl: "https://proton.me/lumo/download",
    helpUrl: "https://proton.me/support/lumo-connectors",
    note: "desktop",
  },
  {
    id: "grok",
    name: "Grok",
    brand: "grok",
    scene: "/wambi/handshake-grok.webp",
    connectorsUrl: "https://grok.com/connectors",
    helpUrl: "https://docs.x.ai/grok/connectors",
    note: "paid",
  },
];

const NAMES: readonly (readonly [AgentId, RegExp])[] = [
  ["claude", /\bclaude\b/i],
  ["chatgpt", /\bchatgpt\b/i],
  ["lumo", /\blumo\b/i],
  ["grok", /\bgrok\b/i],
];

const DOMAINS: readonly (readonly [AgentId, readonly string[]])[] = [
  ["claude", ["claude.ai", "anthropic.com"]],
  ["chatgpt", ["chatgpt.com", "openai.com"]],
  ["lumo", ["lumo.proton.me"]],
  ["grok", ["grok.com", "x.ai"]],
];

/**
 * Which of the four apps an OAuth client is; null for any other. A grant that has a domain is
 * matched by the domain alone: the app's own or one of its subdomains, at a label boundary (never
 * a substring: "box.ai" is not x.ai), whatever its name says (clients register themselves, so
 * "Claude" from evil.example is not Claude). Only a grant with no domain is matched by name, as a
 * whole word.
 */
export function agentFor(grant: { name: string; domain?: string | null }): AgentId | null {
  const domain = (grant.domain ?? "").toLowerCase();
  if (domain) {
    for (const [id, own] of DOMAINS) {
      if (own.some((d) => domain === d || domain.endsWith(`.${d}`))) return id;
    }
    return null;
  }
  for (const [id, pattern] of NAMES) if (pattern.test(grant.name)) return id;
  return null;
}
