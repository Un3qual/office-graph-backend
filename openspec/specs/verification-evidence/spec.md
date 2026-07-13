# verification-evidence Specification

## Purpose
Define explicit checks and admissible evidence used to verify completion.
## Requirements
### Requirement: Verification Uses Explicit Checks

Office Graph SHALL verify completion through explicit verification checks
rather than work-run status, agent-execution status, provider status, or human
claim alone.

#### Scenario: Completion claim is evaluated

- **WHEN** a task, work packet, requirement, change proposal, monitored
  outcome, or other graph item is claimed complete
- **THEN** Office Graph MUST evaluate the required verification checks,
  accepted evidence, failed checks, stale inputs, waivers, approval gates, and
  policy basis before recording verified completion

#### Scenario: Execution succeeds but check is missing

- **WHEN** a work run, agent execution, provider observation, or human handoff
  succeeds but a required verification check has no accepted evidence or valid
  waiver
- **THEN** Office Graph MUST keep the completion unverified and expose the
  missing check or evidence reason

### Requirement: Evidence Candidates Require Acceptance

Office Graph SHALL distinguish evidence candidates from accepted evidence.

#### Scenario: Candidate is produced

- **WHEN** an agent execution, work run, provider observation, human note,
  artifact, approval gate, monitoring outcome, or change-proposal application
  produces material that may prove a claim
- **THEN** Office Graph MUST record or be able to record an evidence candidate
  with source, target, claim, sensitivity, freshness, trust basis, and related
  run, execution, observation, artifact, approval, or operation references

#### Scenario: Candidate is accepted

- **WHEN** policy or an authorized principal accepts an evidence candidate for
  a specific verification check or completion claim
- **THEN** Office Graph MUST record accepted evidence with the check or claim
  it supports, acceptance basis, actor or policy, timestamp, operation
  correlation, and any redaction or visibility constraints

### Requirement: Verification Results Preserve Decision Basis

Office Graph SHALL record verification results with enough context to explain
why completion was accepted, rejected, waived, stale, or partial.

#### Scenario: Verification result is recorded

- **WHEN** Office Graph records a verification result for a target
- **THEN** the result MUST identify target, required checks, satisfied checks,
  failed checks, waived checks, accepted evidence, rejected or stale evidence,
  actor or policy basis, relevant work run or observations, operation
  correlation, timestamp, and resulting verification state

#### Scenario: Direct completion records decision basis

- **WHEN** a direct verification completion records accepted evidence without a
  work run or evidence candidate
- **THEN** Office Graph MUST still populate the verification result's target,
  actor, policy basis, operation correlation, timestamp, accepted evidence, and
  resulting verification state

#### Scenario: Verification becomes stale

- **WHEN** accepted evidence, source observations, work packet versions,
  selected work targets, policy, required checks, artifacts, or relevant graph
  records change after verification
- **THEN** Office Graph MUST be able to mark the verification result stale,
  superseded, or requiring re-verification while preserving the original
  decision record

### Requirement: Waivers Are Governed Exceptions

Office Graph SHALL represent check waivers as governed exceptions rather than
as evidence.

#### Scenario: Check is waived

- **WHEN** a principal or policy waives a required verification check
- **THEN** Office Graph MUST record target, check, requester, approver or
  policy basis, reason, expiration or review rule, separation-of-duties state,
  related approval gate, related work run or observation when applicable,
  operation correlation, and audit linkage

#### Scenario: Waiver allows completion

- **WHEN** policy permits a waived check to allow completion
- **THEN** Office Graph MUST distinguish completion accepted with waiver from
  completion verified by evidence in APIs, projections, audit, and future
  evidence chains

### Requirement: Approval Gates Can Satisfy Or Unblock Checks

Office Graph SHALL let governed approval gates satisfy or unblock verification
only according to policy.

#### Scenario: Approval gate satisfies a check

- **WHEN** a graph-native approval gate or imported provider-native approval is
  relevant to a verification check
- **THEN** Office Graph MUST validate approver authority, scope, source,
  separation-of-duties, expiration, and policy relevance before linking the
  approval as accepted evidence or a check-unblocking decision

#### Scenario: Approval is insufficient

- **WHEN** an approval lacks required authority, has stale source context,
  violates separation of duties, maps to the wrong scope, or cannot prove the
  check under Office Graph policy
- **THEN** Office Graph MUST keep the verification check unsatisfied and
  preserve the insufficiency reason

### Requirement: Initial Evidence Candidates Require Acceptance

Office Graph SHALL implement a candidate-to-accepted evidence path for
packet-backed runs and direct verification workflows.

#### Scenario: Candidate is created

- **WHEN** a work run, execution observation, human note, artifact, or test
  result produces material that may prove a required check
- **THEN** Office Graph MUST create an evidence candidate with source, target
  check or claim, related work run, related observation or artifact, freshness,
  trust basis, sensitivity, operation correlation, and candidate state

#### Scenario: Candidate is accepted

- **WHEN** policy or an authorized actor accepts an evidence candidate for a
  verification check
- **THEN** Office Graph MUST create or update accepted evidence linked to the
  candidate, check, work run when present, acceptance actor or policy basis,
  acceptance operation, timestamp, and visibility constraints, and MUST link the
  check graph item to the evidence graph item plus the evidence graph item to
  the candidate artifact graph item when an artifact is present, and MUST record
  audit and revision trace rows for the accepted evidence and verification result

#### Scenario: Accepted evidence is command-owned

- **WHEN** accepted evidence is linked to a candidate, work run, acceptance
  operation, accepted actor, policy basis, and timestamp
- **THEN** Office Graph MUST derive those accepted-evidence links through the
  evidence acceptance command instead of exposing a simple resource create that
  can bypass candidate validation, verification-result creation, audit traces,
  graph relationships, or run lifecycle updates

#### Scenario: Runless candidate is accepted

- **WHEN** policy or an authorized actor accepts passed evidence for a candidate
  that is linked to a verification check but not to a specific work run
- **THEN** Office Graph MUST satisfy the check-level verification state,
  recompute completion for the parent review finding and task, and leave
  unrelated packet-backed work-run required-check rows unchanged, while following
  the same completion-graph lock order as direct verification completion before
  inserting the no-run verification result

#### Scenario: Runless non-passed candidate is rejected

- **WHEN** policy or an authorized actor attempts to accept non-passed evidence
  for a candidate linked to a verification check but not to a specific work run
- **THEN** Office Graph MUST reject the acceptance before creating accepted
  evidence or a no-run verification result so a later passed runless candidate
  can satisfy the check

#### Scenario: Candidate result is unsupported

- **WHEN** policy or an authorized actor attempts to accept evidence with a
  result outside the supported verification-result vocabulary
- **THEN** Office Graph MUST reject the acceptance before creating accepted
  evidence, verification results, or failed work-run state

### Requirement: Initial Verification Results Link Evidence To Runs

Office Graph SHALL record verification results that explain whether a packet or
work run is verified, unverified, stale, failed, or partial.

#### Scenario: Verification result is recorded

- **WHEN** accepted evidence satisfies or fails a required verification check
  for a packet-backed work run
- **THEN** Office Graph MUST record a verification result that identifies the
  check, accepted evidence, target packet version or graph item, related work
  run, operation correlation, actor or policy basis, timestamp, result state,
  and explanatory reason, and the initial supported result vocabulary MUST
  include passed and failed outcomes

#### Scenario: Verification is missing evidence

- **WHEN** a work run has no accepted evidence or passing result for a
  required check
- **THEN** Office Graph MUST keep the work run and packet completion
  unverified and MUST expose the missing check or evidence reason

### Requirement: Initial Evidence Acceptance Is Authorized

Office Graph SHALL enforce authorization and scope validation before evidence
acceptance changes verification state.

#### Scenario: Unauthorized actor accepts evidence

- **WHEN** an actor lacks the required organization, workspace, capability,
  policy basis, or scope relationship to accept evidence
- **THEN** Office Graph MUST reject the acceptance command and MUST NOT create
  accepted evidence, verification results, or verified work-run state

#### Scenario: Evidence target crosses scope

- **WHEN** an evidence candidate, verification check, packet version, work run,
  or artifact belongs to a different organization or unauthorized workspace
- **THEN** Office Graph MUST reject the command instead of linking cross-scope
  records through verification

### Requirement: Evidence Commands Are Step Specific

Office Graph SHALL expose evidence candidate creation and evidence acceptance as
separate authenticated GraphQL and JSON API commands.

#### Scenario: Operator creates an evidence candidate

- **WHEN** an authorized operator submits a run, required check, eligible
  observation, claim, source, freshness, trust, sensitivity, and idempotency key
- **THEN** the command MUST create or replay one candidate without satisfying
  the check

#### Scenario: Operator accepts evidence

- **WHEN** an authorized operator submits a candidate, title, body, passed or
  failed result, policy basis, and idempotency key
- **THEN** the command MUST preserve candidate/run/check consistency, audit,
  revision, result-slot, and run-verification rules and return the resulting
  evidence and verification state

### Requirement: Required Checks Can Be Governedly Waived

Office Graph SHALL allow a specifically authorized operator to waive a required
verification check with durable reason and policy provenance.

#### Scenario: Operator waives a required check

- **WHEN** a session with `verification.waive` submits a pending run-required
  check, nonblank reason, policy basis, expected run state, and idempotency key
- **THEN** Office Graph MUST record a waived verification result, actor,
  operation, reason, and policy basis; satisfy only that run-required check; and
  recompute run verification state

#### Scenario: Waiver is not allowed

- **WHEN** the check is already satisfied, is outside the run packet contract,
  the run state is stale, or the session lacks `verification.waive`
- **THEN** Office Graph MUST reject the waiver without changing check or run
  state and MUST preserve the required authorization decision
