# change-proposal-validation Specification

## Purpose
TBD - created by archiving change design-proposed-graph-changes. Update Purpose after archive.
## Requirements
### Requirement: Change Proposal Validation
Office Graph SHALL validate change proposals before they can be approved
or applied.

#### Scenario: Change proposal is validated
- **WHEN** a change proposal is submitted
- **THEN** validation MUST check operation kind, target existence or allowed
  creation target, payload schema, preconditions, lifecycle transition,
  referenced resources, idempotency basis, and owning-domain constraints

#### Scenario: Change proposal references normalized intake
- **WHEN** a change proposal references a normalized intake event
- **THEN** the referenced event MUST be the accepted canonical event for that
  intake path, and duplicate, skipped, rejected, conflict, or otherwise
  non-accepted events MUST NOT become proposal origins

#### Scenario: Change proposal is invalid
- **WHEN** validation fails
- **THEN** Office Graph MUST preserve the rejected validation state and reason
  without mutating durable graph truth tables

### Requirement: Duplicate Change Proposals
Office Graph SHALL handle duplicate change proposals deterministically.

#### Scenario: Duplicate proposal is submitted
- **WHEN** a proposal repeats the same idempotency basis or proposes the same
  operation against the same target
- **THEN** Office Graph MUST link to the existing proposal, reject the
  duplicate, or merge through an owning-domain rule rather than creating
  ambiguous competing truth mutations
