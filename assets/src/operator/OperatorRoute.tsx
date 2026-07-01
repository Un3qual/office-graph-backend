import { useMemo } from "react";
import { createGraphQLHttpFetcher } from "./workflowGraphql";
import { OperatorWorkspace } from "./OperatorWorkspace";
import { useOperatorWorkflow } from "./useOperatorWorkflow";
import type { GraphQLFetcher } from "./workflowTypes";

type Props = {
  fetchGraphQL?: GraphQLFetcher;
};

const defaultGraphQLFetcher = createGraphQLHttpFetcher();

export function OperatorRoute({ fetchGraphQL }: Props) {
  const resolvedFetcher = useMemo(() => fetchGraphQL ?? defaultGraphQLFetcher, [fetchGraphQL]);
  const workflow = useOperatorWorkflow(resolvedFetcher);

  return <OperatorWorkspace workflow={workflow} />;
}
