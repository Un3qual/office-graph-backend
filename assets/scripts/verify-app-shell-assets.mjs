import { existsSync, readFileSync } from "node:fs";
import { basename, resolve } from "node:path";

const projectRoot = resolve(import.meta.dirname, "../..");
const controllerPath = resolve(
  projectRoot,
  "lib/office_graph_web/controllers/operator_console_controller.ex",
);
const controller = readFileSync(controllerPath, "utf8");
const reactRouterStaticRoot = resolve(projectRoot, "priv/static/assets/react-router");
const reactRouterIndexPath = resolve(reactRouterStaticRoot, "index.html");
const reactRouterAssetPrefix = "/assets/react-router/";

if (!controller.includes("assets/react-router/index.html")) {
  throw new Error(
    "Operator app shell must serve the deployed React Router index from priv/static/assets/react-router/index.html",
  );
}

if (!existsSync(reactRouterIndexPath)) {
  throw new Error(
    "Deployed React Router index is missing: priv/static/assets/react-router/index.html",
  );
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
  throw new Error("React Router app shell does not reference any deployed assets.");
}

const missingFiles = expectedAssets.filter(
  (assetPath) => !existsSync(reactRouterAssetPath(assetPath)),
);

if (missingFiles.length > 0) {
  throw new Error(
    `Operator app shell references React Router build artifacts that do not exist: ${missingFiles.join(
      ", ",
    )}`,
  );
}

function assetPaths(source) {
  return [...source.matchAll(/\/assets\/[^"'\s<>)]+/g)].map((match) => match[0]);
}

function reactRouterAssetPath(assetPath) {
  if (!assetPath.startsWith(reactRouterAssetPrefix)) {
    throw new Error(`React Router app shell referenced a non-deployed asset path: ${assetPath}`);
  }

  return resolve(reactRouterStaticRoot, assetPath.replace(reactRouterAssetPrefix, ""));
}
