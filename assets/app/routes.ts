import { type RouteConfig, route } from "@react-router/dev/routes";

export default [
  route("operator", "./routes/operator/route.tsx"),
  route("packets", "./routes/packets/route.tsx")
] satisfies RouteConfig;
