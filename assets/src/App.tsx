import "./styles/global.css";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { useState } from "react";
import { OperatorRoute } from "./operator/OperatorRoute";
import type { GraphQLFetcher } from "./operator/workflowTypes";

type Props = {
  fetchGraphQL?: GraphQLFetcher;
};

function createQueryClient() {
  return new QueryClient({
    defaultOptions: {
      queries: {
        retry: false
      }
    }
  });
}

export function App({ fetchGraphQL }: Props) {
  const [queryClient] = useState(createQueryClient);

  return (
    <QueryClientProvider client={queryClient}>
      <OperatorRoute fetchGraphQL={fetchGraphQL} />
    </QueryClientProvider>
  );
}
