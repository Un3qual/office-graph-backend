import { fireEvent, screen, waitFor } from "@testing-library/react";
import type { GraphQLResponse } from "relay-runtime";
import { afterEach, describe, expect, it, vi } from "vitest";
import OperatorRoute from "./route";

import * as support from "./routeTestSupport";

describe("operator route reads", () => {
  afterEach(() => {
    vi.unstubAllGlobals();
    vi.restoreAllMocks();
  });

  it("renders the operator workbench from Relay projection data", async () => {
    const network = support.createOperatorNetwork({
      workflowItems: [support.operatorWorkflowItem()],
      runState: support.operatorRunState(),
    });

    support.renderWithRelay(<OperatorRoute />, network);

    expect(screen.getByRole("heading", { name: "Operator Console" })).toBeInTheDocument();
    const firstRow = await screen.findByRole("button", { name: /evt_1/i });

    await waitFor(() => {
      expect(firstRow).toHaveAttribute("aria-current", "true");
    });
    expect(screen.getByRole("region", { name: "Inbox" })).toHaveTextContent("Ready for packet");
    expect(screen.getByRole("region", { name: "Item detail" })).toHaveTextContent(
      "normalized_intake_event: evt_1",
    );
    expect(await screen.findByText("Prepare packet context")).toBeInTheDocument();
    const readinessCall = network.mock.calls.find(
      ([request]) => request.name === "OperatorPacketReadinessQuery",
    );

    expect(readinessCall).toBeUndefined();

    await waitFor(() => {
      expect(screen.getByRole("region", { name: "Run State" })).toHaveTextContent(
        "Awaiting evidence acceptance",
      );
      expect(screen.getByRole("region", { name: "Verification" })).toHaveTextContent(
        "Owner acceptance",
      );
    });
  });

  it("opens a packet-workspace run link from the route query string", async () => {
    const runState = support.operatorRunState();
    const network = support.createOperatorNetwork({
      workflowItems: [support.operatorWorkflowItem()],
      runState: { ...runState, run: { ...runState.run, id: "run_linked" } },
    });

    support.renderWithRelay(<OperatorRoute />, network, "/operator?runId=run_linked");

    await waitFor(() => {
      const runCall = network.mock.calls.find(
        ([request]) => request.name === "OperatorRunStateQuery",
      );
      expect(runCall?.[1]).toEqual({
        id: "run_linked",
        activityFirst: 5,
        activityAfter: null,
      });
    });
    await waitFor(() => {
      expect(screen.getByRole("region", { name: "Run State" })).toHaveTextContent(
        "Awaiting evidence acceptance",
      );
    });
    expect(screen.getByRole("button", { name: /evt_1/i })).not.toHaveAttribute("aria-current");
    expect(screen.getByRole("region", { name: "Item detail" })).toHaveTextContent(
      "No item selected",
    );
    expect(screen.getByRole("region", { name: "Packet Readiness" })).toHaveTextContent(
      "No packet readiness selected",
    );
  });

  it("loads the next stable run activity page from the product fragment", async () => {
    const firstState = support.operatorRunState({
      activity: {
        edges: [
          {
            cursor: "activity_cursor_1",
            node: {
              kind: "required_check",
              stableId: "required_1",
              title: "Initial required check",
              status: "open",
            },
          },
        ],
        pageInfo: {
          hasNextPage: true,
          hasPreviousPage: false,
          startCursor: "activity_cursor_1",
          endCursor: "activity_cursor_1",
        },
      },
    });
    const secondState = support.operatorRunState({
      activity: {
        edges: [
          {
            cursor: "activity_cursor_2",
            node: {
              kind: "observation",
              stableId: "observation_2",
              title: "Later observation",
              status: "succeeded",
            },
          },
        ],
        pageInfo: {
          hasNextPage: false,
          hasPreviousPage: true,
          startCursor: "activity_cursor_2",
          endCursor: "activity_cursor_2",
        },
      },
    });
    const network = vi.fn(async (request, variables): Promise<GraphQLResponse> => {
      if (request.name === "OperatorWorkflowRouteQuery") {
        return support.workflowConnectionResponse([support.operatorWorkflowItem()], variables);
      }
      if (request.name === "OperatorRunStateQuery") {
        return {
          data: {
            operatorRunState:
              variables.activityAfter === "activity_cursor_1" ? secondState : firstState,
          },
        };
      }
      throw new Error(`Unexpected Relay request in operator route test: ${request.name}`);
    });

    support.renderWithRelay(<OperatorRoute />, network);

    expect(await screen.findByText(/Initial required check/)).toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: "Next run activity page" }));

    expect(await screen.findByText(/Later observation/)).toBeInTheDocument();
    expect(support.lastVariablesFor(network, "OperatorRunStateQuery")).toMatchObject({
      activityAfter: "activity_cursor_1",
      activityFirst: 5,
    });
  });

  it("renders only the requested manual inbox page after paging forward", async () => {
    const nextPage = support.deferredGraphQLResponse();
    const firstItem = support.operatorWorkflowItem();
    const secondItem = support.operatorWorkflowItem({
      id: "operator_workflow_item_global_2",
      normalizedEventId: "evt_2",
      typedId: { type: "normalized_intake_event", id: "evt_2" },
      source: {
        identity: "manual:operator-console-2",
        replayIdentity: "paste:operator-console-2",
        outcome: "accepted",
      },
    });
    const network = vi.fn(async (request, variables): Promise<GraphQLResponse> => {
      if (request.name === "OperatorWorkflowRouteQuery") {
        return variables.after === "cursor_1"
          ? nextPage.promise
          : support.workflowConnectionResponse([firstItem], variables, {
              hasNextPage: true,
              hasPreviousPage: false,
              startCursor: "cursor_1",
              endCursor: "cursor_1",
            });
      }

      if (request.name === "OperatorPacketReadinessQuery") {
        return { data: { operatorPacketReadiness: support.operatorPacketReadiness() } };
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

    expect(screen.getByRole("status")).toHaveTextContent("Loading inbox...");
    expect(screen.queryByRole("button", { name: /evt_1/i })).not.toBeInTheDocument();
    expect(screen.getByRole("region", { name: "Item detail" })).toHaveTextContent(
      "No item selected",
    );

    nextPage.resolve(
      support.workflowConnectionResponse(
        [secondItem],
        { after: "cursor_1" },
        {
          hasNextPage: false,
          hasPreviousPage: true,
          startCursor: "cursor_2",
          endCursor: "cursor_2",
        },
      ),
    );

    await waitFor(() => {
      expect(screen.queryByRole("button", { name: /evt_1/i })).not.toBeInTheDocument();
      expect(screen.getByRole("button", { name: /evt_2/i })).toHaveAttribute(
        "aria-current",
        "true",
      );
      expect(screen.getByLabelText("Inbox pagination")).toHaveTextContent("1 row");
    });
  });

  it("renders distinct policy-safe summaries and proposal previews for one source", async () => {
    const firstItem = support.operatorWorkflowItem({
      id: "operator_workflow_item_summary_1",
      normalizedEventId: "evt_summary_1",
      typedId: { type: "normalized_intake_event", id: "evt_summary_1" },
      title: "Manual intake proposal evt_summary_1",
      sourceSummary: "2 proposed changes · ref evt_summary_1",
      proposedActionPreviews: [
        {
          action: "create_signal",
          title: "Proposed signal · ref evt_summary_1",
          status: "pending",
        },
        { action: "create_task", title: "Proposed task · ref evt_summary_1", status: "pending" },
      ],
      source: {
        identity: "manual:shared-source",
        replayIdentity: "paste:summary-1",
        outcome: "accepted",
      },
    });
    const secondItem = support.operatorWorkflowItem({
      id: "operator_workflow_item_summary_2",
      normalizedEventId: "evt_summary_2",
      typedId: { type: "normalized_intake_event", id: "evt_summary_2" },
      title: "Manual intake proposal evt_summary_2",
      sourceSummary: "1 proposed change · ref evt_summary_2",
      proposedActionPreviews: [
        {
          action: "create_signal",
          title: "Proposed signal · ref evt_summary_2",
          status: "pending",
        },
      ],
      source: {
        identity: "manual:shared-source",
        replayIdentity: "paste:summary-2",
        outcome: "accepted",
      },
    });

    support.renderWithRelay(
      <OperatorRoute />,
      support.createOperatorNetwork({ workflowItems: [firstItem, secondItem] }),
    );

    expect(await screen.findByRole("button", { name: /2 proposed changes/i })).toHaveTextContent(
      "2 proposed changes · ref evt_summary_1",
    );
    expect(screen.getByRole("button", { name: /1 proposed change/i })).toHaveTextContent(
      "1 proposed change · ref evt_summary_2",
    );
    expect(screen.getByRole("region", { name: "Item detail" })).toHaveTextContent(
      "Create signal: Proposed signal · ref evt_summary_1",
    );
    expect(document.body).not.toHaveTextContent("SECRET_TOKEN");
  });

  it("loads bounded relationship overflow detail", async () => {
    const item = support.operatorWorkflowItem({
      relationshipSummary: { graphLinks: 21, graphRelationships: 1, hasMore: true },
    });
    const network = vi.fn(async (request, variables): Promise<GraphQLResponse> => {
      if (request.name === "OperatorWorkflowRouteQuery") {
        return support.workflowConnectionResponse([item], variables);
      }
      if (request.name === "OperatorRunStateQuery") {
        return { data: { operatorRunState: support.operatorRunState() } };
      }
      if (request.name === "OperatorRelationshipDetailsQuery") {
        const secondPage = variables.after === "relationship_cursor_1";
        return {
          data: {
            operatorRelationshipDetails: {
              edges: [
                {
                  cursor: secondPage ? "relationship_cursor_2" : "relationship_cursor_1",
                  node: secondPage
                    ? {
                        kind: "graph_relationship",
                        stableId: "relationship_2",
                        title: "Second relationship",
                        status: null,
                        linkType: null,
                        definitionKey: "depends_on",
                      }
                    : {
                        kind: "graph_link",
                        stableId: "task:task_1",
                        title: "First related task",
                        status: "open",
                        linkType: "task",
                        definitionKey: null,
                      },
                },
              ],
              pageInfo: {
                hasNextPage: !secondPage,
                hasPreviousPage: secondPage,
                startCursor: secondPage ? "relationship_cursor_2" : "relationship_cursor_1",
                endCursor: secondPage ? "relationship_cursor_2" : "relationship_cursor_1",
              },
            },
          },
        };
      }
      throw new Error(`Unexpected Relay request in operator route test: ${request.name}`);
    });

    support.renderWithRelay(<OperatorRoute />, network);

    expect(await screen.findByText(/First related task/)).toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: "Next relationship page" }));
    expect(await screen.findByText(/Second relationship/)).toBeInTheDocument();
    expect(support.lastVariablesFor(network, "OperatorRelationshipDetailsQuery")).toMatchObject({
      id: "evt_1",
      first: 5,
      after: "relationship_cursor_1",
    });
  });

  it("refetches relationship overflow detail after an authoritative proposal refresh", async () => {
    let relationshipReads = 0;
    const proposalAffordance = {
      identity: "apply_proposed_changes",
      state: "enabled",
      reasonCodes: [],
      blockerReasons: [],
      safeExplanation: "Apply pending proposed changes for this intake.",
      requiredFields: ["normalized_event_id", "proposed_change_ids"],
      inputDefaults: [
        { field: "normalized_event_id", value: "evt_1", values: [] },
        { field: "proposed_change_ids", value: null, values: ["change_1"] },
      ],
      targetIds: [{ type: "normalized_intake_event", id: "evt_1" }],
      traceLinks: [],
      decisionLinks: [],
    };
    const item = support.operatorWorkflowItem({
      status: "pending_triage",
      allowedNextActions: ["apply_proposed_changes"],
      commandAffordances: [proposalAffordance],
      relationshipSummary: { graphLinks: 21, graphRelationships: 1, hasMore: true },
    });
    const network = vi.fn(async (request, variables): Promise<GraphQLResponse> => {
      if (request.name === "OperatorWorkflowRouteQuery") {
        return support.workflowConnectionResponse([item], variables);
      }
      if (request.name === "OperatorRunStateQuery") {
        return { data: { operatorRunState: support.operatorRunState() } };
      }
      if (request.name === "OperatorRelationshipDetailsQuery") {
        relationshipReads += 1;
        const secondPage = variables.after === "relationship_cursor_1";
        const title =
          relationshipReads > 2
            ? "Refreshed relationship"
            : secondPage
              ? "Second-page relationship"
              : "Original relationship";
        const cursor = secondPage ? "relationship_cursor_2" : "relationship_cursor_1";
        return {
          data: {
            operatorRelationshipDetails: {
              edges: [
                {
                  cursor,
                  node: {
                    kind: "graph_link",
                    stableId: `task:task_${relationshipReads}`,
                    title,
                    status: "open",
                    linkType: "task",
                    definitionKey: null,
                  },
                },
              ],
              pageInfo: {
                hasNextPage: !secondPage,
                hasPreviousPage: secondPage,
                startCursor: cursor,
                endCursor: cursor,
              },
            },
          },
        };
      }
      if (request.name === "OperatorApplyProposedChangesMutation") {
        return {
          data: {
            applyProposedChanges: {
              command: "apply_proposed_changes",
              operationId: "operation_apply_refresh",
              affectedIds: [],
              signal: { id: "signal_1" },
              task: { id: "task_1" },
              reviewFinding: null,
              verificationCheck: null,
            },
          },
        };
      }
      throw new Error(`Unexpected Relay request in operator route test: ${request.name}`);
    });

    support.renderWithRelay(<OperatorRoute />, network);

    expect(await screen.findByText("Original relationship · Task")).toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: "Next relationship page" }));
    expect(await screen.findByText("Second-page relationship · Task")).toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: "Apply proposed changes" }));

    expect(await screen.findByText("Refreshed relationship · Task")).toBeInTheDocument();
    expect(relationshipReads).toBe(3);
    expect(support.lastVariablesFor(network, "OperatorRelationshipDetailsQuery")).toMatchObject({
      after: null,
    });
  });

  it("updates the selected row and derived workflow panels from Relay data", async () => {
    const secondItem = support.operatorWorkflowItem({
      id: "operator_workflow_item_global_2",
      normalizedEventId: "evt_2",
      typedId: { type: "normalized_intake_event", id: "evt_2" },
      source: {
        identity: "manual:operator-console-2",
        replayIdentity: "paste:operator-console-2",
        outcome: "accepted",
      },
      graphLinks: [
        {
          type: "verification_check",
          id: "check_2",
          graphItemId: "graph_2",
          title: "Review second packet",
          state: "required",
        },
      ],
    });
    const network = support.createOperatorNetwork({
      workflowItems: [support.operatorWorkflowItem(), secondItem],
    });

    support.renderWithRelay(<OperatorRoute />, network);

    const secondRow = await screen.findByRole("button", { name: /evt_2/i });
    fireEvent.click(secondRow);

    await waitFor(() => {
      expect(secondRow).toHaveAttribute("aria-current", "true");
      expect(screen.getByRole("region", { name: "Item detail" })).toHaveTextContent(
        "normalized_intake_event: evt_2",
      );
      expect(screen.getByRole("region", { name: "Packet Readiness" })).toHaveTextContent(
        "Review second packet",
      );
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
        { field: "proposed_change_ids", value: null, values: ["change_1", "change_2"] },
      ],
      targetIds: [{ type: "normalized_intake_event", id: "evt_1" }],
      traceLinks: [],
      decisionLinks: [],
    };
    const network = vi.fn(async (request, variables): Promise<GraphQLResponse> => {
      if (request.name === "OperatorWorkflowRouteQuery") {
        return support.workflowConnectionResponse(
          [
            support.operatorWorkflowItem({
              status: "pending_triage",
              allowedNextActions: ["apply_proposed_changes"],
              commandAffordances: [proposalAffordance],
            }),
          ],
          variables,
        );
      }

      if (request.name === "OperatorRunStateQuery") {
        return { data: { operatorRunState: support.operatorRunState() } };
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
              verificationCheck: { id: "check_1", graphItemId: "graph_1" },
            },
          },
        };
      }

      throw new Error(`Unexpected Relay request in operator route test: ${request.name}`);
    });

    support.renderWithRelay(<OperatorRoute />, network);

    fireEvent.click(await screen.findByRole("button", { name: "Apply proposed changes" }));

    await waitFor(() => {
      expect(
        network.mock.calls.find(
          ([request]) => request.name === "OperatorApplyProposedChangesMutation",
        )?.[1],
      ).toMatchObject({
        input: {
          normalizedEventId: "evt_1",
          proposedChangeIds: ["change_1", "change_2"],
        },
      });
    });
  });

  it("uses complete typed options when parallel run collections are redacted", async () => {
    const runState = support.operatorRunState({
      requiredChecks: [],
      observations: [],
      commandAffordances: [
        support.enabledCommandAffordance("record_execution_observation"),
        support.enabledCommandAffordance("create_evidence_candidate"),
      ],
      commandOptions: {
        observation: [
          support.observationCommandOption({
            key: "required_2",
            label: "Payroll import check",
            verificationCheckId: "check_2",
            sourceGraphItemId: "graph_2",
          }),
        ],
        evidenceCandidate: [
          support.evidenceCandidateCommandOption({
            key: "observation_2",
            label: "Payroll import evidence",
            verificationCheckId: "check_2",
            executionObservationId: "observation_2",
            sourceIdentity: "manual:approved-source",
          }),
        ],
        evidenceAcceptance: [],
        waiver: [],
      },
    });
    const network = support.operatorCommandNetwork(runState);

    support.renderWithRelay(<OperatorRoute />, network);

    expect(await screen.findByRole("option", { name: "Payroll import check" })).toBeInTheDocument();
    fireEvent.change(screen.getByLabelText("Observation outcome"), {
      target: { value: "failed" },
    });
    fireEvent.change(screen.getByLabelText("Observation rationale"), {
      target: { value: "The approved option failed." },
    });
    fireEvent.click(screen.getByRole("button", { name: "Record execution observation" }));

    await waitFor(() =>
      expect(
        support.lastVariablesFor(network, "OperatorRecordExecutionObservationMutation"),
      ).toMatchObject({
        input: {
          runId: "run_1",
          verificationCheckId: "check_2",
          sourceGraphItemId: "graph_2",
          observationSourceKind: "human",
          observationSourceIdentity: "operator-console",
          freshnessState: "fresh",
          trustBasis: "owner_attested",
        },
      }),
    );

    expect(screen.getByRole("option", { name: "Payroll import evidence" })).toBeInTheDocument();
    fireEvent.change(screen.getByLabelText("Evidence claim"), {
      target: { value: "Approved evidence option." },
    });
    fireEvent.click(screen.getByRole("button", { name: "Suggest evidence" }));

    await waitFor(() =>
      expect(
        support.lastVariablesFor(network, "OperatorCreateEvidenceCandidateMutation"),
      ).toMatchObject({
        input: {
          workRunId: "run_1",
          verificationCheckId: "check_2",
          executionObservationId: "observation_2",
          sourceKind: "human",
          sourceIdentity: "manual:approved-source",
          freshnessState: "fresh",
          trustBasis: "owner_attested",
          sensitivity: "internal",
        },
      }),
    );
  });

  it("does not synthesize run start from an inbox-only affordance", async () => {
    const workflowItem = support.operatorWorkflowItem({
      commandAffordances: [
        support.enabledCommandAffordance("start_work_run", [
          { field: "packet_version_id", value: "version_1", values: [] },
        ]),
      ],
    });

    support.renderWithRelay(
      <OperatorRoute />,
      support.createOperatorNetwork({ workflowItems: [workflowItem] }),
    );

    await screen.findByRole("button", { name: /evt_1/i });
    expect(screen.queryByRole("button", { name: "Start work run" })).not.toBeInTheDocument();
  });
});
