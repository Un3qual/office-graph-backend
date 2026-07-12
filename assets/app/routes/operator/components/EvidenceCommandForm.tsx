import { useRef, useState, type FormEvent } from "react";
import { Button } from "../../../../src/ui/Button";
import { FormFeedback } from "../../../../src/ui/FormFeedback";
import { commandFeedback, defaultValue, defaultValues, enabledAffordance, submissionIdentity, targetValues } from "../commandFormSupport";
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
  const [selectedCandidateId, setSelectedCandidateId] = useState("");
  const [waiverReason, setWaiverReason] = useState("");
  const [policyBasis, setPolicyBasis] = useState("owner_exception");
  const candidateAffordance = enabledAffordance(runState.commandAffordances, "create_evidence_candidate");
  const acceptAffordance = enabledAffordance(runState.commandAffordances, "accept_evidence");
  const waiveAffordance = enabledAffordance(runState.commandAffordances, "waive_verification_check");
  const acceptableCandidateIds = acceptAffordance
    ? targetValues(acceptAffordance, "evidence_candidate")
    : [];
  const candidateObservationIds = candidateAffordance
    ? defaultValues(candidateAffordance, "execution_observation_id")
    : [];
  const candidateCheckIds = candidateAffordance
    ? defaultValues(candidateAffordance, "verification_check_id")
    : [];
  const candidateObservations = runState.observations.filter(observation =>
    candidateObservationIds.includes(observation.id) &&
    typeof observation.verificationCheckId === "string" &&
    candidateCheckIds.includes(observation.verificationCheckId)
  );
  const waiverCheckIds = waiveAffordance
    ? defaultValues(waiveAffordance, "run_required_check_id")
    : [];

  const submitCandidate = (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    if (!candidateAffordance) return;
    const input = {
      workRunId: defaultValue(candidateAffordance, "work_run_id") || runState.run.id,
      verificationCheckId: candidateObservations.find(observation =>
        observation.id === new FormData(event.currentTarget).get("executionObservationId")
      )?.verificationCheckId ?? "",
      executionObservationId: String(new FormData(event.currentTarget).get("executionObservationId") ?? ""),
      claim: claim.trim(), sourceKind: "human", sourceIdentity: "operator-console",
      freshnessState: "fresh", trustBasis: "owner_attested",
      sensitivity: defaultValue(candidateAffordance, "sensitivity") || "internal"
    };
    candidateAttempt.current = submissionIdentity(candidateAttempt.current, input);
    candidate.submit({ ...input, idempotencyKey: candidateAttempt.current.key });
  };

  const submitAccept = (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    if (!acceptAffordance) return;
    const input = {
      evidenceCandidateId: selectedCandidateId || acceptableCandidateIds[0] || "",
      title: title.trim(), body: body.trim(), result: "passed", acceptancePolicyBasis: "owner_acceptance"
    };
    acceptAttempt.current = submissionIdentity(acceptAttempt.current, input);
    accept.submit({ ...input, idempotencyKey: acceptAttempt.current.key });
  };

  const submitWaive = (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    if (!waiveAffordance) return;
    const input = {
      runId: defaultValue(waiveAffordance, "run_id") || runState.run.id,
      runRequiredCheckId: String(new FormData(event.currentTarget).get("runRequiredCheckId") ?? ""),
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
      <label htmlFor="evidence-observation">Evidence observation</label>
      <select defaultValue={candidateObservations[0]?.id ?? ""} id="evidence-observation" name="executionObservationId">
        {candidateObservations.map(observation => <option key={observation.id} value={observation.id}>{observation.id}</option>)}
      </select>
      <label htmlFor="evidence-claim">Evidence claim</label><textarea id="evidence-claim" onChange={event => setClaim(event.target.value)} value={claim} />
      <Button isDisabled={candidate.state.status === "pending" || !claim.trim() || candidateObservations.length === 0} type="submit" variant="primary">{candidate.state.status === "pending" ? "Creating evidence candidate" : "Create evidence candidate"}</Button>
      <FormFeedback feedback={commandFeedback(candidate.state)} />
    </form> : null}
    {acceptAffordance ? <form className="operator-command-form" onSubmit={submitAccept}>
      <label htmlFor="evidence-candidate">Evidence candidate</label>
      <select id="evidence-candidate" name="evidenceCandidateId" onChange={event => setSelectedCandidateId(event.target.value)} value={selectedCandidateId || acceptableCandidateIds[0] || ""}>
        {acceptableCandidateIds.map(id => <option key={id} value={id}>{id}</option>)}
      </select>
      <label htmlFor="evidence-title">Evidence title</label><input id="evidence-title" onChange={event => setTitle(event.target.value)} value={title} />
      <label htmlFor="evidence-body">Evidence body</label><textarea id="evidence-body" onChange={event => setBody(event.target.value)} value={body} />
      <Button isDisabled={accept.state.status === "pending" || !title.trim() || !body.trim() || acceptableCandidateIds.length === 0} type="submit" variant="primary">{accept.state.status === "pending" ? "Accepting evidence" : "Accept evidence"}</Button>
      <FormFeedback feedback={commandFeedback(accept.state)} />
    </form> : null}
    {waiveAffordance ? <form className="operator-command-form" onSubmit={submitWaive}>
      <label htmlFor="required-check">Required check</label>
      <select defaultValue={waiverCheckIds[0] ?? ""} id="required-check" name="runRequiredCheckId">
        {waiverCheckIds.map(id => <option key={id} value={id}>{id}</option>)}
      </select>
      <label htmlFor="waiver-reason">Waiver reason</label><textarea id="waiver-reason" onChange={event => setWaiverReason(event.target.value)} value={waiverReason} />
      <label htmlFor="waiver-policy">Policy basis</label><input id="waiver-policy" onChange={event => setPolicyBasis(event.target.value)} value={policyBasis} />
      <Button isDisabled={waive.state.status === "pending" || !waiverReason.trim() || !policyBasis.trim() || waiverCheckIds.length === 0} type="submit" variant="primary">{waive.state.status === "pending" ? "Waiving verification check" : "Waive verification check"}</Button>
      <FormFeedback feedback={commandFeedback(waive.state)} />
    </form> : null}
  </div>;
}
