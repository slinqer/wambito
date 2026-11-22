import { renderToString } from "react-dom/server";
import { describe, expect, it } from "vitest";
import { Icon } from "./Icon.tsx";
import type { IconName } from "./icon-shapes.ts";

const SETTINGS_ICONS = [
  "shield",
  "sliders",
  "bell",
  "folder",
  "info",
  "fingerprint",
  "phone",
  "laptop",
  "key",
  "trash",
  "wand",
  "calendar",
  "widget",
  "eye-off",
  "globe",
  "moon",
  "volume",
  "clock",
  "coin",
  "upload",
  "download",
  "server",
  "map",
  "chat",
] as const satisfies readonly IconName[];

describe("settings icons render", () => {
  for (const id of SETTINGS_ICONS) {
    it(`draws ${id}`, () => {
      const html = renderToString(<Icon name={id} />);
      expect(html).toContain(`data-icon="${id}"`);
      expect(html.match(/<path /g)?.length ?? 0).toBeGreaterThanOrEqual(1);
    });
  }
});
