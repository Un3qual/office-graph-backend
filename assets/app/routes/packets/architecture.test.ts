import { existsSync, readdirSync, readFileSync, statSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import ts from "typescript";
import { describe, expect, it } from "vitest";

const assetsRoot = process.cwd();
const routeRoot = join(process.cwd(), "app/routes/packets");

describe("packet route data architecture", () => {
  it("keeps the packet query and product state owned by the route", () => {
    const dataSource = readFileSync(join(routeRoot, "data.ts"), "utf8");
    const workflowSource = readFileSync(join(routeRoot, "workflow.ts"), "utf8");
    const routeSource = `${dataSource}\n${workflowSource}`;

    expect(existsSync(join(process.cwd(), "src/packets"))).toBe(false);
    expect(dataSource).toContain("PacketsRouteQuery");
    expect(dataSource).toContain("listWorkPackets");
    expect(workflowSource).toContain("usePacketsWorkflow");
    expect(workflowSource).toContain("useLazyLoadQuery");
    expect(workflowSource).not.toContain("useRelayEnvironment");
    expect(workflowSource).not.toContain("fetchQuery");
    expect(workflowSource).not.toContain("QueryState");
    expect(workflowSource).not.toContain("subscription.unsubscribe()");
    expect(workflowSource).not.toContain("useEffect");
    expect(routeSource).not.toContain("@tanstack/react-query");
    expect(routeSource).not.toContain("GraphQLFetcher");
    expect(routeSource).not.toContain("fetchGraphQL");
    expect(routeSource).not.toContain("/api/");
  });

  it("keeps generated Relay types explicit at the route workflow boundary", () => {
    const typesSource = readFileSync(join(routeRoot, "types.ts"), "utf8");
    const workflowSource = readFileSync(join(routeRoot, "workflow.ts"), "utf8");

    expect(typesSource).not.toContain("__generated__");
    expect(typesSource).not.toContain("Fragment$data");
    expect(typesSource).not.toContain('" $fragmentType"');
    expect(workflowSource).toContain("PacketsRoutePacketFragment$data");
    expect(workflowSource).toContain("PacketsRouteQuery as PacketsRouteOperation");
  });

  it("keeps only consumed fields in the packet connection view model", () => {
    const typesSource = readFileSync(join(routeRoot, "types.ts"), "utf8");
    const connectionSource =
      typesSource.match(/export type PacketConnection<TPacket> = \{([^}]*)\}/)?.[1] ?? "";

    expect(connectionSource).toContain("hasNextPage: boolean");
    expect(connectionSource).toContain("nextCursor: string | null");
    expect(connectionSource).toContain("rows: TPacket[]");
    expect(connectionSource).not.toContain("after: string | null");
    expect(connectionSource).not.toContain("empty: boolean");
    expect(connectionSource).not.toContain("hasPreviousPage: boolean");
    expect(connectionSource).not.toContain("startCursor: string | null");
  });

  it("keeps the registered packet workspace and product UI owned by the route", () => {
    const routesSource = readFileSync(join(process.cwd(), "app/routes.ts"), "utf8");

    expect(existsSync(join(routeRoot, "route.tsx"))).toBe(true);
    expect(existsSync(join(routeRoot, "PacketWorkspace.tsx"))).toBe(true);
    expect(existsSync(join(routeRoot, "components/PacketList.tsx"))).toBe(true);
    expect(existsSync(join(routeRoot, "components/PacketDetail.tsx"))).toBe(true);
    expect(existsSync(join(routeRoot, "components/PacketsLayout.tsx"))).toBe(true);
    expect(routesSource).toContain('route("packets", "./routes/packets/route.tsx")');
  });

  it("shares one route-local updated-at formatter across packet list and detail", () => {
    const formatterPath = join(routeRoot, "formatters.ts");
    const packetListSource = readFileSync(join(routeRoot, "components/PacketList.tsx"), "utf8");
    const packetDetailSource = readFileSync(join(routeRoot, "components/PacketDetail.tsx"), "utf8");

    expect(existsSync(formatterPath)).toBe(true);

    const formatterSource = readFileSync(formatterPath, "utf8");

    expect(formatterSource.match(/new Intl\.DateTimeFormat/g)).toHaveLength(1);
    expect(formatterSource).toContain('timeZone: "UTC"');
    expect(packetListSource).toContain("../formatters");
    expect(packetDetailSource).toContain("../formatters");
    expect(packetListSource).not.toContain("new Intl.DateTimeFormat");
    expect(packetDetailSource).not.toContain("new Intl.DateTimeFormat");
  });

  it("shares one route-local lifecycle-state formatter across packet list and detail", () => {
    const formatterSource = readFileSync(join(routeRoot, "formatters.ts"), "utf8");
    const packetListSource = readFileSync(join(routeRoot, "components/PacketList.tsx"), "utf8");
    const packetDetailSource = readFileSync(join(routeRoot, "components/PacketDetail.tsx"), "utf8");

    expect(formatterSource).toContain("export function formatPacketState");
    expect(packetListSource).toContain("formatPacketState");
    expect(packetDetailSource).toContain("formatPacketState");
    expect(packetListSource).not.toContain("function formatState");
    expect(packetDetailSource).not.toContain("function formatState");
  });

  it("keeps packet mutation documents and lifecycle wrappers route-owned", () => {
    const commandsPath = join(routeRoot, "commands.ts");
    const workflowPath = join(routeRoot, "commandWorkflow.ts");

    expect(existsSync(commandsPath)).toBe(true);
    expect(existsSync(workflowPath)).toBe(true);

    const commandsSource = readFileSync(commandsPath, "utf8");
    const workflowSource = readFileSync(workflowPath, "utf8");

    expect(commandsSource).toContain("PacketsCreateWorkPacketMutation");
    expect(commandsSource).toContain("PacketsCreateWorkPacketVersionMutation");
    expect(commandsSource).toContain("PacketsStartWorkRunMutation");
    expect(workflowSource).toContain("useCommandMutation");
    expect(workflowSource).not.toContain("fetchGraphQL");
    expect(workflowSource).not.toContain("/api/");
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

  const collectTokens = (node: ts.Node) => {
    if (ts.isStringLiteralLike(node)) {
      for (const token of node.text.split(/\s+/)) {
        if (/^[a-z][\w-]*$/i.test(token)) names.add(token);
      }
    }

    ts.forEachChild(node, collectTokens);
  };

  const visit = (node: ts.Node) => {
    const attributeName = ts.isJsxAttribute(node) ? node.name.getText(sourceFile) : null;

    if (
      ts.isJsxAttribute(node) &&
      (attributeName === "className" || attributeName?.endsWith("ClassName")) &&
      node.initializer
    ) {
      collectTokens(node.initializer);
    }

    ts.forEachChild(node, visit);
  };

  visit(sourceFile);
  return [...names];
}

function stylesheetClasses(relativePath: string) {
  const styles = readFileSync(join(assetsRoot, relativePath), "utf8");
  return new Set(Array.from(styles.matchAll(/\.([a-z_][\w-]*)/gi), (match) => match[1]));
}
