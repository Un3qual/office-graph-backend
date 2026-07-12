import { describe, expect, it } from "vitest";
import { manualReplayIdentity } from "./commandFormSupport";

describe("manual replay identity", () => {
  it("does not collapse distinct bodies that collide under the legacy 32-bit hash", async () => {
    const first = await manualReplayIdentity("6ll6h3o2r2");
    const second = await manualReplayIdentity("wb5tvsm5ja");

    expect(first).not.toBe(second);
    expect(first).toMatch(/^operator:[a-f0-9]{64}$/);
    expect(second).toMatch(/^operator:[a-f0-9]{64}$/);
  });
});
