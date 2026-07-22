import type { MutationParameters } from "relay-runtime";
import type {
  OperatorAcceptEvidenceMutation as AcceptEvidenceMutation,
  OperatorAcceptEvidenceMutation$variables as AcceptEvidenceVariables,
} from "../../relay/__generated__/OperatorAcceptEvidenceMutation.graphql";
import type {
  OperatorApplyProposedChangesMutation as ApplyProposedChangesMutation,
  OperatorApplyProposedChangesMutation$variables as ApplyProposedChangesVariables,
} from "../../relay/__generated__/OperatorApplyProposedChangesMutation.graphql";
import type {
  OperatorAppendConversationMessageMutation as AppendConversationMessageMutation,
  OperatorAppendConversationMessageMutation$variables as AppendConversationMessageVariables,
} from "../../relay/__generated__/OperatorAppendConversationMessageMutation.graphql";
import type {
  OperatorCancelAgentExecutionMutation as CancelAgentExecutionMutation,
  OperatorCancelAgentExecutionMutation$variables as CancelAgentExecutionVariables,
} from "../../relay/__generated__/OperatorCancelAgentExecutionMutation.graphql";
import type {
  OperatorCreateEvidenceCandidateMutation as CreateEvidenceCandidateMutation,
  OperatorCreateEvidenceCandidateMutation$variables as CreateEvidenceCandidateVariables,
} from "../../relay/__generated__/OperatorCreateEvidenceCandidateMutation.graphql";
import type {
  OperatorCreateWorkPacketMutation as CreateWorkPacketMutation,
  OperatorCreateWorkPacketMutation$variables as CreateWorkPacketVariables,
} from "../../relay/__generated__/OperatorCreateWorkPacketMutation.graphql";
import type {
  OperatorInvokeAgentMutation as InvokeAgentMutation,
  OperatorInvokeAgentMutation$variables as InvokeAgentVariables,
} from "../../relay/__generated__/OperatorInvokeAgentMutation.graphql";
import type {
  OperatorRecordExecutionObservationMutation as RecordExecutionObservationMutation,
  OperatorRecordExecutionObservationMutation$variables as RecordExecutionObservationVariables,
} from "../../relay/__generated__/OperatorRecordExecutionObservationMutation.graphql";
import type {
  OperatorSubmitManualIntakeMutation as SubmitManualIntakeMutation,
  OperatorSubmitManualIntakeMutation$variables as SubmitManualIntakeVariables,
} from "../../relay/__generated__/OperatorSubmitManualIntakeMutation.graphql";
import type {
  OperatorResolveAgentApprovalMutation as ResolveAgentApprovalMutation,
  OperatorResolveAgentApprovalMutation$variables as ResolveAgentApprovalVariables,
} from "../../relay/__generated__/OperatorResolveAgentApprovalMutation.graphql";
import type {
  OperatorResolveAgentContextExpansionMutation as ResolveAgentContextExpansionMutation,
  OperatorResolveAgentContextExpansionMutation$variables as ResolveAgentContextExpansionVariables,
} from "../../relay/__generated__/OperatorResolveAgentContextExpansionMutation.graphql";
import type {
  OperatorStartRunConversationMutation as StartRunConversationMutation,
  OperatorStartRunConversationMutation$variables as StartRunConversationVariables,
} from "../../relay/__generated__/OperatorStartRunConversationMutation.graphql";
import type {
  OperatorWaiveVerificationCheckMutation as WaiveVerificationCheckMutation,
  OperatorWaiveVerificationCheckMutation$variables as WaiveVerificationCheckVariables,
} from "../../relay/__generated__/OperatorWaiveVerificationCheckMutation.graphql";
import {
  commandMutationSuccess,
  useCommandMutation,
  type CommandMutationSuccess,
  type CommandMutationConfig,
} from "../../relay/commandMutation";
import {
  OperatorAcceptEvidenceMutation,
  OperatorAppendConversationMessageMutation,
  OperatorApplyProposedChangesMutation,
  OperatorCancelAgentExecutionMutation,
  OperatorCreateEvidenceCandidateMutation,
  OperatorCreateWorkPacketMutation,
  OperatorInvokeAgentMutation,
  OperatorRecordExecutionObservationMutation,
  OperatorSubmitManualIntakeMutation,
  OperatorResolveAgentApprovalMutation,
  OperatorResolveAgentContextExpansionMutation,
  OperatorStartRunConversationMutation,
  OperatorWaiveVerificationCheckMutation,
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

type InvokeAgentResult = Pick<
  InvokeAgentMutation["response"]["invokeAgent"],
  "contextPackageId" | "execution"
>;
type CancelAgentExecutionResult = Pick<
  CancelAgentExecutionMutation["response"]["cancelAgentExecution"],
  "execution"
>;
type StartRunConversationResult = Pick<
  StartRunConversationMutation["response"]["startRunConversation"],
  "conversation"
>;
type AppendConversationMessageResult = Pick<
  AppendConversationMessageMutation["response"]["appendConversationMessage"],
  "message"
>;
type ResolveAgentApprovalResult = Pick<
  ResolveAgentApprovalMutation["response"]["resolveAgentApproval"],
  "execution" | "request"
>;
type ResolveAgentContextExpansionResult = Pick<
  ResolveAgentContextExpansionMutation["response"]["resolveAgentContextExpansion"],
  "contextPackageId" | "execution" | "request"
>;

const submitManualIntakeConfig = {
  mutation: OperatorSubmitManualIntakeMutation,
  toVariables: (input: SubmitManualIntakeVariables["input"]) => ({ input }),
  mapSuccess(response) {
    const payload = response.submitManualIntake;
    return commandMutationSuccess(payload, {
      normalizedEventId: payload.normalizedEventId,
      proposedChangeIds: payload.proposedChangeIds,
    });
  },
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
      verificationCheck: payload.verificationCheck,
    });
  },
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
      packetVersion: payload.packetVersion,
    });
  },
} satisfies CommandMutationConfig<
  CreateWorkPacketMutation,
  CreateWorkPacketVariables["input"],
  CreateWorkPacketResult
>;

const recordExecutionObservationConfig = {
  mutation: OperatorRecordExecutionObservationMutation,
  toVariables: (input: RecordExecutionObservationVariables["input"]) => ({ input }),
  mapSuccess(response) {
    const payload = response.recordExecutionObservation;
    return commandMutationSuccess(payload, {
      observation: payload.observation,
      run: payload.run,
    });
  },
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
      evidenceCandidate: payload.evidenceCandidate,
    });
  },
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
      run: payload.run,
    });
  },
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
      run: payload.run,
    });
  },
} satisfies CommandMutationConfig<
  WaiveVerificationCheckMutation,
  WaiveVerificationCheckVariables["input"],
  WaiveVerificationCheckResult
>;

const invokeAgentConfig = {
  mutation: OperatorInvokeAgentMutation,
  toVariables: (input: InvokeAgentVariables["input"]) => ({ input }),
  mapSuccess(response) {
    const payload = response.invokeAgent;
    return commandMutationSuccess(payload, {
      contextPackageId: payload.contextPackageId,
      execution: payload.execution,
    });
  },
} satisfies CommandMutationConfig<
  InvokeAgentMutation,
  InvokeAgentVariables["input"],
  InvokeAgentResult
>;

const cancelAgentExecutionConfig = {
  mutation: OperatorCancelAgentExecutionMutation,
  toVariables: (input: CancelAgentExecutionVariables["input"]) => ({ input }),
  mapSuccess(response) {
    const payload = response.cancelAgentExecution;
    return commandMutationSuccess(payload, { execution: payload.execution });
  },
} satisfies CommandMutationConfig<
  CancelAgentExecutionMutation,
  CancelAgentExecutionVariables["input"],
  CancelAgentExecutionResult
>;

const startRunConversationConfig = {
  mutation: OperatorStartRunConversationMutation,
  toVariables: (input: StartRunConversationVariables["input"]) => ({ input }),
  mapSuccess(response) {
    const payload = response.startRunConversation;
    return commandMutationSuccess(payload, { conversation: payload.conversation });
  },
} satisfies CommandMutationConfig<
  StartRunConversationMutation,
  StartRunConversationVariables["input"],
  StartRunConversationResult
>;

const appendConversationMessageConfig = {
  mutation: OperatorAppendConversationMessageMutation,
  toVariables: (input: AppendConversationMessageVariables["input"]) => ({ input }),
  mapSuccess(response) {
    const payload = response.appendConversationMessage;
    return commandMutationSuccess(payload, { message: payload.message });
  },
} satisfies CommandMutationConfig<
  AppendConversationMessageMutation,
  AppendConversationMessageVariables["input"],
  AppendConversationMessageResult
>;

const resolveAgentApprovalConfig = {
  mutation: OperatorResolveAgentApprovalMutation,
  toVariables: (input: ResolveAgentApprovalVariables["input"]) => ({ input }),
  mapSuccess(response) {
    const payload = response.resolveAgentApproval;
    return commandMutationSuccess(payload, {
      execution: payload.execution,
      request: payload.request,
    });
  },
} satisfies CommandMutationConfig<
  ResolveAgentApprovalMutation,
  ResolveAgentApprovalVariables["input"],
  ResolveAgentApprovalResult
>;

const resolveAgentContextExpansionConfig = {
  mutation: OperatorResolveAgentContextExpansionMutation,
  toVariables: (input: ResolveAgentContextExpansionVariables["input"]) => ({ input }),
  mapSuccess(response) {
    const payload = response.resolveAgentContextExpansion;
    return commandMutationSuccess(payload, {
      contextPackageId: payload.contextPackageId,
      execution: payload.execution,
      request: payload.request,
    });
  },
} satisfies CommandMutationConfig<
  ResolveAgentContextExpansionMutation,
  ResolveAgentContextExpansionVariables["input"],
  ResolveAgentContextExpansionResult
>;

export function useOperatorCommand<TMutation extends MutationParameters, TInput, TResult>(
  config: CommandMutationConfig<TMutation, TInput, TResult>,
  onAuthoritativeChange?: (success?: CommandMutationSuccess<TResult>) => void,
) {
  return useCommandMutation(config, onAuthoritativeChange);
}

export function useSubmitManualIntakeCommand(
  onAuthoritativeChange?: (success?: CommandMutationSuccess<SubmitManualIntakeResult>) => void,
) {
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

export function useInvokeAgentCommand(onAuthoritativeChange?: () => void) {
  return useOperatorCommand<InvokeAgentMutation, InvokeAgentVariables["input"], InvokeAgentResult>(
    invokeAgentConfig,
    onAuthoritativeChange,
  );
}

export function useCancelAgentExecutionCommand(onAuthoritativeChange?: () => void) {
  return useOperatorCommand<
    CancelAgentExecutionMutation,
    CancelAgentExecutionVariables["input"],
    CancelAgentExecutionResult
  >(cancelAgentExecutionConfig, onAuthoritativeChange);
}

export function useStartRunConversationCommand(onAuthoritativeChange?: () => void) {
  return useOperatorCommand<
    StartRunConversationMutation,
    StartRunConversationVariables["input"],
    StartRunConversationResult
  >(startRunConversationConfig, onAuthoritativeChange);
}

export function useAppendConversationMessageCommand(onAuthoritativeChange?: () => void) {
  return useOperatorCommand<
    AppendConversationMessageMutation,
    AppendConversationMessageVariables["input"],
    AppendConversationMessageResult
  >(appendConversationMessageConfig, onAuthoritativeChange);
}

export function useResolveAgentApprovalCommand(onAuthoritativeChange?: () => void) {
  return useOperatorCommand<
    ResolveAgentApprovalMutation,
    ResolveAgentApprovalVariables["input"],
    ResolveAgentApprovalResult
  >(resolveAgentApprovalConfig, onAuthoritativeChange);
}

export function useResolveAgentContextExpansionCommand(onAuthoritativeChange?: () => void) {
  return useOperatorCommand<
    ResolveAgentContextExpansionMutation,
    ResolveAgentContextExpansionVariables["input"],
    ResolveAgentContextExpansionResult
  >(resolveAgentContextExpansionConfig, onAuthoritativeChange);
}
