import { useRef, type FormEvent } from "react";
import { Button } from "../../../../src/ui/Button";
import { CommandFormFeedback } from "../../../relay/CommandFormFeedback";
import { defaultValue, defaultValues, enabledAffordance, submissionIdentity } from "../commandFormSupport";
import { useApplyProposedChangesCommand, useCreateWorkPacketCommand } from "../commandWorkflow";
import type { PacketReadinessInput } from "../types";
import type { OperatorWorkflowItem, PacketReadinessState } from "../workflow";

type Props = {
  item: OperatorWorkflowItem | null;
  onRefresh: () => void;
  readiness: PacketReadinessState | null;
  readinessInput: PacketReadinessInput | null;
};

export function PacketCommandForm({ item, onRefresh, readiness, readinessInput }: Props) {
  const apply = useApplyProposedChangesCommand(onRefresh);
  const create = useCreateWorkPacketCommand(onRefresh);
  const applyAttempt = useRef<{ fingerprint: string; key: string } | null>(null);
  const createAttempt = useRef<{ fingerprint: string; key: string } | null>(null);
  const applyFormRef = useRef<HTMLFormElement>(null);
  const createFormRef = useRef<HTMLFormElement>(null);
  const applyAffordance = item ? enabledAffordance(item.commandAffordances, "apply_proposed_changes") : null;
  const createAffordance = readiness && !("isDerived" in readiness)
    ? enabledAffordance(readiness.commandAffordances, "create_work_packet")
    : null;

  if (!applyAffordance && !(createAffordance && readinessInput)) return null;

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
  return <div className="operator-command-stack">
    {applyAffordance ? <form className="operator-command-form" onSubmit={submitApply} ref={applyFormRef}>
      <p>{applyAffordance.safeExplanation}</p>
      <Button isDisabled={apply.state.status === "pending"} type="submit" variant="primary">{apply.state.status === "pending" ? "Applying proposed changes" : "Apply proposed changes"}</Button>
      <CommandFormFeedback formRef={applyFormRef} scope="apply-changes" state={apply.state} />
    </form> : null}
    {createAffordance && readinessInput ? <form className="operator-command-form" onSubmit={submitCreate} ref={createFormRef}>
      <p>{createAffordance.safeExplanation}</p>
      <Button isDisabled={create.state.status === "pending"} type="submit" variant="primary">{create.state.status === "pending" ? "Creating work packet" : "Create work packet"}</Button>
      <CommandFormFeedback formRef={createFormRef} scope="create-packet" state={create.state} />
    </form> : null}
  </div>;
}
