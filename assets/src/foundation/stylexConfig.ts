export const stylexBabelPluginConfig = [
  "@stylexjs/babel-plugin",
  {
    dev: process.env.NODE_ENV !== "production",
    runtimeInjection: true,
    test: process.env.NODE_ENV === "test",
    treeshakeCompensation: true,
    unstable_moduleResolution: {
      rootDir: process.cwd(),
      type: "commonJS"
    }
  }
] as const;
