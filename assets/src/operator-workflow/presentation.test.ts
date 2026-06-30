import { describe, expect, it } from "vitest";
import { listSummary, shortId } from "./presentation";

describe("operator workflow presentation helpers", () => {
  it("summarizes long repeated lists", () => {
    expect(listSummary(["Alpha", "Alpha", "Beta", "Gamma"], 2)).toBe("Alpha, Beta, and 1 more");
  });

  it("shortens UUID-like ids for dense rows", () => {
    expect(shortId("463e8965-859e-46f2-986c-6ef6ad579b40")).toBe("463e8965");
  });
});
