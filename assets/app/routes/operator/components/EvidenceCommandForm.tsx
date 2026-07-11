import { useRef, useState, type FormEvent } from "react";
import { Button } from "../../../../src/ui/Button";
import { FormFeedback } from "../../../../src/ui/FormFeedback";
import { commandFeedback, defaultValue, defaultValues, enabledAffordance, submissionIdentity } from "../commandFormSupport";
import { useAcceptEvidenceCommand, useCreateEvidenceCandidateCommand, useWaiveVerificationCheckCommand } from "../commandWorkflow";
import type { OperatorRunState } from "../workflow";

export function EvidenceCommandForm({ onRefresh, runState }: { onRefresh: () => void; runState: OperatorRunState }) {
  const candidate = useCreateEvidenceCandidateCommand(onRefresh);
  const accept = useAcceptEvidenceCommand(onRefresh);
  const waive = useWaiveVerificationCheckCommand(onRefresh);
  const candidateAttempt = useRef<{ fingerprint: string; key: string } | null>(null);
  const acceptAttempt = useRef<{ fingerprint: string; key: string } | null>(null);
  const waiveAttempt = useRef<{ fingerprint: string; key: string } | null>(null);
  const [claim, setClaim] = useState("");
  const [title, setTitle] = useState("");
  const [body, setBody] = useState("");
  const [waiverReason, setWaiverReason] = useState("");
  const [policyBasis, setPolicyBasis] = useState("owner_exception");
  const candidateAffordance = enabledAffordance(runState.commandAffordances, "create_evidence_candidate");
  const acceptAffordance = enabledAffordance(runState.commandAffordances, "accept_evidence");
  const waiveAffordance = enabledAffordance(runState.commandAffordances, "waive_verification_check");

  const submitCandidate = (event: FormEvent) => {
    event.preventDefault();
    if (!candidateAffordance) return;
    const input = {
      workRunId: defaultValue(candidateAffordance, "work_run_id") || runState.run.id,
      verificationCheckId: defaultValues(candidateAffordance, "verification_check_id")[0] ?? runState.missingEvidence[0]?.verificationCheckId ?? "",
      executionObservationId: defaultValues(candidateAffordance, "execution_observation_id")[0] ?? runState.observations[0]?.id ?? "",
      claim: claim.trim(), sourceKind: "human", sourceIdentity: "operator-console",
      freshnessState: "fresh", trustBasis: "owner_attested",
      sensitivity: defaultValue(candidateAffordance, "sensitivity") || "internal"
    };
    candidateAttempt.current = submissionIdentity(candidateAttempt.current, input);
    candidate.submit({ ...input, idempotencyKey: candidateAttempt.current.key });
  };

  const submitAccept = (event: FormEvent) => {
    event.preventDefault();
    if (!acceptAffordance) return;
    const input = {
      evidenceCandidateId: runState.evidenceCandidates.find(item => item.state === "candidate")?.id ?? "",
      title: title.trim(), body: body.trim(), result: "passed", acceptancePolicyBasis: "owner_acceptance"
    };
    acceptAttempt.current = submissionIdentity(acceptAttempt.current, input);
    accept.submit({ ...input, idempotencyKey: acceptAttempt.current.key });
  };

  const submitWaive = (event: FormEvent) => {
    event.preventDefault();
    if (!waiveAffordance) return;
    const input = {
      runId: defaultValue(waiveAffordance, "run_id") || runState.run.id,
      runRequiredCheckId: defaultValues(waiveAffordance, "run_required_check_id")[0] ?? "",
      expectedExecutionState: defaultValue(waiveAffordance, "expected_execution_state") || runState.run.executionState,
      expectedVerificationState: defaultValue(waiveAffordance, "expected_verification_state") || runState.run.verificationState,
      reason: waiverReason.trim(), policyBasis: policyBasis.trim()
    };
    waiveAttempt.current = submissionIdentity(waiveAttempt.current, input);
    waive.submit({ ...input, idempotencyKey: waiveAttempt.current.key });
  };

  if (!candidateAffordance && !acceptAffordance && !waiveAffordance) return null;
  return <div className="operator-command-stack">
    {candidateAffordance ? <form className="operator-command-form" onSubmit={submitCandidate}>
      <label htmlFor="evidence-claim">Evidence claim</label><textarea id="evidence-claim" onChange={event => setClaim(event.target.value)} value={claim} />
      <Button isDisabled={candidate.state.status === "pending" || !claim.trim()} type="submit" variant="primary">{candidate.state.status === "pending" ? "Creating evidence candidate" : "Create evidence candidate"}</Button>
      <FormFeedback feedback={commandFeedback(candidate.state)} />
    </form> : null}
    {acceptAffordance ? <form className="operator-command-form" onSubmit={submitAccept}>
      <label htmlFor="evidence-title">Evidence title</label><input id="evidence-title" onChange={event => setTitle(event.target.value)} value={title} />
      <label htmlFor="evidence-body">Evidence body</label><textarea id="evidence-body" onChange={event => setBody(event.target.value)} value={body} />
      <Button isDisabled={accept.state.status === "pending" || !title.trim() || !body.trim()} type="submit" variant="primary">{accept.state.status === "pending" ? "Accepting evidence" : "Accept evidence"}</Button>
      <FormFeedback feedback={commandFeedback(accept.state)} />
    </form> : null}
    {waiveAffordance ? <form className="operator-command-form" onSubmit={submitWaive}>
      <label htmlFor="waiver-reason">Waiver reason</label><textarea id="waiver-reason" onChange={event => setWaiverReason(event.target.value)} value={waiverReason} />
      <label htmlFor="waiver-policy">Policy basis</label><input id="waiver-policy" onChange={event => setPolicyBasis(event.target.value)} value={policyBasis} />
      <Button isDisabled={waive.state.status === "pending" || !waiverReason.trim() || !policyBasis.trim()} type="submit" variant="primary">{waive.state.status === "pending" ? "Waiving verification check" : "Waive verification check"}</Button>
      <FormFeedback feedback={commandFeedback(waive.state)} />
    </form> : null}
  </div>;
}
