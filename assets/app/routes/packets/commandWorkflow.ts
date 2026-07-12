import type { MutationParameters } from "relay-runtime";
import type {
  PacketsCreateWorkPacketMutation as CreateWorkPacketMutation,
  PacketsCreateWorkPacketMutation$variables as CreateWorkPacketVariables,
} from "../../relay/__generated__/PacketsCreateWorkPacketMutation.graphql";
import type {
  PacketsCreateWorkPacketVersionMutation as CreateWorkPacketVersionMutation,
  PacketsCreateWorkPacketVersionMutation$variables as CreateWorkPacketVersionVariables,
} from "../../relay/__generated__/PacketsCreateWorkPacketVersionMutation.graphql";
import type {
  PacketsStartWorkRunMutation as StartWorkRunMutation,
  PacketsStartWorkRunMutation$variables as StartWorkRunVariables,
} from "../../relay/__generated__/PacketsStartWorkRunMutation.graphql";
import {
  commandMutationSuccess,
  useCommandMutation,
  type CommandMutationSuccess,
  type CommandMutationConfig,
} from "../../relay/commandMutation";
import {
  PacketsCreateWorkPacketMutation,
  PacketsCreateWorkPacketVersionMutation,
  PacketsStartWorkRunMutation,
} from "./commands";

export type CreateWorkPacketResult = Pick<
  CreateWorkPacketMutation["response"]["createWorkPacket"],
  "packet" | "packetVersion"
>;

export type CreateWorkPacketVersionResult = Pick<
  CreateWorkPacketVersionMutation["response"]["createWorkPacketVersion"],
  "packet" | "packetVersion"
>;

export type StartWorkRunResult = Pick<
  StartWorkRunMutation["response"]["startWorkRun"],
  "requiredChecks" | "run"
>;

const createWorkPacketConfig = {
  mutation: PacketsCreateWorkPacketMutation,
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

const createWorkPacketVersionConfig = {
  mutation: PacketsCreateWorkPacketVersionMutation,
  toVariables: (input: CreateWorkPacketVersionVariables["input"]) => ({ input }),
  mapSuccess(response) {
    const payload = response.createWorkPacketVersion;
    return commandMutationSuccess(payload, {
      packet: payload.packet,
      packetVersion: payload.packetVersion,
    });
  },
} satisfies CommandMutationConfig<
  CreateWorkPacketVersionMutation,
  CreateWorkPacketVersionVariables["input"],
  CreateWorkPacketVersionResult
>;

const startWorkRunConfig = {
  mutation: PacketsStartWorkRunMutation,
  toVariables: (input: StartWorkRunVariables["input"]) => ({ input }),
  mapSuccess(response) {
    const payload = response.startWorkRun;
    return commandMutationSuccess(payload, {
      requiredChecks: payload.requiredChecks,
      run: payload.run,
    });
  },
} satisfies CommandMutationConfig<
  StartWorkRunMutation,
  StartWorkRunVariables["input"],
  StartWorkRunResult
>;

export function usePacketCommand<TMutation extends MutationParameters, TInput, TResult>(
  config: CommandMutationConfig<TMutation, TInput, TResult>,
  onAuthoritativeChange?: (success?: CommandMutationSuccess<TResult>) => void,
) {
  return useCommandMutation(config, onAuthoritativeChange);
}

export function useCreateWorkPacketCommand(
  onAuthoritativeChange?: (success?: CommandMutationSuccess<CreateWorkPacketResult>) => void,
) {
  return usePacketCommand<
    CreateWorkPacketMutation,
    CreateWorkPacketVariables["input"],
    CreateWorkPacketResult
  >(createWorkPacketConfig, onAuthoritativeChange);
}

export function useCreateWorkPacketVersionCommand(
  onAuthoritativeChange?: (success?: CommandMutationSuccess<CreateWorkPacketVersionResult>) => void,
) {
  return usePacketCommand<
    CreateWorkPacketVersionMutation,
    CreateWorkPacketVersionVariables["input"],
    CreateWorkPacketVersionResult
  >(createWorkPacketVersionConfig, onAuthoritativeChange);
}

export function useStartWorkRunCommand(
  onAuthoritativeChange?: (success?: CommandMutationSuccess<StartWorkRunResult>) => void,
) {
  return usePacketCommand<StartWorkRunMutation, StartWorkRunVariables["input"], StartWorkRunResult>(
    startWorkRunConfig,
    onAuthoritativeChange,
  );
}
