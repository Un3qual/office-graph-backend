import { existsSync, readdirSync, readFileSync, statSync } from "node:fs";
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

  it("defines the React Router Framework Mode foundation without moving route behavior yet", () => {
    const projectRoot = process.cwd();
    const packageJson = JSON.parse(readFileSync(join(projectRoot, "package.json"), "utf8")) as {
      dependencies: Record<string, string>;
      devDependencies: Record<string, string>;
      scripts: Record<string, string>;
    };

    expect(existsSync(join(projectRoot, "react-router.config.ts"))).toBe(true);
    expect(existsSync(join(projectRoot, "vite.react-router.config.ts"))).toBe(true);
    expect(existsSync(join(projectRoot, "app/root.tsx"))).toBe(true);
    expect(existsSync(join(projectRoot, "app/routes.ts"))).toBe(true);
    expect(existsSync(join(projectRoot, "app/AppProviders.tsx"))).toBe(true);
    expect(existsSync(join(projectRoot, "app/routes/operator/route.tsx"))).toBe(true);
    expect(existsSync(join(projectRoot, "app/relay/environment.ts"))).toBe(true);
    expect(existsSync(join(projectRoot, "app/relay/fetchGraphQL.ts"))).toBe(true);

    const routerConfig = readFileSync(join(projectRoot, "react-router.config.ts"), "utf8");
    expect(routerConfig).toMatch(/appDirectory:\s*"app"/);
    expect(routerConfig).toMatch(/ssr:\s*false/);
    expect(routerConfig).toMatch(/routeDiscovery:\s*\{\s*mode:\s*"initial"/);

    const routes = readFileSync(join(projectRoot, "app/routes.ts"), "utf8");
    expect(routes).toContain('route("operator", "./routes/operator/route.tsx")');
    expect(routes).toContain("@react-router/dev/routes");

    const providers = readFileSync(join(projectRoot, "app/AppProviders.tsx"), "utf8");
    expect(providers).toContain("RelayEnvironmentProvider");
    expect(providers).not.toContain("QueryClientProvider");
    expect(providers).not.toContain("@tanstack/react-query");

    expect(packageJson.dependencies).toHaveProperty("react-router");
    expect(packageJson.dependencies).toHaveProperty("react-relay");
    expect(packageJson.dependencies).toHaveProperty("relay-runtime");
    expect(packageJson.dependencies).toHaveProperty("@react-router/node");
    expect(packageJson.devDependencies).toHaveProperty("@react-router/dev");
    expect(packageJson.scripts).toMatchObject({
      "router:build": "react-router build --config vite.react-router.config.ts",
      "router:routes": "react-router routes --config vite.react-router.config.ts",
      "router:typegen": "react-router typegen"
    });
  });

  it("keeps the new framework layout shallow and route-first", () => {
    const projectRoot = process.cwd();
    const forbiddenDirs = [
      "app/platform",
      "app/domains",
      "app/shared/design",
      "app/shared/ui"
    ];

    expect(forbiddenDirs.filter((dir) => existsSync(join(projectRoot, dir)))).toEqual([]);
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
