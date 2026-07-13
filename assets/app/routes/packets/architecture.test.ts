import { existsSync, readdirSync, readFileSync, statSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import ts from "typescript";
import { describe, expect, it } from "vitest";
import { analyzeTypeScript } from "../architectureTestSupport";

const assetsRoot = process.cwd();
const routeRoot = join(process.cwd(), "app/routes/packets");

describe("packet route data architecture", () => {
  it("keeps the packet query and product state owned by the route", () => {
    const dataSource = readFileSync(join(routeRoot, "data.ts"), "utf8");
    const workflowSource = readFileSync(join(routeRoot, "workflow.ts"), "utf8");
    const routeSource = `${dataSource}\n${workflowSource}`;
    const routeFacts = analyzeTypeScript(routeSource, "packet-route.tsx");
    const workflowFacts = analyzeTypeScript(workflowSource, "workflow.ts");
    const graphqlDocuments = routeFacts.graphqlDocuments.join("\n");

    expect(existsSync(join(process.cwd(), "src/packets"))).toBe(false);
    expect(graphqlDocuments).toContain("query PacketsRouteQuery");
    expect(graphqlDocuments).toContain("listWorkPackets");
    expect(workflowFacts.identifiers).toContain("usePacketsWorkflow");
    expect(workflowFacts.identifiers).toContain("useLazyLoadQuery");
    expect([...workflowFacts.identifiers]).toEqual(
      expect.not.arrayContaining([
        "useRelayEnvironment",
        "fetchQuery",
        "QueryState",
        "unsubscribe",
        "useEffect",
      ]),
    );
    expect(routeFacts.moduleSpecifiers).not.toContain("@tanstack/react-query");
    expect([...routeFacts.identifiers]).toEqual(
      expect.not.arrayContaining(["GraphQLFetcher", "fetchGraphQL"]),
    );
    expect([...routeFacts.stringLiterals].some((value) => value.startsWith("/api/"))).toBe(false);
  });

  it("keeps generated Relay types explicit at the route workflow boundary", () => {
    const typesSource = readFileSync(join(routeRoot, "types.ts"), "utf8");
    const workflowSource = readFileSync(join(routeRoot, "workflow.ts"), "utf8");
    const typesFacts = analyzeTypeScript(typesSource, "types.ts");
    const workflowFacts = analyzeTypeScript(workflowSource, "workflow.ts");

    expect([...typesFacts.moduleSpecifiers].some((value) => value.includes("__generated__"))).toBe(
      false,
    );
    expect(typesFacts.identifiers).not.toContain("Fragment$data");
    expect(typesFacts.stringLiterals).not.toContain(" $fragmentType");
    expect(workflowFacts.identifiers).toContain("PacketsRoutePacketFragment$data");
    expect(workflowFacts.identifiers).toContain("PacketsRouteOperation");
  });

  it("keeps only consumed fields in the packet connection view model", () => {
    const typesSource = readFileSync(join(routeRoot, "types.ts"), "utf8");
    const properties = analyzeTypeScript(typesSource, "types.ts").typeProperties.get(
      "PacketConnection",
    );

    expect(properties).toEqual(
      new Map([
        ["hasNextPage", "boolean"],
        ["nextCursor", "string | null"],
        ["rows", "TPacket[]"],
      ]),
    );
  });

  it("keeps the registered packet workspace and product UI owned by the route", () => {
    const routesSource = readFileSync(join(process.cwd(), "app/routes.ts"), "utf8");
    const routeCalls = analyzeTypeScript(routesSource, "routes.ts").stringCallArguments.get(
      "route",
    );

    expect(existsSync(join(routeRoot, "route.tsx"))).toBe(true);
    expect(existsSync(join(routeRoot, "PacketWorkspace.tsx"))).toBe(true);
    expect(existsSync(join(routeRoot, "components/PacketList.tsx"))).toBe(true);
    expect(existsSync(join(routeRoot, "components/PacketDetail.tsx"))).toBe(true);
    expect(existsSync(join(routeRoot, "components/PacketsLayout.tsx"))).toBe(true);
    expect(routeCalls).toContainEqual(["packets", "./routes/packets/route.tsx"]);
  });

  it("shares one route-local updated-at formatter across packet list and detail", () => {
    const formatterPath = join(routeRoot, "formatters.ts");
    const packetListSource = readFileSync(join(routeRoot, "components/PacketList.tsx"), "utf8");
    const packetDetailSource = readFileSync(join(routeRoot, "components/PacketDetail.tsx"), "utf8");

    expect(existsSync(formatterPath)).toBe(true);

    const formatterSource = readFileSync(formatterPath, "utf8");
    const packetListFacts = analyzeTypeScript(packetListSource, "PacketList.tsx");
    const packetDetailFacts = analyzeTypeScript(packetDetailSource, "PacketDetail.tsx");

    expect(analyzeTypeScript(formatterSource, "formatters.ts").identifiers).toContain(
      "DateTimeFormat",
    );
    expect(packetListFacts.moduleSpecifiers).toContain("../formatters");
    expect(packetDetailFacts.moduleSpecifiers).toContain("../formatters");
    expect(packetListFacts.identifiers).not.toContain("DateTimeFormat");
    expect(packetDetailFacts.identifiers).not.toContain("DateTimeFormat");
  });

  it("shares one route-local lifecycle-state formatter across packet list and detail", () => {
    const formatterSource = readFileSync(join(routeRoot, "formatters.ts"), "utf8");
    const packetListSource = readFileSync(join(routeRoot, "components/PacketList.tsx"), "utf8");
    const packetDetailSource = readFileSync(join(routeRoot, "components/PacketDetail.tsx"), "utf8");
    const formatterFacts = analyzeTypeScript(formatterSource, "formatters.ts");
    const packetListFacts = analyzeTypeScript(packetListSource, "PacketList.tsx");
    const packetDetailFacts = analyzeTypeScript(packetDetailSource, "PacketDetail.tsx");

    expect(formatterFacts.identifiers).toContain("formatPacketState");
    expect(packetListFacts.identifiers).toContain("formatPacketState");
    expect(packetDetailFacts.identifiers).toContain("formatPacketState");
    expect(packetListFacts.identifiers).not.toContain("formatState");
    expect(packetDetailFacts.identifiers).not.toContain("formatState");
  });

  it("keeps packet mutation documents and lifecycle wrappers route-owned", () => {
    const commandsPath = join(routeRoot, "commands.ts");
    const workflowPath = join(routeRoot, "commandWorkflow.ts");

    expect(existsSync(commandsPath)).toBe(true);
    expect(existsSync(workflowPath)).toBe(true);

    const commandsSource = readFileSync(commandsPath, "utf8");
    const workflowSource = readFileSync(workflowPath, "utf8");
    const commandsFacts = analyzeTypeScript(commandsSource, "commands.ts");
    const workflowFacts = analyzeTypeScript(workflowSource, "commandWorkflow.ts");

    const graphqlDocuments = commandsFacts.graphqlDocuments.join("\n");
    expect(graphqlDocuments).toContain("mutation PacketsCreateWorkPacketMutation");
    expect(graphqlDocuments).toContain("mutation PacketsCreateWorkPacketVersionMutation");
    expect(graphqlDocuments).toContain("mutation PacketsStartWorkRunMutation");
    expect(workflowFacts.identifiers).toContain("useCommandMutation");
    expect(workflowFacts.identifiers).not.toContain("fetchGraphQL");
    expect([...workflowFacts.stringLiterals].some((value) => value.startsWith("/api/"))).toBe(
      false,
    );
  });

  it("does not depend on operator-owned styles through shared components", () => {
    const packetDependencies = localDependencyFiles(sourceFiles(routeRoot));
    const consumedClasses = new Set(
      packetDependencies.flatMap((file) => classNames(readFileSync(file, "utf8"), file)),
    );
    const sharedClasses = stylesheetClasses("src/styles/shared.css");
    const operatorClasses = stylesheetClasses("src/styles/operator.css");
    const packetClasses = stylesheetClasses("src/styles/packets.css");

    const operatorOnlyDependencies = [...consumedClasses]
      .filter(
        (className) =>
          operatorClasses.has(className) &&
          !sharedClasses.has(className) &&
          !packetClasses.has(className),
      )
      .sort();
    const duplicatedSharedClasses = [...sharedClasses]
      .filter((className) => operatorClasses.has(className) || packetClasses.has(className))
      .sort();

    expect(operatorOnlyDependencies).toEqual([]);
    expect(duplicatedSharedClasses).toEqual([]);
  });

  it("collects Button's explicit finite emitted classes", () => {
    const buttonPath = join(assetsRoot, "src/ui/Button.tsx");
    const buttonClasses = classNames(readFileSync(buttonPath, "utf8"), buttonPath);

    expect(buttonClasses).toEqual(
      expect.arrayContaining(["ui-button", "ui-button-primary", "ui-button-secondary"]),
    );
  });

  it("fails closed when a generated class has an unbounded template span", () => {
    const source = `
      function DynamicClass({ suffix }: { suffix: string }) {
        return <div className={\`ui-\${suffix}\`} />;
      }
    `;

    expect(() => classNames(source, "dynamic-class.tsx")).toThrowError(
      "Unsupported dynamic className template span: suffix",
    );
  });

  it("rejects local identifier indirection in a className initializer", () => {
    const source = `
      function LocalClass({ primary }: { primary: boolean }) {
        const buttonClass = primary ? "ui-button-primary" : "ui-button-secondary";
        return <button className={buttonClass} />;
      }
    `;

    expect(() => classNames(source, "local-class.tsx")).toThrowError(
      "Unsupported className expression: buttonClass",
    );
  });

  it("allows caller-supplied classes through a destructured ClassName prop", () => {
    const source = `
      function Shell({ contentClassName }: { contentClassName: string }) {
        return <div className={contentClassName} />;
      }

      function Caller() {
        return <Shell contentClassName="packet-workspace" />;
      }
    `;

    expect(classNames(source, "class-name-prop.tsx")).toEqual(["packet-workspace"]);
  });

  it("does not borrow a className pass-through binding from another function", () => {
    const source = `
      function PassThrough({ className }: { className: string }) {
        return <div className={className} />;
      }

      function Local() {
        const className = "operator-only";
        return <div className={className} />;
      }
    `;

    expect(() => classNames(source, "lexical-class-name.tsx")).toThrowError(
      "Unsupported className expression: className",
    );
  });

  it("fails closed when any conditional template branch is unbounded", () => {
    const source = `
      function DynamicClass({ active, suffix }: { active: boolean; suffix: string }) {
        return <div className={\`ui-\${active ? "active" : suffix}\`} />;
      }
    `;

    expect(() => classNames(source, "conditional-class.tsx")).toThrowError(
      'Unsupported dynamic className template span: active ? "active" : suffix',
    );
  });

  it("distinguishes stylesheet owners from scoped class references", () => {
    const owners = stylesheetClassesFromSource(`
      .packet-command-card .ui-form-feedback { margin-top: 8px; }
      .packet-command-card { display: grid; }
      .ui-owning-control[data-kind="error"] { color: red; }
    `);

    expect([...owners].sort()).toEqual(["packet-command-card", "ui-owning-control"]);
  });
});

function localDependencyFiles(entries: string[]) {
  const pending = [...entries];
  const visited = new Set<string>();

  while (pending.length > 0) {
    const file = pending.pop();
    if (!file || visited.has(file)) continue;

    visited.add(file);
    const source = readFileSync(file, "utf8");

    for (const { fileName } of ts.preProcessFile(source, true, true).importedFiles) {
      if (!fileName.startsWith(".")) continue;

      const dependency = resolveSourceFile(resolve(dirname(file), fileName));
      if (dependency && !visited.has(dependency)) pending.push(dependency);
    }
  }

  return [...visited];
}

function sourceFiles(path: string): string[] {
  return readdirSync(path).flatMap((entry) => {
    const fullPath = join(path, entry);
    const stats = statSync(fullPath);

    if (stats.isDirectory()) return sourceFiles(fullPath);

    return /\.(ts|tsx)$/.test(entry) && !/\.test\.(ts|tsx)$/.test(entry) ? [fullPath] : [];
  });
}

function resolveSourceFile(path: string) {
  for (const candidate of [
    path,
    `${path}.ts`,
    `${path}.tsx`,
    join(path, "index.ts"),
    join(path, "index.tsx"),
  ]) {
    if (existsSync(candidate)) return candidate;
  }

  return null;
}

function classNames(source: string, filename: string) {
  const sourceFile = ts.createSourceFile(
    filename,
    source,
    ts.ScriptTarget.Latest,
    true,
    filename.endsWith("x") ? ts.ScriptKind.TSX : ts.ScriptKind.TS,
  );
  const names = new Set<string>();

  const addTokens = (value: string) => {
    for (const token of value.split(/\s+/)) {
      if (/^[a-z][\w-]*$/i.test(token)) names.add(token);
    }
  };

  const collectExpression = (expression: ts.Expression, passThrough = new Set<string>()) => {
    if (ts.isStringLiteralLike(expression)) {
      addTokens(expression.text);
      return;
    }

    if (ts.isTemplateExpression(expression)) {
      for (const value of finiteTemplateValues(expression, sourceFile)) addTokens(value);
      return;
    }

    if (ts.isConditionalExpression(expression)) {
      collectExpression(expression.whenTrue, passThrough);
      collectExpression(expression.whenFalse, passThrough);
      return;
    }

    if (ts.isArrowFunction(expression) && !ts.isBlock(expression.body)) {
      const arrowPassThrough = new Set(passThrough);
      for (const parameter of expression.parameters) {
        if (ts.isIdentifier(parameter.name)) arrowPassThrough.add(parameter.name.text);
      }
      collectExpression(expression.body, arrowPassThrough);
      return;
    }

    if (ts.isArrayLiteralExpression(expression)) {
      for (const element of expression.elements) {
        if (ts.isSpreadElement(element)) unsupportedClassExpression(element, sourceFile);
        collectExpression(element, passThrough);
      }
      return;
    }

    if (ts.isParenthesizedExpression(expression)) {
      collectExpression(expression.expression, passThrough);
      return;
    }

    if (ts.isIdentifier(expression)) {
      if (expression.text === "undefined" || passThrough.has(expression.text)) {
        return;
      }
      unsupportedClassExpression(expression, sourceFile);
    }

    if (expression.kind === ts.SyntaxKind.NullKeyword) return;

    if (ts.isCallExpression(expression)) {
      if (
        ts.isIdentifier(expression.expression) &&
        expression.expression.text === "composeRenderProps" &&
        expression.arguments.length === 2 &&
        ts.isIdentifier(expression.arguments[0]) &&
        passThrough.has(expression.arguments[0].text) &&
        ts.isArrowFunction(expression.arguments[1])
      ) {
        collectExpression(expression.arguments[1], passThrough);
        return;
      }

      if (
        ts.isPropertyAccessExpression(expression.expression) &&
        expression.expression.name.text === "filter" &&
        expression.arguments.length === 1 &&
        ts.isIdentifier(expression.arguments[0]) &&
        expression.arguments[0].text === "Boolean"
      ) {
        collectExpression(expression.expression.expression, passThrough);
        return;
      }

      if (
        ts.isPropertyAccessExpression(expression.expression) &&
        expression.expression.name.text === "join" &&
        expression.arguments.length === 1 &&
        ts.isStringLiteralLike(expression.arguments[0]) &&
        expression.arguments[0].text === " "
      ) {
        collectExpression(expression.expression.expression, passThrough);
        return;
      }
    }

    unsupportedClassExpression(expression, sourceFile);
  };

  walk(sourceFile, (node) => {
    const attributeName = ts.isJsxAttribute(node) ? node.name.getText(sourceFile) : null;

    if (
      ts.isJsxAttribute(node) &&
      (attributeName === "className" || attributeName?.endsWith("ClassName")) &&
      node.initializer
    ) {
      if (ts.isStringLiteral(node.initializer)) {
        addTokens(node.initializer.text);
      } else if (ts.isJsxExpression(node.initializer) && node.initializer.expression) {
        collectExpression(node.initializer.expression, destructuredClassNameParameters(node));
      } else {
        throw new Error(`Unsupported ${attributeName} initializer in ${filename}`);
      }
    }
  });

  return [...names];
}

function finiteTemplateValues(template: ts.TemplateExpression, sourceFile: ts.SourceFile) {
  let values = [template.head.text];

  for (const span of template.templateSpans) {
    if (!ts.isConditionalExpression(span.expression)) {
      throw new Error(
        `Unsupported dynamic className template span: ${span.expression.getText(sourceFile)}`,
      );
    }

    const spanValues = [span.expression.whenTrue, span.expression.whenFalse].flatMap((branch) =>
      ts.isStringLiteralLike(branch) ? [branch.text] : [],
    );
    if (spanValues.length !== 2) {
      throw new Error(
        `Unsupported dynamic className template span: ${span.expression.getText(sourceFile)}`,
      );
    }

    values = values.flatMap((prefix) =>
      spanValues.map((spanValue) => `${prefix}${spanValue}${span.literal.text}`),
    );
  }

  return values;
}

function destructuredClassNameParameters(node: ts.Node) {
  let current = node.parent;
  while (current && !ts.isFunctionLike(current)) current = current.parent;

  const parameters = new Set<string>();
  for (const parameter of current?.parameters ?? []) {
    if (!ts.isObjectBindingPattern(parameter.name)) continue;

    for (const binding of parameter.name.elements) {
      if (
        ts.isIdentifier(binding.name) &&
        (binding.name.text === "className" || binding.name.text.endsWith("ClassName"))
      ) {
        parameters.add(binding.name.text);
      }
    }
  }

  return parameters;
}

function unsupportedClassExpression(expression: ts.Node, sourceFile: ts.SourceFile): never {
  throw new Error(`Unsupported className expression: ${expression.getText(sourceFile)}`);
}

function walk(node: ts.Node, visit: (node: ts.Node) => void) {
  visit(node);
  ts.forEachChild(node, (child) => walk(child, visit));
}

function stylesheetClasses(relativePath: string) {
  const styles = readFileSync(join(assetsRoot, relativePath), "utf8");
  return stylesheetClassesFromSource(styles);
}

function stylesheetClassesFromSource(styles: string) {
  const withoutComments = styles.replace(/\/\*[\s\S]*?\*\//g, "");
  const owners = new Set<string>();

  for (const match of withoutComments.matchAll(/(?:^|[{}])\s*([^@{}\s][^{}]*?)\s*\{/g)) {
    const selectorList = match[1];
    for (const selector of selectorList.split(",")) {
      const owner = selector.match(/\.([a-z_][\w-]*)/i)?.[1];
      if (owner) owners.add(owner);
    }
  }

  return owners;
}
