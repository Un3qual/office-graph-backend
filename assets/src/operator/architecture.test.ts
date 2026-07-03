import { readdirSync, readFileSync, statSync } from "node:fs";
import { join, relative } from "node:path";
import { describe, expect, it } from "vitest";

describe("operator frontend architecture", () => {
  it("keeps production operator UI code off the old JSON API client", () => {
    const sourceRoot = join(process.cwd(), "src");
    const files = productionSourceFiles(sourceRoot).filter(
      (file) =>
        file === join(sourceRoot, "App.tsx") ||
        file === join(sourceRoot, "main.tsx") ||
        file.startsWith(join(sourceRoot, "operator"))
    );

    const offenders = files.filter((file) =>
      readFileSync(file, "utf8").match(
        /\/api\/operator-workflow|operator-workflow\/api|\.\/operator-workflow\/api/
      )
    );

    expect(offenders.map((file) => relative(sourceRoot, file))).toEqual([]);
  });
});

function productionSourceFiles(root: string): string[] {
  return readdirSync(root).flatMap((entry) => {
    const path = join(root, entry);
    const stat = statSync(path);

    if (stat.isDirectory()) {
      return productionSourceFiles(path);
    }

    if (!path.endsWith(".ts") && !path.endsWith(".tsx")) {
      return [];
    }

    if (path.endsWith(".test.ts") || path.endsWith(".test.tsx")) {
      return [];
    }

    return [path];
  });
}
