/**
 * The public roadmap: the single source for the roadmap page (`/roadmap`, `/en/roadmap`,
 * `/it/roadmap`, `/pt/roadmap`), which the landing's header and footer link to. Add, move or remove
 * an item here (and its copy in every message catalog under `roadmap.items`) and the page follows.
 * No dates anywhere: only a status.
 */

/** Left to right on a desktop, top to bottom on a phone: what is coming first, what is done last. */
export const ROADMAP_STATUSES = ["building", "next", "later", "done"] as const;

export type RoadmapStatus = (typeof ROADMAP_STATUSES)[number];

export interface RoadmapItem {
  /** Unique and stable: the catalog keys and the landing's selection use it. */
  id: string;
  status: RoadmapStatus;
  /** An emoji, drawn in the card's icon box. Decorative. */
  glyph: string;
  /** Catalog key of the title. */
  title: string;
  /** Catalog key of the one-line description. */
  body: string;
}

function item(id: string, status: RoadmapStatus, glyph: string): RoadmapItem {
  return {
    id,
    status,
    glyph,
    title: `roadmap.items.${id}.title`,
    body: `roadmap.items.${id}.body`,
  };
}

/** In the order they appear inside their column. Source: the overall spec's §3.3 (Stages). */
export const ROADMAP_ITEMS: readonly RoadmapItem[] = [
  item("web_app", "done", "🌐"),
  item("demo", "done", "🧪"),
  item("android_app", "done", "📲"),
  item("android_widget", "done", "🎤"),
  item("import_budge", "done", "📥"),
  item("offline", "done", "📴"),
  item("passwordless", "done", "🔑"),
  item("recurring", "done", "🔁"),
  item("languages", "done", "🌍"),
  item("self_host", "done", "🏠"),
  item("connect_ai", "done", "✨"),
  item("bank_alerts", "building", "🏦"),
  item("stores", "building", "📦"),
  item("import_others", "building", "📂"),
  item("iphone_app", "next", "📱"),
  item("e2e_encryption", "next", "🔒"),
  item("ai_one_click", "next", "⚡"),
  item("donations", "next", "💛"),
  item("no_central_server", "later", "🔗"),
  item("whatsapp", "later", "💬"),
  item("on_device_ai", "later", "🧠"),
];

export interface RoadmapColumn {
  status: RoadmapStatus;
  items: RoadmapItem[];
}

/** The columns to render: one per status that has items, in status order. */
export function roadmapColumns(items: readonly RoadmapItem[] = ROADMAP_ITEMS): RoadmapColumn[] {
  return ROADMAP_STATUSES.map((status) => ({
    status,
    items: items.filter((entry) => entry.status === status),
  })).filter((column) => column.items.length > 0);
}

export function roadmapItem(id: string): RoadmapItem {
  const found = ROADMAP_ITEMS.find((entry) => entry.id === id);
  if (!found) throw new Error(`Unknown roadmap item: ${id}`);
  return found;
}
