## ADDED Requirements

### Requirement: Work Run Index Storage Matches Its Public Contract
Office Graph SHALL persist non-null aggregate, execution, and verification
state for every work run, including upgraded legacy rows. Unknown legacy state
MUST remain explicit rather than being inferred as a successful or verified
state. The run index storage SHALL provide an index ordered by organization,
workspace, insertion time descending, and run id descending to match the
authorized keyset query.

#### Scenario: Legacy run has incomplete lifecycle state
- **WHEN** an upgraded run has a null aggregate, execution, or verification
  state
- **THEN** migration MUST backfill each missing value to the explicit
  `unknown` label and enforce the non-null lifecycle contract

#### Scenario: Scoped run page is read
- **WHEN** an authorized reader requests a newest-first page for one
  organization and workspace
- **THEN** storage MUST provide the equality scope and descending
  `inserted_at, id` order through the matching composite index
