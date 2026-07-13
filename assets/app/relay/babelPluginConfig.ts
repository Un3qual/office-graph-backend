export const relayBabelPluginConfig = [
  "babel-plugin-relay",
  {
    artifactDirectory: "./app/relay/__generated__",
    eagerEsModules: true,
  },
] as const;
