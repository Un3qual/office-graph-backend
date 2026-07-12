import react from "@vitejs/plugin-react";
import { defineConfig } from "vite";
import { relayBabelPluginConfig } from "./app/relay/babelPluginConfig";

export default defineConfig({
  plugins: [
    react({
      babel: {
        plugins: [relayBabelPluginConfig],
      },
    }),
  ],
  test: {
    environment: "jsdom",
    globals: true,
    setupFiles: ["./vitest.setup.ts"],
    css: true,
  },
});
