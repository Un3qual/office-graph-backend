import { reactRouter } from "@react-router/dev/vite";
import react from "@vitejs/plugin-react";
import { defineConfig } from "vite";
import { relayBabelPluginConfig } from "./app/relay/babelPluginConfig";
import { stylexBabelPluginConfig } from "./src/foundation/stylexConfig";

export default defineConfig({
  plugins: [
    reactRouter(),
    react({
      babel: {
        plugins: [relayBabelPluginConfig, stylexBabelPluginConfig]
      }
    })
  ]
});
