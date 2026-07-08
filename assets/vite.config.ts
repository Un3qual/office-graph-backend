import { resolve } from "node:path";
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
  build: {
    outDir: "../priv/static",
    emptyOutDir: false,
    sourcemap: true,
    rollupOptions: {
      input: {
        main: resolve(__dirname, "src/main.tsx")
      },
      output: {
        entryFileNames: "assets/operator/[name].js",
        chunkFileNames: "assets/operator/[name].js",
        assetFileNames: "assets/operator/[name][extname]"
      }
    }
  },
  test: {
    environment: "jsdom",
    globals: true,
    setupFiles: ["./vitest.setup.ts"],
    css: true
  }
});
