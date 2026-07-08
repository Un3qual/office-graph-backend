import { existsSync, readFileSync } from "node:fs";
import { basename, resolve } from "node:path";

const projectRoot = resolve(import.meta.dirname, "../..");
const controllerPath = resolve(
  projectRoot,
  "lib/office_graph_web/controllers/operator_console_controller.ex"
);
const controller = readFileSync(controllerPath, "utf8");
const reactRouterBuildRoot = resolve(projectRoot, "assets/build/client");
const reactRouterIndexPath = resolve(reactRouterBuildRoot, "index.html");

if (!controller.includes("assets/build/client/index.html")) {
  throw new Error(
    "Operator app shell must serve the React Router build index from assets/build/client/index.html"
  );
}

if (!existsSync(reactRouterIndexPath)) {
  throw new Error("React Router build index is missing: assets/build/client/index.html");
}

const indexHtml = readFileSync(reactRouterIndexPath, "utf8");
const indexAssets = assetPaths(indexHtml);
const manifestAssets = indexAssets
  .filter((assetPath) => basename(assetPath).startsWith("manifest-"))
  .flatMap((assetPath) => {
    const filePath = reactRouterAssetPath(assetPath);

    return existsSync(filePath) ? assetPaths(readFileSync(filePath, "utf8")) : [];
  });
const expectedAssets = [...new Set([...indexAssets, ...manifestAssets])];

if (expectedAssets.length === 0) {
  throw new Error("React Router build index does not reference any built assets.");
}

const missingFiles = expectedAssets.filter((assetPath) => !existsSync(reactRouterAssetPath(assetPath)));

if (missingFiles.length > 0) {
  throw new Error(
    `Operator app shell references React Router build artifacts that do not exist: ${missingFiles.join(
      ", "
    )}`
  );
}

function assetPaths(source) {
  return [...source.matchAll(/\/assets\/[^"'\s<>)]+/g)].map((match) => match[0]);
}

function reactRouterAssetPath(assetPath) {
  return resolve(reactRouterBuildRoot, "assets", assetPath.replace(/^\/assets\//, ""));
}
