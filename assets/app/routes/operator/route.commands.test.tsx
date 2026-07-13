import { act, fireEvent, screen, waitFor } from "@testing-library/react";
import type { GraphQLResponse } from "relay-runtime";
import { afterEach, describe, expect, it, vi } from "vitest";
import OperatorRoute from "./route";

import * as support from "./routeTestSupport";

describe("operator route reads", () => {
  afterEach(() => {
    vi.unstubAllGlobals();
    vi.restoreAllMocks();
  });

  it("pages overflow command choices and resets their cursor for a different run", async () => {
    const secondItem = support.operatorWorkflowItem({
      id: "operator_workflow_item_command_page_2",
      normalizedEventId: "evt_command_page_2",
      typedId: { type: "normalized_intake_event", id: "evt_command_page_2" },
      title: "Second command-page run",
      sourceSummary: "Second command-page run summary",
      graphLinks: [
        {
          type: "work_run",
          id: "run_2",
          graphItemId: null,
          title: "Second run",
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
        const state = support.operatorRunState({
          commandOptionsOverflow: true,
          commandOptionSummary: {
            observation: 21,
            evidenceCandidate: 1,
            evidenceAcceptance: 1,
            waiver: 1,
          },
          commandAffordances: [support.enabledCommandAffordance("record_execution_observation")],
        });
        return {
          data: { operatorRunState: { ...state, run: { ...state.run, id: variables.id } } },
        };
      }
      if (request.name === "OperatorRunCommandOptionPageQuery") {
        const secondPage = variables.observationAfter === "option_cursor_1";
        const connection = {
          edges: [
            {
              cursor: secondPage ? "option_cursor_2" : "option_cursor_1",
              node: {
                observation: support.observationCommandOption({
                  key: secondPage ? "required_21" : "required_1",
                  label: secondPage ? "Twenty-first check" : "First check",
                }),
                evidenceCandidate: null,
                evidenceAcceptance: null,
                waiver: null,
              },
            },
          ],
          pageInfo: {
            hasNextPage: !secondPage,
            hasPreviousPage: secondPage,
            startCursor: secondPage ? "option_cursor_2" : "option_cursor_1",
            endCursor: secondPage ? "option_cursor_2" : "option_cursor_1",
          },
        };
        return {
          data: {
            observation: connection,
          },
        };
      }
      throw new Error(`Unexpected Relay request in operator route test: ${request.name}`);
    });

    support.renderWithRelay(<OperatorRoute />, network);

    expect(await screen.findByRole("option", { name: "First check" })).toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: "Next observation choices" }));
    expect(await screen.findByRole("option", { name: "Twenty-first check" })).toBeInTheDocument();

    fireEvent.click(screen.getByRole("button", { name: /Second command-page run/i }));

    await waitFor(() => {
      const observationCalls = network.mock.calls.filter(
        ([request, variables]) =>
          request.name === "OperatorRunCommandOptionPageQuery" && variables.id === "run_2",
      );
      expect(observationCalls.at(-1)?.[1]).toMatchObject({
        observationAfter: null,
        loadObservation: true,
        loadEvidenceCandidate: false,
        loadEvidenceAcceptance: false,
        loadWaiver: false,
      });
    });
  });

  it("refetches overflow command choices after an authoritative mutation refresh", async () => {
    let optionReads = 0;
    const overflowRunState = support.operatorRunState({
      commandOptionsOverflow: true,
      commandOptionSummary: {
        observation: 21,
        evidenceCandidate: 1,
        evidenceAcceptance: 1,
        waiver: 1,
      },
      commandAffordances: [support.enabledCommandAffordance("record_execution_observation")],
    });
    const network = vi.fn(async (request, variables): Promise<GraphQLResponse> => {
      if (request.name === "OperatorWorkflowRouteQuery") {
        return support.workflowConnectionResponse([support.operatorWorkflowItem()], variables);
      }
      if (request.name === "OperatorRunStateQuery") {
        return { data: { operatorRunState: overflowRunState } };
      }
      if (request.name === "OperatorRunCommandOptionPageQuery") {
        optionReads += 1;
        const secondPage = variables.observationAfter === "option_cursor_1";
        const label =
          optionReads > 2
            ? "Refreshed overflow choice"
            : secondPage
              ? "Second-page overflow choice"
              : "Original overflow choice";
        const cursor = secondPage ? "option_cursor_2" : "option_cursor_1";
        return {
          data: {
            observation: {
              edges: [
                {
                  cursor,
                  node: {
                    observation: support.observationCommandOption({ label }),
                    evidenceCandidate: null,
                    evidenceAcceptance: null,
                    waiver: null,
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
      if (request.name === "OperatorRecordExecutionObservationMutation") {
        return {
          data: {
            recordExecutionObservation: {
              command: "record_execution_observation",
              operationId: "operation_observation_refresh",
              affectedIds: [],
              observation: { id: "observation_refresh", normalizedStatus: "succeeded" },
              run: { id: "run_1", executionState: "completed", verificationState: "pending" },
            },
          },
        };
      }
      throw new Error(`Unexpected Relay request in operator route test: ${request.name}`);
    });

    support.renderWithRelay(<OperatorRoute />, network);

    expect(
      await screen.findByRole("option", { name: "Original overflow choice" }),
    ).toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: "Next observation choices" }));
    expect(
      await screen.findByRole("option", { name: "Second-page overflow choice" }),
    ).toBeInTheDocument();
    fireEvent.change(screen.getByLabelText("Observation rationale"), {
      target: { value: "Refresh the authoritative overflow options." },
    });
    fireEvent.click(screen.getByRole("button", { name: "Record execution observation" }));

    expect(
      await screen.findByRole("option", { name: "Refreshed overflow choice" }),
    ).toBeInTheDocument();
    expect(optionReads).toBe(3);
    expect(support.lastVariablesFor(network, "OperatorRunCommandOptionPageQuery")).toMatchObject({
      observationAfter: null,
    });
  });

  it("validates locally derived packet readiness before exposing backend commands", async () => {
    const network = vi.fn(async (request, variables): Promise<GraphQLResponse> => {
      if (request.name === "OperatorWorkflowRouteQuery") {
        return support.workflowConnectionResponse([support.operatorWorkflowItem()], variables);
      }

      if (request.name === "OperatorRunStateQuery") {
        return { data: { operatorRunState: support.operatorRunState() } };
      }

      if (request.name === "OperatorPacketReadinessQuery") {
        return { data: { operatorPacketReadiness: support.operatorPacketReadiness() } };
      }

      throw new Error(`Unexpected Relay request in operator route test: ${request.name}`);
    });

    support.renderWithRelay(<OperatorRoute />, network);

    expect(await screen.findByText("Prepare packet context")).toBeInTheDocument();
    expect(screen.getByRole("region", { name: "Packet Readiness" })).toHaveTextContent("Blocked");
    expect(screen.queryByRole("button", { name: "Execute verification" })).not.toBeInTheDocument();
    expect(
      network.mock.calls.some(([request]) => request.name === "OperatorPacketReadinessQuery"),
    ).toBe(false);
    fireEvent.click(screen.getByRole("button", { name: "Validate readiness" }));

    await waitFor(() => {
      const readinessCall = network.mock.calls.find(
        ([request]) => request.name === "OperatorPacketReadinessQuery",
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
          verificationCheckIds: ["check_1"],
        },
      });
    });
    await waitFor(() => {
      expect(screen.getByRole("region", { name: "Packet Readiness" })).toHaveTextContent(
        "Backend readiness",
      );
      expect(screen.getByRole("region", { name: "Packet Readiness" })).toHaveTextContent(
        "Create work packet",
      );
    });
    expect(screen.queryByRole("button", { name: "Execute verification" })).not.toBeInTheDocument();
  });

  it("submits manual intake once and refreshes the current inbox", async () => {
    const mutationResponse = support.deferredGraphQLResponse();
    let workflowReads = 0;
    const network = vi.fn(async (request, variables): Promise<GraphQLResponse> => {
      if (request.name === "OperatorWorkflowRouteQuery") {
        workflowReads += 1;
        return support.workflowConnectionResponse(
          workflowReads === 1
            ? []
            : [
                support.operatorWorkflowItem({
                  id: "operator_workflow_item_new",
                  normalizedEventId: "evt_new",
                }),
              ],
          variables,
        );
      }

      if (request.name === "OperatorSubmitManualIntakeMutation") {
        return mutationResponse.promise;
      }

      if (request.name === "OperatorRunStateQuery") {
        return { data: { operatorRunState: support.operatorRunState() } };
      }

      throw new Error(`Unexpected Relay request in operator route test: ${request.name}`);
    });

    support.renderWithRelay(<OperatorRoute />, network);

    const body = await screen.findByLabelText("Manual intake");
    fireEvent.change(body, { target: { value: "Investigate the failed deployment" } });
    fireEvent.click(screen.getByRole("button", { name: "Submit intake" }));
    fireEvent.click(screen.getByRole("button", { name: "Submitting intake" }));

    expect(screen.getByRole("button", { name: "Submitting intake" })).toBeDisabled();
    await waitFor(() =>
      expect(
        network.mock.calls.filter(
          ([request]) => request.name === "OperatorSubmitManualIntakeMutation",
        ),
      ).toHaveLength(1),
    );
    expect(
      network.mock.calls.find(
        ([request]) => request.name === "OperatorSubmitManualIntakeMutation",
      )?.[1],
    ).toMatchObject({
      input: {
        body: "Investigate the failed deployment",
        replayIdentity: expect.stringMatching(/^operator:/),
        sourceIdentity: "manual:operator-console",
      },
    });

    await act(async () => {
      mutationResponse.resolve({
        data: {
          submitManualIntake: {
            command: "submit_manual_intake",
            operationId: "operation_intake_1",
            affectedIds: [{ type: "normalized_intake_event", id: "evt_new" }],
            normalizedEventId: "evt_new",
            proposedChangeIds: ["change_1"],
          },
        },
      });
    });

    await waitFor(() => expect(workflowReads).toBe(2));
    expect(await screen.findByRole("button", { name: /evt_new/i })).toBeInTheDocument();
  });

  it("leaves a linked run, returns to the first inbox page, and selects a newly submitted intake", async () => {
    let submitted = false;
    const firstItem = support.operatorWorkflowItem();
    const secondItem = support.operatorWorkflowItem({
      id: "operator_workflow_item_2",
      normalizedEventId: "evt_2",
      typedId: { type: "normalized_intake_event", id: "evt_2" },
    });
    const newItem = support.operatorWorkflowItem({
      id: "operator_workflow_item_new",
      normalizedEventId: "evt_new",
      typedId: { type: "normalized_intake_event", id: "evt_new" },
    });
    const network = vi.fn(async (request, variables): Promise<GraphQLResponse> => {
      if (request.name === "OperatorWorkflowRouteQuery") {
        if (variables.after === "cursor_1") {
          return support.workflowConnectionResponse([secondItem], variables);
        }

        return support.workflowConnectionResponse(
          submitted ? [newItem, firstItem] : [firstItem],
          variables,
          submitted ? {} : { hasNextPage: true, endCursor: "cursor_1" },
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
              proposedChangeIds: ["change_new"],
            },
          },
        };
      }

      if (request.name === "OperatorRunStateQuery") {
        return { data: { operatorRunState: support.operatorRunState() } };
      }

      throw new Error(`Unexpected Relay request in operator route test: ${request.name}`);
    });

    support.renderWithRelay(<OperatorRoute />, network, "/operator?runId=run_linked");
    await screen.findByRole("button", { name: /evt_1/i });
    fireEvent.click(screen.getByRole("button", { name: "Next" }));
    await screen.findByRole("button", { name: /evt_2/i });

    fireEvent.change(screen.getByLabelText("Manual intake"), {
      target: { value: "Investigate the new deployment failure" },
    });
    fireEvent.click(screen.getByRole("button", { name: "Submit intake" }));

    const newRow = await screen.findByRole("button", { name: /evt_new/i });
    await waitFor(() => expect(newRow).toHaveAttribute("aria-current", "true"));
    expect(support.lastVariablesFor(network, "OperatorWorkflowRouteQuery")).toEqual({
      first: 50,
      after: null,
    });
    expect(screen.getByRole("button", { name: "Previous" })).toBeDisabled();
  });

  it("creates a packet from the selected enabled affordance defaults", async () => {
    let readinessReads = 0;
    let packetCreated = false;
    const network = vi.fn(async (request, variables): Promise<GraphQLResponse> => {
      if (request.name === "OperatorWorkflowRouteQuery") {
        return support.workflowConnectionResponse(
          [
            packetCreated
              ? support.operatorWorkflowItem({
                  status: "packet_created",
                  allowedNextActions: [],
                  commandAffordances: [],
                  graphLinks: [
                    ...support.operatorWorkflowItem().graphLinks,
                    {
                      type: "work_packet",
                      id: "packet_1",
                      graphItemId: null,
                      title: "Run console verification",
                      state: "ready",
                    },
                  ],
                })
              : support.operatorWorkflowItem(),
          ],
          variables,
        );
      }
      if (request.name === "OperatorRunStateQuery")
        return { data: { operatorRunState: support.operatorRunState() } };
      if (request.name === "OperatorPacketReadinessQuery") {
        readinessReads += 1;
        return {
          data: {
            operatorPacketReadiness: support.operatorPacketReadiness(),
          },
        };
      }
      if (request.name === "OperatorCreateWorkPacketMutation") {
        packetCreated = true;
        return {
          data: {
            createWorkPacket: {
              command: "create_work_packet",
              operationId: "operation_packet_1",
              affectedIds: [],
              packet: {
                id: "packet_1",
                currentVersionId: "version_1",
                title: "Run console verification",
                state: "draft",
              },
              packetVersion: { id: "version_1", versionNumber: 1, lifecycleState: "draft" },
            },
          },
        };
      }
      throw new Error(`Unexpected Relay request in operator route test: ${request.name}`);
    });

    support.renderWithRelay(<OperatorRoute />, network);
    await screen.findByText("Prepare packet context");
    expect(screen.queryByRole("button", { name: "Create work packet" })).not.toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: "Validate readiness" }));
    fireEvent.click(await screen.findByRole("button", { name: "Create work packet" }));

    await waitFor(() =>
      expect(
        network.mock.calls.find(
          ([request]) => request.name === "OperatorCreateWorkPacketMutation",
        )?.[1],
      ).toMatchObject({
        input: {
          title: "Run console verification",
          objective: "Run console verification",
          sourceGraphItemIds: ["graph_1"],
          verificationCheckIds: ["check_1"],
        },
      }),
    );
    await waitFor(() => {
      expect(screen.getByRole("region", { name: "Packet Readiness" })).toHaveTextContent(
        "No packet readiness selected",
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
        return support.workflowConnectionResponse([support.operatorWorkflowItem()], variables);
      }
      if (request.name === "OperatorRunStateQuery") {
        runReads += 1;
        return {
          data: {
            operatorRunState:
              runReads === 1
                ? support.operatorRunState()
                : support.operatorRunState({
                    status: "verified",
                    allowedNextActions: [],
                    commandAffordances: [],
                  }),
          },
        };
      }
      if (request.name === "OperatorAcceptEvidenceMutation")
        return {
          data: {
            acceptEvidence: {
              command: "accept_evidence",
              operationId: "operation_accept_1",
              affectedIds: [],
              evidenceCandidate: { id: "candidate_1", candidateState: "accepted" },
              evidenceItem: { id: "evidence_1", state: "accepted" },
              verificationResult: { id: "result_1", result: "passed" },
              run: { id: "run_1", executionState: "completed", verificationState: "passed" },
            },
          },
        };
      throw new Error(`Unexpected Relay request in operator route test: ${request.name}`);
    });

    support.renderWithRelay(<OperatorRoute />, network);
    fireEvent.change(await screen.findByLabelText("Evidence title"), {
      target: { value: "Deployment verified" },
    });
    fireEvent.change(screen.getByLabelText("Evidence body"), {
      target: { value: "The deployment completed successfully." },
    });
    fireEvent.click(screen.getByRole("button", { name: "Accept evidence" }));

    await waitFor(() =>
      expect(
        network.mock.calls.find(
          ([request]) => request.name === "OperatorAcceptEvidenceMutation",
        )?.[1],
      ).toMatchObject({
        input: {
          evidenceCandidateId: "candidate_1",
          title: "Deployment verified",
          body: "The deployment completed successfully.",
          result: "passed",
          acceptancePolicyBasis: "owner_acceptance",
        },
      }),
    );
    await waitFor(() => expect(runReads).toBe(2));
    await waitFor(() => expect(workflowReads).toBe(2));
    expect(screen.getByRole("region", { name: "Run State" })).toHaveTextContent("Verified");
    expect(screen.getByRole("button", { name: /evt_1/i })).toHaveAttribute("aria-current", "true");
  });

  it("accepts the operator-selected candidate targeted by the enabled affordance", async () => {
    const base = support.operatorRunState();
    const secondCandidate = {
      ...base.evidenceCandidates[0],
      id: "candidate_2",
      verificationCheckId: "check_2",
      executionObservationId: "observation_2",
    };
    const runState = {
      ...base,
      evidenceCandidates: [...base.evidenceCandidates, secondCandidate],
      commandOptions: {
        ...base.commandOptions,
        evidenceAcceptance: [
          ...base.commandOptions.evidenceAcceptance,
          {
            key: "candidate_2",
            label: secondCandidate.claim,
            evidenceCandidateId: "candidate_2",
            result: "passed",
            acceptancePolicyBasis: "owner_acceptance",
          },
        ],
      },
      commandAffordances: [
        support.enabledCommandAffordance(
          "accept_evidence",
          [],
          [
            { type: "work_run", id: "run_1" },
            { type: "evidence_candidate", id: "candidate_1" },
            { type: "evidence_candidate", id: "candidate_2" },
          ],
        ),
      ],
    };
    const network = support.operatorCommandNetwork(runState);

    support.renderWithRelay(<OperatorRoute />, network);
    fireEvent.change(await screen.findByLabelText("Suggested evidence"), {
      target: { value: "candidate_2" },
    });
    fireEvent.change(screen.getByLabelText("Evidence title"), {
      target: { value: "Second candidate" },
    });
    fireEvent.change(screen.getByLabelText("Evidence body"), {
      target: { value: "Accept the affordance-scoped candidate." },
    });
    fireEvent.change(screen.getByLabelText("Evidence result"), {
      target: { value: "failed" },
    });
    fireEvent.click(screen.getByRole("button", { name: "Accept evidence" }));

    await waitFor(() =>
      expect(support.lastVariablesFor(network, "OperatorAcceptEvidenceMutation")).toMatchObject({
        input: { evidenceCandidateId: "candidate_2", result: "failed" },
      }),
    );
  });

  it("falls back to a current candidate after an acceptance refresh", async () => {
    const base = support.operatorRunState();
    const secondCandidate = {
      ...base.evidenceCandidates[0],
      id: "candidate_2",
      verificationCheckId: "check_2",
      executionObservationId: "observation_2",
    };
    const initialState = {
      ...base,
      evidenceCandidates: [...base.evidenceCandidates, secondCandidate],
      commandOptions: {
        ...base.commandOptions,
        evidenceAcceptance: [
          ...base.commandOptions.evidenceAcceptance,
          {
            key: "candidate_2",
            label: secondCandidate.claim,
            evidenceCandidateId: "candidate_2",
            result: "passed",
            acceptancePolicyBasis: "owner_acceptance",
          },
        ],
      },
      commandAffordances: [
        support.enabledCommandAffordance(
          "accept_evidence",
          [],
          [
            { type: "work_run", id: "run_1" },
            { type: "evidence_candidate", id: "candidate_1" },
            { type: "evidence_candidate", id: "candidate_2" },
          ],
        ),
      ],
    };
    const refreshedState = {
      ...base,
      evidenceCandidates: [base.evidenceCandidates[0]],
      commandAffordances: [
        support.enabledCommandAffordance(
          "accept_evidence",
          [],
          [
            { type: "work_run", id: "run_1" },
            { type: "evidence_candidate", id: "candidate_1" },
          ],
        ),
      ],
    };
    let runReads = 0;
    const network = vi.fn(async (request, variables): Promise<GraphQLResponse> => {
      if (request.name === "OperatorWorkflowRouteQuery") {
        return support.workflowConnectionResponse([support.operatorWorkflowItem()], variables);
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
              run: { id: "run_1", executionState: "completed", verificationState: "pending" },
            },
          },
        };
      }
      throw new Error(`Unexpected Relay request in operator route test: ${request.name}`);
    });

    support.renderWithRelay(<OperatorRoute />, network);
    fireEvent.change(await screen.findByLabelText("Suggested evidence"), {
      target: { value: "candidate_2" },
    });
    fireEvent.change(screen.getByLabelText("Evidence title"), {
      target: { value: "Candidate refresh" },
    });
    fireEvent.change(screen.getByLabelText("Evidence body"), {
      target: { value: "Use only the current affordance target." },
    });
    fireEvent.click(screen.getByRole("button", { name: "Accept evidence" }));

    await waitFor(() => expect(runReads).toBe(2));
    await waitFor(() =>
      expect(screen.getByLabelText("Suggested evidence")).toHaveValue("candidate_1"),
    );
    fireEvent.click(screen.getByRole("button", { name: "Accept evidence" }));

    await waitFor(() => {
      const submissions = network.mock.calls.filter(
        ([request]) => request.name === "OperatorAcceptEvidenceMutation",
      );
      expect(submissions).toHaveLength(2);
      expect(submissions[1]?.[1]).toMatchObject({
        input: { evidenceCandidateId: "candidate_1" },
      });
    });
  });

  it("creates evidence from the operator-selected matching observation and check", async () => {
    const base = support.operatorRunState();
    const secondObservation = {
      ...base.observations[0],
      id: "observation_2",
      verificationCheckId: "check_2",
    };
    const runState = {
      ...base,
      observations: [...base.observations, secondObservation],
      commandOptions: {
        ...base.commandOptions,
        evidenceCandidate: [
          ...base.commandOptions.evidenceCandidate,
          support.evidenceCandidateCommandOption({
            key: "observation_2",
            label: "Second observation",
            verificationCheckId: "check_2",
            executionObservationId: "observation_2",
          }),
        ],
      },
      missingEvidence: [
        ...base.missingEvidence,
        { verificationCheckId: "check_2", reason: "missing" },
      ],
      commandAffordances: [
        support.enabledCommandAffordance("create_evidence_candidate", [
          { field: "work_run_id", value: "run_1", values: [] },
          { field: "verification_check_id", value: null, values: ["check_1", "check_2"] },
          {
            field: "execution_observation_id",
            value: null,
            values: ["observation_1", "observation_2"],
          },
        ]),
      ],
    };
    const network = support.operatorCommandNetwork(runState);

    support.renderWithRelay(<OperatorRoute />, network);
    fireEvent.change(await screen.findByLabelText("Evidence observation"), {
      target: { value: "observation_2" },
    });
    fireEvent.change(screen.getByLabelText("Evidence claim"), {
      target: { value: "The second check passed." },
    });
    fireEvent.click(screen.getByRole("button", { name: "Suggest evidence" }));

    await waitFor(() =>
      expect(
        support.lastVariablesFor(network, "OperatorCreateEvidenceCandidateMutation"),
      ).toMatchObject({
        input: {
          executionObservationId: "observation_2",
          verificationCheckId: "check_2",
        },
      }),
    );
  });

  it("waives the operator-selected required check", async () => {
    const base = support.operatorRunState();
    const secondCheck = {
      ...base.requiredChecks[0],
      id: "required_2",
      verificationCheckId: "check_2",
    };
    const runState = {
      ...base,
      requiredChecks: [...base.requiredChecks, secondCheck],
      commandOptions: {
        ...base.commandOptions,
        waiver: [
          ...base.commandOptions.waiver,
          {
            key: "required_2",
            label: "Second required check",
            runId: "run_1",
            runRequiredCheckId: "required_2",
            expectedExecutionState: "completed",
            expectedVerificationState: "pending",
            policyBasis: "security_exception",
          },
        ],
      },
      commandAffordances: [
        support.enabledCommandAffordance("waive_verification_check", [
          { field: "run_id", value: "run_1", values: [] },
          { field: "run_required_check_id", value: null, values: ["required_1", "required_2"] },
          { field: "expected_execution_state", value: "completed", values: [] },
          { field: "expected_verification_state", value: "pending", values: [] },
        ]),
      ],
    };
    const network = support.operatorCommandNetwork(runState);

    support.renderWithRelay(<OperatorRoute />, network);
    fireEvent.change(await screen.findByLabelText("Required check"), {
      target: { value: "required_2" },
    });
    expect(screen.getByLabelText("Policy basis")).toHaveValue("security_exception");
    fireEvent.change(screen.getByLabelText("Waiver reason"), {
      target: { value: "Approved exception for the second check." },
    });
    fireEvent.click(screen.getByRole("button", { name: "Waive verification check" }));

    await waitFor(() =>
      expect(
        support.lastVariablesFor(network, "OperatorWaiveVerificationCheckMutation"),
      ).toMatchObject({
        input: { runRequiredCheckId: "required_2", policyBasis: "security_exception" },
      }),
    );
  });

  it("renders remaining run forms only from exact enabled affordances", async () => {
    const enabled = (
      identity: string,
      inputDefaults: support.CommandAffordancePayload["inputDefaults"] = [],
    ) => ({
      identity,
      state: "enabled",
      reasonCodes: [],
      blockerReasons: [],
      safeExplanation: `${identity} is available.`,
      requiredFields: [],
      inputDefaults,
      targetIds: [],
      traceLinks: [],
      decisionLinks: [],
    });
    const workflowItem = support.operatorWorkflowItem({
      commandAffordances: [
        enabled("start_work_run", [
          { field: "packet_version_id", value: "version_1", values: [] },
          { field: "authority_posture", value: "human_supervised", values: [] },
        ]),
      ],
      graphLinks: [
        {
          type: "work_packet_version",
          id: "version_1",
          graphItemId: null,
          title: "Version 1",
          state: "ready",
        },
        { type: "work_run", id: "run_1", graphItemId: null, title: "Run 1", state: "running" },
      ],
    });
    const runState = support.operatorRunState({
      commandAffordances: [
        enabled("record_execution_observation", [{ field: "run_id", value: "run_1", values: [] }]),
        enabled("create_evidence_candidate", [
          { field: "work_run_id", value: "run_1", values: [] },
          { field: "verification_check_id", value: null, values: ["check_1"] },
          { field: "execution_observation_id", value: null, values: ["observation_1"] },
        ]),
        enabled("waive_verification_check", [
          { field: "run_id", value: "run_1", values: [] },
          { field: "run_required_check_id", value: null, values: ["required_1"] },
        ]),
      ],
    });
    const network = support.createOperatorNetwork({ workflowItems: [workflowItem], runState });

    support.renderWithRelay(<OperatorRoute />, network);

    expect(
      await screen.findByRole("button", { name: "Record execution observation" }),
    ).toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "Start work run" })).not.toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Suggest evidence" })).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Waive verification check" })).toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "Accept evidence" })).not.toBeInTheDocument();
  });
});
