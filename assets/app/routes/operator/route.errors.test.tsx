import { act, fireEvent, screen, waitFor } from "@testing-library/react";
import type { GraphQLResponse } from "relay-runtime";
import { afterEach, describe, expect, it, vi } from "vitest";
import { fetchGraphQL, GraphQLResponseError } from "../../relay/fetchGraphQL";
import OperatorRoute from "./route";

import * as support from "./routeTestSupport";

describe("operator route reads", () => {
  afterEach(() => {
    vi.unstubAllGlobals();
    vi.restoreAllMocks();
  });

  it("renders a Suspense-driven inbox loading workspace", () => {
    const workflowResponse = support.deferredGraphQLResponse();
    const network = vi.fn(async (request): Promise<GraphQLResponse> => {
      if (request.name === "OperatorWorkflowRouteQuery") {
        return workflowResponse.promise;
      }

      throw new Error(`Unexpected Relay request in operator route test: ${request.name}`);
    });

    support.renderWithRelay(<OperatorRoute />, network);

    expect(screen.getByRole("heading", { name: "Operator Console" })).toBeInTheDocument();
    expect(screen.getByRole("status")).toHaveTextContent("Loading inbox...");
    expect(screen.getByRole("region", { name: "Item detail" })).toHaveTextContent(
      "No item selected",
    );
  });

  it("keeps derived readiness and workspace context visible while validation suspends", async () => {
    const readinessResponse = support.deferredGraphQLResponse();
    const network = vi.fn(async (request, variables): Promise<GraphQLResponse> => {
      if (request.name === "OperatorWorkflowRouteQuery") {
        return support.workflowConnectionResponse([support.operatorWorkflowItem()], variables);
      }

      if (request.name === "OperatorRunStateQuery") {
        return { data: { operatorRunState: support.operatorRunState() } };
      }

      if (request.name === "OperatorPacketReadinessQuery") {
        return readinessResponse.promise;
      }

      throw new Error(`Unexpected Relay request in operator route test: ${request.name}`);
    });

    support.renderWithRelay(<OperatorRoute />, network);

    const selectedRow = await screen.findByRole("button", { name: /evt_1/i });
    fireEvent.click(screen.getByRole("button", { name: "Validate readiness" }));

    const readiness = screen.getByRole("region", { name: "Packet Readiness" });

    expect(readiness).toHaveTextContent("Prepare packet context");
    expect(screen.getByRole("button", { name: "Validating readiness" })).toBeDisabled();
    expect(selectedRow).toHaveAttribute("aria-current", "true");
    expect(screen.getByRole("region", { name: "Item detail" })).toHaveTextContent(
      "normalized_intake_event: evt_1",
    );

    await act(async () => {
      readinessResponse.resolve({
        data: { operatorPacketReadiness: support.operatorPacketReadiness() },
      });
    });

    await waitFor(() => {
      expect(screen.getByRole("region", { name: "Packet Readiness" })).toHaveTextContent(
        "Backend readiness",
      );
    });
  });

  it("keeps the operator workspace visible when readiness validation fails", async () => {
    vi.spyOn(console, "error").mockImplementation(() => undefined);
    let readinessReads = 0;
    const network = vi.fn(async (request, variables): Promise<GraphQLResponse> => {
      if (request.name === "OperatorWorkflowRouteQuery") {
        return support.workflowConnectionResponse([support.operatorWorkflowItem()], variables);
      }

      if (request.name === "OperatorRunStateQuery") {
        return { data: { operatorRunState: support.operatorRunState() } };
      }

      if (request.name === "OperatorPacketReadinessQuery") {
        readinessReads += 1;
        if (readinessReads === 1) {
          throw new Error("authorization secret_alpha denied readiness_9");
        }

        return { data: { operatorPacketReadiness: support.operatorPacketReadiness() } };
      }

      throw new Error(`Unexpected Relay request in operator route test: ${request.name}`);
    });

    support.renderWithRelay(<OperatorRoute />, network);

    const selectedRow = await screen.findByRole("button", { name: /evt_1/i });
    fireEvent.click(screen.getByRole("button", { name: "Validate readiness" }));

    await waitFor(() => {
      expect(screen.getByRole("region", { name: "Packet Readiness" })).toHaveTextContent(
        "Unable to validate packet readiness.",
      );
    });
    expect(selectedRow).toHaveAttribute("aria-current", "true");
    expect(screen.getByRole("region", { name: "Item detail" })).toHaveTextContent(
      "normalized_intake_event: evt_1",
    );
    expect(document.body).not.toHaveTextContent("secret_alpha");
    expect(document.body).not.toHaveTextContent("readiness_9");

    fireEvent.click(screen.getByRole("button", { name: "Retry packet readiness" }));

    await waitFor(() => {
      expect(screen.getByRole("region", { name: "Packet Readiness" })).toHaveTextContent(
        "Backend readiness",
      );
    });
    expect(readinessReads).toBe(2);
  });

  it("shows the empty state without enabling workflow commands", async () => {
    const network = support.createOperatorNetwork({ workflowItems: [] });

    support.renderWithRelay(<OperatorRoute />, network);

    expect(await screen.findByText("No operator workflow items.")).toBeInTheDocument();
    expect(screen.getAllByText("No item selected").length).toBeGreaterThan(0);
    expect(screen.getByText("No packet readiness selected.")).toBeInTheDocument();
    expect(screen.queryByText("Loading item detail...")).not.toBeInTheDocument();
    expect(screen.queryByText("Loading readiness...")).not.toBeInTheDocument();
    expect(screen.queryByRole("button", { name: /apply/i })).not.toBeInTheDocument();
  });

  it("treats a nullable Relay workflow connection as an empty inbox", async () => {
    const network = support.createOperatorNetwork({ workflowItems: null });

    support.renderWithRelay(<OperatorRoute />, network);

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
          errors: [{ message: "Operator workflow access is forbidden" }],
        }),
      ),
    );

    support.renderWithRelay(<OperatorRoute />, fetchGraphQL);

    expect(await screen.findByRole("alert")).toHaveTextContent("Unable to load operator inbox.");
    expect(document.body).not.toHaveTextContent("Operator workflow access is forbidden");
    expect(screen.queryByText("No operator workflow items.")).not.toBeInTheDocument();
  });

  it("returns to the previous inbox page when the next page fails", async () => {
    vi.spyOn(console, "error").mockImplementation(() => undefined);
    const network = vi.fn(async (request, variables): Promise<GraphQLResponse> => {
      if (request.name === "OperatorWorkflowRouteQuery") {
        if (variables.after === "cursor_1") {
          throw new Error("GraphQL unavailable secret_alpha");
        }

        return support.workflowConnectionResponse([support.operatorWorkflowItem()], variables, {
          hasNextPage: true,
          hasPreviousPage: false,
          startCursor: "cursor_1",
          endCursor: "cursor_1",
        });
      }

      if (request.name === "OperatorRunStateQuery") {
        return { data: { operatorRunState: support.operatorRunState() } };
      }

      throw new Error(`Unexpected Relay request in operator route test: ${request.name}`);
    });

    support.renderWithRelay(<OperatorRoute />, network);

    expect(await screen.findByRole("button", { name: /evt_1/i })).toBeInTheDocument();
    await waitFor(() => expect(screen.getByRole("button", { name: "Next" })).toBeEnabled());
    fireEvent.click(screen.getByRole("button", { name: "Next" }));

    expect(await screen.findByRole("alert")).toHaveTextContent("Unable to load operator inbox.");
    expect(document.body).not.toHaveTextContent("secret_alpha");
    expect(screen.getByRole("button", { name: "Previous" })).toBeEnabled();

    fireEvent.click(screen.getByRole("button", { name: "Previous" }));

    await waitFor(() => {
      const workflowCalls = network.mock.calls.filter(
        ([request]) => request.name === "OperatorWorkflowRouteQuery",
      );

      expect(workflowCalls.at(-1)?.[1]).toEqual({ first: 50, after: null });
      expect(screen.getByRole("button", { name: /evt_1/i })).toHaveAttribute(
        "aria-current",
        "true",
      );
      expect(screen.getByRole("button", { name: "Previous" })).toBeDisabled();
    });
  });

  it("renders a safe route error for Relay transport failures", async () => {
    vi.spyOn(console, "error").mockImplementation(() => undefined);
    const network = vi.fn(async () => {
      throw new Error("GraphQL unavailable secret_alpha");
    });

    support.renderWithRelay(<OperatorRoute />, network);

    expect(await screen.findByRole("alert")).toHaveTextContent("Unable to load operator inbox.");
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
        return support.workflowConnectionResponse([support.operatorWorkflowItem()], variables);
      }
      if (request.name === "OperatorRunStateQuery") {
        return { data: { operatorRunState: support.operatorRunState() } };
      }
      throw new Error(`Unexpected Relay request in operator route test: ${request.name}`);
    });

    support.renderWithRelay(<OperatorRoute />, network);

    expect(await screen.findByRole("alert")).toHaveTextContent("Unable to load operator inbox");
    fireEvent.click(screen.getByRole("button", { name: "Retry operator workflow" }));

    expect(await screen.findByRole("button", { name: /evt_1/i })).toBeInTheDocument();
    expect(workflowReads).toBe(2);
  });

  it("clears selection-scoped panels while loading a newly selected item", async () => {
    const secondRunState = support.deferredGraphQLResponse();
    const secondItem = support.operatorWorkflowItem({
      id: "operator_workflow_item_global_2",
      normalizedEventId: "evt_2",
      typedId: { type: "normalized_intake_event", id: "evt_2" },
      graphLinks: [
        {
          type: "verification_check",
          id: "check_2",
          graphItemId: "graph_2",
          title: "Review second packet",
          state: "required",
        },
        {
          type: "work_run",
          id: "run_2",
          graphItemId: null,
          title: "Second verification run",
          state: "running",
        },
      ],
    });
    const network = vi.fn(async (request, variables): Promise<GraphQLResponse> => {
      if (request.name === "OperatorWorkflowRouteQuery") {
        return support.workflowConnectionResponse(
          [support.operatorWorkflowItem(), secondItem],
          variables,
        );
      }

      if (request.name === "OperatorRunStateQuery") {
        if (variables.id === "run_2") {
          return secondRunState.promise;
        }

        return { data: { operatorRunState: support.operatorRunState() } };
      }

      throw new Error(`Unexpected Relay request in operator route test: ${request.name}`);
    });

    support.renderWithRelay(<OperatorRoute />, network);

    const secondRow = await screen.findByRole("button", { name: /evt_2/i });

    await waitFor(() => {
      expect(screen.getByRole("region", { name: "Packet Readiness" })).toHaveTextContent(
        "Run console verification",
      );
      expect(screen.getByRole("region", { name: "Run State" })).toHaveTextContent(
        "Awaiting evidence acceptance",
      );
    });

    fireEvent.click(secondRow);

    await waitFor(() => {
      expect(secondRow).toHaveAttribute("aria-current", "true");
      expect(screen.getByRole("region", { name: "Packet Readiness" })).toHaveTextContent(
        "Review second packet",
      );
      expect(screen.getByRole("region", { name: "Run State" })).toHaveTextContent(
        "Loading run state...",
      );
      expect(screen.getByRole("region", { name: "Run State" })).not.toHaveTextContent(
        "Awaiting evidence acceptance",
      );
      expect(screen.getByRole("region", { name: "Verification" })).toHaveTextContent(
        "Loading verification...",
      );
      expect(screen.getByRole("region", { name: "Verification" })).not.toHaveTextContent(
        "Owner acceptance",
      );
      expect(screen.getByRole("region", { name: "Item detail" })).toHaveTextContent(
        "normalized_intake_event: evt_2",
      );
    });

    secondRunState.resolve({
      data: {
        operatorRunState: support.operatorRunState({ status: "verified" }),
      },
    });

    await waitFor(() => {
      expect(screen.getByRole("region", { name: "Packet Readiness" })).toHaveTextContent(
        "Review second packet",
      );
      expect(screen.getByRole("region", { name: "Run State" })).toHaveTextContent("Verified");
    });
  });

  it("keeps inbox, item, and readiness context when a linked run fails", async () => {
    vi.spyOn(console, "error").mockImplementation(() => undefined);
    let runReads = 0;
    const network = vi.fn(async (request, variables): Promise<GraphQLResponse> => {
      if (request.name === "OperatorWorkflowRouteQuery") {
        return support.workflowConnectionResponse([support.operatorWorkflowItem()], variables);
      }

      if (request.name === "OperatorRunStateQuery") {
        runReads += 1;
        if (runReads === 1) {
          throw new Error("authorization secret_alpha denied run_9");
        }

        return { data: { operatorRunState: support.operatorRunState() } };
      }

      throw new Error(`Unexpected Relay request in operator route test: ${request.name}`);
    });

    support.renderWithRelay(<OperatorRoute />, network);

    const selectedRow = await screen.findByRole("button", { name: /evt_1/i });

    await waitFor(() => {
      expect(screen.getByRole("region", { name: "Run State" })).toHaveTextContent(
        "Run state unavailable.",
      );
      expect(screen.getByRole("region", { name: "Verification" })).toHaveTextContent(
        "Verification unavailable.",
      );
    });
    expect(selectedRow).toHaveAttribute("aria-current", "true");
    expect(screen.getByRole("region", { name: "Item detail" })).toHaveTextContent(
      "normalized_intake_event: evt_1",
    );
    expect(screen.getByRole("region", { name: "Packet Readiness" })).toHaveTextContent(
      "Prepare packet context",
    );
    expect(document.body).not.toHaveTextContent("secret_alpha");
    expect(document.body).not.toHaveTextContent("run_9");

    fireEvent.click(screen.getByRole("button", { name: "Retry run state" }));

    await waitFor(() => {
      expect(screen.getByRole("region", { name: "Run State" })).toHaveTextContent(
        "Awaiting evidence acceptance",
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
        decisionLinks: [],
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
        decisionLinks: [],
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
        decisionLinks: [],
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
        decisionLinks: [],
      },
    ];
    const network = support.createOperatorNetwork({
      workflowItems: [
        support.operatorWorkflowItem({
          allowedNextActions: ["legacy_sensitive_fallback"],
          commandAffordances: sensitiveAffordances,
        }),
      ],
      readiness: support.operatorPacketReadiness({
        allowedNextActions: ["legacy_sensitive_readiness_fallback"],
        commandAffordances: sensitiveAffordances,
      }),
      runState: support.operatorRunState({
        allowedNextActions: ["legacy_sensitive_run_fallback"],
        commandAffordances: sensitiveAffordances,
      }),
    });

    support.renderWithRelay(<OperatorRoute />, network);

    await screen.findByRole("button", { name: /evt_1/i });
    const itemDetail = screen.getByRole("region", { name: "Item detail" });

    await waitFor(() => {
      expect(itemDetail).toHaveTextContent("Commands");
      expect(screen.getByRole("region", { name: "Run State" })).toHaveTextContent(
        "Awaiting evidence acceptance",
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

  it("hides manual intake when the backend affordance is restricted", async () => {
    const network = vi.fn(async (request, variables): Promise<GraphQLResponse> => {
      if (request.name === "OperatorWorkflowRouteQuery") {
        return support.workflowConnectionResponse(
          [],
          variables,
          {},
          {
            ...support.enabledCommandAffordance("submit_manual_intake"),
            state: "hidden",
          },
        );
      }
      throw new Error(`Unexpected Relay request in operator route test: ${request.name}`);
    });

    support.renderWithRelay(<OperatorRoute />, network);

    await screen.findByText("No operator workflow items.");
    expect(screen.queryByLabelText("Manual intake")).not.toBeInTheDocument();
  });

  it("recovers when manual replay identity preparation fails", async () => {
    vi.stubGlobal("crypto", {
      subtle: { digest: vi.fn().mockRejectedValue(new Error("digest unavailable")) },
    });
    const network = support.createOperatorNetwork({ workflowItems: [] });

    support.renderWithRelay(<OperatorRoute />, network);
    fireEvent.change(await screen.findByLabelText("Manual intake"), {
      target: { value: "Investigate the deployment" },
    });
    fireEvent.click(screen.getByRole("button", { name: "Submit intake" }));

    expect(await screen.findByRole("alert")).toHaveTextContent(
      "Unable to prepare manual intake. Try again.",
    );
    expect(screen.getByRole("button", { name: "Submit intake" })).toBeEnabled();
    expect(
      network.mock.calls.some(([request]) => request.name === "OperatorSubmitManualIntakeMutation"),
    ).toBe(false);
  });

  it("refreshes after a manual-intake replay conflict and keeps the explicit retry form", async () => {
    let workflowReads = 0;
    const refreshResponse = support.deferredGraphQLResponse();
    const network = vi.fn(async (request, variables): Promise<GraphQLResponse> => {
      if (request.name === "OperatorWorkflowRouteQuery") {
        workflowReads += 1;
        if (workflowReads === 2) return refreshResponse.promise;
        return support.workflowConnectionResponse([], variables);
      }
      if (request.name === "OperatorSubmitManualIntakeMutation")
        throw new GraphQLResponseError(
          "This intake was already accepted. Refresh and retry if the source changed.",
          {
            errors: [
              {
                message:
                  "This intake was already accepted. Refresh and retry if the source changed.",
                extensions: { code: "manual_intake_replay_conflict" },
              } as never,
            ],
          },
          409,
          request.name,
        );
      throw new Error(`Unexpected Relay request in operator route test: ${request.name}`);
    });

    support.renderWithRelay(<OperatorRoute />, network);
    fireEvent.change(await screen.findByLabelText("Manual intake"), {
      target: { value: "Duplicate deployment report" },
    });
    fireEvent.click(screen.getByRole("button", { name: "Submit intake" }));

    expect(await screen.findByRole("alert")).toHaveTextContent("This intake was already accepted");
    await waitFor(() => expect(workflowReads).toBe(2));
    expect(screen.getByLabelText("Manual intake")).toHaveValue("Duplicate deployment report");
    expect(screen.getByRole("button", { name: "Submit intake" })).toBeEnabled();

    await act(async () => {
      refreshResponse.resolve(support.workflowConnectionResponse([], { first: 50, after: null }));
    });
  });

  it("records the operator-selected check and failed outcome", async () => {
    const base = support.operatorRunState();
    const runState = {
      ...base,
      missingEvidence: [
        ...base.missingEvidence,
        { verificationCheckId: "check_2", reason: "missing" },
      ],
      requiredChecks: [
        ...base.requiredChecks,
        {
          id: "required_2",
          graphItemId: "graph_2",
          verificationCheckId: "check_2",
          state: "open",
        },
      ],
      commandOptions: {
        ...base.commandOptions,
        observation: [
          ...base.commandOptions.observation,
          support.observationCommandOption({
            key: "required_2",
            label: "Second verification check",
            verificationCheckId: "check_2",
            sourceGraphItemId: "graph_2",
            defaultOutcomeKey: "degraded",
            outcomes: [
              {
                key: "degraded",
                label: "Needs attention",
                observedStatus: "failed",
                normalizedStatus: "attention_required",
              },
            ],
          }),
        ],
      },
      commandAffordances: [
        support.enabledCommandAffordance(
          "record_execution_observation",
          [{ field: "run_id", value: "run_1", values: [] }],
          [
            { type: "work_run", id: "run_1" },
            { type: "verification_check", id: "check_1" },
            { type: "verification_check", id: "check_2" },
          ],
        ),
      ],
    };
    const network = support.operatorCommandNetwork(runState);

    support.renderWithRelay(<OperatorRoute />, network);
    fireEvent.change(await screen.findByLabelText("Verification check"), {
      target: { value: "required_2" },
    });
    fireEvent.change(screen.getByLabelText("Observation outcome"), {
      target: { value: "degraded" },
    });
    fireEvent.change(screen.getByLabelText("Observation rationale"), {
      target: { value: "The second check failed." },
    });
    fireEvent.click(screen.getByRole("button", { name: "Record execution observation" }));

    await waitFor(() =>
      expect(
        support.lastVariablesFor(network, "OperatorRecordExecutionObservationMutation"),
      ).toMatchObject({
        input: {
          verificationCheckId: "check_2",
          sourceGraphItemId: "graph_2",
          observedStatus: "failed",
          normalizedStatus: "attention_required",
        },
      }),
    );
  });

  it("disables commands whose projected typed option is malformed", async () => {
    const runState = support.operatorRunState({
      commandAffordances: [support.enabledCommandAffordance("record_execution_observation")],
      commandOptions: {
        observation: [support.observationCommandOption({ sourceGraphItemId: "  [REDACTED]  " })],
        evidenceCandidate: [],
        evidenceAcceptance: [],
        waiver: [],
      },
    });

    support.renderWithRelay(<OperatorRoute />, support.operatorCommandNetwork(runState));

    fireEvent.change(await screen.findByLabelText("Observation rationale"), {
      target: { value: "Malformed projected option must stay disabled." },
    });
    expect(screen.getByRole("button", { name: "Record execution observation" })).toBeDisabled();
  });

  it("disables observation options with duplicate outcomes or a missing default", async () => {
    const duplicate = support.observationCommandOption({
      defaultOutcomeKey: "missing",
      outcomes: [
        { key: "same", label: "First", observedStatus: "first", normalizedStatus: "first" },
        { key: "same", label: "Second", observedStatus: "second", normalizedStatus: "second" },
      ],
    });
    const runState = support.operatorRunState({
      commandAffordances: [support.enabledCommandAffordance("record_execution_observation")],
      commandOptions: {
        observation: [duplicate],
        evidenceCandidate: [],
        evidenceAcceptance: [],
        waiver: [],
      },
    });

    support.renderWithRelay(<OperatorRoute />, support.operatorCommandNetwork(runState));

    fireEvent.change(await screen.findByLabelText("Observation rationale"), {
      target: { value: "Invalid outcome bundles cannot submit." },
    });
    expect(screen.getByRole("button", { name: "Record execution observation" })).toBeDisabled();
  });
});
