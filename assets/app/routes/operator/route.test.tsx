import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import type { ReactElement } from "react";
import { RelayEnvironmentProvider } from "react-relay";
import {
  Environment,
  Network,
  RecordSource,
  Store,
  type FetchFunction,
  type GraphQLResponse
} from "relay-runtime";
import { describe, expect, it, vi } from "vitest";
import { getOfficeGraphDataID } from "../../relay/environment";
import OperatorRoute from "./route";

describe("operator route", () => {
  it("renders the operator workbench from Relay projection data", async () => {
    const network = createOperatorNetwork({
      workflowItems: [operatorWorkflowItem()],
      readiness: operatorPacketReadiness(),
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
    expect(await screen.findByText("Backend readiness")).toBeInTheDocument();
    const readinessCall = network.mock.calls.find(
      ([request]) => request.name === "OperatorPacketReadinessQuery"
    );

    expect(readinessCall?.[1]).toMatchObject({
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

    await waitFor(() => {
      expect(screen.getByRole("region", { name: "Run State" })).toHaveTextContent(
        "Awaiting evidence acceptance"
      );
      expect(screen.getByRole("region", { name: "Verification" })).toHaveTextContent(
        "Owner acceptance"
      );
    });
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

  it("shows Relay loading errors", async () => {
    const network = vi.fn(async () => {
      throw new Error("GraphQL unavailable");
    });

    renderWithRelay(<OperatorRoute />, network);

    await waitFor(() => {
      expect(screen.getByText("GraphQL unavailable")).toBeInTheDocument();
    });
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
      workflowItems: [operatorWorkflowItem(), secondItem],
      readiness: operatorPacketReadiness({
        sourceLinks: [
          {
            type: "verification_check",
            id: "check_2",
            graphItemId: "graph_2",
            title: "Review second packet"
          }
        ],
        requiredChecks: [{ id: "check_2", graphItemId: "graph_2", state: "required" }]
      })
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

  it("renders command affordance states without leaking hidden or redacted policy details", async () => {
    const sensitiveAffordances = [
      {
        identity: "prepare_packet",
        state: "enabled",
        reasonCodes: [],
        blockerReasons: [],
        safeExplanation: "Prepare a work packet from the applied intake.",
        requiredFields: [],
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

    const itemDetail = await screen.findByRole("region", { name: "Item detail" });
    await screen.findByRole("region", { name: "Packet Readiness" });
    await screen.findByRole("region", { name: "Run State" });

    expect(itemDetail).toHaveTextContent("Commands");
    expect(itemDetail).toHaveTextContent("Prepare packet");
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
  });
});

function renderWithRelay(ui: ReactElement, network: FetchFunction) {
  const environment = new Environment({
    getDataID: getOfficeGraphDataID,
    network: Network.create(network),
    store: new Store(new RecordSource())
  });

  return render(
    <RelayEnvironmentProvider environment={environment}>{ui}</RelayEnvironmentProvider>
  );
}

function createOperatorNetwork({
  workflowItems,
  readiness,
  runState
}: {
  workflowItems: ReturnType<typeof operatorWorkflowItem>[];
  readiness?: ReturnType<typeof operatorPacketReadiness>;
  runState?: ReturnType<typeof operatorRunState>;
}) {
  return vi.fn(async (request, variables): Promise<GraphQLResponse> => {
    if (request.name === "OperatorWorkflowRouteQuery") {
      return {
        data: {
          operatorWorkflowItems: {
            edges: workflowItems.map((node, index) => ({
              cursor: `cursor_${index + 1}`,
              node
            })),
            pageInfo: {
              hasNextPage: false,
              hasPreviousPage: Boolean(variables.after),
              startCursor: workflowItems.length > 0 ? "cursor_1" : null,
              endCursor: workflowItems.length > 0 ? `cursor_${workflowItems.length}` : null
            }
          }
        }
      };
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

function operatorWorkflowItem(overrides: Partial<OperatorWorkflowItemPayload> = {}) {
  return {
    __typename: "OperatorWorkflowItem",
    id: "operator_workflow_item_global_1",
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
    commandAffordances: [
      {
        identity: "prepare_packet",
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
        targetIds: [{ type: "verification_check", id: "check_1" }],
        traceLinks: [],
        decisionLinks: []
      }
    ],
    operationWatermark: "op_123",
    sourceWatermark: "op_123",
    graphLinks: [
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
    ],
    graphRelationships: [],
    auditTrace: { operationId: null, resourceCount: 0, resources: [] },
    revisionTrace: { operationId: "operation_1", resourceCount: 2, resources: [] },
    ...overrides
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
        targetIds: [{ type: "evidence_candidate", id: "candidate_1" }],
        traceLinks: [],
        decisionLinks: []
      }
    ],
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
    missingEvidence: [{ verificationCheckId: "check_1", reason: "missing_accepted_evidence" }],
    ...overrides
  };
}

type OperatorWorkflowItemPayload = {
  id: string;
  normalizedEventId: string;
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

type OperatorPacketReadinessPayload = {
  allowedNextActions: string[];
  commandAffordances: CommandAffordancePayload[];
  sourceLinks: Array<{ type: string; id: string; graphItemId: string; title: string }>;
  requiredChecks: Array<{ id: string; graphItemId: string; state: string }>;
};

type OperatorRunStatePayload = {
  allowedNextActions: string[];
  commandAffordances: CommandAffordancePayload[];
  status: string;
};

type CommandAffordancePayload = {
  identity: string;
  state: string;
  reasonCodes: string[];
  blockerReasons: string[];
  safeExplanation: string;
  requiredFields: string[];
  targetIds: Array<{ type: string; id: string }>;
  traceLinks: Array<unknown>;
  decisionLinks: Array<unknown>;
};
