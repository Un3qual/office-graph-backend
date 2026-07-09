import { OperatorWorkflowRouteQuery } from "./data";
import { OperatorWorkspace } from "./OperatorWorkspace";
import { useOperatorWorkflow } from "./workflow";

export const routeOwnedOperatorWorkflowQuery = OperatorWorkflowRouteQuery;

export default function OperatorRoute() {
  const workflow = useOperatorWorkflow();

  return <OperatorWorkspace workflow={workflow} />;
}
