import react from "@vitejs/plugin-react";
import { defineConfig } from "vite";
import { relayBabelPluginConfig } from "./app/relay/babelPluginConfig";
import { stylexBabelPluginConfig } from "./src/foundation/stylexConfig";

export default defineConfig({
  plugins: [
    react({
      babel: {
        plugins: [relayBabelPluginConfig, stylexBabelPluginConfig]
      }
    })
  ],
  test: {
    environment: "jsdom",
    globals: true,
    setupFiles: ["./vitest.setup.ts"],
    css: true
  }
});
