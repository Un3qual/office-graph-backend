import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

const root = process.cwd();

describe("frontend static verification", () => {
  it("runs pinned lint and formatting checks with generated outputs excluded", () => {
    const packageJson = JSON.parse(readFileSync(join(root, "package.json"), "utf8")) as {
      scripts: Record<string, string>;
      devDependencies: Record<string, string>;
    };
    const biome = JSON.parse(readFileSync(join(root, "biome.json"), "utf8")) as {
      files: { includes: string[] };
    };

    expect(packageJson.devDependencies["@biomejs/biome"]).toMatch(/^\d+\.\d+\.\d+$/);
    expect(packageJson.scripts.lint).toBe(
      "biome lint app/relay/*.ts app/routes src scripts *.ts *.json",
    );
    expect(packageJson.scripts["format:check"]).toBe(
      "biome format app/relay/*.ts app/routes src scripts *.ts *.json",
    );
    expect(packageJson.scripts.verify).toContain("pnpm run lint && pnpm run format:check");
    expect(biome.files.includes).toEqual(
      expect.arrayContaining([
        "!!app/relay/__generated__",
        "!!build",
        "!!.react-router",
        "!!node_modules",
      ]),
    );
  });

  it("has no unused StyleX runtime or transform path", () => {
    const packageJson = JSON.parse(readFileSync(join(root, "package.json"), "utf8")) as {
      dependencies: Record<string, string>;
      devDependencies: Record<string, string>;
    };
    const vite = readFileSync(join(root, "vite.config.ts"), "utf8");
    const routerVite = readFileSync(join(root, "vite.react-router.config.ts"), "utf8");

    expect(packageJson.dependencies).not.toHaveProperty("@stylexjs/stylex");
    expect(packageJson.devDependencies).not.toHaveProperty("@stylexjs/babel-plugin");
    expect(vite).not.toContain("stylex");
    expect(routerVite).not.toContain("stylex");
    expect(existsSync(join(root, "src/foundation/stylexConfig.ts"))).toBe(false);
  });
});
