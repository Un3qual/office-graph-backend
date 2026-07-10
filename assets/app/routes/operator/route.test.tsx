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
import { fetchGraphQL } from "../../relay/fetchGraphQL";
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
    expect(network.mock.calls.some(([request]) => request.name === "ExecutePacketRunVerificationMutation"))
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
    expect(network.mock.calls.some(([request]) => request.name === "ExecutePacketRunVerificationMutation"))
      .toBe(false);
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
    const network = vi.fn(async (request, variables): Promise<GraphQLResponse> => {
      if (request.name === "OperatorWorkflowRouteQuery") {
        return workflowConnectionResponse([operatorWorkflowItem()], variables);
      }

      if (request.name === "OperatorRunStateQuery") {
        return { data: { operatorRunState: operatorRunState() } };
      }

      if (request.name === "OperatorPacketReadinessQuery") {
        throw new Error("authorization secret_alpha denied readiness_9");
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
    const network = vi.fn(async (request, variables): Promise<GraphQLResponse> => {
      if (request.name === "OperatorWorkflowRouteQuery") {
        return workflowConnectionResponse([operatorWorkflowItem()], variables);
      }

      if (request.name === "OperatorRunStateQuery") {
        throw new Error("authorization secret_alpha denied run_9");
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
    <MemoryRouter initialEntries={["/operator"]}>
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
  pageInfoOverrides: Partial<OperatorWorkflowPageInfoPayload> = {}
): GraphQLResponse {
  if (workflowItems === null) {
    return { data: { operatorWorkflowItems: null } };
  }

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

type OperatorWorkflowPageInfoPayload = {
  hasNextPage: boolean;
  hasPreviousPage: boolean;
  startCursor: string | null;
  endCursor: string | null;
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
  inputDefaults: Array<{ field: string; value: string | null; values: string[] }>;
  targetIds: Array<{ type: string; id: string }>;
  traceLinks: Array<unknown>;
  decisionLinks: Array<unknown>;
};
