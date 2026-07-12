import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

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
});
