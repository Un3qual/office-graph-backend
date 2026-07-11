import { useRef, type FormEvent } from "react";
import { Button } from "../../../../src/ui/Button";
import { FormFeedback } from "../../../../src/ui/FormFeedback";
import { commandFeedback, defaultValue, defaultValues, enabledAffordance, submissionIdentity } from "../commandFormSupport";
import { useApplyProposedChangesCommand, useCreateWorkPacketCommand, useStartWorkRunCommand } from "../commandWorkflow";
import type { PacketReadinessInput } from "../types";
import type { OperatorWorkflowItem } from "../workflow";

type Props = { item: OperatorWorkflowItem | null; onRefresh: () => void; readinessInput: PacketReadinessInput | null };

export function PacketCommandForm({ item, onRefresh, readinessInput }: Props) {
  const apply = useApplyProposedChangesCommand(onRefresh);
  const create = useCreateWorkPacketCommand(onRefresh);
  const start = useStartWorkRunCommand(onRefresh);
  const applyAttempt = useRef<{ fingerprint: string; key: string } | null>(null);
  const createAttempt = useRef<{ fingerprint: string; key: string } | null>(null);
  const startAttempt = useRef<{ fingerprint: string; key: string } | null>(null);
  const applyAffordance = item ? enabledAffordance(item.commandAffordances, "apply_proposed_changes") : null;
  const createAffordance = item ? enabledAffordance(item.commandAffordances, "create_work_packet") : null;
  const startAffordance = item ? enabledAffordance(item.commandAffordances, "start_work_run") : null;

  if (!applyAffordance && !(createAffordance && readinessInput) && !startAffordance) return null;

  const submitApply = (event: FormEvent) => {
    event.preventDefault();
    if (!applyAffordance) return;
    const input = { normalizedEventId: defaultValue(applyAffordance, "normalized_event_id"), proposedChangeIds: defaultValues(applyAffordance, "proposed_change_ids") };
    applyAttempt.current = submissionIdentity(applyAttempt.current, input);
    apply.submit({ ...input, idempotencyKey: applyAttempt.current.key });
  };
  const submitCreate = (event: FormEvent) => {
    event.preventDefault();
    if (!readinessInput) return;
    createAttempt.current = submissionIdentity(createAttempt.current, readinessInput);
    create.submit({ ...readinessInput, idempotencyKey: createAttempt.current.key });
  };
  const submitStart = (event: FormEvent) => {
    event.preventDefault();
    if (!startAffordance || !item) return;
    const input = {
      packetVersionId: defaultValue(startAffordance, "packet_version_id") || item.graphLinks.find(link => link.type === "work_packet_version")?.id || "",
      authorityPosture: defaultValue(startAffordance, "authority_posture") || "human_supervised",
      reason: defaultValue(startAffordance, "reason") || "Operator console run",
      sourceSurface: defaultValue(startAffordance, "source_surface") || "operator_console"
    };
    startAttempt.current = submissionIdentity(startAttempt.current, input);
    start.submit({ ...input, idempotencyKey: startAttempt.current.key });
  };

  return <div className="operator-command-stack">
    {applyAffordance ? <form className="operator-command-form" onSubmit={submitApply}>
      <p>{applyAffordance.safeExplanation}</p>
      <Button isDisabled={apply.state.status === "pending"} type="submit" variant="primary">{apply.state.status === "pending" ? "Applying proposed changes" : "Apply proposed changes"}</Button>
      <FormFeedback feedback={commandFeedback(apply.state)} />
    </form> : null}
    {createAffordance && readinessInput ? <form className="operator-command-form" onSubmit={submitCreate}>
      <p>{createAffordance.safeExplanation}</p>
      <Button isDisabled={create.state.status === "pending"} type="submit" variant="primary">{create.state.status === "pending" ? "Creating work packet" : "Create work packet"}</Button>
      <FormFeedback feedback={commandFeedback(create.state)} />
    </form> : null}
    {startAffordance ? <form className="operator-command-form" onSubmit={submitStart}>
      <p>{startAffordance.safeExplanation}</p>
      <Button isDisabled={start.state.status === "pending"} type="submit" variant="primary">{start.state.status === "pending" ? "Starting work run" : "Start work run"}</Button>
      <FormFeedback feedback={commandFeedback(start.state)} />
    </form> : null}
  </div>;
}
