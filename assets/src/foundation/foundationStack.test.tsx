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
        operatorWorkflowItem: {
          normalizedEventId: "projection_1",
          status: "ready_for_packet"
        }
      }
    }));
    const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });

    render(
      <QueryClientProvider client={client}>
        <FoundationStackProbe fetcher={fetcher} projectionId="projection_1" />
      </QueryClientProvider>
    );

    expect(await screen.findByRole("button", { name: "ready_for_packet" })).toBeInTheDocument();
    expect(fetcher).toHaveBeenCalledWith({
      query: expect.stringContaining("operatorWorkflowItem"),
      variables: { id: "projection_1" }
    });
    expect(fetcher).toHaveBeenCalledWith({
      query: expect.not.stringContaining("operatorProjection"),
      variables: { id: "projection_1" }
    });
  });

  it("exposes the GraphQL projection hook for future feature clients", async () => {
    const fetcher = vi.fn(async () => ({
      data: {
        operatorWorkflowItem: {
          normalizedEventId: "projection_2",
          status: "verified"
        }
      }
    }));
    const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });

    function Probe() {
      const projection = useGraphQLProjection({ fetcher, id: "projection_2" });

      if (projection.isPending) {
        return <p>Loading</p>;
      }

      return <p>{projection.data?.status}</p>;
    }

    render(
      <QueryClientProvider client={client}>
        <Probe />
      </QueryClientProvider>
    );

    await waitFor(() => expect(screen.getByText("verified")).toBeInTheDocument());
  });
});
