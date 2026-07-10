import { describe, expect, it } from "vitest";
import { formatPacketState, formatPacketUpdatedAt } from "./formatters";

describe("packet formatters", () => {
  it("formats packet lifecycle states consistently", () => {
    expect(formatPacketState("ready_for_run")).toBe("Ready for run");
    expect(formatPacketState("READY_for_RUN")).toBe("Ready for run");
  });

  it("formats packet timestamps in UTC", () => {
    expect(formatPacketUpdatedAt("2026-07-09T19:45:00Z")).toBe(
      "Jul 9, 2026, 7:45 PM UTC"
    );
  });
});
