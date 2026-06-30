import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { render, screen, waitFor } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";
import { FoundationStackProbe, useGraphQLProjection } from "./foundationStack";
import { stylexBabelPluginConfig } from "./stylexConfig";

describe("frontend foundation stack", () => {
  it("wires StyleX through the Vite React Babel pipeline", () => {
    expect(stylexBabelPluginConfig[0]).toBe("@stylexjs/babel-plugin");
  });

  it("reads a GraphQL projection through TanStack Query and renders a React Aria button", async () => {
    const fetcher = vi.fn(async () => ({
      data: {
        operatorProjection: {
          id: "projection_1",
          title: "Operator inbox"
        }
      }
    }));
    const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });

    render(
      <QueryClientProvider client={client}>
        <FoundationStackProbe fetcher={fetcher} projectionId="projection_1" />
      </QueryClientProvider>
    );

    expect(await screen.findByRole("button", { name: "Operator inbox" })).toBeInTheDocument();
    expect(fetcher).toHaveBeenCalledWith({
      query: expect.stringContaining("query OperatorProjection"),
      variables: { id: "projection_1" }
    });
  });

  it("exposes the GraphQL projection hook for future feature clients", async () => {
    const fetcher = vi.fn(async () => ({
      data: { operatorProjection: { id: "projection_2", title: "Run review" } }
    }));
    const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });

    function Probe() {
      const projection = useGraphQLProjection({ fetcher, id: "projection_2" });

      if (projection.isPending) {
        return <p>Loading</p>;
      }

      return <p>{projection.data?.title}</p>;
    }

    render(
      <QueryClientProvider client={client}>
        <Probe />
      </QueryClientProvider>
    );

    await waitFor(() => expect(screen.getByText("Run review")).toBeInTheDocument());
  });
});
