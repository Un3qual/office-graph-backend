import type { MutationParameters } from "relay-runtime";
import type {
  PacketsCreateWorkPacketMutation as CreateWorkPacketMutation,
  PacketsCreateWorkPacketMutation$variables as CreateWorkPacketVariables
} from "../../relay/__generated__/PacketsCreateWorkPacketMutation.graphql";
import type {
  PacketsCreateWorkPacketVersionMutation as CreateWorkPacketVersionMutation,
  PacketsCreateWorkPacketVersionMutation$variables as CreateWorkPacketVersionVariables
} from "../../relay/__generated__/PacketsCreateWorkPacketVersionMutation.graphql";
import type {
  PacketsStartWorkRunMutation as StartWorkRunMutation,
  PacketsStartWorkRunMutation$variables as StartWorkRunVariables
} from "../../relay/__generated__/PacketsStartWorkRunMutation.graphql";
import {
  commandMutationSuccess,
  useCommandMutation,
  type CommandMutationConfig
} from "../../relay/commandMutation";
import {
  PacketsCreateWorkPacketMutation,
  PacketsCreateWorkPacketVersionMutation,
  PacketsStartWorkRunMutation
} from "./commands";

type CreateWorkPacketResult = Pick<
  CreateWorkPacketMutation["response"]["createWorkPacket"],
  "packet" | "packetVersion"
>;

type CreateWorkPacketVersionResult = Pick<
  CreateWorkPacketVersionMutation["response"]["createWorkPacketVersion"],
  "packet" | "packetVersion"
>;

type StartWorkRunResult = Pick<
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
      packetVersion: payload.packetVersion
    });
  }
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
      packetVersion: payload.packetVersion
    });
  }
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
      run: payload.run
    });
  }
} satisfies CommandMutationConfig<
  StartWorkRunMutation,
  StartWorkRunVariables["input"],
  StartWorkRunResult
>;

export function usePacketCommand<
  TMutation extends MutationParameters,
  TInput,
  TResult
>(config: CommandMutationConfig<TMutation, TInput, TResult>) {
  return useCommandMutation(config);
}

export function useCreateWorkPacketCommand() {
  return usePacketCommand<
    CreateWorkPacketMutation,
    CreateWorkPacketVariables["input"],
    CreateWorkPacketResult
  >(createWorkPacketConfig);
}

export function useCreateWorkPacketVersionCommand() {
  return usePacketCommand<
    CreateWorkPacketVersionMutation,
    CreateWorkPacketVersionVariables["input"],
    CreateWorkPacketVersionResult
  >(createWorkPacketVersionConfig);
}

export function useStartWorkRunCommand() {
  return usePacketCommand<
    StartWorkRunMutation,
    StartWorkRunVariables["input"],
    StartWorkRunResult
  >(startWorkRunConfig);
}
