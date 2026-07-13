import { existsSync, readdirSync, readFileSync, statSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { analyzeTypeScript } from "../architectureTestSupport";

const assetsRoot = process.cwd();
const routeRoot = join(assetsRoot, "app/routes/operator");

describe("operator route architecture", () => {
  it("keeps operator workflow reads owned by the Relay route module", () => {
    const source = routeSource();
    const workflowSource = readFileSync(join(routeRoot, "workflow.ts"), "utf8");
    const routeFacts = analyzeTypeScript(source, "operator-route.tsx");
    const workflowFacts = analyzeTypeScript(workflowSource, "workflow.ts");
    const graphqlDocuments = routeFacts.graphqlDocuments.join("\n");

    expect(existsSync(join(assetsRoot, "src/operator"))).toBe(false);
    expect(routeFacts.moduleSpecifiers).not.toContain("@tanstack/react-query");
    expect(graphqlDocuments).not.toContain("operatorInbox");
    expect([...routeFacts.identifiers]).toEqual(
      expect.not.arrayContaining([
        "GraphQLFetcher",
        "workflowMappers",
        "fetchQuery",
        "useRelayEnvironment",
        "QueryState",
        "idleQueryState",
        "loadingQueryState",
        "startLoading",
        "successQueryState",
        "errorQueryState",
        "unsubscribe",
        "useEffect",
      ]),
    );
    expect(graphqlDocuments).toContain("query OperatorWorkflowRouteQuery");
    expect(graphqlDocuments).toContain("query OperatorPacketReadinessQuery");
    expect(graphqlDocuments).toContain("query OperatorRunStateQuery");
    expect(workflowFacts.typedCalls.get("useLazyLoadQuery")).toEqual(
      new Set([
        "OperatorWorkflowRouteOperation",
        "OperatorPacketReadinessOperation",
        "OperatorRunStateOperation",
      ]),
    );
  });

  it("keeps generated Relay data types explicit at the route data boundary", () => {
    const typesSource = readFileSync(join(routeRoot, "types.ts"), "utf8");
    const workflowSource = readFileSync(join(routeRoot, "workflow.ts"), "utf8");
    const typesFacts = analyzeTypeScript(typesSource, "types.ts");
    const workflowFacts = analyzeTypeScript(workflowSource, "workflow.ts");

    expect([...typesFacts.moduleSpecifiers].some((value) => value.includes("__generated__"))).toBe(
      false,
    );
    expect(typesFacts.identifiers).not.toContain("Fragment$data");
    expect(typesFacts.stringLiterals).not.toContain(" $fragmentType");
    expect([...workflowFacts.identifiers]).toEqual(
      expect.arrayContaining([
        "OperatorWorkflowItemFragment$data",
        "OperatorPacketReadinessFragment$data",
        "OperatorRunStateFragment$data",
      ]),
    );
  });

  it("keeps command documents and lifecycle wrappers owned by the operator route", () => {
    const commandsPath = join(routeRoot, "commands.ts");
    const workflowPath = join(routeRoot, "commandWorkflow.ts");

    expect(existsSync(commandsPath)).toBe(true);
    expect(existsSync(workflowPath)).toBe(true);

    const commandsSource = readFileSync(commandsPath, "utf8");
    const workflowSource = readFileSync(workflowPath, "utf8");
    const commandsFacts = analyzeTypeScript(commandsSource, "commands.ts");
    const workflowFacts = analyzeTypeScript(workflowSource, "commandWorkflow.ts");

    expect(commandsFacts.graphqlDocuments.join("\n")).toContain(
      "mutation OperatorSubmitManualIntakeMutation",
    );
    expect(commandsFacts.graphqlDocuments.join("\n")).toContain(
      "mutation OperatorWaiveVerificationCheckMutation",
    );
    expect(workflowFacts.identifiers).toContain("useCommandMutation");
    expect(workflowFacts.identifiers).not.toContain("fetchGraphQL");
    expect([...workflowFacts.stringLiterals].some((value) => value.startsWith("/api/"))).toBe(
      false,
    );
  });

  it("does not retain the unused operator-only run-start command path", () => {
    const commandsSource = readFileSync(join(routeRoot, "commands.ts"), "utf8");
    const workflowSource = readFileSync(join(routeRoot, "commandWorkflow.ts"), "utf8");
    const commandsFacts = analyzeTypeScript(commandsSource, "commands.ts");
    const workflowFacts = analyzeTypeScript(workflowSource, "commandWorkflow.ts");

    expect(commandsFacts.graphqlDocuments.join("\n")).not.toContain(
      "mutation OperatorStartWorkRunMutation",
    );
    expect(workflowFacts.identifiers).not.toContain("useStartWorkRunCommand");
    expect(
      existsSync(
        join(assetsRoot, "app/relay/__generated__/OperatorStartWorkRunMutation.graphql.ts"),
      ),
    ).toBe(false);
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
