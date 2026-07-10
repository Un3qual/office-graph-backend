import { existsSync, readdirSync, readFileSync, statSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

const assetsRoot = process.cwd();
const routeRoot = join(assetsRoot, "app/routes/operator");

describe("operator route architecture", () => {
  it("keeps operator workflow reads owned by the Relay route module", () => {
    const source = routeSource();
    const workflowSource = readFileSync(join(routeRoot, "workflow.ts"), "utf8");

    expect(existsSync(join(assetsRoot, "src/operator"))).toBe(false);
    expect(source).not.toContain("@tanstack/react-query");
    expect(source).not.toContain("operatorInbox");
    expect(source).not.toContain("GraphQLFetcher");
    expect(source).not.toContain("workflowMappers");
    expect(source).toContain("OperatorWorkflowRouteQuery");
    expect(source).toContain("OperatorPacketReadinessQuery");
    expect(source).toContain("OperatorRunStateQuery");
    expect(workflowSource).toContain("useLazyLoadQuery<OperatorWorkflowRouteOperation>");
    expect(workflowSource).not.toContain("fetchQuery<OperatorWorkflowRouteOperation>");
  });

  it("keeps generated Relay data types explicit at the route data boundary", () => {
    const typesSource = readFileSync(join(routeRoot, "types.ts"), "utf8");
    const workflowSource = readFileSync(join(routeRoot, "workflow.ts"), "utf8");

    expect(typesSource).not.toContain("__generated__");
    expect(typesSource).not.toContain("Fragment$data");
    expect(typesSource).not.toContain('" $fragmentType"');
    expect(workflowSource).toContain("OperatorWorkflowItemFragment$data");
    expect(workflowSource).toContain("OperatorPacketReadinessFragment$data");
    expect(workflowSource).toContain("OperatorRunStateFragment$data");
  });
});

function routeSource() {
  return sourceFiles(routeRoot)
    .map((file) => readFileSync(file, "utf8"))
    .join("\n");
}

function sourceFiles(path: string): string[] {
  return readdirSync(path).flatMap((entry) => {
    const fullPath = join(path, entry);
    const stats = statSync(fullPath);

    if (stats.isDirectory()) {
      return sourceFiles(fullPath);
    }

    return /\.(ts|tsx)$/.test(entry) && !/\.test\.(ts|tsx)$/.test(entry) ? [fullPath] : [];
  });
}
