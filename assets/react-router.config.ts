import type { Config } from "@react-router/dev/config";

export default {
  appDirectory: "app",
  routeDiscovery: {
    mode: "initial",
  },
  ssr: false,
} satisfies Config;
