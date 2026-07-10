import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

describe("product navigation configuration", () => {
  it("provides one route-owned destination list for every workspace", () => {
    const routeRoot = join(process.cwd(), "app/routes");
    const navigationPath = join(routeRoot, "productNavigation.ts");

    expect(existsSync(navigationPath)).toBe(true);

    const navigationSource = readFileSync(navigationPath, "utf8");
    const layoutSources = [
      "operator/components/OperatorLayout.tsx",
      "packets/components/PacketsLayout.tsx"
    ].map((path) => readFileSync(join(routeRoot, path), "utf8"));

    expect(navigationSource).toContain("export const PRODUCT_DESTINATIONS");
    expect(navigationSource).toContain('{ label: "Operator", to: "/operator" }');
    expect(navigationSource).toContain('{ label: "Packets", to: "/packets" }');
    expect(navigationSource).toContain('{ label: "All Runs" }');
    expect(navigationSource).toContain('{ label: "Entities" }');
    expect(navigationSource).toContain('{ label: "Reports" }');

    for (const source of layoutSources) {
      expect(source).toContain(
        'import { PRODUCT_DESTINATIONS } from "../../productNavigation"'
      );
      expect(source).toContain("destinations={PRODUCT_DESTINATIONS}");
      expect(source).not.toContain("destinations={[");
    }
  });
});
