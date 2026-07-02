import { QueryClient } from "@tanstack/react-query";
import { describe, expect, it, vi } from "vitest";
import {
  fetchPacketReadiness,
  fetchOperatorInbox,
  fetchOperatorItem,
  fetchOperatorRunState,
  operatorQueryKeys
} from "./workflowQueries";
import { createGraphQLHttpFetcher } from "./workflowGraphql";
import { createGraphQLTestFetcher, graphQLInbox, graphQLRunState } from "./testSupport";

describe("operator workflow GraphQL queries", () => {
  it("normalizes the inbox projection into frontend view models", async () => {
    const fetcher = createGraphQLTestFetcher({ operatorInbox: graphQLInbox });

    await expect(fetchOperatorInbox(fetcher)).resolves.toMatchObject({
      empty: false,
      hasMore: false,
      limit: 50,
      nextOffset: null,
      offset: 0,
      sourceWatermark: "op_123",
      rows: [
        {
          normalizedEventId: "evt_1",
          title: "evt_1",
          status: "ready_for_packet",
          allowedNextActions: ["prepare_packet"],
          source: { replayIdentity: "paste:operator-console" }
        }
      ]
    });
    expect(fetcher).toHaveBeenCalledWith({
      query: expect.stringContaining("operatorInbox"),
      variables: { limit: 50, offset: 0 }
    });
  });

  it("sends inbox page parameters through the GraphQL request", async () => {
    const fetcher = createGraphQLTestFetcher({ operatorInbox: graphQLInbox });

    await fetchOperatorInbox(fetcher, { limit: 25, offset: 50 });

    expect(fetcher).toHaveBeenCalledWith({
      query: expect.stringContaining("operatorInbox"),
      variables: { limit: 25, offset: 50 }
    });
  });

  it("uses stable query keys for cache ownership", async () => {
    const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
    const fetcher = createGraphQLTestFetcher({
      operatorInbox: graphQLInbox,
      operatorWorkflowItem: graphQLInbox.rows[0],
      operatorRunState: graphQLRunState
    });

    await client.fetchQuery({
      queryKey: operatorQueryKeys.inbox({ limit: 50, offset: 0 }),
      queryFn: () => fetchOperatorInbox(fetcher)
    });
    await client.fetchQuery({
      queryKey: operatorQueryKeys.item("evt_1"),
      queryFn: () => fetchOperatorItem(fetcher, "evt_1")
    });
    await client.fetchQuery({
      queryKey: operatorQueryKeys.runState("run_1"),
      queryFn: () => fetchOperatorRunState(fetcher, "run_1")
    });

    expect(client.getQueryData(operatorQueryKeys.inbox({ limit: 50, offset: 0 }))).toMatchObject({
      empty: false
    });
    expect(client.getQueryData(operatorQueryKeys.item("evt_1"))).toMatchObject({
      normalizedEventId: "evt_1"
    });
    expect(client.getQueryData(operatorQueryKeys.runState("run_1"))).toMatchObject({
      status: "awaiting_evidence_acceptance"
    });
  });

  it("uses order-independent packet readiness query keys without mutating inputs", () => {
    const input = {
      title: "Packet A",
      objective: "Objective A",
      contextSummary: "Context A",
      requirements: "Requirements A",
      successCriteria: "Success A",
      autonomyPosture: "human_supervised",
      sourceGraphItemIds: ["source_b", "source_a"],
      verificationCheckIds: ["check_b", "check_a"]
    };

    expect(operatorQueryKeys.packetReadiness(input)).toEqual(
      operatorQueryKeys.packetReadiness({
        ...input,
        sourceGraphItemIds: ["source_a", "source_b"],
        verificationCheckIds: ["check_a", "check_b"]
      })
    );
    expect(operatorQueryKeys.packetReadiness(input)).not.toEqual(
      operatorQueryKeys.packetReadiness({ ...input, title: "Packet B" })
    );
    expect(input).toEqual({
      title: "Packet A",
      objective: "Objective A",
      contextSummary: "Context A",
      requirements: "Requirements A",
      successCriteria: "Success A",
      autonomyPosture: "human_supervised",
      sourceGraphItemIds: ["source_b", "source_a"],
      verificationCheckIds: ["check_b", "check_a"]
    });
  });

  it("surfaces GraphQL errors with a useful message", async () => {
    const fetcher = vi.fn(async () => ({
      errors: [{ message: "operator inbox denied" }]
    }));

    await expect(fetchOperatorInbox(fetcher)).rejects.toThrow("operator inbox denied");
  });

  it("rejects missing inbox projections instead of treating them as empty", async () => {
    const fetcher = createGraphQLTestFetcher({ operatorInbox: null });

    await expect(fetchOperatorInbox(fetcher)).rejects.toThrow(
      "The GraphQL operator inbox projection was empty."
    );
  });

  it("rejects missing packet readiness projections instead of fabricating readiness", async () => {
    const fetcher = createGraphQLTestFetcher({ operatorPacketReadiness: null });

    await expect(
      fetchPacketReadiness(fetcher, {
        title: "Packet A",
        objective: "Objective A",
        contextSummary: "Context A",
        requirements: "Requirements A",
        successCriteria: "Success A",
        autonomyPosture: "human_supervised",
        sourceGraphItemIds: [],
        verificationCheckIds: []
      })
    ).rejects.toThrow("The GraphQL packet readiness projection was empty.");
  });

  it("passes abort signals through the HTTP GraphQL fetcher", async () => {
    const signal = new AbortController().signal;
    const fetcher = vi.fn(async () => Response.json({ data: { operatorPacketReadiness: null } }));
    const fetchGraphQL = createGraphQLHttpFetcher({ fetcher });

    await fetchGraphQL({ query: "query Test { ok }", variables: {}, signal });

    expect(fetcher).toHaveBeenCalledWith(
      "/graphql",
      expect.objectContaining({
        signal
      })
    );
  });

  it("passes React Query cancellation signals into GraphQL requests", async () => {
    const signal = new AbortController().signal;
    const fetcher = vi.fn(async () => ({
      data: {
        operatorPacketReadiness: {
          type: "packet_readiness",
          ready: true,
          status: "packet_ready",
          allowedNextActions: ["create_work_packet"],
          blockerReasons: [],
          sourceLinks: [],
          requiredChecks: [],
          sourceWatermark: null
        }
      }
    }));

    await fetchPacketReadiness(
      fetcher,
      {
        title: "Packet A",
        objective: "Objective A",
        contextSummary: "Context A",
        requirements: "Requirements A",
        successCriteria: "Success A",
        autonomyPosture: "human_supervised",
        sourceGraphItemIds: [],
        verificationCheckIds: []
      },
      signal
    );

    expect(fetcher).toHaveBeenCalledWith(
      expect.objectContaining({
        signal
      })
    );
  });
});
