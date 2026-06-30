import { describe, expect, it } from "vitest";
import { designTokenCss, tokenVar } from "./tokens";

describe("design tokens", () => {
  it("exports CSS custom properties from the shared token source", () => {
    expect(designTokenCss).toContain("--og-color-app-background: #f7f9fb;");
    expect(designTokenCss).toContain("--og-layout-sidebar-width: 72px;");
    expect(designTokenCss).toContain("--og-typography-heading-weight: 650;");
  });

  it("provides TypeScript-safe CSS variable references", () => {
    expect(tokenVar.color.text).toBe("var(--og-color-text)");
    expect(tokenVar.radius.panel).toBe("var(--og-radius-panel)");
    expect(tokenVar.layout.inboxWidth).toBe("var(--og-layout-inbox-width)");
  });
});
