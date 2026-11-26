import { renderToString } from "react-dom/server";
import { describe, expect, it } from "vitest";
import source from "../../../../docs/design/system/project/icons/brands.json";
import { BrandLogo, type BrandName } from "./BrandLogo.tsx";

const NAMES = [
  "chatgpt",
  "claude",
  "lumo",
  "grok",
  "revolut",
  "google-wallet",
  "activobank",
] as const satisfies readonly BrandName[];

describe("brand logos render in one colour", () => {
  it("covers every logo of brands.json", () => {
    expect(Object.keys(source.logos).sort()).toEqual([...NAMES].sort());
  });

  for (const name of NAMES) {
    it(`draws ${name} with its own viewBox, every path in currentColor`, () => {
      const logo = source.logos[name];
      const html = renderToString(<BrandLogo name={name} />);
      expect(html).toContain(`data-brand="${name}"`);
      expect(html).toContain(`viewBox="${logo.viewBox}"`);
      expect(html).toContain('aria-hidden="true"');
      const paths = html.match(/<path [^>]*>/g) ?? [];
      expect(paths).toHaveLength(logo.paths.length);
      for (const path of paths) expect(path).toContain('fill="currentColor"');
    });
  }

  it("uses the even-odd rule where brands.json says so", () => {
    const html = renderToString(<BrandLogo name="lumo" />);
    expect(html).toContain('fill-rule="evenodd"');
    expect(renderToString(<BrandLogo name="revolut" />)).not.toContain("evenodd");
  });

  it("takes a size and a class", () => {
    const html = renderToString(<BrandLogo name="grok" size={32} className="x" />);
    expect(html).toContain('width="32"');
    expect(html).toContain('height="32"');
    expect(html).toContain('class="x"');
  });
});
