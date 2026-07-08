import { readdirSync, readFileSync, statSync } from "node:fs";
import { join, relative } from "node:path";
import { describe, expect, it } from "vitest";

const assetsRoot = process.cwd();
const sharedUiRoot = join(assetsRoot, "src/ui");
const packageJsonPath = join(assetsRoot, "package.json");

const forbiddenImportPatterns = [
  /(?:^|\/)app\/routes(?:\/|$)/,
  /(?:^|\/)routes\/operator(?:\/|$)/,
  /(?:^|\/)__generated__(?:\/|$)/,
  /(?:^|\/)app\/relay(?:\/|$)/,
  /^react-relay$/,
  /^relay-runtime$/,
  /\.graphql$/
];

const forbiddenVocabulary = [
  "affordance",
  "affordances",
  "command",
  "commands",
  "evidence",
  "operator",
  "packet",
  "packets",
  "policy",
  "readiness",
  "run",
  "runs",
  "verification",
  "workflow"
];

describe("shared UI import boundaries", () => {
  it("keeps shared UI independent from routes, Relay documents, and product command logic", () => {
    const offenders = sharedUiSourceFiles().flatMap((file) => {
      const source = readFileSync(file, "utf8");
      const imports = importSpecifiers(source);

      return imports
        .filter((specifier) => forbiddenImportPatterns.some((pattern) => pattern.test(specifier)))
        .map((specifier) => `${formatPath(file)} imports ${specifier}`);
    });

    expect(offenders).toEqual([]);
  });

  it("keeps shared UI product-vocabulary-free", () => {
    const forbiddenTerms = new RegExp(`\\b(${forbiddenVocabulary.join("|")})\\b`, "i");
    const offenders = sharedUiSourceFiles().flatMap((file) => {
      const source = readFileSync(file, "utf8");
      const matches = source.match(forbiddenTerms);

      return matches ? [`${formatPath(file)} contains product vocabulary "${matches[0]}"`] : [];
    });

    expect(offenders).toEqual([]);
  });

  it("runs import-boundary checks during frontend verification", () => {
    const packageJson = JSON.parse(readFileSync(packageJsonPath, "utf8")) as {
      scripts: Record<string, string>;
    };

    expect(packageJson.scripts["verify:import-boundaries"]).toBe(
      "vitest run src/ui/importBoundaries.test.ts app/routes/operator/architecture.test.ts"
    );
    expect(packageJson.scripts.verify).toContain("pnpm run verify:import-boundaries");
  });
});

function sharedUiSourceFiles() {
  return sourceFiles(sharedUiRoot);
}

function sourceFiles(path: string): string[] {
  return readdirSync(path).flatMap((entry) => {
    const fullPath = join(path, entry);
    const stats = statSync(fullPath);

    if (stats.isDirectory()) {
      return sourceFiles(fullPath);
    }

    return /\.(ts|tsx)$/.test(entry) && !/\.test\.(ts|tsx)$/.test(entry) ? [fullPath] : [];
  });
}

function importSpecifiers(source: string) {
  const specifiers: string[] = [];
  const importPattern = /import\s+(?:type\s+)?(?:[^"']+\s+from\s+)?["']([^"']+)["']/g;

  for (const match of source.matchAll(importPattern)) {
    specifiers.push(match[1]);
  }

  if (source.includes("graphql`")) {
    specifiers.push("graphql`");
  }

  return specifiers;
}

function formatPath(path: string) {
  return relative(assetsRoot, path);
}
