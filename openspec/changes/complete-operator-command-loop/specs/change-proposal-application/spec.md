## ADDED Requirements

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
