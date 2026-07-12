import type { PacketWorkspaceVersion } from "../types";
import { CommandFieldError } from "../../../relay/CommandFormFeedback";
import { commandFieldErrorProps } from "../../../relay/commandFormSupport";
import type { CommandMutationState } from "../../../relay/commandMutation";

type Props = {
  readonly titleLabel: string;
  readonly version?: PacketWorkspaceVersion;
  readonly commandState?: CommandMutationState<unknown>;
  readonly errorScope?: string;
};

const idleState = { status: "idle" } as const;

export function PacketContractFields({
  titleLabel,
  version,
  commandState = idleState,
  errorScope = "packet-contract",
}: Props) {
  const field = (controlName: string) =>
    commandFieldErrorProps(commandState, errorScope, controlName);
  const error = (controlName: string) => (
    <CommandFieldError controlName={controlName} scope={errorScope} state={commandState} />
  );

  return (
    <div className="packet-contract-fields">
      <label>
        {titleLabel}
        <input {...field("title")} defaultValue={version?.title ?? ""} name="title" required />
        {error("title")}
      </label>
      <label>
        Objective
        <textarea
          {...field("objective")}
          defaultValue={version?.objective ?? ""}
          name="objective"
          required
        />
        {error("objective")}
      </label>
      <label>
        Context summary
        <textarea
          {...field("contextSummary")}
          defaultValue={version?.contextSummary ?? ""}
          name="contextSummary"
          required
        />
        {error("contextSummary")}
      </label>
      <label>
        Requirements
        <textarea
          {...field("requirements")}
          defaultValue={version?.requirements ?? ""}
          name="requirements"
          required
        />
        {error("requirements")}
      </label>
      <label>
        Success criteria
        <textarea
          {...field("successCriteria")}
          defaultValue={version?.successCriteria ?? ""}
          name="successCriteria"
          required
        />
        {error("successCriteria")}
      </label>
      <div>
        <span>Autonomy posture</span>
        <span>Human supervised</span>
        <input
          name="autonomyPosture"
          type="hidden"
          value={version?.autonomyPosture ?? "human_supervised"}
        />
      </div>
      <label>
        Source graph item IDs
        <textarea
          {...field("sourceGraphItemIds")}
          defaultValue={version?.sourceGraphItemIds.join("\n") ?? ""}
          name="sourceGraphItemIds"
          required
        />
        {error("sourceGraphItemIds")}
      </label>
      <label>
        Verification check IDs
        <textarea
          {...field("verificationCheckIds")}
          defaultValue={version?.verificationCheckIds.join("\n") ?? ""}
          name="verificationCheckIds"
          required
        />
        {error("verificationCheckIds")}
      </label>
    </div>
  );
}

export function packetContractInput(form: HTMLFormElement) {
  const data = new FormData(form);

  return {
    title: fieldValue(data, "title"),
    objective: fieldValue(data, "objective"),
    contextSummary: fieldValue(data, "contextSummary"),
    requirements: fieldValue(data, "requirements"),
    successCriteria: fieldValue(data, "successCriteria"),
    autonomyPosture: fieldValue(data, "autonomyPosture"),
    sourceGraphItemIds: idValues(data, "sourceGraphItemIds"),
    verificationCheckIds: idValues(data, "verificationCheckIds"),
  };
}

function fieldValue(data: FormData, field: string) {
  return String(data.get(field) ?? "").trim();
}

function idValues(data: FormData, field: string) {
  return fieldValue(data, field)
    .split(/[\s,]+/)
    .filter(Boolean);
}
