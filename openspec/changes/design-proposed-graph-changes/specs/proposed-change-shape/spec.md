## ADDED Requirements

### Requirement: Proposed Change Envelope
Office Graph SHALL represent agent, generated UI, integration, and human graph
mutation proposals as structured proposed graph changes.

#### Scenario: Proposed change is created
- **WHEN** a human, agent, generated UI, manual intake, or integration proposes
  a graph or domain mutation
- **THEN** Office Graph MUST record proposer principal, agent/run/source when
  applicable, source surface, operation kind, target resource or creation
  target, intended domain action, typed payload, preconditions, idempotency
  basis, validation state, approval state, lifecycle state, and operation
  correlation

#### Scenario: Proposed change targets external context
- **WHEN** a proposed change references provider data
- **THEN** it MUST reference external references, raw archive records, or
  provider-neutral resources rather than embedding opaque provider payload as
  the only target identity
