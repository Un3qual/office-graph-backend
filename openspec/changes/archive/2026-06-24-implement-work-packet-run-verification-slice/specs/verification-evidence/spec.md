## ADDED Requirements

### Requirement: Initial Evidence Candidates Require Acceptance

Office Graph SHALL implement a candidate-to-accepted evidence path for the
first packet-run-verification slice.

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
  acceptance operation, timestamp, and visibility constraints

### Requirement: Initial Verification Results Link Evidence To Runs

Office Graph SHALL record verification results that explain whether a packet or
work run is verified, unverified, stale, failed, or partial.

#### Scenario: Verification result is recorded

- **WHEN** accepted evidence satisfies or fails a required verification check
  for a packet-backed work run
- **THEN** Office Graph MUST record a verification result that identifies the
  check, accepted evidence, target packet version or graph item, related work
  run, operation correlation, actor or policy basis, timestamp, result state,
  and explanatory reason

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
