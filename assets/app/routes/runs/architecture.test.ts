import {
  existsSync,
  mkdtempSync,
  readdirSync,
  readFileSync,
  rmSync,
  statSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, relative, resolve } from "node:path";
import { describe, expect, it } from "vitest";
import {
  analyzeTypeScript,
  bareModuleSpecifierOffenders,
  emittedClassNames,
  localDependencyFiles,
  normalizeModuleSpecifier,
  routeRegistrationOffenders,
  stylesheetOwnerClasses,
  unownedClassNames,
} from "../architectureTestSupport";

const assetsRoot = process.cwd();
const routeRoot = join(assetsRoot, "app/routes/runs");
const allowedRoutePackages = new Set(["react", "react-relay", "react-router"]);

describe("all-runs route architecture", () => {
  it("owns exactly the canonical registered route and keeps generated artifacts outside source", () => {
    const routesSource = readFileSync(join(assetsRoot, "app/routes.ts"), "utf8");
    const routeFiles = routeOwnedDependencyFiles(routesSource);

    expect(routeRegistrationOffenders(routesSource, runsRegistration)).toEqual([]);
    expect(routeFiles.length).toBeGreaterThan(0);
    expect(existsSync(join(assetsRoot, "src/runs"))).toBe(false);
    expect(
      treeFiles(routeRoot).filter((file) => file.split(/[\\/]/).includes("__generated__")),
    ).toEqual([]);

    const generatedImports = routeFiles.flatMap((file) =>
      normalizedImports(file).filter((specifier) => specifier.includes("/__generated__/")),
    );
    expect(generatedImports).not.toEqual([]);
    expect(
      generatedImports.every((specifier) => specifier.startsWith("app/relay/__generated__/")),
    ).toBe(true);
  });

  it("uses shared UI and Relay with product navigation as its only cross-route dependency", () => {
    const imports = routeOwnedDependencyFiles().flatMap(normalizedImports);
    const crossRouteImports = new Set(
      imports.filter(
        (specifier) =>
          specifier.startsWith("app/routes/") && !specifier.startsWith("app/routes/runs/"),
      ),
    );

    expect(crossRouteImports).toEqual(new Set(["app/routes/productNavigation"]));
    expect(imports.some((specifier) => specifier.startsWith("src/ui/"))).toBe(true);
    expect(imports.some((specifier) => specifier.startsWith("app/relay/"))).toBe(true);
  });

  it("requires a shared or runs stylesheet owner for every emitted route dependency class", () => {
    const globalStyles = readFileSync(join(assetsRoot, "src/styles/global.css"), "utf8");
    const runsStyles = readFileSync(join(assetsRoot, "src/styles/runs.css"), "utf8");
    const sharedStyles = readFileSync(join(assetsRoot, "src/styles/shared.css"), "utf8");
    const dependencyFiles = routeDependencyFiles();
    const emittedClasses = dependencyFiles.flatMap((file) =>
      emittedClassNames(readFileSync(file, "utf8"), file),
    );
    const owners = new Set([
      ...stylesheetOwnerClasses(sharedStyles),
      ...stylesheetOwnerClasses(runsStyles),
    ]);

    expect(globalStyles.match(/@import\s+["']\.\/runs\.css["'];/g)).toHaveLength(1);
    expect(emittedClasses).toContain("runs-workspace");
    expect(unownedClassNames(emittedClasses, owners)).toEqual([]);
  });

  it("allows only the route's explicit React, Router, and Relay packages", () => {
    const routeImports = routeOwnedDependencyFiles().flatMap((file) => [
      ...analyzeTypeScript(readFileSync(file, "utf8"), file).moduleSpecifiers,
    ]);

    expect(bareModuleSpecifierOffenders(routeImports, allowedRoutePackages)).toEqual([]);
  });

  it("keeps Tailwind and utility-class conventions out of the project and route", () => {
    const packageSource = readFileSync(join(assetsRoot, "package.json"), "utf8");
    const lockSource = readFileSync(join(assetsRoot, "pnpm-lock.yaml"), "utf8");
    const allStyles = readdirSync(join(assetsRoot, "src/styles"))
      .filter((entry) => entry.endsWith(".css"))
      .map((entry) => readFileSync(join(assetsRoot, "src/styles", entry), "utf8"))
      .join("\n");
    const emittedClasses = routeDependencyFiles().flatMap((file) =>
      emittedClassNames(readFileSync(file, "utf8"), file),
    );
    const tailwindPackage = /(?:^|["'\s/@])(?:@tailwindcss\/[\w-]+|tailwindcss)(?=["'\s/:@]|$)/i;
    const utilityClass =
      /^(?:[a-z]+:)*(?:bg|border|col-span|flex|gap|grid-cols|h|items|justify|m[trblxy]?|max-w|min-h|min-w|p[trblxy]?|rounded|space-[xy]|text|w)-/;

    expect(packageSource).not.toMatch(tailwindPackage);
    expect(lockSource).not.toMatch(tailwindPackage);
    expect(readdirSync(assetsRoot).filter((entry) => /^tailwind\.config\./i.test(entry))).toEqual(
      [],
    );
    expect(allStyles).not.toMatch(/@(apply|tailwind)\b/);
    expect(emittedClasses.filter((className) => utilityClass.test(className))).toEqual([]);
  });

  it("rejects route aliases that target any runs-owned module", () => {
    const source = `
      import { route } from "@react-router/dev/routes";
      export default [
        route("runs", "./routes/runs/route.tsx"),
        route("all-runs", "./routes/runs/route.tsx"),
      ];
    `;

    expect(routeRegistrationOffenders(source, runsRegistration)).toEqual([
      'all-runs targets runs-owned module "./routes/runs/route.tsx"',
    ]);
  });

  it("rejects every emitted class without a shared or runs stylesheet owner", () => {
    const classes = emittedClassNames(
      `export function Fixture() { return <div className="orphan-card" />; }`,
      "fixture.tsx",
    );

    expect(unownedClassNames(classes, new Set(["ui-owned", "runs-owned"]))).toEqual([
      "orphan-card",
    ]);
  });

  it("rejects MUI, Chakra, Ant, Bootstrap, styled-components, and any new bare package", () => {
    const source = `
      import mui from "@mui/material";
      import chakra from "@chakra-ui/react";
      import ant from "antd";
      import bootstrap from "react-bootstrap";
      import styled from "styled-components";
      import unknown from "new-route-framework";
    `;
    const imports = analyzeTypeScript(source).moduleSpecifiers;

    expect(bareModuleSpecifierOffenders(imports, allowedRoutePackages)).toEqual([
      "@chakra-ui/react",
      "@mui/material",
      "antd",
      "new-route-framework",
      "react-bootstrap",
      "styled-components",
    ]);
  });

  it("accepts finite conditional and render-prop class expressions", () => {
    const source = `
      function Fixture({ active, className }: { active: boolean; className?: string }) {
        return (
          <>
            <div className={active ? "state-active" : "state-idle"} />
            <NavLink className={({ isActive }) =>
              isActive ? "nav-item nav-item-active" : "nav-item"
            } />
            <AriaButton
              className={composeRenderProps(className, (className) =>
                ["ui-button", active ? "ui-button-primary" : "ui-button-secondary", className]
                  .filter(Boolean)
                  .join(" ")
              )}
            />
          </>
        );
      }
    `;

    expect(emittedClassNames(source, "fixture.tsx").sort()).toEqual([
      "nav-item",
      "nav-item-active",
      "state-active",
      "state-idle",
      "ui-button",
      "ui-button-primary",
      "ui-button-secondary",
    ]);
  });

  it("traverses finite concatenated and template lazy imports", () => {
    withTemporarySources(
      {
        "entry.tsx": `
          const Concatenated = lazy(() => import("./" + "concatenated"));
          const Templated = lazy(() => import(\`./\${"templated"}\`));
        `,
        "concatenated.tsx": `
          export function Concatenated() {
            return <div className="concatenated-orphan" />;
          }
        `,
        "templated.tsx": `
          import component from "@mui/material";
          export default component;
        `,
      },
      (root) => {
        const files = localDependencyFiles([join(root, "entry.tsx")]);
        const classes = files.flatMap((file) =>
          emittedClassNames(readFileSync(file, "utf8"), file),
        );
        const imports = files.flatMap((file) => [
          ...analyzeTypeScript(readFileSync(file, "utf8"), file).moduleSpecifiers,
        ]);

        expect(files.map((file) => relative(root, file)).sort()).toEqual([
          "concatenated.tsx",
          "entry.tsx",
          "templated.tsx",
        ]);
        expect(classes).toContain("concatenated-orphan");
        expect(bareModuleSpecifierOffenders(imports, allowedRoutePackages)).toContain(
          "@mui/material",
        );
      },
    );
  });

  it("fails closed on non-static and unresolved relative dependencies", () => {
    withTemporarySources(
      {
        "dynamic.tsx": "const Lazy = lazy(() => import(target));",
        "missing-entry.tsx": 'const Lazy = lazy(() => import("./absent"));',
      },
      (root) => {
        expect(() => localDependencyFiles([join(root, "dynamic.tsx")])).toThrowError(
          "Non-static dynamic import",
        );
        expect(() => localDependencyFiles([join(root, "missing-entry.tsx")])).toThrowError(
          "Unable to resolve relative dependency",
        );
      },
    );
  });

  it("collects finite class-bearing JSX spreads", () => {
    const source = `
      function Fixture({ active }: { active: boolean }) {
        return (
          <>
            <Panel {...{ contentClassName: "orphan-card" }} />
            <div {...{ className: active ? "state-active" : "state-idle", role: "status" }} />
          </>
        );
      }
    `;

    expect(emittedClassNames(source, "fixture.tsx").sort()).toEqual([
      "orphan-card",
      "state-active",
      "state-idle",
    ]);
  });

  it("fails closed on unresolved JSX spreads that may conceal class props", () => {
    expect(() =>
      emittedClassNames(
        `function Fixture(props: object) { return <div {...props} />; }`,
        "fixture.tsx",
      ),
    ).toThrowError("Unsupported JSX spread: props");
  });

  it("evaluates static concatenated and template route arguments and still rejects aliases", () => {
    const source = `
      import { route } from "@react-router/dev/routes";
      export default [
        route("ru" + "ns", \`./routes/\${"runs"}/route.tsx\`),
        route("all-" + "runs", "./routes/runs/" + "route.tsx"),
      ];
    `;

    expect(routeRegistrationOffenders(source, runsRegistration)).toEqual([
      'all-runs targets runs-owned module "./routes/runs/route.tsx"',
    ]);
  });

  it("fails closed on non-static route paths and targets", () => {
    expect(
      routeRegistrationOffenders(
        `
          route(routePath, "./routes/runs/route.tsx");
          route("runs", routeTarget);
        `,
        runsRegistration,
      ),
    ).toEqual([
      "route call has a non-static path: routePath",
      "route call has a non-static target: routeTarget",
    ]);
  });
});

const runsRegistration = {
  canonicalPath: "runs",
  ownedModulePrefix: "./routes/runs",
} as const;

function normalizedImports(file: string) {
  const facts = analyzeTypeScript(readFileSync(file, "utf8"), file);
  return [...facts.moduleSpecifiers].map((specifier) =>
    normalizeModuleSpecifier(specifier, file, assetsRoot),
  );
}

function routeDependencyFiles(
  routesSource = readFileSync(join(assetsRoot, "app/routes.ts"), "utf8"),
) {
  return localDependencyFiles([canonicalRouteEntry(routesSource)]);
}

function routeOwnedDependencyFiles(
  routesSource = readFileSync(join(assetsRoot, "app/routes.ts"), "utf8"),
) {
  const ownedPrefix = `${routeRoot}/`;
  return routeDependencyFiles(routesSource).filter(
    (file) => file === routeRoot || file.startsWith(ownedPrefix),
  );
}

function canonicalRouteEntry(routesSource: string) {
  const routeCalls = analyzeTypeScript(routesSource, "routes.ts").stringCallArguments.get("route");
  const target = routeCalls?.find(([path]) => path === runsRegistration.canonicalPath)?.[1];
  if (!target) throw new Error("Canonical runs route is not registered.");

  return resolve(dirname(join(assetsRoot, "app/routes.ts")), target);
}

function treeFiles(path: string): string[] {
  return readdirSync(path).flatMap((entry) => {
    const fullPath = join(path, entry);
    return statSync(fullPath).isDirectory() ? treeFiles(fullPath) : [fullPath];
  });
}

function withTemporarySources(
  sources: Record<string, string>,
  runAssertions: (root: string) => void,
) {
  const root = mkdtempSync(join(tmpdir(), "office-graph-runs-architecture-"));
  try {
    for (const [filename, source] of Object.entries(sources)) {
      writeFileSync(join(root, filename), source);
    }
    runAssertions(root);
  } finally {
    rmSync(root, { force: true, recursive: true });
  }
}
