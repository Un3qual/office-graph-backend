# change-proposal-shape Specification

## Purpose
TBD - created by archiving change design-proposed-graph-changes. Update Purpose after archive.
## Requirements
### Requirement: Change Proposal Envelope
Office Graph SHALL represent agent, generated UI, integration, and human graph
or domain mutation suggestions as structured change proposals.

#### Scenario: Change proposal is created
- **WHEN** a human, agent, generated UI, manual intake, or integration proposes
  a graph or domain mutation
- **THEN** Office Graph MUST record proposer principal, agent/run/source when
  applicable, source surface, operation kind, target resource or creation
  target, intended domain action, typed payload, preconditions, idempotency
  basis, validation state, approval state, lifecycle state, and operation
  correlation

#### Scenario: Change proposal targets external context
- **WHEN** a change proposal references provider data
- **THEN** it MUST reference external references, raw archive records, or
  provider-neutral resources rather than embedding opaque provider payload as
  the only target identity
