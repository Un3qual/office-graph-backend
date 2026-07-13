import { readdirSync, readFileSync, statSync } from "node:fs";
import { dirname, join, relative, resolve } from "node:path";
import ts from "typescript";
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
  /\.graphql$/,
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
  "workflow",
];

describe("shared UI import boundaries", () => {
  it("finds static imports, dynamic imports, re-exports, and Relay tags through the TypeScript AST", () => {
    const source = `
      import value from "./static";
      export { thing } from "./re-export";
      export * from "./star-export";
      const lazy = import("./dynamic");
      const query = graphql\`query TestQuery { node { id } }\`;
      // import ignored from "./comment"
    `;

    expect(moduleSpecifiers(source, "fixture.tsx")).toEqual([
      "./static",
      "./re-export",
      "./star-export",
      "./dynamic",
      "graphql`",
    ]);
  });

  it("rejects normalized relative boundaries and every executable dependency form", () => {
    const source = `
      import relay = require("relay-runtime");
      export * from "./nested/../../../app/relay/environment";
      const literal = import("../../app/" + "relay/fetchGraphQL");
      const template = import(\`../../app/relay/commandMutation\`);
      const unknown = import(runtimeTarget);
      const query = graphql\`query SharedQuery { node { id } }\`;
    `;

    expect(boundaryOffenders(source, join(sharedUiRoot, "fixture.tsx"))).toEqual([
      "relay-runtime",
      "app/relay/environment",
      "app/relay/fetchGraphQL",
      "app/relay/commandMutation",
      "<non-static dynamic import>",
      "graphql`",
    ]);
  });

  it("keeps shared UI independent from routes, Relay documents, and product command logic", () => {
    const offenders = sharedUiSourceFiles().flatMap((file) => {
      const source = readFileSync(file, "utf8");
      return boundaryOffenders(source, file).map(
        (specifier) => `${formatPath(file)} imports ${specifier}`,
      );
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
      "vitest run src/ui/importBoundaries.test.ts app/routes/operator/architecture.test.ts app/routes/packets/architecture.test.ts",
    );
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

export function moduleSpecifiers(source: string, filename: string) {
  const specifiers: string[] = [];
  const sourceFile = ts.createSourceFile(
    filename,
    source,
    ts.ScriptTarget.Latest,
    true,
    filename.endsWith("x") ? ts.ScriptKind.TSX : ts.ScriptKind.TS,
  );

  const addStaticSpecifier = (node: ts.Expression | undefined, failClosed = false) => {
    const specifier = node ? staticStringValue(node) : null;
    if (specifier !== null) {
      specifiers.push(specifier);
    } else if (failClosed) {
      specifiers.push("<non-static dynamic import>");
    }
  };

  const visit = (node: ts.Node) => {
    if (ts.isImportDeclaration(node) || ts.isExportDeclaration(node)) {
      addStaticSpecifier(node.moduleSpecifier);
    } else if (ts.isCallExpression(node) && node.expression.kind === ts.SyntaxKind.ImportKeyword) {
      addStaticSpecifier(node.arguments[0], true);
    } else if (
      ts.isImportEqualsDeclaration(node) &&
      ts.isExternalModuleReference(node.moduleReference)
    ) {
      addStaticSpecifier(node.moduleReference.expression);
    } else if (
      ts.isTaggedTemplateExpression(node) &&
      ts.isIdentifier(node.tag) &&
      node.tag.text === "graphql"
    ) {
      specifiers.push("graphql`");
    }

    ts.forEachChild(node, visit);
  };

  visit(sourceFile);

  return specifiers;
}

export function boundaryOffenders(source: string, filename: string) {
  return moduleSpecifiers(source, filename)
    .map((specifier) => normalizeSpecifier(specifier, filename))
    .filter(
      (specifier) =>
        specifier === "graphql`" ||
        specifier === "<non-static dynamic import>" ||
        forbiddenImportPatterns.some((pattern) => pattern.test(specifier)),
    );
}

function staticStringValue(expression: ts.Expression): string | null {
  if (ts.isStringLiteralLike(expression)) {
    return expression.text;
  }

  if (ts.isParenthesizedExpression(expression)) {
    return staticStringValue(expression.expression);
  }

  if (
    ts.isBinaryExpression(expression) &&
    expression.operatorToken.kind === ts.SyntaxKind.PlusToken
  ) {
    const left = staticStringValue(expression.left);
    const right = staticStringValue(expression.right);
    return left === null || right === null ? null : left + right;
  }

  return null;
}

function normalizeSpecifier(specifier: string, filename: string) {
  if (!specifier.startsWith(".")) return specifier;

  return relative(assetsRoot, resolve(dirname(filename), specifier)).replaceAll("\\", "/");
}

function formatPath(path: string) {
  return relative(assetsRoot, path);
}
