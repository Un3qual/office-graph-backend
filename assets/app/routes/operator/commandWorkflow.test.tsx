import type { ReactNode } from "react";
import { act, renderHook, waitFor } from "@testing-library/react";
import { RelayEnvironmentProvider } from "react-relay";
import {
  Environment,
  Network,
  RecordSource,
  Store,
  type GraphQLResponse,
  type Variables,
} from "relay-runtime";
import { describe, expect, it, vi } from "vitest";
import type { CommandMutationController } from "../../relay/commandMutation";
import { GraphQLResponseError } from "../../relay/fetchGraphQL";
import {
  useAcceptEvidenceCommand,
  useApplyProposedChangesCommand,
  useCreateEvidenceCandidateCommand,
  useCreateWorkPacketCommand,
  useRecordExecutionObservationCommand,
  useSubmitManualIntakeCommand,
  useWaiveVerificationCheckCommand,
} from "./commandWorkflow";

describe("operator command workflow", () => {
  it("moves from idle through pending to the typed success result", async () => {
    const request = deferredRequest();
    const environment = relayEnvironment(request.fetch);
    const { result } = renderHook(() => useSubmitManualIntakeCommand(), {
      wrapper: relayWrapper(environment),
    });

    expect(result.current.state).toEqual({ status: "idle" });

    act(() => {
      result.current.submit({
        idempotencyKey: "intake-1",
        sourceIdentity: "manual:test",
        replayIdentity: "paste:test",
        body: "Create a durable intake event.",
      });
    });

    expect(result.current.state).toEqual({ status: "pending" });
    expect(request.name).toBe("OperatorSubmitManualIntakeMutation");
    expect(request.variables).toEqual({
      input: {
        idempotencyKey: "intake-1",
        sourceIdentity: "manual:test",
        replayIdentity: "paste:test",
        body: "Create a durable intake event.",
      },
    });

    act(() => {
      request.resolve({
        data: {
          submitManualIntake: {
            command: "submit_manual_intake",
            operationId: "operation-1",
            affectedIds: [{ type: "normalized_intake_event", id: "event-1" }],
            normalizedEventId: "event-1",
            proposedChangeIds: ["proposal-1"],
          },
        },
      });
    });

    await waitFor(() => expect(result.current.state.status).toBe("success"));

    expect(result.current.state).toEqual({
      status: "success",
      operationId: "operation-1",
      affectedIds: [{ type: "normalized_intake_event", id: "event-1" }],
      result: {
        normalizedEventId: "event-1",
        proposedChangeIds: ["proposal-1"],
      },
    });

    act(() => result.current.reset());
    expect(result.current.state).toEqual({ status: "idle" });
  });

  it("maps proposed-change application results", async () => {
    const result = {
      signal: { id: "signal-1" },
      task: { id: "task-1" },
      reviewFinding: { id: "finding-1" },
      verificationCheck: { id: "check-1", graphItemId: "graph-item-1" },
    };

    await expectCommandSuccess(
      useApplyProposedChangesCommand,
      {
        idempotencyKey: "apply-1",
        normalizedEventId: "event-1",
        proposedChangeIds: ["proposal-1"],
      },
      "OperatorApplyProposedChangesMutation",
      "applyProposedChanges",
      result,
      result,
    );
  });

  it("maps work-packet creation results", async () => {
    const result = {
      packet: {
        id: "packet-1",
        currentVersionId: "version-1",
        title: "Packet",
        state: "ready",
      },
      packetVersion: { id: "version-1", versionNumber: 1, lifecycleState: "ready" },
    };

    await expectCommandSuccess(
      useCreateWorkPacketCommand,
      {
        autonomyPosture: "human_supervised",
        contextSummary: "Context",
        idempotencyKey: "packet-1",
        objective: "Objective",
        requirements: "Requirements",
        sourceGraphItemIds: ["graph-item-1"],
        successCriteria: "Success",
        title: "Packet",
        verificationCheckIds: ["check-1"],
      },
      "OperatorCreateWorkPacketMutation",
      "createWorkPacket",
      result,
      result,
    );
  });

  it("maps execution-observation results", async () => {
    const result = {
      observation: { id: "observation-1", normalizedStatus: "passed" },
      run: { id: "run-1", executionState: "completed", verificationState: "pending" },
    };

    await expectCommandSuccess(
      useRecordExecutionObservationCommand,
      {
        freshnessState: "current",
        idempotencyKey: "observation-command-1",
        normalizedStatus: "passed",
        observationIdempotencyKey: "observation-1",
        observationRationale: "Observed success",
        observationSourceIdentity: "operator:test",
        observationSourceKind: "manual",
        observedStatus: "passed",
        runId: "run-1",
        sourceGraphItemId: "graph-item-1",
        trustBasis: "operator_attested",
        verificationCheckId: "check-1",
      },
      "OperatorRecordExecutionObservationMutation",
      "recordExecutionObservation",
      result,
      result,
    );
  });

  it("maps evidence-candidate results", async () => {
    const result = { evidenceCandidate: { id: "candidate-1", candidateState: "proposed" } };

    await expectCommandSuccess(
      useCreateEvidenceCandidateCommand,
      {
        claim: "The check passed.",
        executionObservationId: "observation-1",
        freshnessState: "current",
        idempotencyKey: "candidate-1",
        sensitivity: "internal",
        sourceIdentity: "operator:test",
        sourceKind: "manual",
        trustBasis: "operator_attested",
        verificationCheckId: "check-1",
        workRunId: "run-1",
      },
      "OperatorCreateEvidenceCandidateMutation",
      "createEvidenceCandidate",
      result,
      result,
    );
  });

  it("maps evidence acceptance results including a nullable run", async () => {
    const result = {
      evidenceCandidate: { id: "candidate-1", candidateState: "accepted" },
      evidenceItem: { id: "evidence-1", state: "accepted" },
      verificationResult: { id: "result-1", result: "passed" },
      run: null,
    };

    await expectCommandSuccess(
      useAcceptEvidenceCommand,
      {
        acceptancePolicyBasis: "operator_review",
        body: "Evidence body",
        evidenceCandidateId: "candidate-1",
        idempotencyKey: "accept-1",
        result: "passed",
        title: "Accepted evidence",
      },
      "OperatorAcceptEvidenceMutation",
      "acceptEvidence",
      result,
      result,
    );
  });

  it("maps verification-waiver results", async () => {
    const result = {
      verificationResult: { id: "result-1", result: "waived" },
      requiredCheck: { id: "required-1", verificationCheckId: "check-1", state: "waived" },
      run: { id: "run-1", executionState: "completed", verificationState: "passed" },
    };

    await expectCommandSuccess(
      useWaiveVerificationCheckCommand,
      {
        expectedExecutionState: "completed",
        expectedVerificationState: "pending",
        idempotencyKey: "waive-1",
        policyBasis: "approved_exception",
        reason: "Approved exception",
        runId: "run-1",
        runRequiredCheckId: "required-1",
      },
      "OperatorWaiveVerificationCheckMutation",
      "waiveVerificationCheck",
      result,
      result,
    );
  });

  it("refreshes authoritative state when an evidence result slot was completed concurrently", async () => {
    const request = deferredRequest();
    const environment = relayEnvironment(request.fetch);
    const authoritativeRefresh = vi.fn();

    const { result } = renderHook(() => useAcceptEvidenceCommand(authoritativeRefresh), {
      wrapper: relayWrapper(environment),
    });

    act(() => {
      result.current.submit({
        acceptancePolicyBasis: "operator_review",
        body: "Evidence body",
        evidenceCandidateId: "candidate-1",
        idempotencyKey: "accept-conflict",
        result: "passed",
        title: "Accepted evidence",
      });
    });

    act(() => {
      const source = {
        errors: [
          {
            message: "The verification result slot was already completed.",
            extensions: { code: "verification_result_slot_conflict" },
          },
        ],
      };

      request.reject(
        new GraphQLResponseError(
          source.errors[0].message,
          source,
          200,
          "OperatorAcceptEvidenceMutation",
        ),
      );
    });

    await waitFor(() => expect(result.current.state.status).toBe("conflict"));
    expect(authoritativeRefresh).toHaveBeenCalledOnce();
  });
});

async function expectCommandSuccess<TInput, TResult>(
  useCommand: () => CommandMutationController<TInput, TResult>,
  input: TInput,
  mutationName: string,
  responseField: string,
  responseResult: Record<string, unknown>,
  expectedResult: TResult,
) {
  const request = deferredRequest();
  const environment = relayEnvironment(request.fetch);
  const { result } = renderHook(() => useCommand(), {
    wrapper: relayWrapper(environment),
  });

  act(() => {
    result.current.submit(input);
  });

  expect(request.name).toBe(mutationName);
  expect(request.variables).toEqual({ input });

  act(() => {
    request.resolve({
      data: {
        [responseField]: {
          command: "test_command",
          operationId: "operation-1",
          affectedIds: [{ type: "test_resource", id: "resource-1" }],
          ...responseResult,
        },
      },
    });
  });

  await waitFor(() => expect(result.current.state.status).toBe("success"));
  expect(result.current.state).toEqual({
    status: "success",
    operationId: "operation-1",
    affectedIds: [{ type: "test_resource", id: "resource-1" }],
    result: expectedResult,
  });
}

function deferredRequest() {
  let resolveResponse: (response: GraphQLResponse) => void = () => undefined;
  let rejectResponse: (error: Error) => void = () => undefined;
  let name: string | null = null;
  let variables: Variables | null = null;

  return {
    fetch(request: { name: string }, nextVariables: Variables) {
      name = request.name;
      variables = nextVariables;
      return new Promise<GraphQLResponse>((resolve, reject) => {
        resolveResponse = resolve;
        rejectResponse = reject;
      });
    },
    get name() {
      return name;
    },
    get variables() {
      return variables;
    },
    resolve(response: GraphQLResponse) {
      resolveResponse(response);
    },
    reject(error: Error) {
      rejectResponse(error);
    },
  };
}

function relayEnvironment(fetch: ReturnType<typeof deferredRequest>["fetch"]) {
  return new Environment({
    getDataID: () => null,
    network: Network.create(fetch),
    store: new Store(new RecordSource()),
  });
}

function relayWrapper(environment: Environment) {
  return function Wrapper({ children }: { children: ReactNode }) {
    return (
      <RelayEnvironmentProvider environment={environment}>{children}</RelayEnvironmentProvider>
    );
  };
}
