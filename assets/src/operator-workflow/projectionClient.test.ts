import { describe, expect, it, vi } from "vitest";
import {
  createGraphQLOperatorWorkflowProjectionClient,
  createJsonOperatorWorkflowProjectionClient,
  packetReadinessInputForItem,
  runIdForItem
} from "./projectionClient";
import { sampleInbox, samplePacketReadiness, sampleRunState } from "./fixtures";

describe("operator workflow projection client", () => {
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
