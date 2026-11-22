import type { ReactNode } from "react";
import { renderToString } from "react-dom/server";
import { MemoryRouter } from "react-router";
import { describe, expect, it } from "vitest";
import { Icon } from "../../ui/Icon.tsx";
import { SettingsGroup, SettingsRow } from "./parts.tsx";

const icon = <Icon name="shield" size={20} />;
const noop = () => {};
const html = (node: ReactNode) => renderToString(<MemoryRouter>{node}</MemoryRouter>);

describe("SettingsRow", () => {
  it("a switch row is one switch named by its title, with the line as its description", () => {
    const out = html(
      <SettingsRow
        icon={icon}
        title="Sonido"
        line="Al guardar"
        trailing={{ kind: "switch", checked: true, onChange: noop }}
      />,
    );
    expect(out.match(/role="switch"/g)).toHaveLength(1);
    expect(out.match(/<button/g)).toHaveLength(1);
    expect(out).toContain('aria-checked="true"');
    expect(out).toMatch(/aria-labelledby="([^"]+)"/);
    expect(out).toContain("Sonido");
    expect(out).toContain("Al guardar");
  });

  it("a chevron row shows its value and is not pressable without onPress or href", () => {
    const out = html(
      <SettingsRow icon={icon} title="Idioma" trailing={{ kind: "chevron", value: "Español" }} />,
    );
    expect(out).toContain("Español");
    expect(out).toContain('data-icon="chevron-right"');
    expect(out).not.toContain("<button");
    expect(out).not.toContain("<a ");
  });

  it("a chevron row with onPress is a button; with an internal href a link; with http(s) a new-tab link", () => {
    const button = html(
      <SettingsRow icon={icon} title="Idioma" trailing={{ kind: "chevron" }} onPress={noop} />,
    );
    expect(button).toContain("<button");
    const internal = html(
      <SettingsRow icon={icon} title="Idioma" trailing={{ kind: "chevron" }} href="/settings/x" />,
    );
    expect(internal).toContain('href="/settings/x"');
    expect(internal).not.toContain("_blank");
    const external = html(
      <SettingsRow
        icon={icon}
        title="Código"
        trailing={{ kind: "chevron" }}
        href="https://example.com"
      />,
    );
    expect(external).toContain('target="_blank"');
    expect(external).toContain('rel="noreferrer"');
  });

  it("a chip row shows its text", () => {
    const out = html(
      <SettingsRow
        icon={icon}
        title="Este"
        trailing={{ kind: "chip", text: "este dispositivo" }}
      />,
    );
    expect(out).toContain("este dispositivo");
  });

  it("a trash row is a button named by its label, and the row itself is not pressable", () => {
    const out = html(
      <SettingsRow
        icon={icon}
        title="Pixel 8"
        trailing={{ kind: "trash", label: "Quitar Pixel 8", onPress: noop }}
      />,
    );
    expect(out.match(/<button/g)).toHaveLength(1);
    expect(out).toContain('aria-label="Quitar Pixel 8"');
    expect(out).toContain('data-icon="trash"');
  });

  it("a danger row colours its title and icon with over", () => {
    const out = html(
      <SettingsRow icon={icon} title="Borrar" tone="danger" trailing={{ kind: "none" }} />,
    );
    expect(out.match(/text-over/g)?.length).toBeGreaterThanOrEqual(2);
  });
});

describe("SettingsGroup", () => {
  it("names the group by its label", () => {
    const out = html(
      <SettingsGroup label="Dispositivos">
        <SettingsRow icon={icon} title="A" trailing={{ kind: "none" }} />
      </SettingsGroup>,
    );
    expect(out).toContain("Dispositivos");
    expect(out).toContain('role="group"');
    expect(out).toContain("aria-labelledby");
  });

  it("without a label it has no name", () => {
    const out = html(
      <SettingsGroup>
        <SettingsRow icon={icon} title="A" trailing={{ kind: "none" }} />
      </SettingsGroup>,
    );
    expect(out).not.toContain("aria-labelledby");
  });
});
