import { describe, expect, test } from "vitest";
import { loadConfig } from "../src/config.ts";

const base = {
  DATABASE_URL: "postgres://wambito_app:x@db:5432/wambito",
  DATABASE_ADMIN_URL: "postgres://wambito:x@db:5432/wambito",
  BETTER_AUTH_SECRET: "s".repeat(40),
  API_URL: "https://api.wambito.test",
  WEB_URL: "https://wambito.test",
  MAIL_FROM: "Wambito <hola@wambito.test>",
  RESEND_API_KEY: "re_123",
  NODE_ENV: "production",
};

test("production refuses to trust a spoofable X-Forwarded-For without trusted proxies", () => {
  expect(() => loadConfig(base)).toThrow(/TRUSTED_PROXIES/);
});

test("production accepts trusted proxies or a platform client-IP header", () => {
  expect(
    loadConfig({ ...base, TRUSTED_PROXIES: "10.0.0.0/8, 172.16.0.0/12" }).TRUSTED_PROXIES,
  ).toEqual(["10.0.0.0/8", "172.16.0.0/12"]);
  expect(loadConfig({ ...base, CLIENT_IP_HEADER: "fly-client-ip" }).CLIENT_IP_HEADER).toBe(
    "fly-client-ip",
  );
});

test("invalid proxy ranges are rejected", () => {
  expect(() => loadConfig({ ...base, TRUSTED_PROXIES: "not-an-ip" })).toThrow(/TRUSTED_PROXIES/);
});

describe("SIGN_IN_ALLOWLIST", () => {
  const dev = { ...base, NODE_ENV: "development", CLIENT_IP_HEADER: "fly-client-ip" };

  test("is off when unset or an empty line in .env", () => {
    expect(loadConfig(dev).SIGN_IN_ALLOWLIST).toBeUndefined();
    expect(loadConfig({ ...dev, SIGN_IN_ALLOWLIST: "" }).SIGN_IN_ALLOWLIST).toBeUndefined();
  });

  test.each([" ", ",", " , ", ",,"])(
    "fails closed: %j is set but names nobody, so it is a startup error, not 'everyone may sign in'",
    (value) => {
      expect(() => loadConfig({ ...dev, SIGN_IN_ALLOWLIST: value })).toThrow(/SIGN_IN_ALLOWLIST/);
    },
  );

  test("is a trimmed, lower-cased list of emails", () => {
    expect(
      loadConfig({ ...dev, SIGN_IN_ALLOWLIST: " Ana@Correo.com,luis@correo.com ,," })
        .SIGN_IN_ALLOWLIST,
    ).toEqual(["ana@correo.com", "luis@correo.com"]);
  });

  test("rejects an entry that is not an email, so a typo cannot silently lock everyone out", () => {
    expect(() => loadConfig({ ...dev, SIGN_IN_ALLOWLIST: "ana@correo.com,luis" })).toThrow(
      /SIGN_IN_ALLOWLIST/,
    );
  });
});

describe("SMTP_TLS_INSECURE", () => {
  const smtp = {
    ...base,
    NODE_ENV: "development",
    CLIENT_IP_HEADER: "fly-client-ip",
    RESEND_API_KEY: undefined,
  };

  test("defaults to off", () => {
    expect(loadConfig({ ...smtp, SMTP_URL: "smtp://mail.example.com:25" }).SMTP_TLS_INSECURE).toBe(
      undefined,
    );
    expect(
      loadConfig({
        ...smtp,
        SMTP_URL: "smtp://mail.example.com:25",
        SMTP_TLS_INSECURE: "false",
      }).SMTP_TLS_INSECURE,
    ).toBe(false);
  });

  test("a blank value (a line left empty in .env) means off", () => {
    expect(
      loadConfig({ ...smtp, SMTP_URL: "smtp://mail.example.com:25", SMTP_TLS_INSECURE: "" })
        .SMTP_TLS_INSECURE,
    ).toBeUndefined();
  });

  test.each([
    "smtp://user:pw@host.docker.internal:1025",
    "smtp://127.0.0.1:1025",
    "smtp://localhost:1025",
    "smtp://[::1]:1025",
  ])("is allowed for a mail server on this machine: %s", (url) => {
    expect(
      loadConfig({ ...smtp, SMTP_URL: url, SMTP_TLS_INSECURE: "true" }).SMTP_TLS_INSECURE,
    ).toBe(true);
  });

  test("is refused for a remote server: skipping certificate checks is only for Proton Bridge", () => {
    expect(() =>
      loadConfig({ ...smtp, SMTP_URL: "smtp://smtp.example.com:587", SMTP_TLS_INSECURE: "true" }),
    ).toThrow(/SMTP_TLS_INSECURE/);
  });

  test("is refused without an SMTP_URL", () => {
    expect(() =>
      loadConfig({ ...base, CLIENT_IP_HEADER: "fly-client-ip", SMTP_TLS_INSECURE: "true" }),
    ).toThrow(/SMTP_TLS_INSECURE/);
  });

  test("only accepts true or false", () => {
    expect(() =>
      loadConfig({ ...smtp, SMTP_URL: "smtp://localhost:1025", SMTP_TLS_INSECURE: "yes" }),
    ).toThrow(/SMTP_TLS_INSECURE/);
  });
});

describe("DATABASE_ADMIN_URL", () => {
  const { DATABASE_ADMIN_URL: _admin, ...withoutAdmin } = base;
  const prod = { ...withoutAdmin, CLIENT_IP_HEADER: "fly-client-ip" };

  test("production does not need the owner credential, so the running API never holds it", () => {
    expect(loadConfig(prod).DATABASE_ADMIN_URL).toBeUndefined();
  });

  test("development needs it: the API applies migrations on start there", () => {
    expect(() => loadConfig({ ...prod, NODE_ENV: "development" })).toThrow(/DATABASE_ADMIN_URL/);
    expect(
      loadConfig({
        ...prod,
        NODE_ENV: "development",
        DATABASE_ADMIN_URL: "postgres://wambito:x@db:5432/wambito",
      }).DATABASE_ADMIN_URL,
    ).toBe("postgres://wambito:x@db:5432/wambito");
  });
});

describe("E2E_NOW", () => {
  const dev = { ...base, NODE_ENV: "development", CLIENT_IP_HEADER: "fly-client-ip" };

  test("is off when unset or an empty line in .env", () => {
    expect(loadConfig(dev).E2E_NOW).toBeUndefined();
    expect(loadConfig({ ...dev, E2E_NOW: "" }).E2E_NOW).toBeUndefined();
  });

  test("pins the clock to an ISO instant outside production", () => {
    expect(loadConfig({ ...dev, E2E_NOW: "2026-10-21T15:00:00Z" }).E2E_NOW).toEqual(
      new Date("2026-10-21T15:00:00Z"),
    );
    expect(() => loadConfig({ ...dev, E2E_NOW: "yesterday" })).toThrow(/E2E_NOW/);
  });

  test("production refuses a pinned clock", () => {
    expect(() =>
      loadConfig({ ...base, CLIENT_IP_HEADER: "fly-client-ip", E2E_NOW: "2026-10-21T15:00:00Z" }),
    ).toThrow(/E2E_NOW/);
  });
});

describe("GUEST_SIGNUP", () => {
  const prod = { ...base, CLIENT_IP_HEADER: "fly-client-ip" };

  test("is on by default, and when left blank in .env", () => {
    expect(loadConfig(prod).GUEST_SIGNUP).toBe(true);
    expect(loadConfig({ ...prod, GUEST_SIGNUP: "" }).GUEST_SIGNUP).toBe(true);
  });

  test("false turns it off; true keeps it on", () => {
    expect(loadConfig({ ...prod, GUEST_SIGNUP: "false" }).GUEST_SIGNUP).toBe(false);
    expect(loadConfig({ ...prod, GUEST_SIGNUP: "true" }).GUEST_SIGNUP).toBe(true);
  });

  test("only accepts true or false, so a typo doesn't silently open or close it", () => {
    expect(() => loadConfig({ ...prod, GUEST_SIGNUP: "no" })).toThrow(/GUEST_SIGNUP/);
  });
});

describe("WAMBITO_VERSION", () => {
  test("is the version the build was given, and unset (or blank) when it was given none", () => {
    expect(
      loadConfig({ ...base, CLIENT_IP_HEADER: "fly-client-ip" }).WAMBITO_VERSION,
    ).toBeUndefined();
    expect(
      loadConfig({ ...base, CLIENT_IP_HEADER: "fly-client-ip", WAMBITO_VERSION: " " })
        .WAMBITO_VERSION,
    ).toBeUndefined();
    expect(
      loadConfig({
        ...base,
        CLIENT_IP_HEADER: "fly-client-ip",
        WAMBITO_VERSION: "1.0.0+abc1234",
      }).WAMBITO_VERSION,
    ).toBe("1.0.0+abc1234");
  });
});

describe("admin settings", () => {
  const dev = { ...base, NODE_ENV: "development", CLIENT_IP_HEADER: "fly-client-ip" };

  test("ADMIN_USER_IDS is trimmed, empties dropped, unset is []", () => {
    expect(loadConfig({ ...dev, ADMIN_USER_IDS: "a, b,," }).ADMIN_USER_IDS).toEqual(["a", "b"]);
    expect(loadConfig(dev).ADMIN_USER_IDS).toEqual([]);
    expect(loadConfig({ ...dev, ADMIN_USER_IDS: "" }).ADMIN_USER_IDS).toEqual([]);
  });

  test("E2E_PREVIEW_USER_IDS is trimmed, empties dropped, unset is []", () => {
    expect(loadConfig({ ...dev, E2E_PREVIEW_USER_IDS: " a,b ,," }).E2E_PREVIEW_USER_IDS).toEqual([
      "a",
      "b",
    ]);
    expect(loadConfig(dev).E2E_PREVIEW_USER_IDS).toEqual([]);
    expect(loadConfig({ ...dev, E2E_PREVIEW_USER_IDS: "" }).E2E_PREVIEW_USER_IDS).toEqual([]);
  });

  test("ADMIN_ALLOWED_IPS takes IPs and CIDRs; blank means none", () => {
    expect(
      loadConfig({ ...dev, ADMIN_ALLOWED_IPS: "1.2.3.4,10.0.0.0/8" }).ADMIN_ALLOWED_IPS,
    ).toEqual(["1.2.3.4", "10.0.0.0/8"]);
    expect(loadConfig(dev).ADMIN_ALLOWED_IPS).toBeUndefined();
    expect(loadConfig({ ...dev, ADMIN_ALLOWED_IPS: " " }).ADMIN_ALLOWED_IPS).toBeUndefined();
  });

  test("ADMIN_ALLOWED_IPS rejects anything else", () => {
    expect(() => loadConfig({ ...dev, ADMIN_ALLOWED_IPS: "nope" })).toThrow(/ADMIN_ALLOWED_IPS/);
  });
});
