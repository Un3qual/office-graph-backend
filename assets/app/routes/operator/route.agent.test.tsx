import { act, fireEvent, screen, waitFor } from "@testing-library/react";
import type { GraphQLResponse } from "relay-runtime";
import { describe, expect, it, vi } from "vitest";
import { GraphQLResponseError } from "../../relay/fetchGraphQL";
import OperatorRoute from "./route";
import {
  deferredGraphQLResponse,
  enabledCommandAffordance,
  lastVariablesFor,
  operatorRunState,
  operatorWorkflowItem,
  renderWithRelay,
  workflowConnectionResponse,
} from "./routeTestSupport";

describe("operator run agent surface", () => {
  it("shows bounded execution, conversation, context, and gate state", async () => {
    const network = agentNetwork();

    renderWithRelay(<OperatorRoute />, network);

    const panel = await screen.findByRole("region", { name: "Agent Activity" });
    expect(panel).toHaveTextContent("Review the selected run and OpenSpec artifacts.");
    expect(panel).toHaveTextContent("queued");
    expect(panel).toHaveTextContent("included · selected_graph_item");
    expect(panel).toHaveTextContent("Approval: repository.read");
    expect(panel).toHaveTextContent("Context expansion: repository");
    expect(panel).not.toHaveTextContent(/credential|agent administration|role management/i);
  });

  it("invokes and cancels through independent narrow Relay actions", async () => {
    const invocation = deferredGraphQLResponse();
    const network = agentNetwork({ invocation });

    renderWithRelay(<OperatorRoute />, network);

    fireEvent.change(await screen.findByLabelText("Requested outcome"), {
      target: { value: "Review this run for specification gaps." },
    });
    fireEvent.click(screen.getByRole("button", { name: "Invoke agent" }));

    await waitFor(() => {
      expect(lastVariablesFor(network, "OperatorInvokeAgentMutation")).toEqual({
        input: {
          autonomyMode: "human_supervised",
          bindingId: "binding_1",
          graphItemId: "graph_1",
          idempotencyKey: expect.any(String),
          requestedCapabilities: [
            "agent.model.generate",
            "agent.tool.read",
            "proposal.create",
            "repository.read",
          ],
          requestedOutcome: "Review this run for specification gaps.",
          runId: "run_1",
        },
      });
    });
    expect(screen.getByRole("button", { name: "Invoking agent" })).toBeDisabled();
    expect(screen.getByRole("button", { name: "Cancel agent execution" })).toBeEnabled();

    fireEvent.click(screen.getByRole("button", { name: "Cancel agent execution" }));
    await waitFor(() => {
      expect(lastVariablesFor(network, "OperatorCancelAgentExecutionMutation")).toEqual({
        input: {
          executionId: "execution_1",
          expectedStateVersion: 1,
          idempotencyKey: expect.any(String),
        },
      });
    });

    await act(() => {
      invocation.resolve({
        data: {
          invokeAgent: {
            command: "invoke_agent",
            operationId: "operation_invoke",
            affectedIds: [{ type: "agent_execution", id: "execution_2" }],
            execution: {
              id: "execution_2",
              state: "queued",
              stateVersion: 1,
              currentStepKey: null,
            },
            contextPackageId: "context_2",
          },
        },
      });
    });
  });

  it("submits messages and versioned approval and expansion decisions", async () => {
    const network = agentNetwork();

    renderWithRelay(<OperatorRoute />, network);

    fireEvent.change(await screen.findByLabelText("Run message"), {
      target: { value: "Please inspect the authorization boundary." },
    });
    fireEvent.click(screen.getByRole("button", { name: "Send message" }));
    await waitFor(() => {
      expect(lastVariablesFor(network, "OperatorAppendConversationMessageMutation")).toEqual({
        input: {
          body: "Please inspect the authorization boundary.",
          contributionKind: "comment",
          conversationId: "conversation_1",
          domainActionOperationId: null,
          idempotencyKey: expect.any(String),
          proposedGraphChangeId: null,
        },
      });
    });

    fireEvent.change(screen.getByLabelText("Approval resolution reason"), {
      target: { value: "The bounded read is appropriate." },
    });
    fireEvent.click(screen.getByRole("button", { name: "Approve request" }));
    await waitFor(() => {
      expect(lastVariablesFor(network, "OperatorResolveAgentApprovalMutation")).toEqual({
        input: {
          approvalRequestId: "approval_1",
          decision: "approved",
          expectedVersion: 1,
          idempotencyKey: expect.any(String),
          resolutionReason: "The bounded read is appropriate.",
        },
      });
    });

    fireEvent.change(screen.getByLabelText("Context expansion resolution reason"), {
      target: { value: "Allow only the requested repository scope." },
    });
    fireEvent.click(screen.getByRole("button", { name: "Approve context expansion" }));
    await waitFor(() => {
      expect(lastVariablesFor(network, "OperatorResolveAgentContextExpansionMutation")).toEqual({
        input: {
          contextExpansionRequestId: "expansion_1",
          decision: "approved",
          expectedVersion: 1,
          idempotencyKey: expect.any(String),
          resolutionReason: "Allow only the requested repository scope.",
        },
      });
    });
  });

  it("does not expose message submission without the append affordance", async () => {
    const network = agentNetwork({ appendEnabled: false });

    renderWithRelay(<OperatorRoute />, network);

    expect(await screen.findByRole("region", { name: "Agent Activity" })).toBeVisible();
    expect(screen.queryByLabelText("Run message")).not.toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "Send message" })).not.toBeInTheDocument();
  });

  it("refetches stale gates and preserves safe conflict feedback", async () => {
    let conversationReads = 0;
    const network = agentNetwork({
      onConversationRead: () => {
        conversationReads += 1;
      },
      staleApproval: true,
    });

    renderWithRelay(<OperatorRoute />, network);

    fireEvent.change(await screen.findByLabelText("Approval resolution reason"), {
      target: { value: "Approve the exact request shown." },
    });
    fireEvent.click(screen.getByRole("button", { name: "Approve request" }));

    expect(await screen.findByRole("alert")).toHaveTextContent(
      "The approval request version is stale.",
    );
    await waitFor(() => expect(conversationReads).toBe(2));
    expect(screen.getByRole("region", { name: "Run State" })).toHaveTextContent("run_1");
  });

  it("resets drafts when the selected run and graph context changes", async () => {
    const second = operatorWorkflowItem({
      id: "operator_workflow_item_agent_2",
      normalizedEventId: "evt_agent_2",
      title: "Second agent run",
      typedId: { type: "normalized_intake_event", id: "evt_agent_2" },
      graphLinks: [
        {
          type: "verification_check",
          id: "check_2",
          graphItemId: "graph_2",
          title: "Second agent check",
          state: "required",
        },
        {
          type: "work_run",
          id: "run_2",
          graphItemId: null,
          title: "Second agent run",
          state: "running",
        },
      ],
    });
    const network = agentNetwork({ workflowItems: [operatorWorkflowItem(), second] });

    renderWithRelay(<OperatorRoute />, network);

    const draft = await screen.findByLabelText("Run message");
    fireEvent.change(draft, { target: { value: "Do not carry this draft." } });
    fireEvent.click(screen.getByRole("button", { name: /Second agent run/i }));

    await waitFor(() => {
      expect(lastVariablesFor(network, "OperatorRunConversationQuery")).toEqual({
        graphItemId: "graph_2",
        runId: "run_2",
      });
    });
    await waitFor(() => expect(screen.getByLabelText("Run message")).toHaveValue(""));
  });

  it("starts the focused run conversation when none exists", async () => {
    const network = agentNetwork({ noConversation: true });

    renderWithRelay(<OperatorRoute />, network);

    fireEvent.click(await screen.findByRole("button", { name: "Start conversation" }));

    await waitFor(() => {
      expect(lastVariablesFor(network, "OperatorStartRunConversationMutation")).toEqual({
        input: {
          graphItemId: "graph_1",
          idempotencyKey: expect.any(String),
          runId: "run_1",
        },
      });
    });
  });

  it("keeps the run state visible when agent activity cannot load", async () => {
    vi.spyOn(console, "error").mockImplementation(() => undefined);
    const network = agentNetwork({ conversationError: true });

    renderWithRelay(<OperatorRoute />, network);

    expect(await screen.findByText("Agent activity is unavailable.")).toBeVisible();
    expect(screen.getByRole("region", { name: "Run State" })).toHaveTextContent("run_1");
    expect(screen.getByRole("button", { name: "Retry agent activity" })).toBeEnabled();
  });
});

function agentNetwork({
  appendEnabled = true,
  conversationError = false,
  invocation,
  noConversation = false,
  onConversationRead,
  staleApproval = false,
  workflowItems = [operatorWorkflowItem()],
}: {
  appendEnabled?: boolean;
  conversationError?: boolean;
  invocation?: ReturnType<typeof deferredGraphQLResponse>;
  noConversation?: boolean;
  onConversationRead?: () => void;
  staleApproval?: boolean;
  workflowItems?: ReturnType<typeof operatorWorkflowItem>[];
} = {}) {
  return vi.fn((request, variables) => {
    if (request.name === "OperatorWorkflowRouteQuery") {
      return workflowConnectionResponse(workflowItems, variables);
    }
    if (request.name === "OperatorRunStateQuery") {
      const graphItemId = variables.id === "run_2" ? "graph_2" : "graph_1";
      const runState = {
        ...operatorRunState({
          requiredChecks: [
            {
              id: `required_${variables.id}`,
              graphItemId,
              verificationCheckId: `check_${variables.id}`,
              state: "open",
            },
          ],
        }),
        run: {
          id: variables.id,
          aggregateState: "running",
          executionState: "running",
          verificationState: "pending",
        },
      };
      return { data: { operatorRunState: runState } };
    }
    if (request.name === "OperatorRunConversationQuery") {
      onConversationRead?.();
      if (conversationError) {
        throw new GraphQLResponseError(
          "Conversation projection unavailable.",
          { errors: [{ message: "Conversation projection unavailable." } as never] },
          503,
          request.name,
        );
      }
      const surface = agentSurface({
        graphItemId: variables.graphItemId,
        runId: variables.runId,
      });
      const projectedSurface = appendEnabled
        ? surface
        : {
            ...surface,
            allowedNextActions: surface.allowedNextActions.filter(
              (identity) => identity !== "append_conversation_message",
            ),
            commandAffordances: surface.commandAffordances.map((affordance) =>
              affordance.identity === "append_conversation_message"
                ? { ...affordance, state: "disabled" }
                : affordance,
            ),
          };
      return {
        data: {
          operatorRunConversation: noConversation
            ? agentSurfaceWithoutConversation(projectedSurface, variables)
            : projectedSurface,
        },
      };
    }
    if (request.name === "OperatorInvokeAgentMutation") {
      if (invocation) return invocation.promise;
      return commandResponse("invokeAgent", "invoke_agent");
    }
    if (request.name === "OperatorCancelAgentExecutionMutation") {
      return commandResponse("cancelAgentExecution", "cancel_agent_execution");
    }
    if (request.name === "OperatorAppendConversationMessageMutation") {
      return commandResponse("appendConversationMessage", "append_conversation_message");
    }
    if (request.name === "OperatorStartRunConversationMutation") {
      return commandResponse("startRunConversation", "start_run_conversation");
    }
    if (request.name === "OperatorResolveAgentApprovalMutation") {
      if (staleApproval) {
        throw new GraphQLResponseError(
          "The approval request version is stale.",
          {
            errors: [
              {
                message: "The approval request version is stale.",
                extensions: { code: "stale_agent_approval" },
              } as never,
            ],
          },
          409,
          request.name,
        );
      }
      return commandResponse("resolveAgentApproval", "resolve_agent_approval");
    }
    if (request.name === "OperatorResolveAgentContextExpansionMutation") {
      return commandResponse("resolveAgentContextExpansion", "resolve_agent_context_expansion");
    }
    throw new Error(`Unexpected Relay request in agent route test: ${request.name}`);
  });
}

function agentSurfaceWithoutConversation(
  surface: ReturnType<typeof agentSurface>,
  variables: Readonly<Record<string, string>>,
) {
  return {
    ...surface,
    allowedNextActions: ["start_run_conversation", "invoke_agent"],
    commandAffordances: [
      enabledCommandAffordance("start_run_conversation", [
        { field: "run_id", value: variables.runId, values: [] },
        { field: "graph_item_id", value: variables.graphItemId, values: [] },
      ]),
      ...surface.commandAffordances.filter(({ identity }) => identity === "invoke_agent"),
    ],
    conversation: null,
    messages: [],
  };
}

function commandResponse(field: string, command: string): GraphQLResponse {
  return {
    data: {
      [field]: {
        command,
        operationId: `operation_${command}`,
        affectedIds: [],
        conversation: {
          id: "conversation_1",
          runId: "run_1",
          graphItemId: "graph_1",
          state: "active",
          stateVersion: 1,
        },
        message: { id: "message_2", conversationId: "conversation_1" },
        request: { id: "request_1", state: "approved", version: 2 },
        execution: {
          id: "execution_1",
          state: command === "cancel_agent_execution" ? "cancelled" : "queued",
          stateVersion: 2,
          currentStepKey: null,
        },
        contextPackageId: "context_2",
      },
    },
  };
}

function agentSurface({ graphItemId, runId }: { graphItemId: string; runId: string }) {
  return {
    type: "operator_run_conversation",
    sourceWatermark: `${runId}:${graphItemId}:1`,
    allowedNextActions: [
      "append_conversation_message",
      "invoke_agent",
      "cancel_agent_execution",
      "resolve_agent_approval",
      "resolve_agent_context_expansion",
    ],
    commandAffordances: [
      enabledCommandAffordance("append_conversation_message"),
      enabledCommandAffordance("invoke_agent", [
        { field: "binding_id", value: "binding_1", values: [] },
        { field: "run_id", value: runId, values: [] },
        { field: "graph_item_id", value: graphItemId, values: [] },
        {
          field: "requested_capabilities",
          value: null,
          values: ["agent.model.generate", "agent.tool.read", "proposal.create", "repository.read"],
        },
        { field: "autonomy_mode", value: "human_supervised", values: [] },
        {
          field: "requested_outcome",
          value: "Review the selected run and OpenSpec artifacts.",
          values: [],
        },
      ]),
      enabledCommandAffordance("cancel_agent_execution"),
      enabledCommandAffordance("resolve_agent_approval"),
      enabledCommandAffordance("resolve_agent_context_expansion"),
    ],
    conversation: {
      id: "conversation_1",
      runId,
      graphItemId,
      createdByPrincipalId: "principal_1",
      operationId: "operation_conversation",
      purpose: "agent_runtime",
      visibility: "run_participants",
      state: "active",
      stateVersion: 1,
      insertedAt: "2026-07-22T20:00:00Z",
      updatedAt: "2026-07-22T20:00:00Z",
    },
    messages: [
      {
        id: "message_1",
        source: "agent",
        body: "Review the selected run and OpenSpec artifacts.",
        visibility: "run_participants",
        authorPrincipalId: "agent_1",
        executionId: "execution_1",
        contextPackageId: "context_1",
        operationId: "operation_message",
        proposedGraphChangeId: null,
        domainActionOperationId: null,
        insertedAt: "2026-07-22T20:01:00Z",
        referencedContext: {
          visibility: "visible",
          packageId: "context_1",
          version: 1,
          entries: [{ posture: "included", rationaleCode: "selected_graph_item" }],
        },
      },
    ],
    executions: [
      {
        id: "execution_1",
        bindingId: "binding_1",
        state: "queued",
        stateVersion: 1,
        currentStepKey: null,
        attemptCount: 0,
        failureCode: null,
        requestedOutcome: "Review the run.",
        invocationMode: "human",
        origin: "operator",
        autonomyMode: "human_supervised",
        insertedAt: "2026-07-22T20:00:00Z",
        updatedAt: "2026-07-22T20:00:00Z",
      },
    ],
    approvalRequests: [
      {
        id: "approval_1",
        executionId: "execution_1",
        stepKey: "model:review",
        requestedAction: "repository.read",
        reason: "Read repository context.",
        scopeType: "workspace",
        scopeId: "workspace_1",
        capabilityKey: "repository.read",
        sensitivity: "internal",
        externalWrite: false,
        state: "pending",
        version: 1,
        expiresAt: "2026-07-22T21:00:00Z",
        resolutionReason: null,
        insertedAt: "2026-07-22T20:00:00Z",
        updatedAt: "2026-07-22T20:00:00Z",
      },
    ],
    contextExpansionRequests: [
      {
        id: "expansion_1",
        executionId: "execution_1",
        stepKey: "tool:repository",
        targetResourceType: "repository",
        targetResourceId: "repository_1",
        targetScopeType: "workspace",
        targetScopeId: "workspace_1",
        accessMode: "read",
        capabilityKey: "repository.read",
        reason: "Inspect the repository.",
        sensitivity: "internal",
        expectedDurationSeconds: 300,
        state: "pending",
        version: 1,
        expiresAt: "2026-07-22T21:00:00Z",
        resolutionReason: null,
        insertedAt: "2026-07-22T20:00:00Z",
        updatedAt: "2026-07-22T20:00:00Z",
      },
    ],
  };
}
