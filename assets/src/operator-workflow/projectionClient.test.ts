import { describe, expect, it, vi } from "vitest";
import {
  createDefaultOperatorWorkflowProjectionClient,
  createGraphQLOperatorWorkflowProjectionClient,
  createJsonOperatorWorkflowProjectionClient,
  packetReadinessInputForItem,
  runIdForItem
} from "./projectionClient";
import {
  sampleInbox,
  samplePacketReadiness,
  sampleRunState,
  sampleVerificationOutcome
} from "./fixtures";

describe("operator workflow projection client", () => {
  it("defaults product reads to the GraphQL projection transport", async () => {
    const fetcher = vi.fn(async () =>
      new Response(
        JSON.stringify({
          data: {
            operatorInbox: {
              type: "operator_inbox",
              empty: false,
              sourceWatermark: "op_1",
              rows: []
            }
          }
        }),
        { headers: { "Content-Type": "application/json" } }
      )
    );
    vi.stubGlobal("fetch", fetcher);

    try {
      const client = createDefaultOperatorWorkflowProjectionClient();

      await expect(client.loadInbox()).resolves.toMatchObject({
        type: "operator_inbox",
        empty: false,
        source_watermark: "op_1",
        rows: []
      });

      expect(fetcher).toHaveBeenCalledWith(
        "/graphql",
        expect.objectContaining({
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: expect.stringContaining("operatorInbox")
        })
      );
    } finally {
      vi.unstubAllGlobals();
    }
  });

  it("keeps temporary JSON readiness input assembly behind the projection client", async () => {
    const item = {
      ...sampleInbox.rows[0],
      graph_links: [
        {
          type: "verification_check",
          id: "check_1",
          graph_item_id: "graph_1",
          title: "Run tests",
          state: "open"
        },
        {
          type: "work_run",
          id: "run_1",
          graph_item_id: null,
          title: "Run",
          state: "running"
        }
      ]
    };
    const api = {
      loadInbox: vi.fn(async () => sampleInbox),
      loadItem: vi.fn(async () => item),
      loadPacketReadiness: vi.fn(async () => samplePacketReadiness),
      loadRunState: vi.fn(async () => sampleRunState),
      loadVerificationOutcome: vi.fn()
    };
    const client = createJsonOperatorWorkflowProjectionClient(api);

    await client.loadPacketReadinessForItem(item);

    expect(packetReadinessInputForItem(item)).toEqual({
      source_graph_item_ids: ["graph_1"],
      verification_check_ids: ["check_1"]
    });
    expect(runIdForItem(item)).toBe("run_1");
    expect(api.loadPacketReadiness).toHaveBeenCalledWith({
      source_graph_item_ids: ["graph_1"],
      verification_check_ids: ["check_1"]
    });
  });

  it("keeps JSON and GraphQL adapters on the same frontend view model shape", async () => {
    const item = itemWithRun();
    const api = {
      loadInbox: vi.fn(async () => ({ ...sampleInbox, rows: [item] })),
      loadItem: vi.fn(async () => item),
      loadPacketReadiness: vi.fn(async () => samplePacketReadiness),
      loadRunState: vi.fn(async () => sampleRunState),
      loadVerificationOutcome: vi.fn(async () => sampleVerificationOutcome)
    };
    const jsonClient = createJsonOperatorWorkflowProjectionClient(api);
    const graphQLClient = createGraphQLOperatorWorkflowProjectionClient({
      fetcher: async ({ query }) => {
        if (query.includes("operatorInbox")) {
          return { data: { operatorInbox: { ...graphQLInbox, rows: [graphQLItem] } } };
        }

        if (query.includes("operatorWorkflowItem")) {
          return { data: { operatorWorkflowItem: graphQLItem } };
        }

        if (query.includes("operatorPacketReadiness")) {
          return { data: { operatorPacketReadiness: graphQLPacketReadiness } };
        }

        if (query.includes("operatorRunState")) {
          return { data: { operatorRunState: graphQLRunState } };
        }

        return { data: { operatorVerificationOutcome: graphQLVerificationOutcome } };
      }
    });

    await expect(graphQLClient.loadInbox()).resolves.toEqual(await jsonClient.loadInbox());
    await expect(graphQLClient.loadItem(item.normalized_event_id)).resolves.toEqual(
      await jsonClient.loadItem(item.normalized_event_id)
    );
    await expect(graphQLClient.loadPacketReadinessForItem(item)).resolves.toEqual(
      await jsonClient.loadPacketReadinessForItem(item)
    );
    await expect(graphQLClient.loadRunStateForItem(item)).resolves.toEqual(
      await jsonClient.loadRunStateForItem(item)
    );
    await expect(graphQLClient.loadVerificationOutcomeForItem(item)).resolves.toEqual(
      await jsonClient.loadVerificationOutcomeForItem(item)
    );
  });

  it("normalizes GraphQL operator inbox responses into the same view model shape", async () => {
    const fetcher = vi.fn(async () => ({
      data: {
        operatorInbox: {
          type: "operator_inbox",
          empty: false,
          sourceWatermark: "op_1",
          rows: [
            {
              type: "operator_workflow_item",
              typedId: { type: "normalized_intake_event", id: "evt_1" },
              normalizedEventId: "evt_1",
              duplicateOfId: null,
              status: "pending_triage",
              reasonCodes: [],
              source: {
                identity: "manual:paste",
                replayIdentity: "paste:1",
                outcome: "accepted"
              },
              proposedChangeStatus: { pending: 1, applied: 0, rejected: 0, total: 1 },
              blockerReasons: [],
              allowedNextActions: ["prepare_packet"],
              operationWatermark: "op_1",
              sourceWatermark: "op_1",
              graphLinks: [],
              graphRelationships: [],
              auditTrace: { operationId: null, resourceCount: 0, resources: [] },
              revisionTrace: { operationId: null, resourceCount: 0, resources: [] }
            }
          ]
        }
      }
    }));
    const client = createGraphQLOperatorWorkflowProjectionClient({ fetcher });

    await expect(client.loadInbox()).resolves.toMatchObject({
      empty: false,
      rows: [
        {
          normalized_event_id: "evt_1",
          allowed_next_actions: ["prepare_packet"],
          source: { replay_identity: "paste:1" }
        }
      ]
    });
    expect(fetcher).toHaveBeenCalledWith({
      query: expect.stringContaining("operatorInbox"),
      variables: {}
    });
  });

  it.each([
    ["null", { operatorWorkflowItem: null }],
    ["missing", {}],
    ["empty object", { operatorWorkflowItem: {} }]
  ])("rejects %s GraphQL item projections instead of rendering a blank item", async (_label, data) => {
    const fetcher = vi.fn(async () => ({
      data
    }));
    const client = createGraphQLOperatorWorkflowProjectionClient({ fetcher });

    await expect(client.loadItem("missing")).rejects.toThrow(
      "The GraphQL operator workflow item projection was empty."
    );
  });
});

function itemWithRun() {
  return {
    ...sampleInbox.rows[0],
    status: "ready_for_packet",
    allowed_next_actions: ["prepare_packet"],
    graph_links: [
      {
        type: "verification_check",
        id: "check_1",
        graph_item_id: "graph_1",
        title: "Run console verification",
        state: "open"
      },
      {
        type: "work_run",
        id: "run_1",
        graph_item_id: null,
        title: "Console verification run",
        state: "running"
      }
    ]
  };
}

const graphQLItem = {
  type: "operator_workflow_item",
  typedId: { type: "normalized_intake_event", id: "evt_1" },
  normalizedEventId: "evt_1",
  duplicateOfId: null,
  status: "ready_for_packet",
  reasonCodes: [],
  source: {
    identity: "manual:operator-console",
    replayIdentity: "paste:operator-console",
    outcome: "accepted"
  },
  proposedChangeStatus: { pending: 4, applied: 0, rejected: 0, total: 4 },
  blockerReasons: [],
  allowedNextActions: ["prepare_packet"],
  operationWatermark: "op_123",
  sourceWatermark: "op_123",
  graphLinks: [
    {
      type: "verification_check",
      id: "check_1",
      graphItemId: "graph_1",
      title: "Run console verification",
      state: "open"
    },
    {
      type: "work_run",
      id: "run_1",
      graphItemId: null,
      title: "Console verification run",
      state: "running"
    }
  ],
  graphRelationships: [],
  auditTrace: { operationId: null, resourceCount: 0, resources: [] },
  revisionTrace: { operationId: null, resourceCount: 0, resources: [] }
};

const graphQLInbox = {
  type: "operator_inbox",
  empty: false,
  sourceWatermark: "op_123"
};

const graphQLPacketReadiness = {
  type: "packet_readiness",
  ready: true,
  status: "packet_ready",
  allowedNextActions: ["create_work_packet"],
  blockerReasons: [],
  sourceLinks: [
    {
      type: "verification_check",
      id: "check_1",
      graphItemId: "graph_1",
      title: "Run console verification"
    }
  ],
  requiredChecks: [{ id: "check_1", graphItemId: "graph_1", state: "open" }],
  sourceWatermark: null
};

const graphQLRunState = {
  type: "operator_run_state",
  status: "awaiting_evidence_acceptance",
  allowedNextActions: ["accept_evidence"],
  sourceWatermark: "run_1",
  packet: { id: "packet_1", title: "Operator console packet", state: "active" },
  packetVersion: {
    id: "version_1",
    versionNumber: 1,
    lifecycleState: "active",
    objective: "Verify the operator console renders workflow state."
  },
  run: {
    id: "run_1",
    aggregateState: "running",
    executionState: "completed",
    verificationState: "pending"
  },
  requiredChecks: [{ id: "required_1", verificationCheckId: "check_1", state: "open" }],
  observations: [
    {
      id: "observation_1",
      verificationCheckId: "check_1",
      graphItemId: "graph_1",
      normalizedStatus: "succeeded",
      freshnessState: "fresh",
      trustBasis: "owner_attested",
      sourceKind: "human",
      sourceIdentity: "manual:operator-console"
    }
  ],
  evidenceCandidates: [
    {
      id: "candidate_1",
      verificationCheckId: "check_1",
      executionObservationId: "observation_1",
      claim: "Operator console evidence is ready.",
      state: "candidate",
      freshnessState: "fresh",
      trustBasis: "owner_attested",
      sourceKind: "human",
      sourceIdentity: "manual:operator-console"
    }
  ],
  evidenceItems: [],
  verificationResults: [
    {
      id: "result_1",
      result: "passed",
      verificationCheckId: "check_1",
      evidenceItemId: "evidence_1",
      operationId: "operation_1",
      actorPrincipalId: "principal_1",
      policyBasis: "owner_acceptance",
      targetGraphItemId: "graph_1",
      workRunId: "run_1",
      workPacketVersionId: "version_1"
    }
  ],
  missingEvidence: [{ verificationCheckId: "check_1", reason: "missing_accepted_evidence" }]
};

const graphQLVerificationOutcome = {
  type: "verification_outcome",
  status: "awaiting_evidence_acceptance",
  sourceWatermark: "run_1",
  run: graphQLRunState.run,
  verificationResults: graphQLRunState.verificationResults,
  missingEvidence: graphQLRunState.missingEvidence
};
