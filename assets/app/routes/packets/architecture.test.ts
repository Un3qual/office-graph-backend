import { existsSync, readdirSync, readFileSync, statSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { describe, expect, it } from "vitest";
import {
  analyzeTypeScript,
  emittedClassNames as classNames,
  localDependencyFiles,
  stylesheetOwnerClasses as stylesheetClassesFromSource,
} from "../architectureTestSupport";

const assetsRoot = process.cwd();
const routeRoot = join(process.cwd(), "app/routes/packets");

describe("packet route data architecture", () => {
  it("keeps the packet query and product state owned by the route", () => {
    const workflowSource = readFileSync(join(routeRoot, "workflow.ts"), "utf8");
    const routeSource = sourceFiles(routeRoot)
      .map((file) => readFileSync(file, "utf8"))
      .join("\n");
    const routeFacts = analyzeTypeScript(routeSource, "packet-route.tsx");
    const workflowFacts = analyzeTypeScript(workflowSource, "workflow.ts");

    expect(existsSync(join(process.cwd(), "src/packets"))).toBe(false);
    expect(routeFacts.graphqlParseErrors).toEqual([]);
    expect(routeFacts.graphqlOperations).toContain("PacketsRouteQuery");
    expect(routeFacts.graphqlFields).toContain("listWorkPackets");
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
    expect(routeFacts.moduleSpecifiers).not.toContain("<non-static dynamic import>");
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

  it("does not import presentation internals from sibling product routes", () => {
    const siblingRouteImports = sourceFiles(routeRoot).flatMap((file) => {
      const source = readFileSync(file, "utf8");

      return [...analyzeTypeScript(source, file).moduleSpecifiers]
        .filter((specifier) => specifier.startsWith("."))
        .map((specifier) => resolve(dirname(file), specifier).replaceAll("\\", "/"))
        .filter(
          (specifier) =>
            specifier.includes("/app/routes/operator/") || specifier.includes("/app/routes/runs/"),
        );
    });

    expect(siblingRouteImports).toEqual([]);
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

    expect(commandsFacts.graphqlParseErrors).toEqual([]);
    expect(commandsFacts.graphqlOperations).toContain("PacketsCreateWorkPacketMutation");
    expect(commandsFacts.graphqlOperations).toContain("PacketsCreateWorkPacketVersionMutation");
    expect(commandsFacts.graphqlOperations).toContain("PacketsStartWorkRunMutation");
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

function sourceFiles(path: string): string[] {
  return readdirSync(path).flatMap((entry) => {
    const fullPath = join(path, entry);
    const stats = statSync(fullPath);

    if (stats.isDirectory()) return sourceFiles(fullPath);

    return /\.(ts|tsx)$/.test(entry) && !/\.test\.(ts|tsx)$/.test(entry) ? [fullPath] : [];
  });
}

function stylesheetClasses(relativePath: string) {
  const styles = readFileSync(join(assetsRoot, relativePath), "utf8");
  return stylesheetClassesFromSource(styles);
}
