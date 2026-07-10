import { PacketsRouteQuery } from "./data";
import { PacketWorkspace } from "./PacketWorkspace";
import { usePacketsWorkflow } from "./workflow";

export const routeOwnedPacketsQuery = PacketsRouteQuery;

export default function PacketsRoute() {
  const workflow = usePacketsWorkflow();

  return <PacketWorkspace workflow={workflow} />;
}
