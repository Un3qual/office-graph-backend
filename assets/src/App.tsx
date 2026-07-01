import "./styles/global.css";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { OperatorRoute } from "./operator/OperatorRoute";
import type { GraphQLFetcher } from "./operator/workflowTypes";

type Props = {
  fetchGraphQL?: GraphQLFetcher;
};

const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      retry: false
    }
  }
});

export function App({ fetchGraphQL }: Props) {
  return (
    <QueryClientProvider client={queryClient}>
      <OperatorRoute fetchGraphQL={fetchGraphQL} />
    </QueryClientProvider>
  );
}
