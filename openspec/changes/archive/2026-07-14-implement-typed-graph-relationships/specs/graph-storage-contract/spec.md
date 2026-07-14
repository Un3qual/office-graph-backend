## ADDED Requirements

### Requirement: Persisted Edges Reference Canonical Definitions
Office Graph SHALL persist graph relationships with a concrete definition
reference, organization and governing scope, lifecycle, operation, provenance,
and concrete graph-item endpoints.

#### Scenario: Relationship row is written
- **WHEN** a WorkGraph command persists a relationship
- **THEN** the row MUST reference a canonical definition and MUST NOT use a
  free-form relationship string as its authority

#### Scenario: Substantive relationship context exists
- **WHEN** a relationship needs an explanation, approval, finding, evidence, or
  payload
- **THEN** that fact MUST remain in an owning typed resource linked by the edge
  rather than becoming edge metadata

### Requirement: Legacy Relationship Vocabulary Is Migrated Deterministically
Office Graph SHALL replace the current unreleased relationship strings with the
canonical direction and keys during migration.

#### Scenario: Produced task edge is backfilled
- **WHEN** migration encounters `produced_task` from a signal to a task
- **THEN** it MUST store `generated_from` from the task to the signal after
  validating both endpoint kinds

#### Scenario: Review-finding edge is backfilled
- **WHEN** migration encounters `has_review_finding` from a task to a finding
- **THEN** it MUST store `review_finding_for` from the finding to the task and
  retain the relationship identity or an explicit replacement mapping

#### Scenario: Verification edge is backfilled
- **WHEN** migration encounters `requires_verification` with compatible finding
  and check endpoints
- **THEN** it MUST store the canonical `requires_check` definition

#### Scenario: Evidence edges are backfilled
- **WHEN** migration encounters `has_evidence` from a check to an evidence item
  or `references_artifact` from an evidence item to an artifact
- **THEN** it MUST store canonical `evidenced_by` or `generated_from`
  relationships respectively after validating endpoint kinds

#### Scenario: Unknown legacy value exists
- **WHEN** migration encounters any unrecognized relationship value or
  incompatible endpoint kinds
- **THEN** it MUST abort with a bounded diagnostic and MUST NOT partially remove
  the legacy column
