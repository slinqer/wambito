import { describe, expect, test } from "vitest";
import { clientHeader } from "../src/http/client-headers.ts";

describe("clientHeader", () => {
  test("a header under another prefix is ignored", () => {
    expect(clientHeader(new Headers({ "x-other-locale": "es" }), "locale")).toBeUndefined();
    const both = new Headers({ "x-wambito-timezone": "America/Bogota", "x-other-locale": "en" });
    expect(clientHeader(both, "locale")).toBeUndefined();
    expect(clientHeader(both, "timezone")).toBe("America/Bogota");
  });

  test("neither", () => {
    expect(clientHeader(undefined, "timezone")).toBeUndefined();
    expect(clientHeader(new Headers(), "timezone")).toBeUndefined();
    expect(clientHeader(new Headers({ "x-other-timezone": "UTC" }), "timezone")).toBeUndefined();
  });

  test.each(["locale", "next", "timezone", "client", "background", "user"] as const)(
    "%s reads x-wambito-%s",
    (name) => {
      expect(clientHeader(new Headers({ [`x-wambito-${name}`]: "new" }), name)).toBe("new");
    },
  );
});
