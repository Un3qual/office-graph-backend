## ADDED Requirements

### Requirement: Execution Observation Recording Has Supported Product Commands
Office Graph SHALL expose run observation recording through authenticated
GraphQL and JSON API commands over the Runs domain boundary.

#### Scenario: Operator records an observation
- **WHEN** an authorized operator submits run, check, source graph item,
  provider/source identity, observed and normalized status, freshness, trust,
  rationale, and idempotency data
- **THEN** the command MUST preserve run-contract validation, source replay,
  operation replay, lifecycle updates, and typed observation provenance

#### Scenario: Observation conflicts with its run
- **WHEN** the submitted check, graph item, source identity, or replay input is
  outside the run packet contract or conflicts with an existing observation
- **THEN** the command MUST fail without changing run execution state
