## MODIFIED Requirements

### Requirement: Work Runs Have An Authorized Bounded Index Projection

Office Graph SHALL provide a read-only work-run index projection that returns
only this safe output for the resolved session's authorized organization and
workspace: run id, objective, aggregate state, execution state, verification
state, insertion time, and owning packet id and title. Runs created without a
selected packet version SHALL remain visible in the index and inspectable
through `operatorRunState`. The projection SHALL require the existing
skeleton-read capability and use one actor-authorized run-page read plus one
actor-authorized, scope-filtered, page-batched packet read. It SHALL NOT load
enrichment per row, duplicate `operatorRunState` detail assembly, or own a
command.

#### Scenario: Authorized scope receives only its runs

- **WHEN** an authorized session reads the work-run index
- **THEN** it MUST receive only summaries from its resolved organization and
  workspace, and no run or packet label from another tenant or workspace may
  appear

#### Scenario: Scoped run has no packet version

- **WHEN** an authorized scoped run represents selected graph work without a
  packet version
- **THEN** the index MUST return the run and its packet and the selected detail
  MUST represent the absent packet version

#### Scenario: Read authorization is denied

- **WHEN** the resolved session lacks the skeleton-read capability
- **THEN** the index MUST reject the read using the existing safe authorization
  shape and MUST NOT return a partial or unscoped row set

#### Scenario: Index uses stable newest-first keyset pagination

- **WHEN** an authorized reader requests a forward page and then requests its
  next page after newer runs are inserted
- **THEN** the index MUST order rows by `inserted_at DESC, id DESC`, encode
  that total order in its opaque cursor, and return the original continuation
  without skipping or duplicating preexisting rows

#### Scenario: Cursor or page limit is invalid

- **WHEN** a caller supplies a malformed, stale, unsupported, or invalid cursor
  or a limit outside the supported connection bounds
- **THEN** the index MUST return the existing safe validation shape and MUST
  NOT issue an unbounded or ambiguously ordered read

#### Scenario: Index size grows

- **WHEN** the number of runs in the authorized scope grows while the requested
  page size stays fixed
- **THEN** the index MUST retain its constant bound of one actor-authorized
  run-page read plus one actor-authorized, scope-filtered, page-batched packet
  read and MUST NOT load packet data one row at a time
