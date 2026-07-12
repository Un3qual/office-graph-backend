# manual-intake-adapter Specification

## Purpose
TBD - created by archiving change design-ingestion-and-integrations. Update Purpose after archive.
## Requirements
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
  duplicate signals, tasks, findings, evidence, or change proposals

### Requirement: Manual Intake Uses Integration Path
Manual intake SHALL use the same normalization, idempotency, replay, and domain
action routing shape as future provider adapters.

#### Scenario: Manual intake becomes a signal
- **WHEN** manual intake produces an Office Graph signal
- **THEN** it MUST pass through the shared adapter output contract and domain
  action path rather than writing graph truth tables directly

### Requirement: Manual Intake Has Supported Product Commands

Office Graph SHALL expose manual intake submission through authenticated
GraphQL and JSON API commands over the Integrations domain boundary.

#### Scenario: Operator submits manual intake

- **WHEN** an authorized operator submits body, source identity, replay
  identity, and idempotency key
- **THEN** both API families MUST apply the existing archive, normalization,
  duplicate, operation-correlation, authorization, and proposed-change rules
  and return the normalized event and proposed-change identities

#### Scenario: Intake replay conflicts

- **WHEN** the same source and replay identity arrives with different content
- **THEN** both API families MUST return the existing stable replay conflict and
  MUST NOT create a second accepted event
