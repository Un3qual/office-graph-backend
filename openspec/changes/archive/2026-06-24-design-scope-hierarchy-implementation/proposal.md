## Why

The accepted identity, authorization, audit/revision, code-boundary, and graph
projection designs require typed scope hierarchy and governed scope moves, but
the implementation plan does not yet say how those concerns are coordinated.
This change closes that planning gap before backend migrations or product code
turn scope parentage into durable behavior.

## What Changes

- Add a design-only implementation plan for typed authorization scope rows,
  closure rows, inheritance modes, and ownership boundaries.
- Define how scope moves are validated, made idempotent, operation-correlated,
  audited, revised, and recorded without direct parent-id updates.
- Define closure rebuild and repair planning, including tenant/type/cycle
  checks and safe recomputation of affected ancestor/descendant rows.
- Define how authorization explanation caches, graph projection read models,
  frontend/render caches, work packet context, and realtime invalidation react
  to scope hierarchy changes.
- Defer Phoenix, Ash, Ecto, migration, Oban, GraphQL, JSON API, React, and
  runtime implementation work to later implementation changes.

## Capabilities

### New Capabilities

- `scope-hierarchy-implementation-plan`: Planning requirements for scope table
  ownership, closure row semantics, inheritance modes, repair/rebuild posture,
  and deferred migration/code boundaries.
- `scope-move-operation-plan`: Planning requirements for governed scope move
  commands, validation, idempotency, operation correlation, audit, revision,
  authorization decision, and repair records.
- `scope-projection-invalidation-plan`: Planning requirements for invalidating
  authorization explanations, graph projections, render caches, work packet
  context, and realtime subscribers after scope hierarchy changes.

### Modified Capabilities

- None. This change coordinates implementation planning for accepted
  requirements without changing accepted product behavior.

## Impact

- Affects future backend implementation plans for `OfficeGraph.Authorization`,
  `OfficeGraph.Operations`, `OfficeGraph.Audit`, `OfficeGraph.Revisions`,
  `OfficeGraph.Projections`, work packet projection/context assembly, and
  realtime invalidation.
- Affects future migration planning for authorization scope rows, closure rows,
  scope move records, authorization decision records, audit targets, revision
  rows, repair jobs, and projection/cache invalidation state.
- Does not add product code, migrations, runtime dependencies, APIs, or UI.
