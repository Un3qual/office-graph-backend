import * as babel from "@babel/core";
import { reactRouter } from "@react-router/dev/vite";
import { defineConfig, type Plugin } from "vite";
import { relayBabelPluginConfig } from "./app/relay/babelPluginConfig";
import { stylexBabelPluginConfig } from "./src/foundation/stylexConfig";

export default defineConfig({
  plugins: [reactRouter(), officeGraphBabelTransforms()]
});

function officeGraphBabelTransforms(): Plugin {
  return {
    name: "office-graph:babel-transforms",
    enforce: "pre",
    async transform(code, id) {
      const [filename] = id.split("?");

      if (!filename || filename.includes("/node_modules/") || !sourceFilePattern.test(filename)) {
        return null;
      }

      const result = await babel.transformAsync(code, {
        babelrc: false,
        configFile: false,
        filename: id,
        sourceFileName: filename,
        parserOpts: {
          allowAwaitOutsideFunction: true,
          plugins: parserPlugins(filename),
          sourceType: "module"
        },
        plugins: [
          relayBabelPluginConfig as babel.PluginItem,
          stylexBabelPluginConfig as babel.PluginItem
        ],
        sourceMaps: true
      });

      if (!result) {
        return null;
      }

      return {
        code: result.code ?? code,
        map: result.map ?? null
      };
    }
  };
}

const sourceFilePattern = /\.[cm]?[jt]sx?$/;

function parserPlugins(filename: string) {
  const plugins: string[] = [];

  if (!filename.endsWith(".ts")) {
    plugins.push("jsx");
  }

  if (/\.[cm]?tsx?$/.test(filename)) {
    plugins.push("typescript");
  }

  return plugins as NonNullable<NonNullable<babel.TransformOptions["parserOpts"]>["plugins"]>;
}
