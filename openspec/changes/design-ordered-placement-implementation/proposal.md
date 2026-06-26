## Why

Office Graph already narrowed MVP ordering to domain-owned task-list and rich
text block ordering, but reusable ordered placement still needs an
implementation design before shared APIs, migrations, position-key libraries,
rebalance jobs, projections, or strategy extensions are built.

## What Changes

- Define the reusable ordered placement implementation contract for explicit
  placement scope, collection identity, concrete owner/item references,
  membership lifecycle, and strategy selection.
- Define sortable position-key generation, insertion and move commands,
  optimistic conflict handling, scoped uniqueness, rebalancing, and repair
  behavior.
- Define dense ordinal and ordered projection behavior as derived state over
  durable placement truth records.
- Define how placement commands link to operation correlation, typed revision
  history, audit records, domain events, realtime updates, and future
  migrations from v1 domain-owned ordering.
- Explicitly defer product code, database migrations, Ash resources, GraphQL
  and JSON API command shapes, Oban jobs, render caches, grid placement,
  swimlanes, topological ordering, and strategy-specific extension tables
  until later implementation tasks.

## Capabilities

### New Capabilities

- `ordered-placement-implementation`: Defines reusable ordered placement
  scope, storage ownership, concrete foreign-key strategy, insertion and move
  semantics, lifecycle, and uniqueness rules.
- `placement-position-keys`: Defines sortable position keys, key generation,
  conflict behavior, rebalancing, and repair requirements.
- `placement-ordinal-projections`: Defines derived dense ordinals, ordered
  projection reads, pagination, authorization filtering, read-model
  invalidation, and realtime update posture.
- `placement-traceability-migration`: Defines operation, revision, audit, and
  domain-event traceability for placement operations plus additive migration
  readiness and explicit deferrals.

### Modified Capabilities

- None. Existing durable specs are not changed by this planning change; the
  new capability builds on the active persistence, revision/audit, code
  organization, graph projection, and UI projection contracts.

## Impact

- Affects future OpenSpec planning for ordered placement context boundaries,
  Ash actions, Ecto migrations, position-key utilities, command validation,
  repair/rebalance jobs, derived ordinal projections, realtime updates,
  revisions, audit records, and migration backfills.
- Provides the acceptance contract later implementation work must satisfy
  before generic ordered placement behavior becomes shared infrastructure.
- Does not implement application code, database migrations, APIs, background
  jobs, frontend behavior, render caches, or storage infrastructure.
