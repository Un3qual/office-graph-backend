import {
  cpSync,
  existsSync,
  mkdirSync,
  readFileSync,
  readdirSync,
  rmSync,
  writeFileSync
} from "node:fs";
import { extname, join, resolve } from "node:path";

const projectRoot = resolve(import.meta.dirname, "../..");
const buildRoot = resolve(projectRoot, "assets/build/client");
const buildAssetsRoot = resolve(buildRoot, "assets");
const buildIndexPath = resolve(buildRoot, "index.html");
const staticRoot = resolve(projectRoot, "priv/static/assets/react-router");
const assetPrefix = "/assets/react-router/";

if (!existsSync(buildIndexPath)) {
  throw new Error("React Router build index is missing: assets/build/client/index.html");
}

if (!existsSync(buildAssetsRoot)) {
  throw new Error("React Router build assets are missing: assets/build/client/assets");
}

rmSync(staticRoot, { force: true, recursive: true });
mkdirSync(staticRoot, { recursive: true });
cpSync(buildAssetsRoot, staticRoot, { recursive: true });

const indexHtml = rewriteAssetPaths(readFileSync(buildIndexPath, "utf8"));
writeFileSync(join(staticRoot, "index.html"), indexHtml);
rewriteCopiedTextAssets(staticRoot);

function rewriteCopiedTextAssets(directory) {
  for (const entry of readdirSync(directory, { withFileTypes: true })) {
    const path = join(directory, entry.name);

    if (entry.isDirectory()) {
      rewriteCopiedTextAssets(path);
      continue;
    }

    if (![".css", ".html", ".js"].includes(extname(entry.name))) {
      continue;
    }

    const source = readFileSync(path, "utf8");
    const rewritten = rewriteAssetPaths(source);

    if (source !== rewritten) {
      writeFileSync(path, rewritten);
    }
  }
}

function rewriteAssetPaths(source) {
  return source.replace(/\/assets\/(?!react-router\/)/g, assetPrefix);
}
