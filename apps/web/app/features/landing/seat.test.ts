import { describe, expect, it } from "vitest";
import { seatHalves } from "./Landing.tsx";

describe("seatHalves", () => {
  it("splits a two-word call to action at its space", () => {
    expect(seatHalves("Empieza ahora")).toEqual(["Empieza", "ahora"]);
    expect(seatHalves("Get started")).toEqual(["Get", "started"]);
  });

  it("keeps the dot with the first half, so the halves read back as the label", () => {
    const label = "Muy pronto · Síguelo en GitHub";
    const [before, after] = seatHalves(label);
    expect([before, after]).toEqual(["Muy pronto ·", "Síguelo en GitHub"]);
    expect(`${before} ${after}`).toBe(label);
  });

  it("leaves a one-word label whole", () => {
    expect(seatHalves("Start")).toEqual(["Start", ""]);
  });
});
