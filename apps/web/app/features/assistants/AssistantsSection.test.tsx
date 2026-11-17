import { useQueryClient } from "@tanstack/react-query";
import { renderToString } from "react-dom/server";
import { describe, expect, it } from "vitest";
import { ApiProvider } from "../../api/ApiProvider.tsx";
import type { ApiMode } from "../../api/scope.ts";
import { AppMessages } from "../../i18n/AppMessages.tsx";
import { IntlProvider } from "../../i18n/IntlProvider.tsx";
import { ToastProvider } from "../../ui/Toast.tsx";
import { AssistantsSection } from "./AssistantsSection.tsx";
import type { Assistant } from "./queries.ts";

const CLAUDE: Assistant = {
  clientId: "https://claude.ai/oauth/mcp-oauth-client-metadata",
  name: "Claude",
  icon: null,
  uri: "https://claude.ai",
  domain: "claude.ai",
  scopes: ["finance:read", "finance:write", "offline_access"],
  connectedAt: "2026-10-02T09:00:00.000Z",
  lastUsedAt: "2026-10-20T18:30:00.000Z",
};

/** The assistants the API listed, already in the cache, as after the first fetch. */
function Listed({ items }: { items: Assistant[] }) {
  useQueryClient().setQueryData(["assistants"], items);
  return null;
}

/** Settings → Assistants in an API mode, rendered on the server. */
const render = (mode: ApiMode) =>
  renderToString(
    <ApiProvider mode={mode} fetch={async () => new Response(null, { status: 404 })}>
      <IntlProvider locale="en">
        <AppMessages>
          <ToastProvider>
            <Listed items={[CLAUDE]} />
            <AssistantsSection timeZone="Europe/Madrid" origin="https://app.wambito.com" />
          </ToastProvider>
        </AppMessages>
      </IntlProvider>
    </ApiProvider>,
  );

describe("AssistantsSection", () => {
  it("the list and Revoke show for a preview account (no off note)", () => {
    const html = render("local");
    expect(html).toContain("Your assistants");
    expect(html).toContain("Claude");
    expect(html).toContain("Revoke");
    expect(html).not.toContain("Not available yet with end-to-end encryption");
  });

  it("the demo, which has no account behind it, shows the address and steps only", () => {
    const html = render("demo");
    expect(html).toContain("https://app.wambito.com/mcp");
    expect(html).not.toContain("Your assistants");
    expect(html).not.toContain("Revoke");
  });
});
