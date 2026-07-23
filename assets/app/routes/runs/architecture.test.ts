import { existsSync, readdirSync, readFileSync, statSync } from "node:fs";
import { dirname, join, relative, resolve } from "node:path";
import ts from "typescript";
import { describe, expect, it } from "vitest";
import { analyzeTypeScript } from "../architectureTestSupport";

const assetsRoot = process.cwd();
const routeRoot = join(assetsRoot, "app/routes/runs");

describe("all-runs route architecture", () => {
  it("owns the canonical registered route and keeps generated artifacts outside route source", () => {
    const routeCalls = analyzeTypeScript(
      readFileSync(join(assetsRoot, "app/routes.ts"), "utf8"),
      "routes.ts",
    ).stringCallArguments.get("route");
    const registeredRunsRoutes = routeCalls?.filter(([path]) => path === "runs") ?? [];

    expect(existsSync(join(routeRoot, "route.tsx"))).toBe(true);
    expect(existsSync(join(routeRoot, "RunWorkspace.tsx"))).toBe(true);
    expect(existsSync(join(routeRoot, "components/RunList.tsx"))).toBe(true);
    expect(existsSync(join(routeRoot, "components/RunDetail.tsx"))).toBe(true);
    expect(existsSync(join(routeRoot, "components/RunsLayout.tsx"))).toBe(true);
    expect(registeredRunsRoutes).toEqual([["runs", "./routes/runs/route.tsx"]]);
    expect(existsSync(join(routeRoot, "__generated__"))).toBe(false);

    const generatedImports = productionSourceFiles(routeRoot).flatMap((file) =>
      normalizedImports(file).filter((specifier) => specifier.includes("/__generated__/")),
    );
    expect(generatedImports).not.toEqual([]);
    expect(
      generatedImports.every((specifier) => specifier.startsWith("app/relay/__generated__/")),
    ).toBe(true);
  });

  it("uses shared UI and Relay without importing operator or packet route internals", () => {
    const imports = productionSourceFiles(routeRoot).flatMap((file) =>
      normalizedImports(file).map((specifier) => [relative(assetsRoot, file), specifier] as const),
    );
    const crossRouteImports = imports.filter(
      ([, specifier]) =>
        specifier.startsWith("app/routes/") && !specifier.startsWith("app/routes/runs/"),
    );

    expect(crossRouteImports).toEqual([
      ["app/routes/runs/components/RunsLayout.tsx", "app/routes/productNavigation"],
    ]);
    expect(imports.some(([, specifier]) => specifier.startsWith("src/ui/"))).toBe(true);
    expect(imports.some(([, specifier]) => specifier.startsWith("app/relay/"))).toBe(true);
    expect(
      imports.filter(
        ([, specifier]) =>
          specifier.startsWith("app/routes/operator/") ||
          specifier.startsWith("app/routes/packets/"),
      ),
    ).toEqual([]);
  });

  it("owns route styles through global runs.css without borrowing route-specific styles", () => {
    const globalStyles = readFileSync(join(assetsRoot, "src/styles/global.css"), "utf8");
    const runsStyles = readFileSync(join(assetsRoot, "src/styles/runs.css"), "utf8");
    const sharedStyles = readFileSync(join(assetsRoot, "src/styles/shared.css"), "utf8");
    const operatorStyles = readFileSync(join(assetsRoot, "src/styles/operator.css"), "utf8");
    const packetStyles = readFileSync(join(assetsRoot, "src/styles/packets.css"), "utf8");
    const routeClasses = productionSourceFiles(routeRoot).flatMap((file) =>
      staticClassNames(readFileSync(file, "utf8"), file),
    );
    const runsClasses = stylesheetClasses(runsStyles);
    const sharedClasses = stylesheetClasses(sharedStyles);
    const operatorOnly = setDifference(stylesheetClasses(operatorStyles), sharedClasses);
    const packetOnly = setDifference(stylesheetClasses(packetStyles), sharedClasses);

    expect(globalStyles.match(/@import\s+["']\.\/runs\.css["'];/g)).toHaveLength(1);
    expect(routeClasses.filter((className) => className.startsWith("runs-"))).not.toEqual([]);
    expect(
      routeClasses.filter(
        (className) =>
          !runsClasses.has(className) &&
          !sharedClasses.has(className) &&
          (operatorOnly.has(className) || packetOnly.has(className)),
      ),
    ).toEqual([]);
    expect(
      routeClasses.filter(
        (className) =>
          className.startsWith("runs-") &&
          !runsClasses.has(className) &&
          !sharedClasses.has(className),
      ),
    ).toEqual([]);
  });

  it("does not add Tailwind, dependent UI libraries, utility classes, or a route framework", () => {
    const packageJson = JSON.parse(readFileSync(join(assetsRoot, "package.json"), "utf8")) as {
      dependencies?: Record<string, string>;
      devDependencies?: Record<string, string>;
    };
    const dependencies = Object.keys({
      ...packageJson.dependencies,
      ...packageJson.devDependencies,
    });
    const routeImports = productionSourceFiles(routeRoot).flatMap(normalizedImports);
    const routeClasses = productionSourceFiles(routeRoot).flatMap((file) =>
      staticClassNames(readFileSync(file, "utf8"), file),
    );
    const forbiddenDependency =
      /(?:^|[-/@])(tailwind|daisyui|flowbite|headlessui|heroicons|shadcn|twind)(?:[-/@]|$)/i;
    const utilityClass =
      /^(?:[a-z]+:)*(?:bg|border|col-span|flex|gap|grid-cols|h|items|justify|m[trblxy]?|max-w|min-h|min-w|p[trblxy]?|rounded|space-[xy]|text|w)-/;
    const styles = readFileSync(join(assetsRoot, "src/styles/runs.css"), "utf8");

    expect(dependencies.filter((dependency) => forbiddenDependency.test(dependency))).toEqual([]);
    expect(routeImports.filter((specifier) => forbiddenDependency.test(specifier))).toEqual([]);
    expect(routeClasses.filter((className) => utilityClass.test(className))).toEqual([]);
    expect(styles).not.toMatch(/@(apply|tailwind)\b/);
  });
});

function productionSourceFiles(path: string): string[] {
  return readdirSync(path).flatMap((entry) => {
    const fullPath = join(path, entry);
    const stats = statSync(fullPath);
    if (stats.isDirectory()) return productionSourceFiles(fullPath);
    return /\.(ts|tsx)$/.test(entry) && !/\.test\.(ts|tsx)$/.test(entry) ? [fullPath] : [];
  });
}

function normalizedImports(file: string) {
  const facts = analyzeTypeScript(readFileSync(file, "utf8"), file);
  return [...facts.moduleSpecifiers].map((specifier) =>
    specifier.startsWith(".")
      ? relative(assetsRoot, resolve(dirname(file), specifier)).replaceAll("\\", "/")
      : specifier,
  );
}

function staticClassNames(source: string, filename: string) {
  const sourceFile = ts.createSourceFile(
    filename,
    source,
    ts.ScriptTarget.Latest,
    true,
    filename.endsWith("x") ? ts.ScriptKind.TSX : ts.ScriptKind.TS,
  );
  const classes = new Set<string>();

  const visit = (node: ts.Node) => {
    const attributeName = ts.isJsxAttribute(node) ? node.name.getText(sourceFile) : null;
    if (
      ts.isJsxAttribute(node) &&
      (attributeName === "className" || attributeName?.endsWith("ClassName"))
    ) {
      const initializer = node.initializer;
      if (!initializer) throw new Error(`Missing className initializer in ${filename}`);

      if (ts.isStringLiteral(initializer)) {
        for (const className of initializer.text.split(/\s+/)) classes.add(className);
      } else {
        throw new Error(`All-runs className must be a static string in ${filename}`);
      }
    }

    ts.forEachChild(node, visit);
  };

  visit(sourceFile);
  return [...classes];
}

function stylesheetClasses(source: string) {
  return new Set([...source.matchAll(/\.([a-z_][\w-]*)/gi)].map((match) => match[1]));
}

function setDifference(values: Set<string>, excluded: Set<string>) {
  return new Set([...values].filter((value) => !excluded.has(value)));
}
