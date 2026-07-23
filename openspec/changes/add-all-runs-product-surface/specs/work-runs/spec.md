## ADDED Requirements

### Requirement: Work Runs Have An Authorized Bounded Index Projection

Office Graph SHALL provide a read-only work-run index projection that returns
only safe run-summary fields for the resolved session's authorized organization
and workspace: run id, owning packet id and title, packet-version id and
version number, objective, aggregate/execution/verification states, insertion
time, and a stable source watermark. The projection SHALL require the existing
skeleton-read capability, join packet and packet-version labels in its bounded
list query, and SHALL NOT duplicate `operatorRunState` detail assembly or own a
command.

#### Scenario: Authorized scope receives only its runs

- **WHEN** an authorized session reads the work-run index
- **THEN** it MUST receive only summaries from its resolved organization and
  workspace, and no row, packet label, packet-version label, or watermark from
  another tenant or workspace may appear

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
- **THEN** the index MUST retain a constant query-count bound and MUST NOT load
  packet or packet-version labels one row at a time

### Requirement: Work Run Index Has A Read-Only Relay Connection

Office Graph SHALL expose the bounded index as the forward `operatorRuns(first:, after:)`
Relay connection with `OperatorRunSummary` nodes and existing connection
validation, cursor, and safe-error conventions. It SHALL use the existing
shared `OfficeGraphWeb.RequestSession` resolution unchanged, including the
intentionally deferred bootstrap posture, and SHALL NOT create a route-specific
actor, session, or fallback.

#### Scenario: Client reads a run page

- **WHEN** an authorized client requests `operatorRuns` with a valid forward
  page input
- **THEN** GraphQL MUST return ordered edges, opaque cursors, page information,
  and only the summary fields defined by the index projection

#### Scenario: Client requests a subsequent page

- **WHEN** an authorized client supplies the connection's end cursor as `after`
- **THEN** GraphQL MUST return the next stable page using the projection's
  keyset semantics

#### Scenario: Contract is extended

- **WHEN** the all-runs index is implemented
- **THEN** it MUST add no run mutation, hidden compatibility query, or second
  detailed-run projection; `operatorRunState` remains the detail and activity
  source

#### Scenario: Shared request session resolves the read

- **WHEN** `operatorRuns` or its selected `operatorRunState` detail read
  resolves an actor
- **THEN** it MUST consume the existing shared `RequestSession` resolution
  unchanged and MUST NOT create a route-specific actor, session, bootstrap, or
  fallback
