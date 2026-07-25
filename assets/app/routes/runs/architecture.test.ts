import { existsSync, readdirSync, readFileSync, statSync } from "node:fs";
import { dirname, join, relative, resolve } from "node:path";
import type { RouteConfigEntry } from "@react-router/dev/routes";
import { describe, expect, it } from "vitest";
import appRouteConfig from "../../routes";
import { analyzeTypeScript } from "../architectureTestSupport";

const assetsRoot = process.cwd();
const routeRoot = join(assetsRoot, "app/routes/runs");
const routeFiles = sourceFiles(routeRoot);
const allowedPackages = new Set(["react", "react-relay", "react-router"]);

describe("all-runs route architecture", () => {
  it("owns the one canonical runs registration and keeps generated artifacts in Relay", async () => {
    const registrations = routeRegistrations(await appRouteConfig);
    const runsRegistrations = registrations.filter(
      ({ file, path }) => path === "runs" || file.includes("/runs/"),
    );

    expect(runsRegistrations).toEqual([{ file: "./routes/runs/route.tsx", path: "runs" }]);
    expect(existsSync(join(assetsRoot, "src/runs"))).toBe(false);
    expect(routeFiles.filter((file) => file.includes("/__generated__/"))).toEqual([]);

    const generatedImports = routeFiles
      .flatMap(importsFor)
      .filter((specifier) => specifier.includes("/__generated__/"));

    expect(generatedImports.length).toBeGreaterThan(0);
    expect(
      generatedImports.every((specifier) => specifier.startsWith("app/relay/__generated__/")),
    ).toBe(true);
  });

  it("uses shared UI and Relay without importing sibling product routes", () => {
    const imports = routeFiles.flatMap(importsFor);
    const siblingRouteImports = imports.filter(
      (specifier) =>
        specifier.startsWith("app/routes/") &&
        !specifier.startsWith("app/routes/runs/") &&
        specifier !== "app/routes/productNavigation",
    );
    const barePackages = imports.filter((specifier) => !specifier.includes("/"));

    expect(siblingRouteImports).toEqual([]);
    expect(imports.some((specifier) => specifier.startsWith("src/ui/"))).toBe(true);
    expect(imports.some((specifier) => specifier.startsWith("app/relay/"))).toBe(true);
    expect(barePackages.filter((specifier) => !allowedPackages.has(specifier))).toEqual([]);
  });

  it("uses the global runs stylesheet without Tailwind or a route-specific UI dependency", () => {
    const globalStyles = readFileSync(join(assetsRoot, "src/styles/global.css"), "utf8");
    const packageJson = JSON.parse(readFileSync(join(assetsRoot, "package.json"), "utf8")) as {
      dependencies?: Record<string, string>;
      devDependencies?: Record<string, string>;
    };
    const packageNames = [
      ...Object.keys(packageJson.dependencies ?? {}),
      ...Object.keys(packageJson.devDependencies ?? {}),
    ];
    const routeClassTokens = routeFiles
      .flatMap((file) => [...analyzeTypeScript(readFileSync(file, "utf8"), file).stringLiterals])
      .flatMap((value) => value.split(/\s+/));
    const utilityClass =
      /^(?:[a-z]+:)*(?:bg|border|col-span|flex|gap|grid-cols|h|items|justify|m[trblxy]?|max-w|min-h|min-w|p[trblxy]?|rounded|space-[xy]|text|w)-/;

    expect(globalStyles.match(/@import\s+["']\.\/runs\.css["'];/g)).toHaveLength(1);
    expect(
      packageNames.filter((name) => /tailwind|bootstrap|chakra|mui|styled-components/i.test(name)),
    ).toEqual([]);
    expect(routeClassTokens.filter((token) => utilityClass.test(token))).toEqual([]);
  });
});

function routeRegistrations(
  entries: RouteConfigEntry[],
  parentPath = "",
): Array<{
  file: string;
  path: string;
}> {
  return entries.flatMap((entry) => {
    const path = [parentPath, entry.path].filter(Boolean).join("/");
    const registration = { file: entry.file, path };

    return [registration, ...routeRegistrations(entry.children ?? [], path)];
  });
}

function importsFor(file: string) {
  return [...analyzeTypeScript(readFileSync(file, "utf8"), file).moduleSpecifiers].map(
    (specifier) =>
      specifier.startsWith(".")
        ? relative(assetsRoot, resolve(dirname(file), specifier)).replaceAll("\\", "/")
        : specifier,
  );
}

function sourceFiles(path: string): string[] {
  return readdirSync(path).flatMap((entry) => {
    const file = join(path, entry);
    if (statSync(file).isDirectory()) return sourceFiles(file);

    return /\.(ts|tsx)$/.test(entry) &&
      !/\.test\.(ts|tsx)$/.test(entry) &&
      !/TestSupport\.(ts|tsx)$/.test(entry)
      ? [file]
      : [];
  });
}
