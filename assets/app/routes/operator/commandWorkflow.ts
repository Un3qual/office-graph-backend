import type { MutationParameters } from "relay-runtime";
import type {
  OperatorAcceptEvidenceMutation as AcceptEvidenceMutation,
  OperatorAcceptEvidenceMutation$variables as AcceptEvidenceVariables
} from "../../relay/__generated__/OperatorAcceptEvidenceMutation.graphql";
import type {
  OperatorApplyProposedChangesMutation as ApplyProposedChangesMutation,
  OperatorApplyProposedChangesMutation$variables as ApplyProposedChangesVariables
} from "../../relay/__generated__/OperatorApplyProposedChangesMutation.graphql";
import type {
  OperatorCreateEvidenceCandidateMutation as CreateEvidenceCandidateMutation,
  OperatorCreateEvidenceCandidateMutation$variables as CreateEvidenceCandidateVariables
} from "../../relay/__generated__/OperatorCreateEvidenceCandidateMutation.graphql";
import type {
  OperatorCreateWorkPacketMutation as CreateWorkPacketMutation,
  OperatorCreateWorkPacketMutation$variables as CreateWorkPacketVariables
} from "../../relay/__generated__/OperatorCreateWorkPacketMutation.graphql";
import type {
  OperatorRecordExecutionObservationMutation as RecordExecutionObservationMutation,
  OperatorRecordExecutionObservationMutation$variables as RecordExecutionObservationVariables
} from "../../relay/__generated__/OperatorRecordExecutionObservationMutation.graphql";
import type {
  OperatorStartWorkRunMutation as StartWorkRunMutation,
  OperatorStartWorkRunMutation$variables as StartWorkRunVariables
} from "../../relay/__generated__/OperatorStartWorkRunMutation.graphql";
import type {
  OperatorSubmitManualIntakeMutation as SubmitManualIntakeMutation,
  OperatorSubmitManualIntakeMutation$variables as SubmitManualIntakeVariables
} from "../../relay/__generated__/OperatorSubmitManualIntakeMutation.graphql";
import type {
  OperatorWaiveVerificationCheckMutation as WaiveVerificationCheckMutation,
  OperatorWaiveVerificationCheckMutation$variables as WaiveVerificationCheckVariables
} from "../../relay/__generated__/OperatorWaiveVerificationCheckMutation.graphql";
import {
  commandMutationSuccess,
  useCommandMutation,
  type CommandMutationConfig
} from "../../relay/commandMutation";
import {
  OperatorAcceptEvidenceMutation,
  OperatorApplyProposedChangesMutation,
  OperatorCreateEvidenceCandidateMutation,
  OperatorCreateWorkPacketMutation,
  OperatorRecordExecutionObservationMutation,
  OperatorStartWorkRunMutation,
  OperatorSubmitManualIntakeMutation,
  OperatorWaiveVerificationCheckMutation
} from "./commands";

type SubmitManualIntakeResult = {
  readonly normalizedEventId: string;
  readonly proposedChangeIds: readonly string[];
};

type ApplyProposedChangesResult = Pick<
  ApplyProposedChangesMutation["response"]["applyProposedChanges"],
  "reviewFinding" | "signal" | "task" | "verificationCheck"
>;

type CreateWorkPacketResult = Pick<
  CreateWorkPacketMutation["response"]["createWorkPacket"],
  "packet" | "packetVersion"
>;

type StartWorkRunResult = Pick<
  StartWorkRunMutation["response"]["startWorkRun"],
  "requiredChecks" | "run"
>;

type RecordExecutionObservationResult = Pick<
  RecordExecutionObservationMutation["response"]["recordExecutionObservation"],
  "observation" | "run"
>;

type CreateEvidenceCandidateResult = Pick<
  CreateEvidenceCandidateMutation["response"]["createEvidenceCandidate"],
  "evidenceCandidate"
>;

type AcceptEvidenceResult = Pick<
  AcceptEvidenceMutation["response"]["acceptEvidence"],
  "evidenceCandidate" | "evidenceItem" | "run" | "verificationResult"
>;

type WaiveVerificationCheckResult = Pick<
  WaiveVerificationCheckMutation["response"]["waiveVerificationCheck"],
  "requiredCheck" | "run" | "verificationResult"
>;

const submitManualIntakeConfig = {
  mutation: OperatorSubmitManualIntakeMutation,
  toVariables: (input: SubmitManualIntakeVariables["input"]) => ({ input }),
  mapSuccess(response) {
    const payload = response.submitManualIntake;
    return commandMutationSuccess(payload, {
      normalizedEventId: payload.normalizedEventId,
      proposedChangeIds: payload.proposedChangeIds
    });
  }
} satisfies CommandMutationConfig<
  SubmitManualIntakeMutation,
  SubmitManualIntakeVariables["input"],
  SubmitManualIntakeResult
>;

const applyProposedChangesConfig = {
  mutation: OperatorApplyProposedChangesMutation,
  toVariables: (input: ApplyProposedChangesVariables["input"]) => ({ input }),
  mapSuccess(response) {
    const payload = response.applyProposedChanges;
    return commandMutationSuccess(payload, {
      signal: payload.signal,
      task: payload.task,
      reviewFinding: payload.reviewFinding,
      verificationCheck: payload.verificationCheck
    });
  }
} satisfies CommandMutationConfig<
  ApplyProposedChangesMutation,
  ApplyProposedChangesVariables["input"],
  ApplyProposedChangesResult
>;

const createWorkPacketConfig = {
  mutation: OperatorCreateWorkPacketMutation,
  toVariables: (input: CreateWorkPacketVariables["input"]) => ({ input }),
  mapSuccess(response) {
    const payload = response.createWorkPacket;
    return commandMutationSuccess(payload, {
      packet: payload.packet,
      packetVersion: payload.packetVersion
    });
  }
} satisfies CommandMutationConfig<
  CreateWorkPacketMutation,
  CreateWorkPacketVariables["input"],
  CreateWorkPacketResult
>;

const startWorkRunConfig = {
  mutation: OperatorStartWorkRunMutation,
  toVariables: (input: StartWorkRunVariables["input"]) => ({ input }),
  mapSuccess(response) {
    const payload = response.startWorkRun;
    return commandMutationSuccess(payload, {
      requiredChecks: payload.requiredChecks,
      run: payload.run
    });
  }
} satisfies CommandMutationConfig<
  StartWorkRunMutation,
  StartWorkRunVariables["input"],
  StartWorkRunResult
>;

const recordExecutionObservationConfig = {
  mutation: OperatorRecordExecutionObservationMutation,
  toVariables: (input: RecordExecutionObservationVariables["input"]) => ({ input }),
  mapSuccess(response) {
    const payload = response.recordExecutionObservation;
    return commandMutationSuccess(payload, {
      observation: payload.observation,
      run: payload.run
    });
  }
} satisfies CommandMutationConfig<
  RecordExecutionObservationMutation,
  RecordExecutionObservationVariables["input"],
  RecordExecutionObservationResult
>;

const createEvidenceCandidateConfig = {
  mutation: OperatorCreateEvidenceCandidateMutation,
  toVariables: (input: CreateEvidenceCandidateVariables["input"]) => ({ input }),
  mapSuccess(response) {
    const payload = response.createEvidenceCandidate;
    return commandMutationSuccess(payload, {
      evidenceCandidate: payload.evidenceCandidate
    });
  }
} satisfies CommandMutationConfig<
  CreateEvidenceCandidateMutation,
  CreateEvidenceCandidateVariables["input"],
  CreateEvidenceCandidateResult
>;

const acceptEvidenceConfig = {
  mutation: OperatorAcceptEvidenceMutation,
  toVariables: (input: AcceptEvidenceVariables["input"]) => ({ input }),
  mapSuccess(response) {
    const payload = response.acceptEvidence;
    return commandMutationSuccess(payload, {
      evidenceCandidate: payload.evidenceCandidate,
      evidenceItem: payload.evidenceItem,
      verificationResult: payload.verificationResult,
      run: payload.run
    });
  }
} satisfies CommandMutationConfig<
  AcceptEvidenceMutation,
  AcceptEvidenceVariables["input"],
  AcceptEvidenceResult
>;

const waiveVerificationCheckConfig = {
  mutation: OperatorWaiveVerificationCheckMutation,
  toVariables: (input: WaiveVerificationCheckVariables["input"]) => ({ input }),
  mapSuccess(response) {
    const payload = response.waiveVerificationCheck;
    return commandMutationSuccess(payload, {
      verificationResult: payload.verificationResult,
      requiredCheck: payload.requiredCheck,
      run: payload.run
    });
  }
} satisfies CommandMutationConfig<
  WaiveVerificationCheckMutation,
  WaiveVerificationCheckVariables["input"],
  WaiveVerificationCheckResult
>;

export function useOperatorCommand<
  TMutation extends MutationParameters,
  TInput,
  TResult
>(config: CommandMutationConfig<TMutation, TInput, TResult>, onAuthoritativeChange?: () => void) {
  return useCommandMutation(config, onAuthoritativeChange);
}

export function useSubmitManualIntakeCommand(onAuthoritativeChange?: () => void) {
  return useOperatorCommand<
    SubmitManualIntakeMutation,
    SubmitManualIntakeVariables["input"],
    SubmitManualIntakeResult
  >(submitManualIntakeConfig, onAuthoritativeChange);
}

export function useApplyProposedChangesCommand(onAuthoritativeChange?: () => void) {
  return useOperatorCommand<
    ApplyProposedChangesMutation,
    ApplyProposedChangesVariables["input"],
    ApplyProposedChangesResult
  >(applyProposedChangesConfig, onAuthoritativeChange);
}

export function useCreateWorkPacketCommand(onAuthoritativeChange?: () => void) {
  return useOperatorCommand<
    CreateWorkPacketMutation,
    CreateWorkPacketVariables["input"],
    CreateWorkPacketResult
  >(createWorkPacketConfig, onAuthoritativeChange);
}

export function useStartWorkRunCommand(onAuthoritativeChange?: () => void) {
  return useOperatorCommand<
    StartWorkRunMutation,
    StartWorkRunVariables["input"],
    StartWorkRunResult
  >(startWorkRunConfig, onAuthoritativeChange);
}

export function useRecordExecutionObservationCommand(onAuthoritativeChange?: () => void) {
  return useOperatorCommand<
    RecordExecutionObservationMutation,
    RecordExecutionObservationVariables["input"],
    RecordExecutionObservationResult
  >(recordExecutionObservationConfig, onAuthoritativeChange);
}

export function useCreateEvidenceCandidateCommand(onAuthoritativeChange?: () => void) {
  return useOperatorCommand<
    CreateEvidenceCandidateMutation,
    CreateEvidenceCandidateVariables["input"],
    CreateEvidenceCandidateResult
  >(createEvidenceCandidateConfig, onAuthoritativeChange);
}

export function useAcceptEvidenceCommand(onAuthoritativeChange?: () => void) {
  return useOperatorCommand<
    AcceptEvidenceMutation,
    AcceptEvidenceVariables["input"],
    AcceptEvidenceResult
  >(acceptEvidenceConfig, onAuthoritativeChange);
}

export function useWaiveVerificationCheckCommand(onAuthoritativeChange?: () => void) {
  return useOperatorCommand<
    WaiveVerificationCheckMutation,
    WaiveVerificationCheckVariables["input"],
    WaiveVerificationCheckResult
  >(waiveVerificationCheckConfig, onAuthoritativeChange);
}
