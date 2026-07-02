import type { UseQueryResult } from "@tanstack/react-query";
import { render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";
import { InboxList } from "./InboxList";
import { ItemSummary } from "./ItemSummary";
import { ReadinessPanel } from "./ReadinessPanel";
import { RunPanel } from "./RunPanel";
import { graphQLInbox, graphQLRunState } from "../testSupport";
import { graphQLItem, graphQLRunState as mapRunState } from "../workflowMappers";
import type { OperatorInbox, OperatorRunState, OperatorWorkflowItem, PacketReadiness } from "../workflowTypes";

describe("operator panels", () => {
  it("shows an empty item state while the disabled item query is idle", () => {
    render(
      <ItemSummary
        item={null}
        itemQuery={queryResult<OperatorWorkflowItem>({
          fetchStatus: "idle",
          isError: false,
          isPending: true
        })}
      />
    );

    expect(screen.getAllByText("No item selected").length).toBeGreaterThan(0);
    expect(screen.queryByText("Loading item detail...")).not.toBeInTheDocument();
  });

  it("keeps the item detail loading state while the first fetch is paused", () => {
    render(
      <ItemSummary
        item={null}
        itemQuery={queryResult<OperatorWorkflowItem>({
          fetchStatus: "paused",
          isError: false,
          isPending: true
        })}
      />
    );

    expect(screen.getByText("Loading item detail...")).toBeInTheDocument();
  });

  it("labels stale readiness data when a refetch fails", () => {
    render(
      <ReadinessPanel
        readiness={packetReadiness}
        readinessQuery={queryResult<PacketReadiness>({
          data: packetReadiness,
          error: new Error("Unable to refresh readiness."),
          fetchStatus: "idle",
          isError: true,
          isPending: false
        })}
      />
    );

    expect(screen.getByText("Unable to refresh readiness.")).toBeInTheDocument();
    expect(screen.getByText("Showing last loaded readiness.")).toBeInTheDocument();
    expect(screen.getByText("Yes")).toBeInTheDocument();
  });

  it("labels stale run data when a refetch fails", () => {
    const runState = mapRunState(graphQLRunState);

    render(
      <RunPanel
        runId="run_1"
        runState={queryResult<OperatorRunState>({
          data: runState,
          error: new Error("Unable to refresh run."),
          fetchStatus: "idle",
          isError: true,
          isPending: false
        })}
      />
    );

    expect(screen.getByText("Unable to refresh run.")).toBeInTheDocument();
    expect(screen.getByText("Showing last loaded run state.")).toBeInTheDocument();
    expect(screen.getByText("Awaiting evidence acceptance")).toBeInTheDocument();
  });

  it("does not show run loading copy during a background refetch with data", () => {
    const runState = mapRunState(graphQLRunState);

    render(
      <RunPanel
        runId="run_1"
        runState={queryResult<OperatorRunState>({
          data: runState,
          fetchStatus: "fetching",
          isError: false,
          isPending: false
        })}
      />
    );

    expect(screen.queryByText("Loading run state...")).not.toBeInTheDocument();
    expect(screen.getByText("Awaiting evidence acceptance")).toBeInTheDocument();
  });

  it("labels stale inbox data when a refetch fails", () => {
    const row = graphQLItem(graphQLInbox.rows[0]);

    render(
      <InboxList
        inbox={queryResult<OperatorInbox>({
          data: { type: "operator_inbox", empty: false, sourceWatermark: "op_123", rows: [row] },
          error: new Error("Unable to refresh inbox."),
          fetchStatus: "idle",
          isError: true,
          isPending: false,
          isSuccess: false
        })}
        onSelect={vi.fn()}
        rows={[row]}
        selectedId={row.normalizedEventId}
      />
    );

    expect(screen.getByText("Unable to refresh inbox.")).toBeInTheDocument();
    expect(screen.getByText("Showing last loaded inbox.")).toBeInTheDocument();
    expect(screen.getByRole("button", { name: /evt_1/i })).toBeInTheDocument();
  });

  it("shows blocker context for blocked inbox rows", () => {
    const blocked = {
      ...graphQLItem(graphQLInbox.rows[0]),
      allowedNextActions: [],
      blockerReasons: ["duplicate_intake"],
      status: "blocked"
    };

    render(
      <InboxList
        inbox={queryResult<OperatorInbox>({
          data: { type: "operator_inbox", empty: false, sourceWatermark: "op_123", rows: [blocked] },
          fetchStatus: "idle",
          isError: false,
          isPending: false,
          isSuccess: true
        })}
        onSelect={vi.fn()}
        rows={[blocked]}
        selectedId={blocked.normalizedEventId}
      />
    );

    expect(screen.getByRole("button", { name: /blockers duplicate intake/i })).toBeInTheDocument();
  });
});

function queryResult<T>(overrides: Partial<UseQueryResult<T>>): UseQueryResult<T> {
  return {
    data: undefined,
    error: null,
    fetchStatus: "idle",
    isError: false,
    isPending: false,
    isSuccess: false,
    ...overrides
  } as UseQueryResult<T>;
}

const packetReadiness: PacketReadiness = {
  type: "packet_readiness",
  ready: true,
  status: "packet_ready",
  allowedNextActions: ["create_work_packet"],
  blockerReasons: [],
  sourceLinks: [{ type: "task", id: "task_1", graphItemId: "graph_1", title: "Task" }],
  requiredChecks: [{ id: "check_1", graphItemId: "graph_1", state: "required" }],
  sourceWatermark: null
};
