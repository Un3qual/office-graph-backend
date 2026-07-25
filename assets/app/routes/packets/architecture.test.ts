import { existsSync, readdirSync, readFileSync, statSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { describe, expect, it } from "vitest";
import { analyzeTypeScript } from "../architectureTestSupport";

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
        .filter((specifier) =>
          ["operator", "runs"].some(
            (area) =>
              specifier.endsWith(`/app/routes/${area}`) ||
              specifier.includes(`/app/routes/${area}/`),
          ),
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

  it("loads packet styles globally without importing operator-owned source", () => {
    const globalStyles = readFileSync(join(assetsRoot, "src/styles/global.css"), "utf8");
    const imports = sourceFiles(routeRoot).flatMap((file) => [
      ...analyzeTypeScript(readFileSync(file, "utf8"), file).moduleSpecifiers,
    ]);

    expect(globalStyles.match(/@import\s+["']\.\/packets\.css["'];/g)).toHaveLength(1);
    expect(imports.filter((specifier) => specifier.includes("/operator/"))).toEqual([]);
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
