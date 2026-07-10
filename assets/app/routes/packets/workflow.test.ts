import { describe, expect, it } from "vitest";
import { packetConnectionFromRows, selectedPacketId } from "./workflow";

describe("packet route workflow", () => {
  it("maps only the connection fields consumed by the packet workspace", () => {
    const rows = [packet()];

    expect(
      packetConnectionFromRows(rows, {
        endCursor: "cursor_1",
        hasNextPage: true
      })
    ).toEqual({
      hasNextPage: true,
      nextCursor: "cursor_1",
      rows
    });
  });

  it("disables forward pagination when Relay omits the end cursor", () => {
    expect(
      packetConnectionFromRows([packet()], {
        endCursor: null,
        hasNextPage: true
      })
    ).toMatchObject({
      hasNextPage: false,
      nextCursor: null
    });
  });

  it("derives selection from the requested row or the first row without mirroring state", () => {
    const rows = [packet(), packet({ id: "packet_2", title: "Second packet" })];

    expect(selectedPacketId(rows, null)).toBe("packet_1");
    expect(selectedPacketId(rows, "packet_2")).toBe("packet_2");
    expect(selectedPacketId(rows, "packet_missing")).toBe("packet_1");
    expect(selectedPacketId([], "packet_2")).toBeNull();
  });
});

function packet(overrides: Partial<Packet> = {}): Packet {
  return {
    id: "packet_1",
    title: "First packet",
    state: "active",
    currentVersionId: "version_1",
    operationId: "operation_1",
    updatedAt: "2026-07-09T12:00:00Z",
    ...overrides
  };
}

type Packet = {
  id: string;
  title: string;
  state: string;
  currentVersionId: string | null;
  operationId: string | null;
  updatedAt: string;
};
