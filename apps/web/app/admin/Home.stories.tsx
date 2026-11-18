import type { Meta, StoryObj } from "@storybook/react-vite";
import { type ReactNode, useState } from "react";
import { MemoryRouter, Route, Routes, useLocation } from "react-router";
import { expect, fn, userEvent, waitFor, within } from "storybook/test";
import { expectTarget } from "../../.storybook/story-utils.ts";
import { createApiClient } from "../api/client.ts";
import { AdminMessages } from "./AdminMessages.tsx";
import { HomeScreen } from "./HomeScreen.tsx";
import { AdminSessionContext, createAdminSession } from "./use-admin.ts";

/**
 * The admin home (spec §6) against a fake API: user metrics first, the weekly sign-ups, the
 * suspended count, the audit list and the look-up box.
 */

const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": status < 300 ? "application/json" : "application/problem+json" },
  });
const problem = (status: number, code: string) =>
  json(status, { type: "about:blank", title: code, status, code });

/** Twelve ISO weeks ending 2026-11-02, growing. */
const WEEKS = Array.from({ length: 12 }, (_, i) => {
  const day = new Date(Date.UTC(2026, 10, 2) - (11 - i) * 7 * 86_400_000);
  return { weekStart: day.toISOString().slice(0, 10), withEmail: 2 + i, guests: 1 + (i % 4) };
});

/** Ninety days ending 2026-11-18, growing. */
const DAILY = Array.from({ length: 90 }, (_, i) => ({
  day: new Date(Date.UTC(2026, 10, 18) - (89 - i) * 86_400_000).toISOString().slice(0, 10),
  count: 20 + i,
}));

const ACTIVITY = {
  dailyActive: DAILY,
  cohorts: [
    { weekStart: "2026-10-12", size: 40, week1: 31, week4: 22, week12: null },
    { weekStart: "2026-10-19", size: 52, week1: 40, week4: null, week12: null },
  ],
  installsByPlatform: [
    { platform: "android", count: 210 },
    { platform: "ios", count: 90 },
    { platform: "web", count: 100 },
    { platform: "unknown", count: 12 },
  ],
  versions: [
    { platform: "android", appVersion: "1.4.0", users: 150 },
    { platform: "web", appVersion: "04565f80", users: 80 },
  ],
};

const METRICS = {
  ...ACTIVITY,
  total: 412,
  withEmail: 301,
  guests: 111,
  active30d: 187,
  suspended: 3,
  signups7d: 24,
  signupsPrev7d: 17,
  weekly: WEEKS,
};

const EMPTY_METRICS = {
  dailyActive: [],
  cohorts: [],
  installsByPlatform: [],
  versions: [],
  total: 0,
  withEmail: 0,
  guests: 0,
  active30d: 0,
  suspended: 0,
  signups7d: 0,
  signupsPrev7d: 0,
  weekly: WEEKS.map((w) => ({ ...w, withEmail: 0, guests: 0 })),
};

const entry = (n: number, over: Record<string, unknown> = {}) => ({
  id: `audit-${n}`,
  at: new Date(Date.UTC(2026, 10, 3, 18, 0) - n * 3_600_000).toISOString(),
  adminUserId: "admin-1",
  action: "sessions.revoke",
  targetUserId: "7a1c0000-0000-4000-8000-000000000001",
  emailHash: null,
  reason: `Reason number ${n}`,
  detail: null,
  ...over,
});

const FIRST_PAGE = {
  entries: [
    entry(1, { action: "account.suspend", reason: "Chargeback abuse" }),
    entry(2, { action: "email.change_requested", detail: { to: "x" } }),
    entry(3, { action: "admin.verified", targetUserId: null, reason: null }),
    ...Array.from({ length: 47 }, (_, i) => entry(i + 4)),
  ],
  next: "cursor-2",
};
const SECOND_PAGE = {
  entries: [entry(51, { action: "account.delete", reason: "Asked by email" })],
  next: null,
};

type Handler = (request: Request) => Response | Promise<Response>;

interface Spies {
  onRequest(line: string): void;
}

/** A fake API; the home reaches it through the admin session's `adminFetch`. */
function Stage({
  handlers,
  onRequest,
  children,
}: {
  handlers: Record<string, Handler>;
  onRequest: Spies["onRequest"];
  children: ReactNode;
}) {
  const [session] = useState(() => {
    const fetch = async (input: RequestInfo | URL) => {
      const request = input as Request;
      const url = new URL(request.url);
      const path = url.pathname.replace("/api", "");
      onRequest(`${request.method} ${path}${url.search}`);
      const handler = handlers[`${request.method} ${path}`];
      return handler ? handler(request) : problem(404, "not_found");
    };
    const client = createApiClient({
      fetch,
      baseUrl: "http://localhost/api",
      onUnauthorized: fn(),
    });
    return createAdminSession({
      client,
      authenticate: async () => Promise.reject(new Error("no")),
    });
  });
  return (
    <MemoryRouter initialEntries={["/admin"]}>
      <AdminMessages>
        <AdminSessionContext value={session}>
          <Routes>
            <Route path="/admin" element={children} />
            <Route path="/admin/users/:id" element={<Landed />} />
          </Routes>
        </AdminSessionContext>
      </AdminMessages>
    </MemoryRouter>
  );
}

function Landed() {
  return <p>Landed on {useLocation().pathname}</p>;
}

const happy = (): Record<string, Handler> => ({
  "GET /v1/admin/metrics": () => json(200, METRICS),
  "GET /v1/admin/audit": (request) =>
    json(200, new URL(request.url).searchParams.has("before") ? SECOND_PAGE : FIRST_PAGE),
});

const meta = {
  title: "Admin/Home",
  args: { onRequest: fn() },
  parameters: {
    viewport: {
      options: {
        phone: { name: "Phone", styles: { width: "390px", height: "844px" }, type: "mobile" },
      },
    },
  },
  globals: { viewport: { value: "phone", isRotated: false } },
} satisfies Meta<Spies>;

export default meta;
type Story = StoryObj<Spies>;

const render = (handlers: Record<string, Handler>): Story["render"] =>
  function Render(args) {
    return (
      <Stage handlers={handlers} onRequest={args.onRequest}>
        <HomeScreen />
      </Stage>
    );
  };

/** Users first: the five cards, the weekly chart, the suspended count, then the audit list. */
export const Home: Story = {
  render: render(happy()),
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await canvas.findByRole("heading", { level: 1, name: "Administración" });
    const card = (name: string) => canvas.getByRole("group", { name });
    await waitFor(() => expect(within(card("Cuentas")).getByText("412")).toBeVisible());
    await expect(within(card("Con correo")).getByText("301")).toBeVisible();
    await expect(within(card("Sin correo")).getByText("111")).toBeVisible();
    await expect(within(card("Activas en 30 días")).getByText("187")).toBeVisible();
    const signups = card("Altas en 7 días");
    await expect(within(signups).getByText("24")).toBeVisible();
    await expect(within(signups).getByText("Los 7 días anteriores: 17")).toBeVisible();
    // The chart is drawn, and its figures are also a table for screen readers.
    await expect(canvas.getByRole("heading", { level: 2, name: "Altas por semana" })).toBeVisible();
    await expect(canvas.getByRole("table", { name: "Altas por semana" })).toBeInTheDocument();
    await expect(canvas.getByText("Cuentas suspendidas: 3")).toBeVisible();
    // 50 audit rows, newest first, in words (not the raw action code).
    const list = canvas.getByRole("list", { name: "Registro de auditoría" });
    await waitFor(() => expect(within(list).getAllByRole("listitem")).toHaveLength(50));
    await expect(within(list).getAllByRole("listitem")[0]).toHaveTextContent("Cuenta suspendida");
    await expect(within(list).getAllByRole("listitem")[0]).toHaveTextContent("Chargeback abuse");
    await expect(canvas.queryByText("account.suspend")).toBeNull();
  },
};

/** "Cargar más" asks for the page after the cursor and appends it; no cursor, no button. */
export const HomeLoadMore: Story = {
  render: render(happy()),
  play: async ({ canvasElement, args }) => {
    const canvas = within(canvasElement);
    const more = await canvas.findByRole("button", { name: "Cargar más" });
    await expectTarget(more);
    await userEvent.click(more);
    const list = canvas.getByRole("list", { name: "Registro de auditoría" });
    await waitFor(() => expect(within(list).getAllByRole("listitem")).toHaveLength(51));
    await expect(canvas.queryByRole("button", { name: "Cargar más" })).toBeNull();
    await expect(args.onRequest).toHaveBeenCalledWith("GET /v1/admin/audit?before=cursor-2");
  },
};

/** No accounts yet: zeros everywhere and an audit list that says it is empty. */
export const HomeEmpty: Story = {
  render: render({
    "GET /v1/admin/metrics": () => json(200, EMPTY_METRICS),
    "GET /v1/admin/audit": () => json(200, { entries: [], next: null }),
  }),
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await waitFor(() =>
      expect(within(canvas.getByRole("group", { name: "Cuentas" })).getByText("0")).toBeVisible(),
    );
    await expect(canvas.getByText("Cuentas suspendidas: 0")).toBeVisible();
    await expect(canvas.getByText("Aún no hay acciones registradas.")).toBeVisible();
    await expect(canvas.queryByRole("button", { name: "Cargar más" })).toBeNull();
  },
};

/** While the numbers are on their way: a busy region, no zeros that could be mistaken for data. */
export const HomeLoading: Story = {
  render: render({
    "GET /v1/admin/metrics": () => new Promise<Response>(() => {}),
    "GET /v1/admin/audit": () => new Promise<Response>(() => {}),
  }),
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await expect(canvas.getByRole("status")).toHaveTextContent("Cargando…");
    await expect(canvas.queryByRole("group", { name: "Cuentas" })).toBeNull();
    // The look-up box does not wait for the numbers.
    await expect(canvas.getByRole("button", { name: "Buscar" })).toBeVisible();
  },
};

/** The metrics call failed: the reason and a retry that asks again. */
export const HomeError: Story = {
  render: render({
    "GET /v1/admin/metrics": () => problem(500, "internal"),
    "GET /v1/admin/audit": () => json(200, FIRST_PAGE),
  }),
  play: async ({ canvasElement, args }) => {
    const canvas = within(canvasElement);
    await expect(await canvas.findByRole("alert")).toBeVisible();
    const retry = canvas.getByRole("button", { name: "Reintentar" });
    await expectTarget(retry);
    await userEvent.click(retry);
    await waitFor(() =>
      expect(
        (args.onRequest as ReturnType<typeof fn>).mock.calls.filter(
          ([line]) => line === "GET /v1/admin/metrics",
        ),
      ).toHaveLength(2),
    );
  },
};

/** The same screen in English, by day (contrast is checked in both themes). */
export const HomeDayEnglish: Story = {
  globals: { theme: "day", locale: "en" },
  render: render(happy()),
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await canvas.findByRole("heading", { level: 1, name: "Admin" });
    await waitFor(() => expect(canvas.getByRole("group", { name: "Accounts" })).toBeVisible());
    await expect(canvas.getByText("Suspended accounts: 3")).toBeVisible();
  },
};

/** An email goes to the API as `email=` (trimmed); an account that exists opens its page. */
export const LookupByEmail: Story = {
  render: render({
    ...happy(),
    "GET /v1/admin/users": () => json(200, { id: "u-ana" }),
  }),
  play: async ({ canvasElement, args }) => {
    const canvas = within(canvasElement);
    const input = await canvas.findByRole("textbox", { name: "Correo o id de la cuenta" });
    await userEvent.type(input, "  Ana@Example.test ");
    await userEvent.click(canvas.getByRole("button", { name: "Buscar" }));
    await expect(await canvas.findByText("Landed on /admin/users/u-ana")).toBeVisible();
    await expect(args.onRequest).toHaveBeenCalledWith(
      "GET /v1/admin/users?email=Ana%40Example.test",
    );
  },
};

/** Without an @ the input is an account id. */
export const LookupById: Story = {
  render: render({
    ...happy(),
    "GET /v1/admin/users": () => json(200, { id: "u-ana" }),
  }),
  play: async ({ canvasElement, args }) => {
    const canvas = within(canvasElement);
    const input = await canvas.findByRole("textbox", { name: "Correo o id de la cuenta" });
    await userEvent.type(input, "u-ana{enter}");
    await expect(await canvas.findByText("Landed on /admin/users/u-ana")).toBeVisible();
    await expect(args.onRequest).toHaveBeenCalledWith("GET /v1/admin/users?id=u-ana");
  },
};

/** A miss stays on the home and says so beside the box. */
export const LookupMiss: Story = {
  render: render({
    ...happy(),
    "GET /v1/admin/users": () => problem(404, "user_not_found"),
  }),
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    const input = await canvas.findByRole("textbox", { name: "Correo o id de la cuenta" });
    await userEvent.type(input, "nobody@example.test{enter}");
    await expect(await canvas.findByRole("alert")).toHaveTextContent(
      "Ninguna cuenta con ese correo o id",
    );
    await expect(input).toHaveAttribute("aria-invalid", "true");
  },
};

/**
 * The cards say Without email / With email, and the four activity blocks render from the metrics:
 * daily actives, cohorts ("at least N", "—" for none yet), installs by platform and versions.
 */
export const HomeActivity: Story = {
  globals: { theme: "day", locale: "en" },
  render: render(happy()),
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await waitFor(() => expect(canvas.getByRole("group", { name: "Without email" })).toBeVisible());
    await expect(
      within(canvas.getByRole("group", { name: "With email" })).getByText("301"),
    ).toBeVisible();
    await expect(canvas.queryByText("Guests")).toBeNull();

    const daily = canvas.getByRole("table", { name: "Daily active people" });
    await expect(within(daily).getAllByRole("row")).toHaveLength(91);
    await expect(
      canvas.getByRole("heading", { level: 2, name: "Daily active people" }),
    ).toBeVisible();

    const cohorts = canvas.getByRole("table", { name: "Cohorts" });
    const rows = within(cohorts).getAllByRole("row");
    await expect(rows).toHaveLength(3);
    await expect(rows[1]).toHaveTextContent("40");
    await expect(rows[1]).toHaveTextContent("at least 31");
    await expect(rows[1]).toHaveTextContent("at least 22");
    await expect(rows[1]).toHaveTextContent("—");
    await expect(rows[2]).toHaveTextContent("at least 40");

    const installs = canvas.getByRole("list", { name: "Installs by platform" });
    await expect(within(installs).getByText("Android")).toBeVisible();
    await expect(within(installs).getByText("210")).toBeVisible();
    await expect(within(installs).getByText("Unknown")).toBeVisible();

    const versions = canvas.getByRole("table", { name: "Versions" });
    await expect(within(versions).getByText("1.4.0")).toBeVisible();
    await expect(within(versions).getByText("04565f80")).toBeVisible();
  },
};
