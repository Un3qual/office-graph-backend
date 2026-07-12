import type { NavDestination } from "../../src/ui/NavRail";

export const PRODUCT_DESTINATIONS = [
  { label: "Operator", to: "/operator" },
  { label: "Packets", to: "/packets" },
  { label: "All Runs" },
  { label: "Entities" },
  { label: "Reports" },
] as const satisfies readonly NavDestination[];
