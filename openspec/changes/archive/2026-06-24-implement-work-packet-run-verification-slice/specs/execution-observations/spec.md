## ADDED Requirements

### Requirement: Initial Execution Observations Preserve Source And Trust

Office Graph SHALL persist human/manual and simple provider-like execution
observations with enough source, freshness, and trust information for
verification decisions.

#### Scenario: Observation is recorded

- **WHEN** an authorized actor records a human note, manual status, test
  result, provider check status, or integration job status for selected work
- **THEN** Office Graph MUST record source kind, source identity, observed
  status, normalized status, source timestamp, ingestion timestamp, freshness
  state, trust basis, operation correlation, and related work-run or graph
  references

#### Scenario: Observation source is duplicated

- **WHEN** the same source identity and replay or idempotency key is recorded
  more than once in the same organization and workspace
- **THEN** Office Graph MUST return the existing observation or reject the
  duplicate according to the owning command's idempotency rules

### Requirement: Initial Observations Can Become Evidence Candidates

Office Graph SHALL allow an execution observation to produce an evidence
candidate without treating the observation as accepted evidence by default.

#### Scenario: Observation is relevant to a check

- **WHEN** an observation is linked to a required verification check or work
  run evidence expectation
- **THEN** Office Graph MUST be able to create an evidence candidate that
  references the observation, target check, claim, trust basis, freshness
  state, source, and operation correlation

#### Scenario: Observation is stale or untrusted

- **WHEN** an observation is stale, untrusted, unauthenticated, unrelated to
  the target, or outside the actor's authorized scope
- **THEN** Office Graph MUST NOT accept it as evidence and MUST preserve the
  rejection or missing-requirement reason
