import { existsSync, readFileSync } from "node:fs";
import { resolve } from "node:path";

const projectRoot = resolve(import.meta.dirname, "../..");
const controllerPath = resolve(
  projectRoot,
  "lib/office_graph_web/controllers/operator_console_controller.ex"
);
const controller = readFileSync(controllerPath, "utf8");

const expectedAssets = [
  "/assets/operator/main.css",
  "/assets/operator/main.js"
];

const missingReferences = expectedAssets.filter((assetPath) => !controller.includes(assetPath));
if (missingReferences.length > 0) {
  throw new Error(
    `Operator app shell is missing asset references: ${missingReferences.join(", ")}`
  );
}

const missingFiles = expectedAssets
  .map((assetPath) => ({
    assetPath,
    filePath: resolve(projectRoot, "priv/static", assetPath.replace(/^\//, ""))
  }))
  .filter(({ filePath }) => !existsSync(filePath));

if (missingFiles.length > 0) {
  throw new Error(
    `Operator app shell references build artifacts that do not exist: ${missingFiles
      .map(({ assetPath }) => assetPath)
      .join(", ")}`
  );
}
