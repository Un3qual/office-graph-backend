import { spawnSync } from "node:child_process";
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const scriptDir = dirname(fileURLToPath(import.meta.url));
const assetsRoot = resolve(scriptDir, "..");
const repoRoot = resolve(assetsRoot, "..");
const schemaPath = resolve(assetsRoot, "schema.graphql");
const schemaExpression = "OfficeGraphWeb.GraphQL.Schema |> Absinthe.Schema.to_sdl() |> IO.write()";
const mode = process.argv[2];

if (!["--check", "--write"].includes(mode)) {
  console.error("Usage: node scripts/graphql-schema.mjs --check|--write");
  process.exit(2);
}

const schema = generateSchema();

if (mode === "--write") {
  writeFileSync(schemaPath, schema);
  process.exit(0);
}

if (!existsSync(schemaPath)) {
  console.error("Relay schema snapshot is missing. Run `pnpm run relay:schema` from assets/.");
  process.exit(1);
}

const current = readFileSync(schemaPath, "utf8");

if (current !== schema) {
  console.error("Relay schema snapshot is stale. Run `pnpm run relay:schema` from assets/.");
  process.exit(1);
}

function generateSchema() {
  runMix(["compile", "--quiet"]);
  const result = runMix(["run", "--no-start", "--no-compile", "-e", schemaExpression]);

  return `${result.stdout.trimEnd()}\n`;
}

function runMix(args) {
  const result = spawnSync("mix", args, {
    cwd: repoRoot,
    encoding: "utf8",
    maxBuffer: 20 * 1024 * 1024,
  });

  if (result.error) {
    console.error(`Unable to run Mix: ${result.error.message}`);
    process.exit(1);
  }

  if (result.status !== 0) {
    if (result.stdout) process.stdout.write(result.stdout);
    if (result.stderr) process.stderr.write(result.stderr);
    process.exit(result.status ?? 1);
  }

  if (result.stderr) {
    process.stderr.write(result.stderr);
  }

  return result;
}
