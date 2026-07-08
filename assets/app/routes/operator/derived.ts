import type {
  OperatorRunState,
  OperatorWorkflowItem,
  PacketReadinessInput,
  VerificationOutcome
} from "./types";

export function packetReadinessInputForItem(item: OperatorWorkflowItem): PacketReadinessInput {
  const sourceLinks = item.graphLinks.filter(
    (link) => link.graphItemId && link.type !== "work_run"
  );
  const verificationChecks = item.graphLinks.filter((link) => link.type === "verification_check");
  const sourceTitles = uniqueNonBlank(sourceLinks.map((link) => link.title ?? ""));
  const verificationTitles = uniqueNonBlank(verificationChecks.map((link) => link.title ?? ""));
  const title = firstNonBlank([...verificationTitles, ...sourceTitles, itemTitle(item)]);
  const sourceSummary = sourceTitles.join("\n");
  const verificationSummary = verificationTitles.join("\n");

  return {
    title,
    objective: title,
    contextSummary: sourceSummary,
    requirements: sourceSummary,
    successCriteria: verificationSummary,
    autonomyPosture: "human_supervised",
    sourceGraphItemIds: sourceLinks.flatMap((link) => (link.graphItemId ? [link.graphItemId] : [])),
    verificationCheckIds: verificationChecks.map((link) => link.id)
  };
}

export function runIdForItem(item: OperatorWorkflowItem | null) {
  return item?.graphLinks.find((link) => link.type === "work_run")?.id ?? null;
}

export function itemTitle(item: OperatorWorkflowItem) {
  return item.normalizedEventId;
}

export function verificationOutcomeFromRunState(runState: OperatorRunState): VerificationOutcome {
  return {
    type: "verification_outcome",
    status: runState.status,
    sourceWatermark: runState.sourceWatermark ?? null,
    run: runState.run,
    verificationResults: runState.verificationResults,
    missingEvidence: runState.missingEvidence
  };
}

function uniqueNonBlank(values: readonly string[]) {
  return [...new Set(values.map((value) => value.trim()).filter(Boolean))];
}

function firstNonBlank(values: readonly string[]) {
  return values.map((value) => value.trim()).find(Boolean) ?? "";
}
