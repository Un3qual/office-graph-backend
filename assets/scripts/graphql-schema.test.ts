import { mkdtempSync, readFileSync, rmSync, writeFileSync, chmodSync } from "node:fs";
import { tmpdir } from "node:os";
import { delimiter, dirname, resolve } from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { afterEach, describe, expect, it } from "vitest";

const scriptDir = dirname(fileURLToPath(import.meta.url));
const schemaPath = resolve(scriptDir, "../schema.graphql");
const schemaScript = resolve(scriptDir, "graphql-schema.mjs");
const temporaryDirectories: string[] = [];

afterEach(() => {
  for (const directory of temporaryDirectories.splice(0)) {
    rmSync(directory, { force: true, recursive: true });
  }
});

describe("GraphQL schema generation", () => {
  it("reports an actionable error when Mix is unavailable", () => {
    const result = spawnSync(process.execPath, [schemaScript, "--check"], {
      encoding: "utf8",
      env: { ...process.env, PATH: "" },
    });

    expect(result.status).toBe(1);
    expect(result.stderr).toContain("Unable to run Mix");
    expect(result.stderr).not.toContain("ERR_INVALID_ARG_TYPE");
  });

  it("reuses compiled beams when the parent verification gate already compiled them", () => {
    const invocation = runWithFakeMix({ OFFICE_GRAPH_SCHEMA_PRECOMPILED: "1" });

    expect(invocation.status).toBe(0);
    expect(invocation.mixCalls).toEqual([
      "run --no-start --no-compile -e OfficeGraphWeb.GraphQL.Schema |> Absinthe.Schema.to_sdl() |> IO.write()",
    ]);
  });

  it("compiles before standalone schema validation", () => {
    const invocation = runWithFakeMix({});

    expect(invocation.status).toBe(0);
    expect(invocation.mixCalls).toEqual([
      "compile --quiet",
      "run --no-start --no-compile -e OfficeGraphWeb.GraphQL.Schema |> Absinthe.Schema.to_sdl() |> IO.write()",
    ]);
  });
});

function runWithFakeMix(extraEnvironment: Record<string, string>) {
  const directory = mkdtempSync(resolve(tmpdir(), "office-graph-schema-test-"));
  temporaryDirectories.push(directory);
  const fakeMix = resolve(directory, "mix");
  const logPath = resolve(directory, "mix-calls.log");

  writeFileSync(
    fakeMix,
    `#!/bin/sh
printf '%s\\n' "$*" >> "$FAKE_MIX_LOG"
if [ "$1" = "run" ]; then
  exec /bin/sh -c 'cat "$FAKE_SCHEMA_PATH"'
fi
`,
  );
  chmodSync(fakeMix, 0o755);

  const environment = { ...process.env };
  delete environment.OFFICE_GRAPH_SCHEMA_PRECOMPILED;

  const result = spawnSync(process.execPath, [schemaScript, "--check"], {
    encoding: "utf8",
    env: {
      ...environment,
      ...extraEnvironment,
      FAKE_MIX_LOG: logPath,
      FAKE_SCHEMA_PATH: schemaPath,
      PATH: `${directory}${delimiter}${process.env.PATH ?? ""}`,
    },
  });

  return {
    status: result.status,
    mixCalls: readFileSync(logPath, "utf8").trim().split("\n"),
  };
}
