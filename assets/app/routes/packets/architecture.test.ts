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
    expect(workflowSource).toContain("useRelayEnvironment");
    expect(workflowSource).toContain("fetchQuery");
    expect(workflowSource).toContain("subscription.unsubscribe()");
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
});
