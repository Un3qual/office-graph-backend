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
import { join, relative } from "node:path";
import * as routeHelpers from "@react-router/dev/routes";
import {
  index as registerIndex,
  layout as registerLayout,
  prefix as registerPrefix,
  relative as relativeRouteHelpers,
  route as registerRoute,
} from "@react-router/dev/routes";
import { describe, expect, it } from "vitest";
import appRouteConfig from "../../routes";
import {
  analyzeRouteConfig,
  analyzeTypeScript,
  bareModuleSpecifierOffenders,
  emittedClassNames,
  localDependencyFiles,
  normalizeModuleSpecifier,
  stylesheetOwnerClasses,
  unownedClassNames,
} from "../architectureTestSupport";

const assetsRoot = process.cwd();
const appDirectory = join(assetsRoot, "app");
const routeRoot = join(appDirectory, "routes/runs");
const allowedRoutePackages = new Set(["react", "react-relay", "react-router"]);
const resolvedAppRouteConfig = await appRouteConfig;

describe("all-runs route architecture", () => {
  it("owns exactly the canonical registered route and keeps generated artifacts outside source", () => {
    const routeFiles = routeOwnedDependencyFiles();

    expect(analyzeRunsRouteConfig(resolvedAppRouteConfig).offenders).toEqual([]);
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
    const emittedClasses = dependencyFiles.flatMap(routeDependencyClassNames);
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
    const emittedClasses = routeDependencyFiles().flatMap(routeDependencyClassNames);
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

  it("rejects absolute runs-owned targets regardless of helper import syntax", () => {
    const absoluteRunsRoute = join(routeRoot, "route.tsx");
    const routes = [
      registerRoute("runs", "./routes/runs/route.tsx"),
      routeHelpers.route("all-" + "runs", absoluteRunsRoute),
    ];

    expect(analyzeRunsRouteConfig(routes).offenders).toEqual([
      `all-runs targets runs-owned module "${absoluteRunsRoute}"`,
    ]);
  });

  it("rejects runs-owned aliases emitted by a reassigned relative-derived registrar", () => {
    let mutableRegistrar = relativeRouteHelpers("app/routes").route;
    mutableRegistrar = registerRoute;
    const wrappedRegistrar = (path: string, file: string) => mutableRegistrar(path, file);
    const routes = [
      registerRoute("runs", "./routes/runs/route.tsx"),
      wrappedRegistrar("all-runs", "./routes/runs/route.tsx"),
    ];

    expect(analyzeRunsRouteConfig(routes).offenders).toEqual([
      `all-runs targets runs-owned module "${join(routeRoot, "route.tsx")}"`,
    ]);
  });

  it("does not accept a prefixed index entry as the canonical runs route", () => {
    const routes = registerPrefix("runs", [registerIndex("./routes/runs/route.tsx")]);

    expect(analyzeRunsRouteConfig(routes).offenders).toEqual([
      "canonical runs route must target one owned module",
      `runs targets runs-owned module "${join(routeRoot, "route.tsx")}"`,
    ]);
  });

  it("accepts official route helpers and nested prefixes alongside the canonical route", () => {
    const routes = [
      registerIndex("./routes/home.tsx"),
      registerLayout("./routes/shell.tsx", [
        ...registerPrefix("admin", [registerRoute("settings", "./routes/settings.tsx")]),
      ]),
      registerRoute("runs", "./routes/runs/route.tsx"),
    ];

    expect(analyzeRunsRouteConfig(routes).offenders).toEqual([]);
  });

  it("analyzes runs-owned modules hidden in official helpers and nesting", () => {
    const routes = [
      registerRoute("runs", "./routes/runs/route.tsx"),
      registerIndex("./routes/runs/index.tsx"),
      registerLayout("./routes/runs/layout.tsx", [
        registerRoute("legacy", "./routes/legacy.tsx", [
          registerRoute("history", "./routes/runs/history.tsx"),
        ]),
        ...registerPrefix("archive", [registerRoute("history", "./routes/runs/archive.tsx")]),
      ]),
    ];

    expect(analyzeRunsRouteConfig(routes).offenders).toEqual([
      `<index> targets runs-owned module "${join(routeRoot, "index.tsx")}"`,
      `<pathless> targets runs-owned module "${join(routeRoot, "layout.tsx")}"`,
      `legacy/history targets runs-owned module "${join(routeRoot, "history.tsx")}"`,
      `archive/history targets runs-owned module "${join(routeRoot, "archive.tsx")}"`,
    ]);
  });

  it("accepts relative-derived helpers and exposes one absolute canonical target", () => {
    const {
      index: registerRelativeIndex,
      layout: registerRelativeLayout,
      prefix: registerRelativePrefix,
      route: registerRelativeRoute,
    } = relativeRouteHelpers("app/routes");
    const routes = [
      registerRelativeIndex("home.tsx"),
      registerRelativeLayout("shell.tsx", [
        ...registerRelativePrefix("admin", [registerRelativeRoute("settings", "settings.tsx")]),
      ]),
      registerRelativeRoute("runs", "runs/route.tsx"),
    ];
    const analysis = analyzeRunsRouteConfig(routes);

    expect(analysis.offenders).toEqual([]);
    expect(analysis.canonicalTarget).toBe(join(routeRoot, "route.tsx"));
    expect(routeOwnedDependencyFiles(routes)).toContain(join(routeRoot, "route.tsx"));
  });

  it("fails closed for invalid resolved route config values", () => {
    expect(analyzeRunsRouteConfig(undefined).offenders).toEqual([
      "resolved route config must be an array of valid route entries",
    ]);
    expect(analyzeRunsRouteConfig([{ path: "runs" }]).offenders).toEqual([
      "resolved route config must be an array of valid route entries",
    ]);
    const invalidEntries = [
      { file: "./routes/runs/route.tsx", id: 42 },
      { file: "./routes/runs/route.tsx", id: "root" },
      { file: "./routes/runs/route.tsx", caseSensitive: "yes" },
      {
        file: "./routes/runs/route.tsx",
        // biome-ignore lint/suspicious/noThenProperty: This fixture must model a promise-like route entry.
        then() {},
        catch() {},
      },
    ];

    for (const entry of invalidEntries) {
      expect
        .soft(analyzeRunsRouteConfig([entry]).offenders)
        .toEqual(["resolved route config must be an array of valid route entries"]);
    }
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

  it("rejects node and absolute module specifiers outside the explicit allowlist", () => {
    const source = `
      import fs from "node:fs";
      import localMachineModule from "/opt/private/local-machine-module.ts";
      import React from "react";
    `;
    const imports = analyzeTypeScript(source).moduleSpecifiers;

    expect(bareModuleSpecifierOffenders(imports, allowedRoutePackages)).toEqual([
      "/opt/private/local-machine-module.ts",
      "node:fs",
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

  it("rejects structurally narrowed spreads that retain wider runtime class props", () => {
    const source = `
      function Fixture(wide: { className?: string; role: string }) {
        const narrow: { role: string } = wide;
        return <div {...narrow} />;
      }
    `;

    expect(() => emittedClassNames(source, "fixture.tsx")).toThrowError(
      "Unsupported JSX spread: narrow",
    );
  });

  it("normalizes dot segments before comparing canonical and owned route targets", () => {
    const routes = [
      registerRoute("runs", "./routes/neighbor/../runs/route.tsx"),
      registerRoute("all-runs", "./routes/runs/../runs/index.tsx"),
    ];

    expect(analyzeRunsRouteConfig(routes).offenders).toEqual([
      `all-runs targets runs-owned module "${join(routeRoot, "index.tsx")}"`,
    ]);
  });
});

const runsRegistration = {
  appDirectory,
  canonicalModule: "./routes/runs/route.tsx",
  canonicalPath: "runs",
  ownedModuleDirectory: "./routes/runs",
} as const;

function normalizedImports(file: string) {
  const facts = analyzeTypeScript(readFileSync(file, "utf8"), file);
  return [...facts.moduleSpecifiers].map((specifier) =>
    normalizeModuleSpecifier(specifier, file, assetsRoot),
  );
}

function routeDependencyClassNames(file: string) {
  const routeOwned = file === routeRoot || file.startsWith(`${routeRoot}/`);
  return emittedClassNames(readFileSync(file, "utf8"), file, {
    unresolvedSpreads: routeOwned ? "reject" : "skip",
  });
}

function analyzeRunsRouteConfig(routeConfig: unknown) {
  return analyzeRouteConfig(routeConfig, runsRegistration);
}

function routeDependencyFiles(routeConfig: unknown = resolvedAppRouteConfig) {
  return localDependencyFiles([canonicalRouteEntry(routeConfig)]);
}

function routeOwnedDependencyFiles(routeConfig: unknown = resolvedAppRouteConfig) {
  const ownedPrefix = `${routeRoot}/`;
  return routeDependencyFiles(routeConfig).filter(
    (file) => file === routeRoot || file.startsWith(ownedPrefix),
  );
}

function canonicalRouteEntry(routeConfig: unknown) {
  const analysis = analyzeRunsRouteConfig(routeConfig);
  if (analysis.offenders.length > 0) {
    throw new Error(`Invalid runs route registration: ${analysis.offenders.join("; ")}`);
  }
  if (!analysis.canonicalTarget) throw new Error("Canonical runs route is not registered.");

  return analysis.canonicalTarget;
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
