import { spawnSync } from "node:child_process";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";

const assetsRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const scriptPath = resolve(assetsRoot, "scripts/graphql-schema.mjs");

describe("GraphQL schema generation prerequisites", () => {
  it("reports an actionable error when Mix is unavailable", () => {
    const result = spawnSync(process.execPath, [scriptPath, "--check"], {
      cwd: assetsRoot,
      encoding: "utf8",
      env: { ...process.env, PATH: "" }
    });

    expect(result.status).toBe(1);
    expect(result.stderr).toContain("Unable to run Mix");
    expect(result.stderr).not.toContain("ERR_INVALID_ARG_TYPE");
  });
});
