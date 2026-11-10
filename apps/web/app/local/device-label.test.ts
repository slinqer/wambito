import { describe, expect, it } from "vitest";
import { deviceLabel } from "./device-label.ts";

const FIREFOX_MAC =
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 14.6; rv:132.0) Gecko/20100101 Firefox/132.0";
const CHROME_ANDROID =
  "Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Mobile Safari/537.36";
const SAFARI_IOS =
  "Mozilla/5.0 (iPhone; CPU iPhone OS 18_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.1 Mobile/15E148 Safari/604.1";
const EDGE_WINDOWS =
  "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36 Edg/130.0.0.0";

describe("deviceLabel", () => {
  it("names Firefox on macOS", () => {
    expect(deviceLabel(FIREFOX_MAC)).toBe("Firefox on macOS");
  });

  it("names Chrome on Android", () => {
    expect(deviceLabel(CHROME_ANDROID)).toBe("Chrome on Android");
  });

  it("names Safari on iOS", () => {
    expect(deviceLabel(SAFARI_IOS)).toBe("Safari on iOS");
  });

  it("names Edge on Windows", () => {
    expect(deviceLabel(EDGE_WINDOWS)).toBe("Edge on Windows");
  });

  it("gives Web for an unknown agent", () => {
    expect(deviceLabel("")).toBe("Web");
    expect(deviceLabel("curl/8.7.1")).toBe("Web");
  });
});
