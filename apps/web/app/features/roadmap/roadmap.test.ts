import { describe, expect, it } from "vitest";
import en from "../../i18n/messages/en.json" with { type: "json" };
import es from "../../i18n/messages/es.json" with { type: "json" };
import itMessages from "../../i18n/messages/it.json" with { type: "json" };
import ptMessages from "../../i18n/messages/pt.json" with { type: "json" };
import { ROADMAP_ITEMS, ROADMAP_STATUSES, roadmapColumns, roadmapItem } from "./roadmap.ts";

type Tree = { [key: string]: string | Tree };

function flatten(tree: Tree, prefix = ""): Record<string, string> {
  const out: Record<string, string> = {};
  for (const [key, value] of Object.entries(tree)) {
    const path = prefix ? `${prefix}.${key}` : key;
    if (typeof value === "string") out[path] = value;
    else Object.assign(out, flatten(value, path));
  }
  return out;
}

const catalogs = {
  es: flatten(es),
  en: flatten(en),
  it: flatten(itMessages),
  pt: flatten(ptMessages),
} as const;

describe("roadmap items", () => {
  it("has unique ids", () => {
    const ids = ROADMAP_ITEMS.map((item) => item.id);
    expect(new Set(ids).size).toBe(ids.length);
    expect(ids.length).toBeGreaterThan(0);
  });

  it("only uses known statuses", () => {
    for (const item of ROADMAP_ITEMS) expect(ROADMAP_STATUSES, item.id).toContain(item.status);
  });

  it("gives every item a glyph", () => {
    for (const item of ROADMAP_ITEMS) expect(item.glyph.trim(), item.id).not.toBe("");
  });

  it("has every catalog key in every language", () => {
    const keys = [
      ...ROADMAP_ITEMS.flatMap((item) => [item.title, item.body]),
      ...ROADMAP_STATUSES.map((status) => `roadmap.status.${status}`),
      "roadmap.title",
      "roadmap.intro",
      "roadmap.meta.title",
      "roadmap.meta.description",
    ];
    for (const locale of ["es", "en", "it", "pt"] as const) {
      for (const key of keys) expect(catalogs[locale], `${locale}:${key}`).toHaveProperty([key]);
    }
  });

  it("promises no dates and no call to propose or vote", () => {
    const datePattern =
      /\b(20\d\d|Q[1-4]|T[1-4])\b|\b(enero|febrero|marzo|abril|mayo|junio|julio|agosto|septiembre|octubre|noviembre|diciembre|january|february|march|april|june|july|august|september|october|november|december|gennaio|febbraio|aprile|maggio|giugno|luglio|settembre|ottobre|dicembre|janeiro|fevereiro|março|maio|junho|julho|setembro|outubro|novembro|dezembro)\b/i;
    const votePattern =
      /discussions|\bvot(a|o|e|ar|ing|es|are|ate)\b|\bpropon(e|er|ga)\b|\bpropose\b|\bproponi\b|\bpropõe\b/i;
    for (const locale of ["es", "en", "it", "pt"] as const) {
      for (const [key, value] of Object.entries(catalogs[locale])) {
        if (!key.startsWith("roadmap.")) continue;
        expect(value, `${locale}:${key}`).not.toMatch(datePattern);
        expect(value, `${locale}:${key}`).not.toMatch(votePattern);
      }
    }
  });

  it("never calls Wambito a game", () => {
    for (const locale of ["es", "en", "it", "pt"] as const) {
      for (const [key, value] of Object.entries(catalogs[locale])) {
        if (!key.startsWith("roadmap.")) continue;
        expect(value, `${locale}:${key}`).not.toMatch(
          /\bjueg(o|a)s?\b|\bgames?\b|\bgiochi?\b|\bjogos?\b/i,
        );
      }
    }
  });
});

describe("roadmapColumns", () => {
  it("groups the items by status, in the order building, next, later, done", () => {
    const columns = roadmapColumns([
      { id: "a", status: "later", glyph: "x", title: "t", body: "b" },
      { id: "d", status: "done", glyph: "x", title: "t", body: "b" },
      { id: "b", status: "building", glyph: "x", title: "t", body: "b" },
      { id: "c", status: "later", glyph: "x", title: "t", body: "b" },
    ]);
    expect(columns.map((column) => [column.status, column.items.map((i) => i.id)])).toEqual([
      ["building", ["b"]],
      ["later", ["a", "c"]],
      ["done", ["d"]],
    ]);
  });

  it("leaves out the statuses that have no items", () => {
    const columns = roadmapColumns();
    expect(columns.length).toBeGreaterThan(0);
    for (const column of columns) expect(column.items.length).toBeGreaterThan(0);
    expect(columns.map((column) => column.status)).toEqual(["building", "next", "later", "done"]);
  });
});

describe("the roadmap's statuses", () => {
  it("has working offline and connecting your AI done", () => {
    expect(roadmapItem("offline").status).toBe("done");
    expect(roadmapItem("connect_ai").status).toBe("done");
  });

  it("builds the store listings and plans the iPhone app next", () => {
    expect(roadmapItem("stores").status).toBe("building");
    expect(roadmapItem("bank_alerts").status).toBe("building");
    expect(roadmapItem("iphone_app").status).toBe("next");
  });

  it("plans the on-device AI recap for later", () => {
    expect(roadmapItem("on_device_ai").status).toBe("later");
  });
});
