import type { ConcreteRequest, ReaderInlineDataFragment } from "relay-runtime";
import { describe, expect, it } from "vitest";

describe("packet route Relay data", () => {
  it("imports the compiled route query and inline packet fragment through Vite", async () => {
    const data = await import("./data");
    const routeQuery = data.PacketsRouteQuery as ConcreteRequest;
    const detailQuery = data.PacketsWorkspaceDetailQuery as ConcreteRequest;
    const packetFragment = data.PacketsRoutePacketFragment as ReaderInlineDataFragment;

    expect(routeQuery.params.name).toBe("PacketsRouteQuery");
    expect(routeQuery.params.text).toContain("listWorkPackets(first: $first, after: $after)");
    expect(routeQuery.params.text).not.toContain("filter: { id:");
    expect(routeQuery.params.text).toContain("linkedPacket: getWorkPacket(id: $packetId)");
    expect(packetFragment.name).toBe("PacketsRoutePacketFragment");
    expect(packetFragment.kind).toBe("InlineDataFragment");
    expect(detailQuery.params.name).toBe("PacketsWorkspaceDetailQuery");
    expect(detailQuery.params.text).toContain("operatorPacketWorkspace(id: $id)");
    expect(routeQuery.params.text).toContain("operatorPacketCreateAffordance");
    expect(routeQuery.params.text).toContain("identity");
    expect(routeQuery.params.text).toContain("state");

    for (const field of [
      "currentVersion",
      "versionHistory",
      "sourceGraphItemIds",
      "verificationCheckIds",
      "commandAffordances",
      "allowedNextActions",
    ]) {
      expect(detailQuery.params.text).toContain(field);
    }

    for (const field of ["id", "title", "state", "currentVersionId", "operationId", "updatedAt"]) {
      expect(routeQuery.params.text).toContain(field);
    }
  });
});
