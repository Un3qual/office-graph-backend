# change-proposal-application Specification

## Purpose
TBD - created by archiving change design-proposed-graph-changes. Update Purpose after archive.
## Requirements
### Requirement: Change Proposal Application Through Domain Actions
Office Graph SHALL apply accepted change proposals through owning domain
actions.

#### Scenario: Change proposal is applied
- **WHEN** a change proposal is valid, authorized, and approved when required
- **THEN** Office Graph MUST call the owning domain action to mutate product
  state and MUST record applied operation reference, result, actor, timestamp,
  and related run or approval when applicable

#### Scenario: Domain action writes related records
- **WHEN** applying a change proposal creates, updates, links, verifies,
  waives, restores, deletes, or writes externally
- **THEN** normal domain behavior MUST produce applicable operation
  correlation, revisions, audit records, authorization decision records,
  evidence, verification results, run events, sync events, or external action
  traces

### Requirement: Change Proposal Does Not Become Truth
Office Graph SHALL distinguish proposal state from accepted product truth.

#### Scenario: Change proposal remains pending or rejected
- **WHEN** a change proposal is pending, invalid, rejected, superseded, or
  expired
- **THEN** Office Graph MUST preserve the proposal for traceability without
  treating the proposed payload as accepted graph or domain state

### Requirement: Proposed Change Sets Have A Supported Apply Command

Office Graph SHALL expose application of the complete manual-intake proposal
set as an authenticated GraphQL and JSON API command.

#### Scenario: Operator applies a proposal set

- **WHEN** an authorized operator submits the normalized event id, complete
  proposal ids, and idempotency key
- **THEN** the command MUST preserve proposal ordering, scope, pending-state,
  completeness, validation, operation, audit, and revision contracts and return
  the applied graph identities

#### Scenario: Proposal set became stale

- **WHEN** any supplied proposal is no longer pending or no longer belongs to
  the submitted event and scope
- **THEN** the command MUST fail as a conflict without applying any remaining
  proposal
