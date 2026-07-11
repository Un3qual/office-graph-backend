import type { OperatorRunStateFragment$data } from "../../relay/__generated__/OperatorRunStateFragment.graphql";
import type { OperatorWorkflowItemFragment$data } from "../../relay/__generated__/OperatorWorkflowItemFragment.graphql";
import type {
  DerivedPacketReadiness,
  PacketReadinessInput
} from "./types";

export function packetReadinessInputForItem(
  item: OperatorWorkflowItemFragment$data
): PacketReadinessInput {
  const defaults = commandInputDefaults(createWorkPacketAffordance(item));

  return {
    title: defaultValue(defaults, "title"),
    objective: defaultValue(defaults, "objective"),
    contextSummary: defaultValue(defaults, "context_summary"),
    requirements: defaultValue(defaults, "requirements"),
    successCriteria: defaultValue(defaults, "success_criteria"),
    autonomyPosture: defaultValue(defaults, "autonomy_posture"),
    sourceGraphItemIds: defaultValues(defaults, "source_graph_item_ids"),
    verificationCheckIds: defaultValues(defaults, "verification_check_ids")
  };
}

export function packetReadinessForItem(
  item: OperatorWorkflowItemFragment$data,
  input: PacketReadinessInput
): DerivedPacketReadiness<
  OperatorWorkflowItemFragment$data["commandAffordances"][number]
> {
  const command = createWorkPacketAffordance(item);
  const sourceLinks = item.graphLinks.filter((link) => link.graphItemId && link.type !== "work_run");
  const requiredChecks = item.graphLinks.filter((link) => link.type === "verification_check");

  return {
    type: "packet_readiness",
    ready: false,
    status: "blocked",
    allowedNextActions: [],
    commandAffordances: command ? [command] : [],
    blockerReasons: derivedReadinessBlockers(command, input, item.blockerReasons),
    sourceLinks: sourceLinks.map((link) => ({
      title: link.title ?? link.id
    })),
    requiredChecks: requiredChecks.map((link) => ({
      state: link.state ?? "unknown"
    })),
    sourceWatermark: item.sourceWatermark ?? item.operationWatermark ?? null,
    isDerived: true
  };
}

export function runIdForItem(item: OperatorWorkflowItemFragment$data | null) {
  return item?.graphLinks.find((link) => link.type === "work_run")?.id ?? null;
}

export function itemTitle(item: OperatorWorkflowItemFragment$data) {
  return item.normalizedEventId;
}

export function verificationOutcomeFromRunState(runState: OperatorRunStateFragment$data) {
  return {
    type: "verification_outcome",
    status: runState.status,
    sourceWatermark: runState.sourceWatermark ?? null,
    run: runState.run,
    verificationResults: runState.verificationResults,
    missingEvidence: runState.missingEvidence
  };
}

export function createWorkPacketAffordance(item: OperatorWorkflowItemFragment$data) {
  return (
    item.commandAffordances.find((affordance) => affordance.identity === "create_work_packet") ??
    null
  );
}

function commandInputDefaults(
  affordance: OperatorWorkflowItemFragment$data["commandAffordances"][number] | null
) {
  return affordance?.inputDefaults ?? [];
}

function defaultValue(
  defaults: ReturnType<typeof commandInputDefaults>,
  field: string
) {
  return defaults.find((defaultEntry) => defaultEntry.field === field)?.value ?? "";
}

function defaultValues(
  defaults: ReturnType<typeof commandInputDefaults>,
  field: string
) {
  return [...(defaults.find((defaultEntry) => defaultEntry.field === field)?.values ?? [])];
}

function derivedReadinessBlockers(
  command: OperatorWorkflowItemFragment$data["commandAffordances"][number] | null,
  input: PacketReadinessInput,
  itemBlockers: readonly string[]
) {
  if (command?.blockerReasons && command.blockerReasons.length > 0) {
    return [...command.blockerReasons];
  }

  if (!packetReadinessInputComplete(input)) {
    return itemBlockers.length > 0 ? [...itemBlockers] : ["missing_packet_readiness_input"];
  }

  return ["backend_packet_readiness_required"];
}

function packetReadinessInputComplete(input: PacketReadinessInput) {
  return (
    input.title.trim() !== "" &&
    input.objective.trim() !== "" &&
    input.contextSummary.trim() !== "" &&
    input.requirements.trim() !== "" &&
    input.successCriteria.trim() !== "" &&
    input.autonomyPosture.trim() !== "" &&
    input.sourceGraphItemIds.length > 0 &&
    input.verificationCheckIds.length > 0
  );
}
