import type { OperatorWorkflowItem, PacketReadinessInput } from "./workflowTypes";

export function packetReadinessInputForItem(item: OperatorWorkflowItem): PacketReadinessInput {
  const sourceLinks = item.graphLinks.filter(
    (link) => link.graphItemId && link.type !== "work_run"
  );
  const verificationChecks = item.graphLinks.filter((link) => link.type === "verification_check");

  return {
    sourceGraphItemIds: sourceLinks.flatMap((link) => (link.graphItemId ? [link.graphItemId] : [])),
    verificationCheckIds: verificationChecks.map((link) => link.id)
  };
}

export function runIdForItem(item: OperatorWorkflowItem | null) {
  return item?.graphLinks.find((link) => link.type === "work_run")?.id ?? null;
}
