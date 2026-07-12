import { useRef, useState, type FormEvent } from "react";
import { Button } from "../../../../src/ui/Button";
import { FormFeedback } from "../../../../src/ui/FormFeedback";
import { commandFeedback, enabledAffordance, submissionIdentity } from "../commandFormSupport";
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
  const [evidenceResult, setEvidenceResult] = useState("");
  const [waiverReason, setWaiverReason] = useState("");
  const [policyBasis, setPolicyBasis] = useState("");
  const candidateAffordance = enabledAffordance(runState.commandAffordances, "create_evidence_candidate");
  const acceptAffordance = enabledAffordance(runState.commandAffordances, "accept_evidence");
  const waiveAffordance = enabledAffordance(runState.commandAffordances, "waive_verification_check");
  const candidateOptions = runState.commandOptions.evidenceCandidate.filter((option) =>
    completeOption(option, [
      "key", "label", "workRunId", "verificationCheckId", "executionObservationId",
      "sourceKind", "sourceIdentity", "freshnessState", "trustBasis", "sensitivity"
    ])
  );
  const acceptOptions = runState.commandOptions.evidenceAcceptance.filter((option) =>
    completeOption(option, [
      "key", "label", "evidenceCandidateId", "result", "acceptancePolicyBasis"
    ])
  );
  const currentAcceptOption =
    acceptOptions.find(({ evidenceCandidateId }) => evidenceCandidateId === selectedCandidateId) ??
    acceptOptions[0];
  const currentCandidateId = currentAcceptOption?.evidenceCandidateId ?? "";
  const waiverOptions = runState.commandOptions.waiver.filter((option) =>
    completeOption(option, [
      "key", "label", "runId", "runRequiredCheckId", "expectedExecutionState",
      "expectedVerificationState", "policyBasis"
    ])
  );
  const currentResult = evidenceResult || currentAcceptOption?.result || "";

  const submitCandidate = (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    if (!candidateAffordance) return;
    const optionKey = new FormData(event.currentTarget).get("evidenceCandidateOptionKey");
    const option = candidateOptions.find(({ key }) => key === optionKey);
    if (!option) return;
    const input = {
      workRunId: option.workRunId,
      verificationCheckId: option.verificationCheckId,
      executionObservationId: option.executionObservationId,
      claim: claim.trim(),
      sourceKind: option.sourceKind,
      sourceIdentity: option.sourceIdentity,
      freshnessState: option.freshnessState,
      trustBasis: option.trustBasis,
      sensitivity: option.sensitivity
    };
    candidateAttempt.current = submissionIdentity(candidateAttempt.current, input);
    candidate.submit({ ...input, idempotencyKey: candidateAttempt.current.key });
  };

  const submitAccept = (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    if (!acceptAffordance || !currentAcceptOption) return;
    const input = {
      evidenceCandidateId: currentAcceptOption.evidenceCandidateId,
      title: title.trim(), body: body.trim(), result: currentResult,
      acceptancePolicyBasis: currentAcceptOption.acceptancePolicyBasis
    };
    acceptAttempt.current = submissionIdentity(acceptAttempt.current, input);
    accept.submit({ ...input, idempotencyKey: acceptAttempt.current.key });
  };

  const submitWaive = (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    if (!waiveAffordance) return;
    const optionKey = new FormData(event.currentTarget).get("waiverOptionKey");
    const option = waiverOptions.find(({ key }) => key === optionKey);
    if (!option) return;
    const input = {
      runId: option.runId,
      runRequiredCheckId: option.runRequiredCheckId,
      expectedExecutionState: option.expectedExecutionState,
      expectedVerificationState: option.expectedVerificationState,
      reason: waiverReason.trim(), policyBasis: (policyBasis || option.policyBasis).trim()
    };
    waiveAttempt.current = submissionIdentity(waiveAttempt.current, input);
    waive.submit({ ...input, idempotencyKey: waiveAttempt.current.key });
  };

  if (!candidateAffordance && !acceptAffordance && !waiveAffordance) return null;
  return <div className="operator-command-stack">
    {candidateAffordance ? <form className="operator-command-form" onSubmit={submitCandidate}>
      <label htmlFor="evidence-observation">Evidence observation</label>
      <select defaultValue={candidateOptions[0]?.key ?? ""} id="evidence-observation" name="evidenceCandidateOptionKey">
        {candidateOptions.map(option => <option key={option.key} value={option.key}>{option.label}</option>)}
      </select>
      <label htmlFor="evidence-claim">Evidence claim</label><textarea id="evidence-claim" onChange={event => setClaim(event.target.value)} value={claim} />
      <Button isDisabled={candidate.state.status === "pending" || !claim.trim() || candidateOptions.length === 0} type="submit" variant="primary">{candidate.state.status === "pending" ? "Creating evidence candidate" : "Create evidence candidate"}</Button>
      <FormFeedback feedback={commandFeedback(candidate.state)} />
    </form> : null}
    {acceptAffordance ? <form className="operator-command-form" onSubmit={submitAccept}>
      <label htmlFor="evidence-candidate">Evidence candidate</label>
      <select id="evidence-candidate" name="evidenceCandidateId" onChange={event => setSelectedCandidateId(event.target.value)} value={currentCandidateId}>
        {acceptOptions.map(option => <option key={option.key} value={option.evidenceCandidateId}>{option.label}</option>)}
      </select>
      <label htmlFor="evidence-result">Evidence result</label>
      <select id="evidence-result" name="evidenceResult" onChange={event => setEvidenceResult(event.target.value)} value={currentResult}>
        <option value="passed">Passed</option>
        <option value="failed">Failed</option>
      </select>
      <label htmlFor="evidence-title">Evidence title</label><input id="evidence-title" onChange={event => setTitle(event.target.value)} value={title} />
      <label htmlFor="evidence-body">Evidence body</label><textarea id="evidence-body" onChange={event => setBody(event.target.value)} value={body} />
      <Button isDisabled={accept.state.status === "pending" || !title.trim() || !body.trim() || acceptOptions.length === 0} type="submit" variant="primary">{accept.state.status === "pending" ? "Accepting evidence" : "Accept evidence"}</Button>
      <FormFeedback feedback={commandFeedback(accept.state)} />
    </form> : null}
    {waiveAffordance ? <form className="operator-command-form" onSubmit={submitWaive}>
      <label htmlFor="required-check">Required check</label>
      <select defaultValue={waiverOptions[0]?.key ?? ""} id="required-check" name="waiverOptionKey">
        {waiverOptions.map(option => <option key={option.key} value={option.key}>{option.label}</option>)}
      </select>
      <label htmlFor="waiver-reason">Waiver reason</label><textarea id="waiver-reason" onChange={event => setWaiverReason(event.target.value)} value={waiverReason} />
      <label htmlFor="waiver-policy">Policy basis</label><input id="waiver-policy" onChange={event => setPolicyBasis(event.target.value)} value={policyBasis || waiverOptions[0]?.policyBasis || ""} />
      <Button isDisabled={waive.state.status === "pending" || !waiverReason.trim() || waiverOptions.length === 0} type="submit" variant="primary">{waive.state.status === "pending" ? "Waiving verification check" : "Waive verification check"}</Button>
      <FormFeedback feedback={commandFeedback(waive.state)} />
    </form> : null}
  </div>;
}

function completeOption(option: object, fields: string[]) {
  const values = option as Record<string, unknown>;
  return fields.every((field) => typeof values[field] === "string" && values[field] !== "");
}
