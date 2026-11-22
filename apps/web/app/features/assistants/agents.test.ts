import { describe, expect, it } from "vitest";
import { AGENTS, agentFor } from "./agents.ts";

describe("agentFor", () => {
  it("knows the four apps by name or domain, in any case", () => {
    expect(agentFor({ name: "Claude" })).toBe("claude");
    expect(agentFor({ name: "mcp client", domain: "anthropic.com" })).toBe("claude");
    expect(agentFor({ name: "ChatGPT", domain: "chatgpt.com" })).toBe("chatgpt");
    expect(agentFor({ name: "x", domain: "OpenAI.com" })).toBe("chatgpt");
    expect(agentFor({ name: "Lumo" })).toBe("lumo");
    expect(agentFor({ name: "Proton Lumo+" })).toBe("lumo");
    expect(agentFor({ name: "Grok" })).toBe("grok");
    expect(agentFor({ name: "x", domain: "grok.x.ai" })).toBe("grok");
  });

  it("is null for any other client", () => {
    expect(agentFor({ name: "Cursor" })).toBeNull();
    expect(agentFor({ name: "Cursor", domain: "cursor.com" })).toBeNull();
    expect(agentFor({ name: "Cursor", domain: null })).toBeNull();
  });
});

describe("AGENTS", () => {
  it("lists Claude, ChatGPT, Lumo+ and Grok in that order with their links", () => {
    expect(AGENTS.map((a) => [a.id, a.name, a.brand])).toEqual([
      ["claude", "Claude", "claude"],
      ["chatgpt", "ChatGPT", "chatgpt"],
      ["lumo", "Lumo+", "lumo"],
      ["grok", "Grok", "grok"],
    ]);
    for (const agent of AGENTS) expect(agent.scene).toBe(`/wambi/handshake-${agent.id}.webp`);
    expect(AGENTS.map((a) => a.connectorsUrl)).toEqual([
      "https://claude.ai/settings/connectors",
      "https://chatgpt.com/plugins",
      "https://proton.me/lumo/download",
      "https://grok.com/connectors",
    ]);
    expect(AGENTS.map((a) => a.helpUrl)).toEqual([
      "https://support.claude.com/en/articles/11175166-getting-started-with-custom-connectors-using-remote-mcp",
      "https://help.openai.com/en/articles/12584461-connecting-custom-mcp-servers-in-chatgpt",
      "https://proton.me/support/lumo-connectors",
      "https://docs.x.ai/grok/connectors",
    ]);
  });
});
