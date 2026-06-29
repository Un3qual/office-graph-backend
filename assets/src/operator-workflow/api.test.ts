import { describe, expect, it, vi } from "vitest";
import { createOperatorWorkflowApi } from "./api";

describe("operator workflow API client", () => {
  it("loads inbox rows from the JSON API", async () => {
    const fetcher = vi.fn(async () => {
      return response({
        type: "operator_inbox",
        empty: false,
        source_watermark: "op_123",
        rows: [
          {
            type: "operator_workflow_item",
            typed_id: { type: "normalized_intake_event", id: "evt_1" },
            normalized_event_id: "evt_1",
            duplicate_of_id: null,
            status: "pending_triage",
            reason_codes: [],
            source: {
              identity: "manual:paste",
              replay_identity: "paste:1",
              outcome: "accepted"
            },
            proposed_change_status: {
              pending: 4,
              applied: 0,
              rejected: 0,
              total: 4
            },
            blocker_reasons: [],
            allowed_next_actions: ["apply_proposed_changes"],
            operation_watermark: "op_123",
            source_watermark: "op_123",
            graph_links: [],
            graph_relationships: [],
            audit_trace: { operation_id: null, resource_count: 0, resources: [] },
            revision_trace: { operation_id: null, resource_count: 0, resources: [] }
          }
        ]
      });
    });

    const api = createOperatorWorkflowApi({ fetcher });

    await expect(api.loadInbox()).resolves.toMatchObject({
      empty: false,
      source_watermark: "op_123",
      rows: [
        {
          normalized_event_id: "evt_1",
          status: "pending_triage",
          allowed_next_actions: ["apply_proposed_changes"]
        }
      ]
    });

    expect(fetcher).toHaveBeenCalledWith("/api/operator-workflow/inbox", {
      headers: { accept: "application/json" },
      method: "GET"
    });
  });

  it("preserves the empty inbox response", async () => {
    const fetcher = vi.fn(async () =>
      response({
        type: "operator_inbox",
        empty: true,
        source_watermark: null,
        rows: []
      })
    );
    const api = createOperatorWorkflowApi({ fetcher });

    await expect(api.loadInbox()).resolves.toEqual({
      type: "operator_inbox",
      empty: true,
      source_watermark: null,
      rows: []
    });
  });

  it("turns API error envelopes into typed client errors", async () => {
    const fetcher = vi.fn(async () =>
      response(
        {
          error: {
            code: "not_found",
            detail: "The operator workflow item could not be found.",
            normalized_event_id: "missing"
          }
        },
        { ok: false, status: 404 }
      )
    );
    const api = createOperatorWorkflowApi({ fetcher });

    await expect(api.loadItem("missing")).rejects.toMatchObject({
      code: "not_found",
      detail: "The operator workflow item could not be found.",
      status: 404
    });
  });

  it("loads item detail by normalized event id", async () => {
    const fetcher = vi.fn(async () =>
      response({
        type: "operator_workflow_item",
        typed_id: { type: "normalized_intake_event", id: "evt_2" },
        normalized_event_id: "evt_2",
        duplicate_of_id: null,
        status: "ready_for_packet",
        reason_codes: [],
        source: {
          identity: "manual:paste",
          replay_identity: "paste:2",
          outcome: "accepted"
        },
        proposed_change_status: { pending: 0, applied: 4, rejected: 0, total: 4 },
        blocker_reasons: [],
        allowed_next_actions: ["prepare_packet"],
        operation_watermark: "op_456",
        source_watermark: "op_456",
        graph_links: [{ type: "verification_check", id: "check_1", graph_item_id: "graph_1", title: "Run tests", state: "open" }],
        graph_relationships: [],
        audit_trace: { operation_id: "op_456", resource_count: 4, resources: [] },
        revision_trace: { operation_id: "op_456", resource_count: 4, resources: [] }
      })
    );

    const api = createOperatorWorkflowApi({ fetcher });

    await expect(api.loadItem("evt_2")).resolves.toMatchObject({
      normalized_event_id: "evt_2",
      status: "ready_for_packet",
      graph_links: [{ type: "verification_check", title: "Run tests" }]
    });
    expect(fetcher).toHaveBeenCalledWith("/api/operator-workflow/items/evt_2", {
      headers: { accept: "application/json" },
      method: "GET"
    });
  });

  it("posts packet readiness input", async () => {
    const fetcher = vi.fn(async () =>
      response({
        type: "packet_readiness",
        ready: true,
        status: "packet_ready",
        allowed_next_actions: ["create_work_packet"],
        blocker_reasons: [],
        source_links: [{ type: "verification_check", id: "check_1", graph_item_id: "graph_1", title: "Run tests" }],
        required_checks: [{ id: "check_1", graph_item_id: "graph_1", state: "open" }],
        source_watermark: null
      })
    );
    const input = {
      source_graph_item_ids: ["graph_1"],
      verification_check_ids: ["check_1"]
    };
    const api = createOperatorWorkflowApi({ fetcher });

    await expect(api.loadPacketReadiness(input)).resolves.toMatchObject({
      ready: true,
      status: "packet_ready"
    });
    expect(fetcher).toHaveBeenCalledWith("/api/operator-workflow/packet-readiness", {
      body: JSON.stringify(input),
      headers: { accept: "application/json", "content-type": "application/json" },
      method: "POST"
    });
  });

  it("loads run state and verification outcome by run id", async () => {
    const fetcher = vi
      .fn()
      .mockResolvedValueOnce(
        response({
          type: "operator_run_state",
          status: "awaiting_evidence_acceptance",
          allowed_next_actions: ["accept_evidence"],
          source_watermark: "run_1",
          packet: { id: "packet_1", title: "Packet", state: "active" },
          packet_version: {
            id: "version_1",
            version_number: 1,
            lifecycle_state: "active",
            objective: "Verify work"
          },
          run: {
            id: "run_1",
            aggregate_state: "running",
            execution_state: "completed",
            verification_state: "pending"
          },
          required_checks: [],
          observations: [],
          evidence_candidates: [],
          evidence_items: [],
          verification_results: [],
          missing_evidence: [{ verification_check_id: "check_1", reason: "missing_evidence" }]
        })
      )
      .mockResolvedValueOnce(
        response({
          type: "verification_outcome",
          status: "awaiting_evidence_acceptance",
          source_watermark: "run_1",
          run: { id: "run_1", aggregate_state: "running", execution_state: "completed", verification_state: "pending" },
          verification_results: [],
          missing_evidence: [{ verification_check_id: "check_1", reason: "missing_evidence" }]
        })
      );
    const api = createOperatorWorkflowApi({ fetcher });

    await expect(api.loadRunState("run_1")).resolves.toMatchObject({
      status: "awaiting_evidence_acceptance",
      run: { id: "run_1" }
    });
    await expect(api.loadVerificationOutcome("run_1")).resolves.toMatchObject({
      status: "awaiting_evidence_acceptance",
      run: { id: "run_1" }
    });
    expect(fetcher).toHaveBeenNthCalledWith(1, "/api/operator-workflow/runs/run_1", {
      headers: { accept: "application/json" },
      method: "GET"
    });
    expect(fetcher).toHaveBeenNthCalledWith(
      2,
      "/api/operator-workflow/runs/run_1/verification-outcome",
      {
        headers: { accept: "application/json" },
        method: "GET"
      }
    );
  });
});

function response(body: unknown, init: { ok?: boolean; status?: number } = {}) {
  return {
    ok: init.ok ?? true,
    status: init.status ?? 200,
    async json() {
      return body;
    }
  } as Response;
}
