import { act, fireEvent, render, screen, waitFor } from "@testing-library/react";
import type { ReactElement } from "react";
import { RelayEnvironmentProvider } from "react-relay";
import { MemoryRouter } from "react-router";
import {
  Environment,
  Network,
  RecordSource,
  Store,
  type FetchFunction,
  type GraphQLResponse
} from "relay-runtime";
import { afterEach, describe, expect, it, vi } from "vitest";
import { getOfficeGraphDataID } from "../../relay/environment";
import { fetchGraphQL, GraphQLResponseError } from "../../relay/fetchGraphQL";
import OperatorRoute from "./route";

describe("operator route", () => {
  afterEach(() => {
    vi.unstubAllGlobals();
    vi.restoreAllMocks();
  });

  it("renders a Suspense-driven inbox loading workspace", () => {
    const workflowResponse = deferredGraphQLResponse();
    const network = vi.fn(async (request): Promise<GraphQLResponse> => {
      if (request.name === "OperatorWorkflowRouteQuery") {
        return workflowResponse.promise;
      }

      throw new Error(`Unexpected Relay request in operator route test: ${request.name}`);
    });

    renderWithRelay(<OperatorRoute />, network);

    expect(screen.getByRole("heading", { name: "Operator Console" })).toBeInTheDocument();
    expect(screen.getByRole("status")).toHaveTextContent("Loading inbox...");
    expect(screen.getByRole("region", { name: "Item detail" })).toHaveTextContent(
      "No item selected"
    );
  });

  it("renders the operator workbench from Relay projection data", async () => {
    const network = createOperatorNetwork({
      workflowItems: [operatorWorkflowItem()],
      runState: operatorRunState()
    });

    renderWithRelay(<OperatorRoute />, network);

    expect(screen.getByRole("heading", { name: "Operator Console" })).toBeInTheDocument();
    const firstRow = await screen.findByRole("button", { name: /evt_1/i });

    await waitFor(() => {
      expect(firstRow).toHaveAttribute("aria-current", "true");
    });
    expect(screen.getByRole("region", { name: "Inbox" })).toHaveTextContent("Ready for packet");
    expect(screen.getByRole("region", { name: "Item detail" })).toHaveTextContent(
      "normalized_intake_event: evt_1"
    );
    expect(await screen.findByText("Prepare packet context")).toBeInTheDocument();
    const readinessCall = network.mock.calls.find(
      ([request]) => request.name === "OperatorPacketReadinessQuery"
    );

    expect(readinessCall).toBeUndefined();

    await waitFor(() => {
      expect(screen.getByRole("region", { name: "Run State" })).toHaveTextContent(
        "Awaiting evidence acceptance"
      );
      expect(screen.getByRole("region", { name: "Verification" })).toHaveTextContent(
        "Owner acceptance"
      );
    });
  });

  it("opens a packet-workspace run link from the route query string", async () => {
    const runState = operatorRunState();
    const network = createOperatorNetwork({
      workflowItems: [operatorWorkflowItem()],
      runState: { ...runState, run: { ...runState.run, id: "run_linked" } }
    });

    renderWithRelay(<OperatorRoute />, network, "/operator?runId=run_linked");

    await waitFor(() => {
      const runCall = network.mock.calls.find(
        ([request]) => request.name === "OperatorRunStateQuery"
      );
      expect(runCall?.[1]).toEqual({ id: "run_linked" });
    });
    await waitFor(() => {
      expect(screen.getByRole("region", { name: "Run State" })).toHaveTextContent(
        "Awaiting evidence acceptance"
      );
    });
    expect(screen.getByRole("button", { name: /evt_1/i })).not.toHaveAttribute(
      "aria-current"
    );
    expect(screen.getByRole("region", { name: "Item detail" })).toHaveTextContent(
      "No item selected"
    );
    expect(screen.getByRole("region", { name: "Packet Readiness" })).toHaveTextContent(
      "No packet readiness selected"
    );
  });

  it("validates locally derived packet readiness before exposing backend commands", async () => {
    const network = vi.fn(async (request, variables): Promise<GraphQLResponse> => {
      if (request.name === "OperatorWorkflowRouteQuery") {
        return workflowConnectionResponse([operatorWorkflowItem()], variables);
      }

      if (request.name === "OperatorRunStateQuery") {
        return { data: { operatorRunState: operatorRunState() } };
      }

      if (request.name === "OperatorPacketReadinessQuery") {
        return { data: { operatorPacketReadiness: operatorPacketReadiness() } };
      }

      throw new Error(`Unexpected Relay request in operator route test: ${request.name}`);
    });

    renderWithRelay(<OperatorRoute />, network);

    expect(await screen.findByText("Prepare packet context")).toBeInTheDocument();
    expect(screen.getByRole("region", { name: "Packet Readiness" })).toHaveTextContent(
      "Blocked"
    );
    expect(screen.queryByRole("button", { name: "Execute verification" })).not.toBeInTheDocument();
    expect(network.mock.calls.some(([request]) => request.name === "OperatorPacketReadinessQuery"))
      .toBe(false);
    fireEvent.click(screen.getByRole("button", { name: "Validate readiness" }));

    await waitFor(() => {
      const readinessCall = network.mock.calls.find(
        ([request]) => request.name === "OperatorPacketReadinessQuery"
      );

      expect(readinessCall?.[1]).toEqual({
        input: {
          title: "Run console verification",
          objective: "Run console verification",
          contextSummary: "Run console verification",
          requirements: "Run console verification",
          successCriteria: "Run console verification",
          autonomyPosture: "human_supervised",
          sourceGraphItemIds: ["graph_1"],
          verificationCheckIds: ["check_1"]
        }
      });
    });
    await waitFor(() => {
      expect(screen.getByRole("region", { name: "Packet Readiness" })).toHaveTextContent(
        "Backend readiness"
      );
      expect(screen.getByRole("region", { name: "Packet Readiness" })).toHaveTextContent(
        "Create work packet"
      );
    });
    expect(screen.queryByRole("button", { name: "Execute verification" })).not.toBeInTheDocument();
  });

  it("keeps derived readiness and workspace context visible while validation suspends", async () => {
    const readinessResponse = deferredGraphQLResponse();
    const network = vi.fn(async (request, variables): Promise<GraphQLResponse> => {
      if (request.name === "OperatorWorkflowRouteQuery") {
        return workflowConnectionResponse([operatorWorkflowItem()], variables);
      }

      if (request.name === "OperatorRunStateQuery") {
        return { data: { operatorRunState: operatorRunState() } };
      }

      if (request.name === "OperatorPacketReadinessQuery") {
        return readinessResponse.promise;
      }

      throw new Error(`Unexpected Relay request in operator route test: ${request.name}`);
    });

    renderWithRelay(<OperatorRoute />, network);

    const selectedRow = await screen.findByRole("button", { name: /evt_1/i });
    fireEvent.click(screen.getByRole("button", { name: "Validate readiness" }));

    const readiness = screen.getByRole("region", { name: "Packet Readiness" });

    expect(readiness).toHaveTextContent("Prepare packet context");
    expect(screen.getByRole("button", { name: "Validating readiness" })).toBeDisabled();
    expect(selectedRow).toHaveAttribute("aria-current", "true");
    expect(screen.getByRole("region", { name: "Item detail" })).toHaveTextContent(
      "normalized_intake_event: evt_1"
    );

    await act(async () => {
      readinessResponse.resolve({
        data: { operatorPacketReadiness: operatorPacketReadiness() }
      });
    });

    await waitFor(() => {
      expect(screen.getByRole("region", { name: "Packet Readiness" })).toHaveTextContent(
        "Backend readiness"
      );
    });
  });

  it("keeps the operator workspace visible when readiness validation fails", async () => {
    vi.spyOn(console, "error").mockImplementation(() => undefined);
    let readinessReads = 0;
    const network = vi.fn(async (request, variables): Promise<GraphQLResponse> => {
      if (request.name === "OperatorWorkflowRouteQuery") {
        return workflowConnectionResponse([operatorWorkflowItem()], variables);
      }

      if (request.name === "OperatorRunStateQuery") {
        return { data: { operatorRunState: operatorRunState() } };
      }

      if (request.name === "OperatorPacketReadinessQuery") {
        readinessReads += 1;
        if (readinessReads === 1) {
          throw new Error("authorization secret_alpha denied readiness_9");
        }

        return { data: { operatorPacketReadiness: operatorPacketReadiness() } };
      }

      throw new Error(`Unexpected Relay request in operator route test: ${request.name}`);
    });

    renderWithRelay(<OperatorRoute />, network);

    const selectedRow = await screen.findByRole("button", { name: /evt_1/i });
    fireEvent.click(screen.getByRole("button", { name: "Validate readiness" }));

    await waitFor(() => {
      expect(screen.getByRole("region", { name: "Packet Readiness" })).toHaveTextContent(
        "Unable to validate packet readiness."
      );
    });
    expect(selectedRow).toHaveAttribute("aria-current", "true");
    expect(screen.getByRole("region", { name: "Item detail" })).toHaveTextContent(
      "normalized_intake_event: evt_1"
    );
    expect(document.body).not.toHaveTextContent("secret_alpha");
    expect(document.body).not.toHaveTextContent("readiness_9");

    fireEvent.click(screen.getByRole("button", { name: "Retry packet readiness" }));

    await waitFor(() => {
      expect(screen.getByRole("region", { name: "Packet Readiness" })).toHaveTextContent(
        "Backend readiness"
      );
    });
    expect(readinessReads).toBe(2);
  });

  it("shows the empty state without enabling workflow commands", async () => {
    const network = createOperatorNetwork({ workflowItems: [] });

    renderWithRelay(<OperatorRoute />, network);

    expect(await screen.findByText("No operator workflow items.")).toBeInTheDocument();
    expect(screen.getAllByText("No item selected").length).toBeGreaterThan(0);
    expect(screen.getByText("No packet readiness selected.")).toBeInTheDocument();
    expect(screen.queryByText("Loading item detail...")).not.toBeInTheDocument();
    expect(screen.queryByText("Loading readiness...")).not.toBeInTheDocument();
    expect(screen.queryByRole("button", { name: /apply/i })).not.toBeInTheDocument();
  });

  it("treats a nullable Relay workflow connection as an empty inbox", async () => {
    const network = createOperatorNetwork({ workflowItems: null });

    renderWithRelay(<OperatorRoute />, network);

    expect(await screen.findByText("No operator workflow items.")).toBeInTheDocument();
    expect(screen.getByText("No packet readiness selected.")).toBeInTheDocument();
    expect(screen.queryByText(/GraphQL operator workflow connection/i)).not.toBeInTheDocument();
  });

  it("surfaces GraphQL errors instead of treating a null workflow connection as empty", async () => {
    vi.spyOn(console, "error").mockImplementation(() => undefined);
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue(
        Response.json({
          data: { operatorWorkflowItems: null },
          errors: [{ message: "Operator workflow access is forbidden" }]
        })
      )
    );

    renderWithRelay(<OperatorRoute />, fetchGraphQL);

    expect(await screen.findByRole("alert")).toHaveTextContent(
      "Unable to load operator inbox."
    );
    expect(document.body).not.toHaveTextContent("Operator workflow access is forbidden");
    expect(screen.queryByText("No operator workflow items.")).not.toBeInTheDocument();
  });

  it("renders only the requested manual inbox page after paging forward", async () => {
    const nextPage = deferredGraphQLResponse();
    const firstItem = operatorWorkflowItem();
    const secondItem = operatorWorkflowItem({
      id: "operator_workflow_item_global_2",
      normalizedEventId: "evt_2",
      typedId: { type: "normalized_intake_event", id: "evt_2" },
      source: {
        identity: "manual:operator-console-2",
        replayIdentity: "paste:operator-console-2",
        outcome: "accepted"
      }
    });
    const network = vi.fn(async (request, variables): Promise<GraphQLResponse> => {
      if (request.name === "OperatorWorkflowRouteQuery") {
        return variables.after === "cursor_1"
          ? nextPage.promise
          : workflowConnectionResponse([firstItem], variables, {
              hasNextPage: true,
              hasPreviousPage: false,
              startCursor: "cursor_1",
              endCursor: "cursor_1"
            });
      }

      if (request.name === "OperatorPacketReadinessQuery") {
        return { data: { operatorPacketReadiness: operatorPacketReadiness() } };
      }

      if (request.name === "OperatorRunStateQuery") {
        return { data: { operatorRunState: operatorRunState() } };
      }

      throw new Error(`Unexpected Relay request in operator route test: ${request.name}`);
    });

    renderWithRelay(<OperatorRoute />, network);

    expect(await screen.findByRole("button", { name: /evt_1/i })).toBeInTheDocument();
    await waitFor(() =>
      expect(screen.getByRole("button", { name: "Next" })).toBeEnabled()
    );
    fireEvent.click(screen.getByRole("button", { name: "Next" }));

    expect(screen.getByRole("status")).toHaveTextContent("Loading inbox...");
    expect(screen.queryByRole("button", { name: /evt_1/i })).not.toBeInTheDocument();
    expect(screen.getByRole("region", { name: "Item detail" })).toHaveTextContent(
      "No item selected"
    );

    nextPage.resolve(
      workflowConnectionResponse([secondItem], { after: "cursor_1" }, {
        hasNextPage: false,
        hasPreviousPage: true,
        startCursor: "cursor_2",
        endCursor: "cursor_2"
      })
    );

    await waitFor(() => {
      expect(screen.queryByRole("button", { name: /evt_1/i })).not.toBeInTheDocument();
      expect(screen.getByRole("button", { name: /evt_2/i })).toHaveAttribute(
        "aria-current",
        "true"
      );
      expect(screen.getByLabelText("Inbox pagination")).toHaveTextContent("1 row");
    });
  });

  it("renders distinct policy-safe summaries and proposal previews for one source", async () => {
    const firstItem = operatorWorkflowItem({
      id: "operator_workflow_item_summary_1",
      normalizedEventId: "evt_summary_1",
      typedId: { type: "normalized_intake_event", id: "evt_summary_1" },
      title: "Investigate invoice export",
      sourceSummary: "manual:shared-source · Investigate invoice export",
      proposedActionPreviews: [
        { action: "create_signal", title: "Investigate invoice export", status: "pending" },
        { action: "create_task", title: "Investigate invoice export", status: "pending" }
      ],
      source: {
        identity: "manual:shared-source",
        replayIdentity: "paste:summary-1",
        outcome: "accepted"
      }
    });
    const secondItem = operatorWorkflowItem({
      id: "operator_workflow_item_summary_2",
      normalizedEventId: "evt_summary_2",
      typedId: { type: "normalized_intake_event", id: "evt_summary_2" },
      title: "Review payroll import",
      sourceSummary: "manual:shared-source · Review payroll import",
      proposedActionPreviews: [
        { action: "create_signal", title: "Review payroll import", status: "pending" }
      ],
      source: {
        identity: "manual:shared-source",
        replayIdentity: "paste:summary-2",
        outcome: "accepted"
      }
    });

    renderWithRelay(
      <OperatorRoute />,
      createOperatorNetwork({ workflowItems: [firstItem, secondItem] })
    );

    expect(await screen.findByRole("button", { name: /Investigate invoice export/i })).toBeInTheDocument();
    expect(screen.getByRole("button", { name: /Review payroll import/i })).toBeInTheDocument();
    expect(screen.getByRole("region", { name: "Item detail" })).toHaveTextContent(
      "Create signal: Investigate invoice export"
    );
  });

  it("returns to the previous inbox page when the next page fails", async () => {
    vi.spyOn(console, "error").mockImplementation(() => undefined);
    const network = vi.fn(async (request, variables): Promise<GraphQLResponse> => {
      if (request.name === "OperatorWorkflowRouteQuery") {
        if (variables.after === "cursor_1") {
          throw new Error("GraphQL unavailable secret_alpha");
        }

        return workflowConnectionResponse([operatorWorkflowItem()], variables, {
          hasNextPage: true,
          hasPreviousPage: false,
          startCursor: "cursor_1",
          endCursor: "cursor_1"
        });
      }

      if (request.name === "OperatorRunStateQuery") {
        return { data: { operatorRunState: operatorRunState() } };
      }

      throw new Error(`Unexpected Relay request in operator route test: ${request.name}`);
    });

    renderWithRelay(<OperatorRoute />, network);

    expect(await screen.findByRole("button", { name: /evt_1/i })).toBeInTheDocument();
    await waitFor(() =>
      expect(screen.getByRole("button", { name: "Next" })).toBeEnabled()
    );
    fireEvent.click(screen.getByRole("button", { name: "Next" }));

    expect(await screen.findByRole("alert")).toHaveTextContent(
      "Unable to load operator inbox."
    );
    expect(document.body).not.toHaveTextContent("secret_alpha");
    expect(screen.getByRole("button", { name: "Previous" })).toBeEnabled();

    fireEvent.click(screen.getByRole("button", { name: "Previous" }));

    await waitFor(() => {
      const workflowCalls = network.mock.calls.filter(
        ([request]) => request.name === "OperatorWorkflowRouteQuery"
      );

      expect(workflowCalls.at(-1)?.[1]).toEqual({ first: 50, after: null });
      expect(screen.getByRole("button", { name: /evt_1/i })).toHaveAttribute(
        "aria-current",
        "true"
      );
      expect(screen.getByRole("button", { name: "Previous" })).toBeDisabled();
    });
  });

  it("renders a safe route error for Relay transport failures", async () => {
    vi.spyOn(console, "error").mockImplementation(() => undefined);
    const network = vi.fn(async () => {
      throw new Error("GraphQL unavailable secret_alpha");
    });

    renderWithRelay(<OperatorRoute />, network);

    expect(await screen.findByRole("alert")).toHaveTextContent(
      "Unable to load operator inbox."
    );
    expect(document.body).not.toHaveTextContent("GraphQL unavailable");
    expect(document.body).not.toHaveTextContent("secret_alpha");
  });

  it("retries a failed workflow query without requiring navigation", async () => {
    vi.spyOn(console, "error").mockImplementation(() => undefined);
    let workflowReads = 0;
    const network = vi.fn(async (request, variables): Promise<GraphQLResponse> => {
      if (request.name === "OperatorWorkflowRouteQuery") {
        workflowReads += 1;
        if (workflowReads === 1) throw new Error("temporary workflow failure");
        return workflowConnectionResponse([operatorWorkflowItem()], variables);
      }
      if (request.name === "OperatorRunStateQuery") {
        return { data: { operatorRunState: operatorRunState() } };
      }
      throw new Error(`Unexpected Relay request in operator route test: ${request.name}`);
    });

    renderWithRelay(<OperatorRoute />, network);

    expect(await screen.findByRole("alert")).toHaveTextContent("Unable to load operator inbox");
    fireEvent.click(screen.getByRole("button", { name: "Retry operator workflow" }));

    expect(await screen.findByRole("button", { name: /evt_1/i })).toBeInTheDocument();
    expect(workflowReads).toBe(2);
  });

  it("updates the selected row and derived workflow panels from Relay data", async () => {
    const secondItem = operatorWorkflowItem({
      id: "operator_workflow_item_global_2",
      normalizedEventId: "evt_2",
      typedId: { type: "normalized_intake_event", id: "evt_2" },
      source: {
        identity: "manual:operator-console-2",
        replayIdentity: "paste:operator-console-2",
        outcome: "accepted"
      },
      graphLinks: [
        {
          type: "verification_check",
          id: "check_2",
          graphItemId: "graph_2",
          title: "Review second packet",
          state: "required"
        }
      ]
    });
    const network = createOperatorNetwork({
      workflowItems: [operatorWorkflowItem(), secondItem]
    });

    renderWithRelay(<OperatorRoute />, network);

    const secondRow = await screen.findByRole("button", { name: /evt_2/i });
    fireEvent.click(secondRow);

    await waitFor(() => {
      expect(secondRow).toHaveAttribute("aria-current", "true");
      expect(screen.getByRole("region", { name: "Item detail" })).toHaveTextContent(
        "normalized_intake_event: evt_2"
      );
      expect(screen.getByRole("region", { name: "Packet Readiness" })).toHaveTextContent(
        "Review second packet"
      );
    });
  });

  it("clears selection-scoped panels while loading a newly selected item", async () => {
    const secondRunState = deferredGraphQLResponse();
    const secondItem = operatorWorkflowItem({
      id: "operator_workflow_item_global_2",
      normalizedEventId: "evt_2",
      typedId: { type: "normalized_intake_event", id: "evt_2" },
      graphLinks: [
        {
          type: "verification_check",
          id: "check_2",
          graphItemId: "graph_2",
          title: "Review second packet",
          state: "required"
        },
        {
          type: "work_run",
          id: "run_2",
          graphItemId: null,
          title: "Second verification run",
          state: "running"
        }
      ]
    });
    const network = vi.fn(async (request, variables): Promise<GraphQLResponse> => {
      if (request.name === "OperatorWorkflowRouteQuery") {
        return workflowConnectionResponse([operatorWorkflowItem(), secondItem], variables);
      }

      if (request.name === "OperatorRunStateQuery") {
        if (variables.id === "run_2") {
          return secondRunState.promise;
        }

        return { data: { operatorRunState: operatorRunState() } };
      }

      throw new Error(`Unexpected Relay request in operator route test: ${request.name}`);
    });

    renderWithRelay(<OperatorRoute />, network);

    const secondRow = await screen.findByRole("button", { name: /evt_2/i });

    await waitFor(() => {
      expect(screen.getByRole("region", { name: "Packet Readiness" })).toHaveTextContent(
        "Run console verification"
      );
      expect(screen.getByRole("region", { name: "Run State" })).toHaveTextContent(
        "Awaiting evidence acceptance"
      );
    });

    fireEvent.click(secondRow);

    await waitFor(() => {
      expect(secondRow).toHaveAttribute("aria-current", "true");
      expect(screen.getByRole("region", { name: "Packet Readiness" })).toHaveTextContent(
        "Review second packet"
      );
      expect(screen.getByRole("region", { name: "Run State" })).toHaveTextContent(
        "Loading run state..."
      );
      expect(screen.getByRole("region", { name: "Run State" })).not.toHaveTextContent(
        "Awaiting evidence acceptance"
      );
      expect(screen.getByRole("region", { name: "Verification" })).toHaveTextContent(
        "Loading verification..."
      );
      expect(screen.getByRole("region", { name: "Verification" })).not.toHaveTextContent(
        "Owner acceptance"
      );
      expect(screen.getByRole("region", { name: "Item detail" })).toHaveTextContent(
        "normalized_intake_event: evt_2"
      );
    });

    secondRunState.resolve({
      data: {
        operatorRunState: operatorRunState({ status: "verified" })
      }
    });

    await waitFor(() => {
      expect(screen.getByRole("region", { name: "Packet Readiness" })).toHaveTextContent(
        "Review second packet"
      );
      expect(screen.getByRole("region", { name: "Run State" })).toHaveTextContent("Verified");
    });
  });

  it("keeps inbox, item, and readiness context when a linked run fails", async () => {
    vi.spyOn(console, "error").mockImplementation(() => undefined);
    let runReads = 0;
    const network = vi.fn(async (request, variables): Promise<GraphQLResponse> => {
      if (request.name === "OperatorWorkflowRouteQuery") {
        return workflowConnectionResponse([operatorWorkflowItem()], variables);
      }

      if (request.name === "OperatorRunStateQuery") {
        runReads += 1;
        if (runReads === 1) {
          throw new Error("authorization secret_alpha denied run_9");
        }

        return { data: { operatorRunState: operatorRunState() } };
      }

      throw new Error(`Unexpected Relay request in operator route test: ${request.name}`);
    });

    renderWithRelay(<OperatorRoute />, network);

    const selectedRow = await screen.findByRole("button", { name: /evt_1/i });

    await waitFor(() => {
      expect(screen.getByRole("region", { name: "Run State" })).toHaveTextContent(
        "Run state unavailable."
      );
      expect(screen.getByRole("region", { name: "Verification" })).toHaveTextContent(
        "Verification unavailable."
      );
    });
    expect(selectedRow).toHaveAttribute("aria-current", "true");
    expect(screen.getByRole("region", { name: "Item detail" })).toHaveTextContent(
      "normalized_intake_event: evt_1"
    );
    expect(screen.getByRole("region", { name: "Packet Readiness" })).toHaveTextContent(
      "Prepare packet context"
    );
    expect(document.body).not.toHaveTextContent("secret_alpha");
    expect(document.body).not.toHaveTextContent("run_9");

    fireEvent.click(screen.getByRole("button", { name: "Retry run state" }));

    await waitFor(() => {
      expect(screen.getByRole("region", { name: "Run State" })).toHaveTextContent(
        "Awaiting evidence acceptance"
      );
    });
    expect(runReads).toBe(2);
  });

  it("renders command affordance states without leaking hidden or redacted policy details", async () => {
    const sensitiveAffordances = [
      {
        identity: "create_work_packet",
        state: "enabled",
        reasonCodes: [],
        blockerReasons: [],
        safeExplanation: "Prepare a work packet from the applied intake.",
        requiredFields: [],
        inputDefaults: [],
        targetIds: [],
        traceLinks: [],
        decisionLinks: []
      },
      {
        identity: "accept_evidence",
        state: "disabled",
        reasonCodes: ["missing_accepted_evidence"],
        blockerReasons: ["missing accepted evidence"],
        safeExplanation: "Accept evidence after a candidate is selected.",
        requiredFields: ["evidence_item_id"],
        inputDefaults: [],
        targetIds: [],
        traceLinks: [],
        decisionLinks: []
      },
      {
        identity: "delete_restricted_packet",
        state: "hidden",
        reasonCodes: ["policy_hidden"],
        blockerReasons: ["requires secret_policy_bundle_alpha"],
        safeExplanation: "Secret graph item graph_secret_99 exists in a restricted compartment.",
        requiredFields: ["restricted_resource_id"],
        inputDefaults: [],
        targetIds: [],
        traceLinks: [],
        decisionLinks: []
      },
      {
        identity: "inspect_vip_target",
        state: "redacted",
        reasonCodes: ["target_redacted"],
        blockerReasons: ["tenant policy map alpha"],
        safeExplanation: "VIP target graph_secret_42 is restricted by policy bundle alpha.",
        requiredFields: ["target_graph_item_id"],
        inputDefaults: [],
        targetIds: [],
        traceLinks: [],
        decisionLinks: []
      }
    ];
    const network = createOperatorNetwork({
      workflowItems: [
        operatorWorkflowItem({
          allowedNextActions: ["legacy_sensitive_fallback"],
          commandAffordances: sensitiveAffordances
        })
      ],
      readiness: operatorPacketReadiness({
        allowedNextActions: ["legacy_sensitive_readiness_fallback"],
        commandAffordances: sensitiveAffordances
      }),
      runState: operatorRunState({
        allowedNextActions: ["legacy_sensitive_run_fallback"],
        commandAffordances: sensitiveAffordances
      })
    });

    renderWithRelay(<OperatorRoute />, network);

    await screen.findByRole("button", { name: /evt_1/i });
    const itemDetail = screen.getByRole("region", { name: "Item detail" });

    await waitFor(() => {
      expect(itemDetail).toHaveTextContent("Commands");
      expect(screen.getByRole("region", { name: "Run State" })).toHaveTextContent(
        "Awaiting evidence acceptance"
      );
    });

    expect(itemDetail).toHaveTextContent("Create work packet");
    expect(itemDetail).toHaveTextContent("Accept evidence disabled");
    expect(itemDetail).toHaveTextContent("Accept evidence after a candidate is selected.");
    expect(itemDetail).toHaveTextContent("Hidden command: Policy hidden");
    expect(itemDetail).toHaveTextContent("Redacted command: Target redacted");

    const renderedText = document.body.textContent ?? "";

    expect(renderedText).not.toMatch(/legacy sensitive/i);
    expect(renderedText).not.toMatch(/delete restricted packet/i);
    expect(renderedText).not.toMatch(/inspect vip target/i);
    expect(renderedText).not.toMatch(/graph_secret_99|graph_secret_42/i);
    expect(renderedText).not.toMatch(/secret policy bundle alpha/i);
    expect(renderedText).not.toMatch(/tenant policy map alpha/i);
    expect(renderedText).not.toMatch(/restricted resource id/i);
    expect(renderedText).not.toMatch(/target graph item id/i);
    expect(screen.queryByRole("button", { name: "Accept evidence" })).not.toBeInTheDocument();
  });

  it("submits manual intake once and refreshes the current inbox", async () => {
    const mutationResponse = deferredGraphQLResponse();
    let workflowReads = 0;
    const network = vi.fn(async (request, variables): Promise<GraphQLResponse> => {
      if (request.name === "OperatorWorkflowRouteQuery") {
        workflowReads += 1;
        return workflowConnectionResponse(
          workflowReads === 1
            ? []
            : [operatorWorkflowItem({ id: "operator_workflow_item_new", normalizedEventId: "evt_new" })],
          variables
        );
      }

      if (request.name === "OperatorSubmitManualIntakeMutation") {
        return mutationResponse.promise;
      }

      if (request.name === "OperatorRunStateQuery") {
        return { data: { operatorRunState: operatorRunState() } };
      }

      throw new Error(`Unexpected Relay request in operator route test: ${request.name}`);
    });

    renderWithRelay(<OperatorRoute />, network);

    const body = await screen.findByLabelText("Manual intake");
    fireEvent.change(body, { target: { value: "Investigate the failed deployment" } });
    fireEvent.click(screen.getByRole("button", { name: "Submit intake" }));
    fireEvent.click(screen.getByRole("button", { name: "Submitting intake" }));

    expect(screen.getByRole("button", { name: "Submitting intake" })).toBeDisabled();
    await waitFor(() => expect(
      network.mock.calls.filter(([request]) => request.name === "OperatorSubmitManualIntakeMutation")
    ).toHaveLength(1));
    expect(
      network.mock.calls.find(([request]) => request.name === "OperatorSubmitManualIntakeMutation")?.[1]
    ).toMatchObject({
      input: {
        body: "Investigate the failed deployment",
        replayIdentity: expect.stringMatching(/^operator:/),
        sourceIdentity: "manual:operator-console"
      }
    });

    await act(async () => {
      mutationResponse.resolve({
        data: {
          submitManualIntake: {
            command: "submit_manual_intake",
            operationId: "operation_intake_1",
            affectedIds: [{ type: "normalized_intake_event", id: "evt_new" }],
            normalizedEventId: "evt_new",
            proposedChangeIds: ["change_1"]
          }
        }
      });
    });

    await waitFor(() => expect(workflowReads).toBe(2));
    expect(await screen.findByRole("button", { name: /evt_new/i })).toBeInTheDocument();
  });

  it("leaves a linked run, returns to the first inbox page, and selects a newly submitted intake", async () => {
    let submitted = false;
    const firstItem = operatorWorkflowItem();
    const secondItem = operatorWorkflowItem({
      id: "operator_workflow_item_2",
      normalizedEventId: "evt_2",
      typedId: { type: "normalized_intake_event", id: "evt_2" }
    });
    const newItem = operatorWorkflowItem({
      id: "operator_workflow_item_new",
      normalizedEventId: "evt_new",
      typedId: { type: "normalized_intake_event", id: "evt_new" }
    });
    const network = vi.fn(async (request, variables): Promise<GraphQLResponse> => {
      if (request.name === "OperatorWorkflowRouteQuery") {
        if (variables.after === "cursor_1") {
          return workflowConnectionResponse([secondItem], variables);
        }

        return workflowConnectionResponse(
          submitted ? [newItem, firstItem] : [firstItem],
          variables,
          submitted ? {} : { hasNextPage: true, endCursor: "cursor_1" }
        );
      }

      if (request.name === "OperatorSubmitManualIntakeMutation") {
        submitted = true;
        return {
          data: {
            submitManualIntake: {
              command: "submit_manual_intake",
              operationId: "operation_intake_new",
              affectedIds: [{ type: "normalized_intake_event", id: "evt_new" }],
              normalizedEventId: "evt_new",
              proposedChangeIds: ["change_new"]
            }
          }
        };
      }

      if (request.name === "OperatorRunStateQuery") {
        return { data: { operatorRunState: operatorRunState() } };
      }

      throw new Error(`Unexpected Relay request in operator route test: ${request.name}`);
    });

    renderWithRelay(<OperatorRoute />, network, "/operator?runId=run_linked");
    await screen.findByRole("button", { name: /evt_1/i });
    fireEvent.click(screen.getByRole("button", { name: "Next" }));
    await screen.findByRole("button", { name: /evt_2/i });

    fireEvent.change(screen.getByLabelText("Manual intake"), {
      target: { value: "Investigate the new deployment failure" }
    });
    fireEvent.click(screen.getByRole("button", { name: "Submit intake" }));

    const newRow = await screen.findByRole("button", { name: /evt_new/i });
    await waitFor(() => expect(newRow).toHaveAttribute("aria-current", "true"));
    expect(lastVariablesFor(network, "OperatorWorkflowRouteQuery")).toEqual({
      first: 50,
      after: null
    });
    expect(screen.getByRole("button", { name: "Previous" })).toBeDisabled();
  });

  it("hides manual intake when the backend affordance is restricted", async () => {
    const network = vi.fn(async (request, variables): Promise<GraphQLResponse> => {
      if (request.name === "OperatorWorkflowRouteQuery") {
        return workflowConnectionResponse([], variables, {}, {
          ...enabledCommandAffordance("submit_manual_intake"),
          state: "hidden"
        });
      }
      throw new Error(`Unexpected Relay request in operator route test: ${request.name}`);
    });

    renderWithRelay(<OperatorRoute />, network);

    await screen.findByText("No operator workflow items.");
    expect(screen.queryByLabelText("Manual intake")).not.toBeInTheDocument();
  });

  it("recovers when manual replay identity preparation fails", async () => {
    vi.stubGlobal("crypto", {
      subtle: { digest: vi.fn().mockRejectedValue(new Error("digest unavailable")) }
    });
    const network = createOperatorNetwork({ workflowItems: [] });

    renderWithRelay(<OperatorRoute />, network);
    fireEvent.change(await screen.findByLabelText("Manual intake"), {
      target: { value: "Investigate the deployment" }
    });
    fireEvent.click(screen.getByRole("button", { name: "Submit intake" }));

    expect(await screen.findByRole("alert")).toHaveTextContent(
      "Unable to prepare manual intake. Try again."
    );
    expect(screen.getByRole("button", { name: "Submit intake" })).toBeEnabled();
    expect(network.mock.calls.some(([request]) =>
      request.name === "OperatorSubmitManualIntakeMutation"
    )).toBe(false);
  });

  it("refreshes after a manual-intake replay conflict and keeps the explicit retry form", async () => {
    let workflowReads = 0;
    const refreshResponse = deferredGraphQLResponse();
    const network = vi.fn(async (request, variables): Promise<GraphQLResponse> => {
      if (request.name === "OperatorWorkflowRouteQuery") {
        workflowReads += 1;
        if (workflowReads === 2) return refreshResponse.promise;
        return workflowConnectionResponse([], variables);
      }
      if (request.name === "OperatorSubmitManualIntakeMutation") throw new GraphQLResponseError(
        "This intake was already accepted. Refresh and retry if the source changed.",
        { errors: [{
          message: "This intake was already accepted. Refresh and retry if the source changed.",
          extensions: { code: "manual_intake_replay_conflict" }
        } as never] },
        409,
        request.name
      );
      throw new Error(`Unexpected Relay request in operator route test: ${request.name}`);
    });

    renderWithRelay(<OperatorRoute />, network);
    fireEvent.change(await screen.findByLabelText("Manual intake"), { target: { value: "Duplicate deployment report" } });
    fireEvent.click(screen.getByRole("button", { name: "Submit intake" }));

    expect(await screen.findByRole("alert")).toHaveTextContent("This intake was already accepted");
    await waitFor(() => expect(workflowReads).toBe(2));
    expect(screen.getByLabelText("Manual intake")).toHaveValue("Duplicate deployment report");
    expect(screen.getByRole("button", { name: "Submit intake" })).toBeEnabled();

    await act(async () => {
      refreshResponse.resolve(workflowConnectionResponse([], { first: 50, after: null }));
    });
  });

  it("applies only the selected item's enabled proposal affordance defaults", async () => {
    const proposalAffordance = {
      identity: "apply_proposed_changes",
      state: "enabled",
      reasonCodes: [],
      blockerReasons: [],
      safeExplanation: "Apply pending proposed changes for this intake.",
      requiredFields: ["normalized_event_id", "proposed_change_ids"],
      inputDefaults: [
        { field: "normalized_event_id", value: "evt_1", values: [] },
        { field: "proposed_change_ids", value: null, values: ["change_1", "change_2"] }
      ],
      targetIds: [{ type: "normalized_intake_event", id: "evt_1" }],
      traceLinks: [],
      decisionLinks: []
    };
    const network = vi.fn(async (request, variables): Promise<GraphQLResponse> => {
      if (request.name === "OperatorWorkflowRouteQuery") {
        return workflowConnectionResponse([
          operatorWorkflowItem({
            status: "pending_triage",
            allowedNextActions: ["apply_proposed_changes"],
            commandAffordances: [proposalAffordance]
          })
        ], variables);
      }

      if (request.name === "OperatorRunStateQuery") {
        return { data: { operatorRunState: operatorRunState() } };
      }

      if (request.name === "OperatorApplyProposedChangesMutation") {
        return {
          data: {
            applyProposedChanges: {
              command: "apply_proposed_changes",
              operationId: "operation_apply_1",
              affectedIds: [],
              signal: { id: "signal_1" },
              task: { id: "task_1" },
              reviewFinding: { id: "finding_1" },
              verificationCheck: { id: "check_1", graphItemId: "graph_1" }
            }
          }
        };
      }

      throw new Error(`Unexpected Relay request in operator route test: ${request.name}`);
    });

    renderWithRelay(<OperatorRoute />, network);

    fireEvent.click(await screen.findByRole("button", { name: "Apply proposed changes" }));

    await waitFor(() => {
      expect(
        network.mock.calls.find(([request]) => request.name === "OperatorApplyProposedChangesMutation")?.[1]
      ).toMatchObject({
        input: {
          normalizedEventId: "evt_1",
          proposedChangeIds: ["change_1", "change_2"]
        }
      });
    });
  });

  it("creates a packet from the selected enabled affordance defaults", async () => {
    let readinessReads = 0;
    let packetCreated = false;
    const network = vi.fn(async (request, variables): Promise<GraphQLResponse> => {
      if (request.name === "OperatorWorkflowRouteQuery") {
        return workflowConnectionResponse([
          packetCreated
            ? operatorWorkflowItem({
                status: "packet_created",
                allowedNextActions: [],
                commandAffordances: [],
                graphLinks: [
                  ...operatorWorkflowItem().graphLinks,
                  {
                    type: "work_packet",
                    id: "packet_1",
                    graphItemId: null,
                    title: "Run console verification",
                    state: "ready"
                  }
                ]
              })
            : operatorWorkflowItem()
        ], variables);
      }
      if (request.name === "OperatorRunStateQuery") return { data: { operatorRunState: operatorRunState() } };
      if (request.name === "OperatorPacketReadinessQuery") {
        readinessReads += 1;
        return {
          data: {
            operatorPacketReadiness: operatorPacketReadiness()
          }
        };
      }
      if (request.name === "OperatorCreateWorkPacketMutation") {
        packetCreated = true;
        return {
          data: { createWorkPacket: {
            command: "create_work_packet", operationId: "operation_packet_1", affectedIds: [],
            packet: { id: "packet_1", currentVersionId: "version_1", title: "Run console verification", state: "draft" },
            packetVersion: { id: "version_1", versionNumber: 1, lifecycleState: "draft" }
          } }
        };
      }
      throw new Error(`Unexpected Relay request in operator route test: ${request.name}`);
    });

    renderWithRelay(<OperatorRoute />, network);
    await screen.findByText("Prepare packet context");
    expect(screen.queryByRole("button", { name: "Create work packet" })).not.toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: "Validate readiness" }));
    fireEvent.click(await screen.findByRole("button", { name: "Create work packet" }));

    await waitFor(() => expect(
      network.mock.calls.find(([request]) => request.name === "OperatorCreateWorkPacketMutation")?.[1]
    ).toMatchObject({ input: {
      title: "Run console verification",
      objective: "Run console verification",
      sourceGraphItemIds: ["graph_1"],
      verificationCheckIds: ["check_1"]
    } }));
    await waitFor(() => {
      expect(screen.getByRole("region", { name: "Packet Readiness" })).toHaveTextContent(
        "No packet readiness selected"
      );
    });
    expect(readinessReads).toBe(1);
    expect(screen.queryByRole("button", { name: "Validate readiness" })).not.toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "Create work packet" })).not.toBeInTheDocument();
  });

  it("accepts evidence from the enabled run affordance and refreshes run state", async () => {
    let runReads = 0;
    let workflowReads = 0;
    const network = vi.fn(async (request, variables): Promise<GraphQLResponse> => {
      if (request.name === "OperatorWorkflowRouteQuery") {
        workflowReads += 1;
        return workflowConnectionResponse([operatorWorkflowItem()], variables);
      }
      if (request.name === "OperatorRunStateQuery") {
        runReads += 1;
        return {
          data: {
            operatorRunState:
              runReads === 1
                ? operatorRunState()
                : operatorRunState({
                    status: "verified",
                    allowedNextActions: [],
                    commandAffordances: []
                  })
          }
        };
      }
      if (request.name === "OperatorAcceptEvidenceMutation") return {
        data: { acceptEvidence: {
          command: "accept_evidence", operationId: "operation_accept_1", affectedIds: [],
          evidenceCandidate: { id: "candidate_1", candidateState: "accepted" },
          evidenceItem: { id: "evidence_1", state: "accepted" },
          verificationResult: { id: "result_1", result: "passed" },
          run: { id: "run_1", executionState: "completed", verificationState: "passed" }
        } }
      };
      throw new Error(`Unexpected Relay request in operator route test: ${request.name}`);
    });

    renderWithRelay(<OperatorRoute />, network);
    fireEvent.change(await screen.findByLabelText("Evidence title"), { target: { value: "Deployment verified" } });
    fireEvent.change(screen.getByLabelText("Evidence body"), { target: { value: "The deployment completed successfully." } });
    fireEvent.click(screen.getByRole("button", { name: "Accept evidence" }));

    await waitFor(() => expect(
      network.mock.calls.find(([request]) => request.name === "OperatorAcceptEvidenceMutation")?.[1]
    ).toMatchObject({ input: {
      evidenceCandidateId: "candidate_1",
      title: "Deployment verified",
      body: "The deployment completed successfully.",
      result: "passed",
      acceptancePolicyBasis: "owner_acceptance"
    } }));
    await waitFor(() => expect(runReads).toBe(2));
    await waitFor(() => expect(workflowReads).toBe(2));
    expect(screen.getByRole("region", { name: "Run State" })).toHaveTextContent("Verified");
    expect(screen.getByRole("button", { name: /evt_1/i })).toHaveAttribute("aria-current", "true");
  });

  it("accepts the operator-selected candidate targeted by the enabled affordance", async () => {
    const base = operatorRunState();
    const secondCandidate = {
      ...base.evidenceCandidates[0],
      id: "candidate_2",
      verificationCheckId: "check_2",
      executionObservationId: "observation_2"
    };
    const runState = {
      ...base,
      evidenceCandidates: [...base.evidenceCandidates, secondCandidate],
      commandAffordances: [
        enabledCommandAffordance("accept_evidence", [], [
          { type: "work_run", id: "run_1" },
          { type: "evidence_candidate", id: "candidate_1" },
          { type: "evidence_candidate", id: "candidate_2" }
        ])
      ]
    };
    const network = operatorCommandNetwork(runState);

    renderWithRelay(<OperatorRoute />, network);
    fireEvent.change(await screen.findByLabelText("Evidence candidate"), {
      target: { value: "candidate_2" }
    });
    fireEvent.change(screen.getByLabelText("Evidence title"), {
      target: { value: "Second candidate" }
    });
    fireEvent.change(screen.getByLabelText("Evidence body"), {
      target: { value: "Accept the affordance-scoped candidate." }
    });
    fireEvent.change(screen.getByLabelText("Evidence result"), {
      target: { value: "failed" }
    });
    fireEvent.click(screen.getByRole("button", { name: "Accept evidence" }));

    await waitFor(() => expect(lastVariablesFor(network, "OperatorAcceptEvidenceMutation"))
      .toMatchObject({
        input: { evidenceCandidateId: "candidate_2", result: "failed" }
      }));
  });

  it("falls back to a current candidate after an acceptance refresh", async () => {
    const base = operatorRunState();
    const secondCandidate = {
      ...base.evidenceCandidates[0],
      id: "candidate_2",
      verificationCheckId: "check_2",
      executionObservationId: "observation_2"
    };
    const initialState = {
      ...base,
      evidenceCandidates: [...base.evidenceCandidates, secondCandidate],
      commandAffordances: [
        enabledCommandAffordance("accept_evidence", [], [
          { type: "work_run", id: "run_1" },
          { type: "evidence_candidate", id: "candidate_1" },
          { type: "evidence_candidate", id: "candidate_2" }
        ])
      ]
    };
    const refreshedState = {
      ...base,
      evidenceCandidates: [base.evidenceCandidates[0]],
      commandAffordances: [
        enabledCommandAffordance("accept_evidence", [], [
          { type: "work_run", id: "run_1" },
          { type: "evidence_candidate", id: "candidate_1" }
        ])
      ]
    };
    let runReads = 0;
    const network = vi.fn(async (request, variables): Promise<GraphQLResponse> => {
      if (request.name === "OperatorWorkflowRouteQuery") {
        return workflowConnectionResponse([operatorWorkflowItem()], variables);
      }
      if (request.name === "OperatorRunStateQuery") {
        runReads += 1;
        return { data: { operatorRunState: runReads === 1 ? initialState : refreshedState } };
      }
      if (request.name === "OperatorAcceptEvidenceMutation") {
        return {
          data: {
            acceptEvidence: {
              command: "accept_evidence",
              operationId: `operation_accept_${runReads}`,
              affectedIds: [],
              evidenceCandidate: { id: "candidate_2", candidateState: "accepted" },
              evidenceItem: { id: "evidence_2", state: "accepted" },
              verificationResult: { id: "result_2", result: "passed" },
              run: { id: "run_1", executionState: "completed", verificationState: "pending" }
            }
          }
        };
      }
      throw new Error(`Unexpected Relay request in operator route test: ${request.name}`);
    });

    renderWithRelay(<OperatorRoute />, network);
    fireEvent.change(await screen.findByLabelText("Evidence candidate"), {
      target: { value: "candidate_2" }
    });
    fireEvent.change(screen.getByLabelText("Evidence title"), {
      target: { value: "Candidate refresh" }
    });
    fireEvent.change(screen.getByLabelText("Evidence body"), {
      target: { value: "Use only the current affordance target." }
    });
    fireEvent.click(screen.getByRole("button", { name: "Accept evidence" }));

    await waitFor(() => expect(runReads).toBe(2));
    await waitFor(() => expect(screen.getByLabelText("Evidence candidate")).toHaveValue("candidate_1"));
    fireEvent.click(screen.getByRole("button", { name: "Accept evidence" }));

    await waitFor(() => {
      const submissions = network.mock.calls.filter(
        ([request]) => request.name === "OperatorAcceptEvidenceMutation"
      );
      expect(submissions).toHaveLength(2);
      expect(submissions[1]?.[1]).toMatchObject({
        input: { evidenceCandidateId: "candidate_1" }
      });
    });
  });

  it("creates evidence from the operator-selected matching observation and check", async () => {
    const base = operatorRunState();
    const secondObservation = {
      ...base.observations[0],
      id: "observation_2",
      verificationCheckId: "check_2"
    };
    const runState = {
      ...base,
      observations: [...base.observations, secondObservation],
      missingEvidence: [
        ...base.missingEvidence,
        { verificationCheckId: "check_2", reason: "missing" }
      ],
      commandAffordances: [
        enabledCommandAffordance("create_evidence_candidate", [
          { field: "work_run_id", value: "run_1", values: [] },
          { field: "verification_check_id", value: null, values: ["check_1", "check_2"] },
          { field: "execution_observation_id", value: null, values: ["observation_1", "observation_2"] }
        ])
      ]
    };
    const network = operatorCommandNetwork(runState);

    renderWithRelay(<OperatorRoute />, network);
    fireEvent.change(await screen.findByLabelText("Evidence observation"), {
      target: { value: "observation_2" }
    });
    fireEvent.change(screen.getByLabelText("Evidence claim"), {
      target: { value: "The second check passed." }
    });
    fireEvent.click(screen.getByRole("button", { name: "Create evidence candidate" }));

    await waitFor(() => expect(lastVariablesFor(network, "OperatorCreateEvidenceCandidateMutation"))
      .toMatchObject({
        input: {
          executionObservationId: "observation_2",
          verificationCheckId: "check_2"
        }
      }));
  });

  it("waives the operator-selected required check", async () => {
    const base = operatorRunState();
    const secondCheck = {
      ...base.requiredChecks[0],
      id: "required_2",
      verificationCheckId: "check_2"
    };
    const runState = {
      ...base,
      requiredChecks: [...base.requiredChecks, secondCheck],
      commandAffordances: [
        enabledCommandAffordance("waive_verification_check", [
          { field: "run_id", value: "run_1", values: [] },
          { field: "run_required_check_id", value: null, values: ["required_1", "required_2"] },
          { field: "expected_execution_state", value: "completed", values: [] },
          { field: "expected_verification_state", value: "pending", values: [] }
        ])
      ]
    };
    const network = operatorCommandNetwork(runState);

    renderWithRelay(<OperatorRoute />, network);
    fireEvent.change(await screen.findByLabelText("Required check"), {
      target: { value: "required_2" }
    });
    fireEvent.change(screen.getByLabelText("Waiver reason"), {
      target: { value: "Approved exception for the second check." }
    });
    fireEvent.click(screen.getByRole("button", { name: "Waive verification check" }));

    await waitFor(() => expect(lastVariablesFor(network, "OperatorWaiveVerificationCheckMutation"))
      .toMatchObject({ input: { runRequiredCheckId: "required_2" } }));
  });

  it("records the operator-selected check and failed outcome", async () => {
    const base = operatorRunState();
    const runState = {
      ...base,
      missingEvidence: [
        ...base.missingEvidence,
        { verificationCheckId: "check_2", reason: "missing" }
      ],
      requiredChecks: [
        ...base.requiredChecks,
        {
          id: "required_2",
          graphItemId: "graph_2",
          verificationCheckId: "check_2",
          state: "open"
        }
      ],
      commandAffordances: [
        enabledCommandAffordance("record_execution_observation", [
          { field: "run_id", value: "run_1", values: [] }
        ], [
          { type: "work_run", id: "run_1" },
          { type: "verification_check", id: "check_1" },
          { type: "verification_check", id: "check_2" }
        ])
      ]
    };
    const network = operatorCommandNetwork(runState);

    renderWithRelay(<OperatorRoute />, network);
    fireEvent.change(await screen.findByLabelText("Verification check"), {
      target: { value: "check_2" }
    });
    fireEvent.change(screen.getByLabelText("Observation outcome"), {
      target: { value: "failed" }
    });
    fireEvent.change(screen.getByLabelText("Observation rationale"), {
      target: { value: "The second check failed." }
    });
    fireEvent.click(screen.getByRole("button", { name: "Record execution observation" }));

    await waitFor(() => expect(lastVariablesFor(network, "OperatorRecordExecutionObservationMutation"))
      .toMatchObject({
        input: {
          verificationCheckId: "check_2",
          sourceGraphItemId: "graph_2",
          observedStatus: "failed",
          normalizedStatus: "failed"
        }
      }));
  });

  it("uses complete typed options when parallel run collections are redacted", async () => {
    const runState = operatorRunState({
      requiredChecks: [],
      observations: [],
      commandAffordances: [
        enabledCommandAffordance("record_execution_observation"),
        enabledCommandAffordance("create_evidence_candidate")
      ],
      commandOptions: {
        observation: [
          observationCommandOption({
            key: "required_2",
            label: "Payroll import check",
            verificationCheckId: "check_2",
            sourceGraphItemId: "graph_2"
          })
        ],
        evidenceCandidate: [
          evidenceCandidateCommandOption({
            key: "observation_2",
            label: "Payroll import evidence",
            verificationCheckId: "check_2",
            executionObservationId: "observation_2",
            sourceIdentity: "manual:approved-source"
          })
        ],
        evidenceAcceptance: [],
        waiver: []
      }
    });
    const network = operatorCommandNetwork(runState);

    renderWithRelay(<OperatorRoute />, network);

    expect(await screen.findByRole("option", { name: "Payroll import check" })).toBeInTheDocument();
    fireEvent.change(screen.getByLabelText("Observation outcome"), {
      target: { value: "failed" }
    });
    fireEvent.change(screen.getByLabelText("Observation rationale"), {
      target: { value: "The approved option failed." }
    });
    fireEvent.click(screen.getByRole("button", { name: "Record execution observation" }));

    await waitFor(() =>
      expect(lastVariablesFor(network, "OperatorRecordExecutionObservationMutation")).toMatchObject({
        input: {
          runId: "run_1",
          verificationCheckId: "check_2",
          sourceGraphItemId: "graph_2",
          observationSourceKind: "human",
          observationSourceIdentity: "operator-console",
          freshnessState: "fresh",
          trustBasis: "owner_attested"
        }
      })
    );

    expect(screen.getByRole("option", { name: "Payroll import evidence" })).toBeInTheDocument();
    fireEvent.change(screen.getByLabelText("Evidence claim"), {
      target: { value: "Approved evidence option." }
    });
    fireEvent.click(screen.getByRole("button", { name: "Create evidence candidate" }));

    await waitFor(() =>
      expect(lastVariablesFor(network, "OperatorCreateEvidenceCandidateMutation")).toMatchObject({
        input: {
          workRunId: "run_1",
          verificationCheckId: "check_2",
          executionObservationId: "observation_2",
          sourceKind: "human",
          sourceIdentity: "manual:approved-source",
          freshnessState: "fresh",
          trustBasis: "owner_attested",
          sensitivity: "internal"
        }
      })
    );
  });

  it("disables commands whose projected typed option is malformed", async () => {
    const runState = operatorRunState({
      commandAffordances: [enabledCommandAffordance("record_execution_observation")],
      commandOptions: {
        observation: [observationCommandOption({ sourceGraphItemId: "" })],
        evidenceCandidate: [],
        evidenceAcceptance: [],
        waiver: []
      }
    });

    renderWithRelay(<OperatorRoute />, operatorCommandNetwork(runState));

    fireEvent.change(await screen.findByLabelText("Observation rationale"), {
      target: { value: "Malformed projected option must stay disabled." }
    });
    expect(screen.getByRole("button", { name: "Record execution observation" })).toBeDisabled();
  });

  it("does not synthesize run start from an inbox-only affordance", async () => {
    const workflowItem = operatorWorkflowItem({
      commandAffordances: [
        enabledCommandAffordance("start_work_run", [
          { field: "packet_version_id", value: "version_1", values: [] }
        ])
      ]
    });

    renderWithRelay(<OperatorRoute />, createOperatorNetwork({ workflowItems: [workflowItem] }));

    await screen.findByRole("button", { name: /evt_1/i });
    expect(screen.queryByRole("button", { name: "Start work run" })).not.toBeInTheDocument();
  });

  it("renders remaining run forms only from exact enabled affordances", async () => {
    const enabled = (identity: string, inputDefaults: CommandAffordancePayload["inputDefaults"] = []) => ({
      identity, state: "enabled", reasonCodes: [], blockerReasons: [],
      safeExplanation: `${identity} is available.`, requiredFields: [], inputDefaults,
      targetIds: [], traceLinks: [], decisionLinks: []
    });
    const workflowItem = operatorWorkflowItem({
      commandAffordances: [
        enabled("start_work_run", [
          { field: "packet_version_id", value: "version_1", values: [] },
          { field: "authority_posture", value: "human_supervised", values: [] }
        ])
      ],
      graphLinks: [
        { type: "work_packet_version", id: "version_1", graphItemId: null, title: "Version 1", state: "ready" },
        { type: "work_run", id: "run_1", graphItemId: null, title: "Run 1", state: "running" }
      ]
    });
    const runState = operatorRunState({ commandAffordances: [
      enabled("record_execution_observation", [{ field: "run_id", value: "run_1", values: [] }]),
      enabled("create_evidence_candidate", [
        { field: "work_run_id", value: "run_1", values: [] },
        { field: "verification_check_id", value: null, values: ["check_1"] },
        { field: "execution_observation_id", value: null, values: ["observation_1"] }
      ]),
      enabled("waive_verification_check", [
        { field: "run_id", value: "run_1", values: [] },
        { field: "run_required_check_id", value: null, values: ["required_1"] }
      ])
    ] });
    const network = createOperatorNetwork({ workflowItems: [workflowItem], runState });

    renderWithRelay(<OperatorRoute />, network);

    expect(await screen.findByRole("button", { name: "Record execution observation" })).toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "Start work run" })).not.toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Create evidence candidate" })).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Waive verification check" })).toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "Accept evidence" })).not.toBeInTheDocument();
  });
});

function operatorCommandNetwork(runState: ReturnType<typeof operatorRunState>) {
  return vi.fn(async (request, variables): Promise<GraphQLResponse> => {
    if (request.name === "OperatorWorkflowRouteQuery") {
      return workflowConnectionResponse([operatorWorkflowItem()], variables);
    }
    if (request.name === "OperatorRunStateQuery") {
      return { data: { operatorRunState: runState } };
    }
    if (request.name.endsWith("Mutation")) {
      return new Promise<GraphQLResponse>(() => undefined);
    }
    throw new Error(`Unexpected Relay request in operator route test: ${request.name}`);
  });
}

function lastVariablesFor(network: ReturnType<typeof vi.fn>, requestName: string) {
  return [...network.mock.calls]
    .reverse()
    .find(([request]) => request.name === requestName)?.[1];
}

function renderWithRelay(
  ui: ReactElement,
  network: FetchFunction,
  initialEntry = "/operator"
) {
  const environment = new Environment({
    getDataID: getOfficeGraphDataID,
    network: Network.create(network),
    store: new Store(new RecordSource())
  });

  return render(
    <MemoryRouter initialEntries={[initialEntry]}>
      <RelayEnvironmentProvider environment={environment}>{ui}</RelayEnvironmentProvider>
    </MemoryRouter>
  );
}

function createOperatorNetwork({
  workflowItems,
  readiness,
  runState
}: {
  workflowItems: ReturnType<typeof operatorWorkflowItem>[] | null;
  readiness?: ReturnType<typeof operatorPacketReadiness>;
  runState?: ReturnType<typeof operatorRunState>;
}) {
  return vi.fn(async (request, variables): Promise<GraphQLResponse> => {
    if (request.name === "OperatorWorkflowRouteQuery") {
      return workflowConnectionResponse(workflowItems, variables);
    }

    if (request.name === "OperatorPacketReadinessQuery") {
      return {
        data: {
          operatorPacketReadiness: readiness ?? operatorPacketReadiness()
        }
      };
    }

    if (request.name === "OperatorRunStateQuery") {
      return {
        data: {
          operatorRunState: runState ?? operatorRunState()
        }
      };
    }

    throw new Error(`Unexpected Relay request in operator route test: ${request.name}`);
  });
}

function workflowConnectionResponse(
  workflowItems: ReturnType<typeof operatorWorkflowItem>[] | null,
  variables: Readonly<Record<string, unknown>>,
  pageInfoOverrides: Partial<OperatorWorkflowPageInfoPayload> = {},
  manualIntakeAffordance: CommandAffordancePayload = enabledCommandAffordance("submit_manual_intake")
): GraphQLResponse {
  if (workflowItems === null) {
    return {
      data: {
        operatorManualIntakeAffordance: manualIntakeAffordance,
        operatorWorkflowItems: null
      }
    };
  }

  return {
    data: {
      operatorManualIntakeAffordance: manualIntakeAffordance,
      operatorWorkflowItems: {
        edges: workflowItems.map((node, index) => ({
          cursor: `cursor_${index + 1}`,
          node
        })),
        pageInfo: {
          hasNextPage: false,
          hasPreviousPage: Boolean(variables.after),
          startCursor: workflowItems.length > 0 ? "cursor_1" : null,
          endCursor: workflowItems.length > 0 ? `cursor_${workflowItems.length}` : null,
          ...pageInfoOverrides
        }
      }
    }
  };
}

function deferredGraphQLResponse() {
  let resolve!: (value: GraphQLResponse) => void;
  const promise = new Promise<GraphQLResponse>((resolvePromise) => {
    resolve = resolvePromise;
  });

  return { promise, resolve };
}

function operatorWorkflowItem(overrides: Partial<OperatorWorkflowItemPayload> = {}) {
  const graphLinks = overrides.graphLinks ?? [
    {
      type: "verification_check",
      id: "check_1",
      graphItemId: "graph_1",
      title: "Run console verification",
      state: "required"
    },
    {
      type: "work_run",
      id: "run_1",
      graphItemId: null,
      title: "Console verification run",
      state: "running"
    }
  ];
  const commandAffordances = overrides.commandAffordances ?? [
    preparePacketCommandForGraphLinks(graphLinks)
  ];

  return {
    __typename: "OperatorWorkflowItem",
    id: "operator_workflow_item_global_1",
    type: "operator_workflow_item",
    typedId: { type: "normalized_intake_event", id: "evt_1" },
    normalizedEventId: "evt_1",
    duplicateOfId: null,
    title: "Run console verification",
    sourceSummary: "manual:operator-console · Run console verification",
    proposedActionPreviews: [
      { action: "create_signal", title: "Run console verification", status: "pending" }
    ],
    status: "ready_for_packet",
    reasonCodes: [],
    source: {
      identity: "manual:operator-console",
      replayIdentity: "paste:operator-console",
      outcome: "accepted"
    },
    proposedChangeStatus: { pending: 4, applied: 0, rejected: 0, total: 4 },
    blockerReasons: [],
    allowedNextActions: ["create_work_packet"],
    commandAffordances,
    operationWatermark: "op_123",
    sourceWatermark: "op_123",
    graphLinks,
    graphRelationships: [],
    auditTrace: { operationId: null, resourceCount: 0, resources: [] },
    revisionTrace: { operationId: "operation_1", resourceCount: 2, resources: [] },
    ...overrides
  };
}

function preparePacketCommandForGraphLinks(
  graphLinks: OperatorWorkflowItemPayload["graphLinks"]
): CommandAffordancePayload {
  const verificationCheck = graphLinks.find((link) => link.type === "verification_check");
  const title = verificationCheck?.title ?? "Run console verification";
  const sourceGraphItemIds = graphLinks.flatMap((link) =>
    link.graphItemId && link.type !== "work_run" ? [link.graphItemId] : []
  );
  const verificationCheckIds = graphLinks
    .filter((link) => link.type === "verification_check")
    .map((link) => link.id);

  return {
    identity: "create_work_packet",
    state: "enabled",
    reasonCodes: [],
    blockerReasons: [],
    safeExplanation: "Prepare a work packet from the applied intake.",
    requiredFields: [
      "title",
      "objective",
      "context_summary",
      "requirements",
      "success_criteria",
      "autonomy_posture",
      "source_graph_item_ids",
      "verification_check_ids"
    ],
    inputDefaults: [
      { field: "title", value: title, values: [] },
      { field: "objective", value: title, values: [] },
      { field: "context_summary", value: title, values: [] },
      { field: "requirements", value: title, values: [] },
      { field: "success_criteria", value: title, values: [] },
      { field: "autonomy_posture", value: "human_supervised", values: [] },
      { field: "source_graph_item_ids", value: null, values: sourceGraphItemIds },
      { field: "verification_check_ids", value: null, values: verificationCheckIds },
      { field: "primary_source_graph_item_id", value: verificationCheck?.graphItemId ?? null, values: [] },
      { field: "primary_verification_check_id", value: verificationCheck?.id ?? null, values: [] }
    ],
    targetIds: verificationCheck ? [{ type: "verification_check", id: verificationCheck.id }] : [],
    traceLinks: [],
    decisionLinks: []
  };
}

function enabledCommandAffordance(
  identity: string,
  inputDefaults: CommandAffordancePayload["inputDefaults"] = [],
  targetIds: CommandAffordancePayload["targetIds"] = []
): CommandAffordancePayload {
  return {
    identity,
    state: "enabled",
    reasonCodes: [],
    blockerReasons: [],
    safeExplanation: `${identity} is available.`,
    requiredFields: [],
    inputDefaults,
    targetIds,
    traceLinks: [],
    decisionLinks: []
  };
}

function operatorPacketReadiness(overrides: Partial<OperatorPacketReadinessPayload> = {}) {
  return {
    type: "packet_readiness",
    ready: true,
    status: "packet_ready",
    allowedNextActions: ["create_work_packet"],
    commandAffordances: [
      {
        identity: "create_work_packet",
        state: "enabled",
        reasonCodes: [],
        blockerReasons: [],
        safeExplanation: "Create a work packet from the selected sources and checks.",
        requiredFields: [],
        inputDefaults: [],
        targetIds: [],
        traceLinks: [],
        decisionLinks: []
      }
    ],
    blockerReasons: [],
    sourceLinks: [
      {
        type: "verification_check",
        id: "check_1",
        graphItemId: "graph_1",
        title: "Run console verification"
      }
    ],
    requiredChecks: [{ id: "check_1", graphItemId: "graph_1", state: "required" }],
    sourceWatermark: "op_123",
    ...overrides
  };
}

function operatorRunState(overrides: Partial<OperatorRunStatePayload> = {}) {
  return {
    type: "operator_run_state",
    status: "awaiting_evidence_acceptance",
    allowedNextActions: ["accept_evidence"],
    commandAffordances: [
      {
        identity: "accept_evidence",
        state: "enabled",
        reasonCodes: [],
        blockerReasons: [],
        safeExplanation: "Accept a candidate as evidence for a missing check.",
        requiredFields: [],
        inputDefaults: [],
        targetIds: [{ type: "evidence_candidate", id: "candidate_1" }],
        traceLinks: [],
        decisionLinks: []
      }
    ],
    commandOptions: {
      observation: [observationCommandOption()],
      evidenceCandidate: [evidenceCandidateCommandOption()],
      evidenceAcceptance: [
        {
          key: "candidate_1",
          label: "Run console verification",
          evidenceCandidateId: "candidate_1",
          result: "passed",
          acceptancePolicyBasis: "owner_acceptance"
        }
      ],
      waiver: [
        {
          key: "required_1",
          label: "Run console verification",
          runId: "run_1",
          runRequiredCheckId: "required_1",
          expectedExecutionState: "completed",
          expectedVerificationState: "pending",
          policyBasis: "owner_exception"
        }
      ]
    },
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
    requiredChecks: [{ id: "required_1", graphItemId: "graph_1", verificationCheckId: "check_1", state: "open" }],
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
    missingEvidence: [{ verificationCheckId: "check_1", reason: "missing_accepted_evidence" }],
    ...overrides
  };
}

function observationCommandOption(overrides: Partial<ObservationCommandOptionPayload> = {}) {
  return {
    key: "required_1",
    label: "Run console verification",
    runId: "run_1",
    verificationCheckId: "check_1",
    sourceGraphItemId: "graph_1",
    observationSourceKind: "human",
    observationSourceIdentity: "operator-console",
    freshnessState: "fresh",
    trustBasis: "owner_attested",
    ...overrides
  };
}

function evidenceCandidateCommandOption(
  overrides: Partial<EvidenceCandidateCommandOptionPayload> = {}
) {
  return {
    key: "observation_1",
    label: "Run console verification",
    workRunId: "run_1",
    verificationCheckId: "check_1",
    executionObservationId: "observation_1",
    sourceKind: "human",
    sourceIdentity: "manual:operator-console",
    freshnessState: "fresh",
    trustBasis: "owner_attested",
    sensitivity: "internal",
    ...overrides
  };
}

type OperatorWorkflowItemPayload = {
  id: string;
  status: string;
  normalizedEventId: string;
  title: string;
  sourceSummary: string;
  proposedActionPreviews: Array<{ action: string; title: string; status: string }>;
  typedId: { type: string; id: string };
  allowedNextActions: string[];
  commandAffordances: CommandAffordancePayload[];
  source: { identity: string; replayIdentity: string; outcome: string };
  graphLinks: Array<{
    type: string;
    id: string;
    graphItemId: string | null;
    title: string;
    state: string | null;
  }>;
};

type OperatorWorkflowPageInfoPayload = {
  hasNextPage: boolean;
  hasPreviousPage: boolean;
  startCursor: string | null;
  endCursor: string | null;
};

type OperatorPacketReadinessPayload = {
  allowedNextActions: string[];
  commandAffordances: CommandAffordancePayload[];
  status: string;
  sourceLinks: Array<{ type: string; id: string; graphItemId: string; title: string }>;
  requiredChecks: Array<{ id: string; graphItemId: string; state: string }>;
};

type OperatorRunStatePayload = {
  allowedNextActions: string[];
  commandAffordances: CommandAffordancePayload[];
  commandOptions: {
    observation: ObservationCommandOptionPayload[];
    evidenceCandidate: EvidenceCandidateCommandOptionPayload[];
    evidenceAcceptance: Array<{
      key: string;
      label: string;
      evidenceCandidateId: string;
      result: string;
      acceptancePolicyBasis: string;
    }>;
    waiver: Array<{
      key: string;
      label: string;
      runId: string;
      runRequiredCheckId: string;
      expectedExecutionState: string;
      expectedVerificationState: string;
      policyBasis: string;
    }>;
  };
  requiredChecks: Array<{
    id: string;
    graphItemId: string | null;
    verificationCheckId: string | null;
    state: string;
  }>;
  observations: Array<{
    id: string;
    verificationCheckId: string | null;
    graphItemId: string | null;
    normalizedStatus: string;
    freshnessState: string;
    trustBasis: string;
    sourceKind: string;
    sourceIdentity: string;
  }>;
  status: string;
};

type ObservationCommandOptionPayload = {
  key: string;
  label: string;
  runId: string;
  verificationCheckId: string;
  sourceGraphItemId: string;
  observationSourceKind: string;
  observationSourceIdentity: string;
  freshnessState: string;
  trustBasis: string;
};

type EvidenceCandidateCommandOptionPayload = {
  key: string;
  label: string;
  workRunId: string;
  verificationCheckId: string;
  executionObservationId: string;
  sourceKind: string;
  sourceIdentity: string;
  freshnessState: string;
  trustBasis: string;
  sensitivity: string;
};

type CommandAffordancePayload = {
  identity: string;
  state: string;
  reasonCodes: string[];
  blockerReasons: string[];
  safeExplanation: string;
  requiredFields: string[];
  inputDefaults: Array<{ field: string; value: string | null; values: string[] }>;
  targetIds: Array<{ type: string; id: string }>;
  traceLinks: Array<unknown>;
  decisionLinks: Array<unknown>;
};
