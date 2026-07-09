import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

const assetsRoot = process.cwd();

describe("Relay compiler workflow", () => {
  it("declares a compiler workflow and runs stale-artifact checks during verification", () => {
    const packageJson = JSON.parse(readFileSync(join(assetsRoot, "package.json"), "utf8")) as {
      scripts: Record<string, string>;
      devDependencies: Record<string, string>;
    };

    expect(packageJson.devDependencies).toHaveProperty("relay-compiler");
    expect(packageJson.scripts["relay:schema"]).toBe("node scripts/graphql-schema.mjs --write");
    expect(packageJson.scripts.relay).toBe("pnpm run relay:schema && relay-compiler --noWatchman");
    expect(packageJson.scripts["relay:check"]).toBe(
      "node scripts/graphql-schema.mjs --check && relay-compiler --noWatchman --validate"
    );
    expect(packageJson.scripts.verify).toContain("pnpm run relay:check");

    const relayConfigPath = join(assetsRoot, "relay.config.json");
    expect(existsSync(relayConfigPath)).toBe(true);
    expect(JSON.parse(readFileSync(relayConfigPath, "utf8"))).toMatchObject({
      src: "./app",
      schema: "./schema.graphql",
      language: "typescript",
      artifactDirectory: "./app/relay/__generated__",
      eagerEsModules: true
    });
  });

  it("extracts the schema without starting the OTP application or mixing compile logs into SDL", () => {
    const schemaScript = readFileSync(join(assetsRoot, "scripts/graphql-schema.mjs"), "utf8");

    expect(schemaScript).toContain('["compile", "--quiet"]');
    expect(schemaScript).toContain(
      '["run", "--no-start", "--no-compile", "-e", schemaExpression]'
    );
  });

  it("keeps route-owned operator GraphQL documents near the route", () => {
    const dataSource = readFileSync(join(assetsRoot, "app/routes/operator/data.ts"), "utf8");

    expect(dataSource).toContain("OperatorWorkflowRouteQuery");
    expect(dataSource).toContain("OperatorWorkflowItemFragment");
    expect(dataSource).toContain("ExecutePacketRunVerificationMutation");
    expect(dataSource).toContain("operatorWorkflowItems");
    expect(dataSource).not.toContain("@connection");
    expect(dataSource).not.toContain("ConnectionHandler.getConnection");
    expect(dataSource).not.toContain("@tanstack/react-query");
  });

  it("generates TypeScript artifacts for the operator query, fragment, and mutation", () => {
    const generatedDir = join(assetsRoot, "app/relay/__generated__");

    expect(readGenerated(generatedDir, "OperatorWorkflowRouteQuery.graphql.ts")).toContain(
      "export type OperatorWorkflowRouteQuery$data"
    );
    expect(readGenerated(generatedDir, "OperatorWorkflowItemFragment.graphql.ts")).toContain(
      "export type OperatorWorkflowItemFragment$key"
    );
    expect(
      readGenerated(generatedDir, "ExecutePacketRunVerificationMutation.graphql.ts")
    ).toContain("export type ExecutePacketRunVerificationMutation$data");
  });

  it("exposes mutation payload and store-update helpers for ergonomic tests", () => {
    const helperSource = readFileSync(join(assetsRoot, "app/relay/operatorTestPayloads.ts"), "utf8");
    const dataSource = readFileSync(join(assetsRoot, "app/routes/operator/data.ts"), "utf8");

    expect(helperSource).toContain("ExecutePacketRunVerificationMutation$data");
    expect(helperSource).toContain("operatorVerificationMutationPayload");
    expect(dataSource).toContain("operatorWorkflowRouteRootID");
    expect(dataSource).toContain("updateOperatorWorkflowAfterVerification");
  });
});

function readGenerated(generatedDir: string, filename: string) {
  const artifactPath = join(generatedDir, filename);

  expect(existsSync(artifactPath)).toBe(true);
  return readFileSync(artifactPath, "utf8");
}
