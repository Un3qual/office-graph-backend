## Context

The persistence model requires Office Graph to avoid polymorphic local
references, keep product data typed and relational, preserve operation
correlation, and make rich text and ordered placement revision-ready. It also
narrows the first schema to explicit task-list ordering and rich text block
ordering while preserving a path to later shared placement behavior.

This change records guardrails for that later shared placement path, but it
does not make ordered placement the next active planning or implementation
lane. No first product surface currently justifies generic graph-addressable
placement tables. Any future ordering implementation must therefore arrive
through a later accepted OpenSpec change instead of being pulled into the
current backend or product slice.

## Goals / Non-Goals

**Goals:**

- Define explicit placement scope, collection identity, membership identity,
  lifecycle, strategy, and parent/child behavior.
- Define how reusable graph-addressable placement tables and typed
  domain-owned placement tables share one contract while preserving concrete
  foreign keys.
- Define sortable position keys, insertion, move, conflict, uniqueness,
  rebalance, and repair semantics.
- Define derived dense ordinals and ordered projection behavior without making
  display indexes authoritative.
- Define operation, revision, audit, domain-event, and realtime traceability.
- Preserve additive migration readiness from v1 task-list and rich text block
  ordering.

**Non-Goals:**

- No Phoenix, Ash, Ecto, database migration, GraphQL, JSON API, React, Oban,
  realtime, or agent-runtime implementation.
- No final column list, module tree, resolver shape, background job code, or
  position-key library code.
- No generic "move any resource" mutation that bypasses typed domain actions.
- No strategy-specific extension tables for grids, swimlanes, boards,
  galleries, topological ordering, external-provider order sync, or live
  collaborative ordering until a later accepted change proves the semantics.
- No persisted render cache or projection read-model implementation.

## Decisions

### 1. Model placement as scoped collection membership, not authorization

An ordered collection represents an ordered relationship owned by a scope and
domain. It is not a tenant, workspace, initiative, grant, or authorization
boundary. A collection should carry organization scope, optional workspace,
initiative and workstream scope where applicable, collection kind, structure
kind, ordering strategy, lifecycle state, and one explicit owner reference.

The owner reference should be a concrete graph identity foreign key when the
owner is graph-addressable. Typed embedded or high-volume domains may instead
own a concrete typed collection table such as rich text document block order.
Items inside the collection keep their own authorization, lifecycle,
sensitivity, and typed resource rules. Ordered projections must filter items
through those rules before presentation.

Alternatives considered:

- **Treat collection as an access container:** This would confuse ordering
  with authorization and could leak restricted siblings through list behavior.
- **Store ordering directly on every item only:** This is simple for one list,
  but weak for nested structures, membership lifecycle, history, and future
  shared command semantics.

### 2. Defer generic storage until a concrete product surface exists

Generic graph-addressable placement tables should not be introduced for the
current slice. They become appropriate only when an accepted product surface
requires one ordered collection to hold graph-addressable items across typed
domains and when typed placement tables would create worse duplication or
weaker semantics.

Until then, task-list ordering, rich text block ordering, and any near-term
manual ordering should remain domain-owned, skeletal, or deferred. The shared
contract can exist as design guidance, but storage, public APIs, position-key
libraries, projection caches, jobs, and migrations require a later accepted
change that names the product surface and proves the need.

Alternatives considered:

- **Pick a generic surface now:** This would force storage and API decisions
  before the product surface has proved it needs cross-domain ordering.
- **Delete the future contract entirely:** This avoids current planning work
  but loses useful guardrails against polymorphic owner/item storage and raw
  ordinal writes when ordering returns.

### 3. Use a shared contract with concrete storage families

The reusable graph-addressable storage family should be shaped around:

- `ordered_collections` for collection identity, scope, kind, strategy,
  lifecycle, owner graph identity, and optimistic collection version.
- `ordered_placements` for stable membership identity, collection, item graph
  identity, current lifecycle, current parent placement when nested, current
  position key, lock version, and create/delete operation references.
- `ordered_placement_versions` for historical position key, parent placement,
  lifecycle state, move intent, basis versions, validity or supersession, and
  operation correlation.

The current fields on `ordered_placements` are an indexed read surface for
active ordering; version rows preserve reconstruction. They must be updated by
the same domain command and operation correlation. If that denormalization
ever becomes unsafe for a specific domain, that domain may use a current-view
or materialized-current table as long as the revision contract remains
reconstructable.

Typed domains should use concrete placement tables that implement the same
columns and semantics with typed foreign keys. Examples include task-list
ordering and rich text block ordering. Shared code may provide value objects,
validators, command helpers, and position-key functions, but persistence
should not collapse typed domains into polymorphic owner/item pairs.

Alternatives considered:

- **One generic table for every ordered thing:** Reuses code but loses SQL
  constraints and domain-specific validation for embedded or high-volume
  structures.
- **Separate unrelated ordering implementations forever:** Preserves concrete
  foreign keys but duplicates conflict, rebalance, revision, and projection
  behavior.

### 4. Make domain commands own insertion and moves

Placement writes should be explicit domain commands such as insert task in
workstream list, move rich text block, move gallery photo, or reorder section.
Callers should provide placement intent: target collection, item, optional
parent placement, before and/or after placement, observed collection version,
observed placement versions, idempotency key when applicable, and reason. They
should not be required to generate position keys.

Commands must validate organization and scope, item eligibility, parent
membership, cycle prevention, sibling lifecycle, before/after consistency,
typed domain lifecycle, authorization, and sensitivity obligations before
writing placement state. Moving an item without content changes creates new
placement version state, not a new content revision.

If a command needs to create the collection and first placement together, it
must do so in one transaction. If any part fails, no collection, placement,
revision, audit, domain event, or projection invalidation record becomes
visible.

Alternatives considered:

- **Expose raw position-key mutation to clients:** Faster to wire, but lets
  clients encode storage strategy and makes future strategy changes harder.
- **Use dense ordinal commands as the write contract:** Easy for UI forms, but
  fragile under concurrency and filtered views.

### 5. Use opaque lexicographic fractional position keys first

If a later accepted change introduces reusable manual ordering, the first
reusable strategy should use lexicographically sortable fractional strings
generated over a fixed ASCII alphabet and compared with bytewise database
semantics. Keys are internal ordering values, not user-facing numbers. APIs may
expose opaque placement cursors or relative placement references, but clients
should not depend on key format.

Insertion generates a key between neighboring active siblings under the same
collection and parent. Prepend and append use the same generator with one
missing neighbor. The implementation should set a maximum accepted key length
and a minimum gap policy; when concentrated inserts make the key too long or
the gap too small, the command either rebalances the sibling range in the same
operation or schedules a domain rebalance depending on the product path.

Floating-point positions and decimal strings should not be used for durable
placement keys. They are harder to reason about across databases, collations,
precision, and deterministic repair.

Alternatives considered:

- **Dense integers:** Simple to inspect but require frequent renumbering and
  broad write conflicts.
- **Floating ranks:** Compact but vulnerable to precision and serialization
  edge cases.
- **Provider-specific order tokens:** Useful for import provenance, but not a
  stable Office Graph ordering strategy.

### 6. Enforce uniqueness and conflicts at the placement boundary

Active placement uniqueness should prevent two active memberships for the
same item in a collection unless the collection kind explicitly allows
duplicates. Active key uniqueness should be scoped by collection, parent
placement, lifecycle state, and position key. Because SQL `NULL` handling can
weaken parent-scoped uniqueness, implementations should use an explicit root
sentinel, generated parent scope key, or equivalent expression index for root
siblings.

Commands should use optimistic collection and placement version checks. On a
conflict, the command may reload latest sibling state and retry only when the
user or agent intent remains unambiguous, such as "move before placement X"
where X still exists in the same parent. If the target disappeared, moved to a
different parent, changed lifecycle, or policy context changed, the command
must return a conflict or create a change proposal instead of silently
overwriting another move.

Alternatives considered:

- **Global locks for every reorder:** Strong but too limiting for unrelated
  collections and high-activity boards.
- **Last-write-wins:** Simple but loses user intent and undermines audit and
  revision history.

### 7. Treat rebalance and repair as domain operations

Rebalancing rewrites position keys for active siblings while preserving their
relative order. It should operate within one collection and parent range, use
one operation correlation record, create placement version rows for affected
placements, emit projection invalidation, and avoid content revisions.

Repair is for inconsistent state: duplicate active keys, missing current
versions, orphaned parent placements, impossible lifecycle combinations, or
broken denormalized current fields. A repair job may detect and report these
states automatically. It may perform deterministic repairs only when all
affected records are in one authorized organization and the repair can be
proven from placement versions. Otherwise it should mark the collection
degraded, write audit/operation evidence, and require an explicit
administrator or support workflow.

Alternatives considered:

- **Silent background renumbering:** Keeps lists looking healthy but hides
  product history and can surprise active users.
- **Manual-only repair:** Safer but leaves recoverable mechanical corruption
  unresolved for too long.

### 8. Derive ordinals and ordered projections from placement truth

Dense ordinals, list numbers, card indexes, slide numbers, and display row
numbers are derived from current active placement order. They are not durable
write inputs or identity. Query-backed projections should compute display
ordinals with window functions or equivalent after applying tenant, scope,
authorization, sensitivity, lifecycle, and tombstone filters. When policy does
not permit revealing hidden siblings, visible ordinals should be relative to
the authorized result rather than absolute positions in the full collection.

Persisted ordinal read models may be introduced later for stable high-traffic
surfaces. Such read models must identify source placement records, source
operation watermark, authorization and sensitivity inputs, invalidation
events, staleness behavior, and rebuild path. Pagination should use stable
placement cursors or source watermarks rather than treating dense ordinals as
durable offsets.

Alternatives considered:

- **Persist dense ordinals as truth:** Convenient for display but expensive
  and conflict-prone under inserts and filtered reads.
- **Expose absolute hidden-aware list positions:** Useful for debugging but
  risks leaking restricted siblings.

### 9. Link placement operations to operation, revision, audit, and events

Every placement-changing command should create or reuse one operation
correlation record. Placement version rows, typed aggregate revisions, domain
events, realtime invalidation events, and change proposal results should
reference that operation.

Revision history should link to the placement version state that reconstructs
the move or rebalance. It should not copy full list snapshots unless a domain
explicitly needs snapshot records for performance or legal reconstruction.
Audit records are required for policy-sensitive placement behavior, including
cross-scope moves, restricted item exposure, administrative repair, restore,
purge-adjacent actions, external writes, approval-gated moves, and sensitive
agent actions. Routine low-risk reorders can rely on revisions and operation
correlation unless policy requires durable audit.

Alternatives considered:

- **Audit every reorder:** Too noisy for normal editing and document work.
- **Only store current placement:** Fast but cannot explain moves,
  rebalances, conflicts, or repair.

### 10. Migrate from v1 ordering additively

Any future implementation should not replace task-list and rich text block
ordering records just to introduce shared behavior. Instead, it should:

1. Introduce shared position-key value types, validation, and command
   contracts.
2. Wrap existing task-list and rich text placement records through domain
   adapters that expose the shared placement contract.
3. Add missing compatibility fields such as operation references, lock
   versions, lifecycle, parent scope keys, or version rows through typed
   migrations.
4. Backfill deterministic placement versions from current order where history
   did not yet exist, clearly marking the backfill operation.
5. Add generic graph-addressable placement tables only for product surfaces
   that truly need cross-domain collection membership.

Strategy-specific extension tables should be created only after a surface
needs their semantics. For example, board columns, swimlanes, grid cells,
gallery crop/focal metadata, and topological dependency order each need typed
requirements before storage exists.

Alternatives considered:

- **Cut over all v1 ordering into generic placement tables immediately:**
  Creates churn before the shared behavior has enough real usage.
- **Leave each domain isolated indefinitely:** Avoids migration work but makes
  conflict, rebalance, audit, and projection behavior inconsistent.

## Risks / Trade-offs

- [Risk] Shared placement becomes a generic schema escape hatch. ->
  Mitigation: require typed domain commands, concrete foreign keys, and later
  accepted requirements for new strategy-specific storage.
- [Risk] Position-key implementation details leak into clients. ->
  Mitigation: expose relative move intent and opaque cursors, not key
  generation responsibilities.
- [Risk] Rebalance writes surprise users during active editing. ->
  Mitigation: scope rebalances to one sibling range, use optimistic checks,
  emit realtime invalidation, and preserve relative order under one operation.
- [Risk] Derived ordinals leak restricted siblings. -> Mitigation: compute
  visible ordinals after authorization filtering unless policy explicitly
  permits absolute collection positions.
- [Risk] Backfilled placement history looks like user-authored history. ->
  Mitigation: use explicit backfill operation records, source markers, and
  revision metadata.

## Migration Plan

This change does not create migrations and does not select ordering as the next
implementation lane. Later accepted implementation work should be additive:

1. Add shared key and command primitives without changing storage.
2. Add missing compatibility fields to v1 domain-owned ordering tables.
3. Backfill placement versions and operation references for existing records.
4. Introduce generic graph-addressable placement tables only for the first
   accepted cross-domain ordered surface.
5. Add read models, rebalance workers, repair workers, and strategy extension
   tables only when their corresponding requirements are accepted.

Rollback should preserve existing domain-owned ordering as the source of truth
until the shared placement contract is proven. Backfills should be reversible
or superseded by explicit repair operations rather than destructive rewrites.

## Open Questions

- Which later product surface, if any, first justifies generic
  graph-addressable placement tables instead of typed domain-owned placement
  tables?
- Which PostgreSQL collation or explicit bytewise comparison mechanism will be
  used for position keys in migrations?
- Which surfaces need persisted ordinal read models rather than query-backed
  ordinals?
- Which placement commands require durable audit by default versus revision
  and operation correlation only?
