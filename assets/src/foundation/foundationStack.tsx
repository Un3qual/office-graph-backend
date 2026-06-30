import { useQuery } from "@tanstack/react-query";
import * as stylex from "@stylexjs/stylex";
import { Button } from "../ui/Button";

type Projection = {
  id: string;
  title: string;
};

type GraphQLProjectionResponse = {
  data?: {
    operatorProjection?: Projection;
  };
};

type GraphQLFetcher = (request: {
  query: string;
  variables: { id: string };
}) => Promise<GraphQLProjectionResponse>;

const operatorProjectionQuery = `
  query OperatorProjection($id: ID!) {
    operatorProjection(id: $id) {
      id
      title
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
    queryKey: ["operatorProjection", id],
    queryFn: async () => {
      const response = await fetcher({
        query: operatorProjectionQuery,
        variables: { id }
      });
      const projection = response.data?.operatorProjection;

      if (!projection) {
        throw new Error("The GraphQL projection response was empty.");
      }

      return projection;
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
      <Button isDisabled={projection.isPending}>{projection.data?.title ?? "Loading"}</Button>
    </div>
  );
}
