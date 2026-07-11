import type { PacketWorkspaceVersion } from "../types";

type Props = {
  readonly titleLabel: string;
  readonly version?: PacketWorkspaceVersion;
};

export function PacketContractFields({ titleLabel, version }: Props) {
  return (
    <div className="packet-contract-fields">
      <label>
        {titleLabel}
        <input defaultValue={version?.title ?? ""} name="title" required />
      </label>
      <label>
        Objective
        <textarea defaultValue={version?.objective ?? ""} name="objective" required />
      </label>
      <label>
        Context summary
        <textarea
          defaultValue={version?.contextSummary ?? ""}
          name="contextSummary"
          required
        />
      </label>
      <label>
        Requirements
        <textarea
          defaultValue={version?.requirements ?? ""}
          name="requirements"
          required
        />
      </label>
      <label>
        Success criteria
        <textarea
          defaultValue={version?.successCriteria ?? ""}
          name="successCriteria"
          required
        />
      </label>
      <label>
        Autonomy posture
        <select
          defaultValue={version?.autonomyPosture ?? "human_supervised"}
          name="autonomyPosture"
        >
          <option value="human_supervised">Human supervised</option>
        </select>
      </label>
      <label>
        Source graph item IDs
        <textarea
          defaultValue={version?.sourceGraphItemIds.join("\n") ?? ""}
          name="sourceGraphItemIds"
          required
        />
      </label>
      <label>
        Verification check IDs
        <textarea
          defaultValue={version?.verificationCheckIds.join("\n") ?? ""}
          name="verificationCheckIds"
          required
        />
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
    verificationCheckIds: idValues(data, "verificationCheckIds")
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
