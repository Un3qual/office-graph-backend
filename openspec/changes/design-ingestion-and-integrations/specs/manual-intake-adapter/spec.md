## ADDED Requirements

### Requirement: Manual Intake Adapter
Office Graph SHALL use manual pasted intake as the first adapter for the
backend walking skeleton.

#### Scenario: User submits pasted signal
- **WHEN** a user pastes a messy report, review note, bug description, CI
  excerpt, or other text into Office Graph
- **THEN** the intake path MUST create a raw archive reference, normalized
  event envelope, source identity, idempotency basis, actor principal context,
  and intended domain action before creating or proposing graph state

#### Scenario: Manual intake duplicates prior input
- **WHEN** the same manual input is submitted again with the same idempotency
  basis
- **THEN** Office Graph MUST identify the duplicate and avoid creating
  duplicate signals, tasks, findings, evidence, or proposed changes

### Requirement: Manual Intake Uses Integration Path
Manual intake SHALL use the same normalization, idempotency, replay, and domain
action routing shape as future provider adapters.

#### Scenario: Manual intake becomes a signal
- **WHEN** manual intake produces an Office Graph signal
- **THEN** it MUST pass through the shared adapter output contract and domain
  action path rather than writing graph truth tables directly
