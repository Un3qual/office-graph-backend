## ADDED Requirements

### Requirement: Placement Operations Are Correlated
Office Graph SHALL defer placement-changing command implementation until a
later accepted ordering change, and any future placement-changing command SHALL
link to an operation correlation record.

#### Scenario: Placement command succeeds
- **WHEN** a later accepted ordering implementation inserts, moves, deletes,
  restores, rebalances, repairs, or backfills placement state
- **THEN** every placement version, typed aggregate revision, domain event,
  realtime invalidation event, change proposal result, and derived projection
  update created by that command MUST reference the same operation correlation
  identifier

#### Scenario: Placement command is idempotent
- **WHEN** a placement command is retried with the same idempotency basis after
  a timeout, network retry, agent retry, or provider replay
- **THEN** Office Graph MUST resolve it to the original operation result or
  reject it as a conflicting command without creating duplicate active
  placement state

### Requirement: Placement Revisions Reconstruct Moves
Office Graph SHALL preserve enough typed placement version and revision state
to reconstruct meaningful historical order changes.

#### Scenario: Historical order is requested
- **WHEN** an authorized user, agent, export, restore workflow, or
  investigation asks how an ordered collection looked at a prior operation or
  revision
- **THEN** Office Graph MUST reconstruct the order from typed placement
  versions, lifecycle state, supersession or validity ranges, and operation
  correlation without parsing a generic JSON version payload

#### Scenario: Placement and content change together
- **WHEN** one user action changes item content and moves that item in an
  ordered collection
- **THEN** the content revision and placement version MUST remain separate
  typed records that share the same operation correlation identifier

### Requirement: Placement Audit Is Policy Sensitive
Office Graph SHALL write durable audit records for placement operations that
are policy-sensitive while keeping routine reorder history in revisions and
operation correlation.

#### Scenario: Sensitive placement operation occurs
- **WHEN** a placement operation crosses scope boundaries, exposes restricted
  context, uses elevated administrative repair, restores or purges adjacent
  state, performs an external write, requires approval, or is performed by a
  sensitive agent authority
- **THEN** Office Graph MUST write the audit and authorization decision records
  required by policy and link them to the placement operation

#### Scenario: Routine reorder occurs
- **WHEN** an authorized low-risk user reorders visible items within one
  ordinary collection and no policy requires durable audit
- **THEN** Office Graph MAY rely on placement versions, typed revisions,
  domain events, and operation correlation without writing a separate audit
  record

### Requirement: V1 Ordering Migrates Additively
Office Graph SHALL migrate from first-cut task-list and rich text block
ordering through additive typed changes rather than destructive replacement.

#### Scenario: Existing domain-owned ordering is adopted
- **WHEN** reusable placement behavior is introduced after task-list or rich
  text block ordering already exists
- **THEN** Office Graph MUST preserve the domain-owned ordering records,
  add missing compatibility fields or version tables through typed migrations,
  and expose the records through the shared placement contract

#### Scenario: Placement history is backfilled
- **WHEN** current ordering records need initial placement version history for
  the shared contract
- **THEN** Office Graph MUST create deterministic backfill operation records
  and placement versions that are distinguishable from user-authored reorder
  history

### Requirement: Deferred Placement Work Requires Later Acceptance
Office Graph SHALL defer strategy-specific placement storage and broad generic
APIs until a later accepted change defines their concrete semantics.

#### Scenario: Strategy-specific extension is requested
- **WHEN** grids, swimlanes, board columns, gallery crop or focal metadata,
  topological dependency order, external-provider order writeback, live
  collaborative ordering, or CRDT-style order merging is requested
- **THEN** Office Graph MUST require a later accepted OpenSpec change before
  adding strategy-specific tables, background workers, API commands, or
  projection caches for that behavior

#### Scenario: Generic placement mutation is requested
- **WHEN** a caller asks for one API that can reorder any resource in any
  collection
- **THEN** Office Graph MUST route the request through typed domain commands
  or change proposals and MUST NOT provide a mutation path that bypasses typed
  lifecycle, authorization, revision, and audit rules
