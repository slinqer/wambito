import { describe, expect, it } from "vitest";
import { ICON_NAMES, iconShapes } from "./icon-shapes.ts";

describe("iconShapes", () => {
  it("has a filled drawing for every icon", () => {
    for (const name of ICON_NAMES) {
      expect(iconShapes(name, "filled").length, name).toBeGreaterThan(0);
    }
  });

  it("draws the tabs' icons in two variants", () => {
    for (const name of ["home", "chart"] as const) {
      expect(iconShapes(name, "outline")).not.toEqual(iconShapes(name, "filled"));
    }
  });

  it("falls back to the filled drawing when an icon has no outline", () => {
    expect(iconShapes("search", "outline")).toEqual(iconShapes("search", "filled"));
  });

  it("strokes or fills every shape, never both or neither", () => {
    for (const name of ICON_NAMES) {
      for (const shape of [...iconShapes(name, "filled"), ...iconShapes(name, "outline")]) {
        expect(Boolean(shape.fill) !== Boolean(shape.stroke), `${name}: ${shape.d}`).toBe(true);
      }
    }
  });
});
