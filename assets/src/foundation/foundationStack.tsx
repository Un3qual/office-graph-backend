import { useQuery } from "@tanstack/react-query";
import * as stylex from "@stylexjs/stylex";
import { Button } from "../ui/Button";

type Projection = {
  id: string;
  status: string;
};

type OperatorWorkflowItemProjection = {
  normalizedEventId: string;
  status: string;
};

type GraphQLProjectionResponse = {
  data?: {
    operatorWorkflowItem?: OperatorWorkflowItemProjection;
  };
};

type GraphQLFetcher = (request: {
  query: string;
  variables: { id: string };
}) => Promise<GraphQLProjectionResponse>;

const operatorWorkflowProjectionQuery = `
  query OperatorWorkflowProjection($id: ID!) {
    operatorWorkflowItem(id: $id) {
      normalizedEventId
      status
    }
  }
`;

const styles = stylex.create({
  probe: {
    display: "inline-flex"
  }
});

export function useGraphQLProjection({ fetcher, id }: { fetcher: GraphQLFetcher; id: string }) {
  return useQuery({
    queryKey: ["operatorWorkflowProjection", id],
    queryFn: async () => {
      const response = await fetcher({
        query: operatorWorkflowProjectionQuery,
        variables: { id }
      });
      const projection = response.data?.operatorWorkflowItem;

      if (!projection) {
        throw new Error("The GraphQL projection response was empty.");
      }

      return {
        id: projection.normalizedEventId,
        status: projection.status
      };
    }
  });
}

export function FoundationStackProbe({
  fetcher,
  projectionId
}: {
  fetcher: GraphQLFetcher;
  projectionId: string;
}) {
  const projection = useGraphQLProjection({ fetcher, id: projectionId });

  return (
    <div {...stylex.props(styles.probe)}>
      <Button isDisabled={projection.isPending}>{projection.data?.status ?? "Loading"}</Button>
    </div>
  );
}
