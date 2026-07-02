import type {
  OperatorWorkflowItem,
  PacketReadiness,
  PacketReadinessInput
} from "./workflowTypes";

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

export function packetReadinessForLoadedItem(item: OperatorWorkflowItem): PacketReadiness | null {
  if (item.status !== "ready_for_packet" || !item.allowedNextActions.includes("prepare_packet")) {
    return null;
  }

  const sourceLinks = item.graphLinks.flatMap((link) =>
    link.graphItemId && link.type !== "work_run"
      ? [{ type: link.type, id: link.id, graphItemId: link.graphItemId, title: link.title }]
      : []
  );
  const requiredChecks = item.graphLinks.flatMap((link) =>
    link.graphItemId && link.type === "verification_check"
      ? [{ id: link.id, graphItemId: link.graphItemId, state: link.state ?? "required" }]
      : []
  );

  if (sourceLinks.length === 0 || requiredChecks.length === 0) {
    return null;
  }

  return {
    type: "packet_readiness",
    ready: true,
    status: item.status,
    allowedNextActions: item.allowedNextActions,
    blockerReasons: [],
    sourceLinks,
    requiredChecks,
    sourceWatermark: item.sourceWatermark,
    isDerived: true
  };
}

export function runIdForItem(item: OperatorWorkflowItem | null) {
  return item?.graphLinks.find((link) => link.type === "work_run")?.id ?? null;
}
