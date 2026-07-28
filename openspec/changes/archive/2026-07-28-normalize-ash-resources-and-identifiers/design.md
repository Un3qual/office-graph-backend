## Context

Office Graph started this change with 72 UUID-primary-key Ash resources. Most used
`uuid_primary_key`, and many callers also inject `Ecto.UUID.generate/0`, so
ordinary writes allocate UUIDv4 values in the application. The repository runs
PostgreSQL 17, while the pinned Ash 3.29 and AshPostgres 2.10 stack supports
PostgreSQL 18's native `uuidv7()` default. The project owner approved upgrading
the repository-managed development and verification database to PostgreSQL 18
as part of this change.

Relationship declarations are incomplete. Many resources declare concrete
foreign-key attributes without the corresponding Ash relationship, and many
existing `belongs_to` declarations disable Ash's implied source attribute only
to restate that attribute manually. This limits generated API, managed
relationship, aggregate, and relationship-backed validation options.

Eight resource attributes use the generic Ash `:map` type:

| Resource field | Current behavior | Normalized shape |
|---|---|---|
| `RunEvent.payload` | No production reader or writer | Remove until an event-specific typed field or extension resource is required |
| `ExecutionObservation.metadata` | Stores only an observation classification | `classification` typed string column |
| `RawArchive.metadata` | Stores GitHub event and installation envelope data | Typed `provider_event` and `external_installation_id` columns; raw provider body remains opaque archive content |
| `ProposedGraphChange.payload` | Always stores title and body | Typed `title` and `body` columns |
| `DocumentMark.attrs` | Current `strong` mark uses an empty map | Remove; future marks with parameters use typed mark columns or references |
| `OperationCorrelation.metadata` | Stores only a command input digest | `command_input_digest` typed string column |
| `EvidenceItem.visibility_constraints` | Always empty and has no consumer | Remove; existing typed sensitivity and policy fields remain authoritative |
| `OutboundAction.input` | Two known command shapes | Typed review-reply/check-update columns on the owning action |

The generic Tombstones context owns one polymorphic `resource_type` /
`resource_id` table. Only graph relationships reference it, and no product
command currently creates those rows. Graph relationships already carry their
lifecycle, last operation, principal, and validity interval, so deletion state
belongs on that table.

The physical context folders also mix resources, changes, commands, adapters,
workers, projections, and value objects at one level. Public module names are
already useful and do not need to change; physical paths can improve without a
namespace migration.

## Goals / Non-Goals

**Goals:**

- Make concrete database references first-class Ash relationships.
- Let `belongs_to` define ordinary foreign-key attributes and keep explicit
  attributes only for polymorphic identifiers or proven special constraints.
- Remove all eight generic map attributes without hiding typed behavior in a
  renamed JSON wrapper.
- Replace the generic tombstone table with owning-resource deletion fields.
- Generate time-ordered UUIDv7 identifiers in PostgreSQL for ordinary writes
  while retaining explicit-ID support for deterministic replay, imports, and
  tests.
- Run repository-managed development and verification databases on PostgreSQL
  18 so UUIDv7 uses the native database function.
- Make large contexts easier to navigate and keep value-object behavior with
  the value object that owns it.
- Enforce the resulting conventions with structural and behavior tests.

**Non-Goals:**

- Complete the Relay/AshGraphql or AshJsonApi migration.
- Remove existing raw SQL, direct Ecto, transaction orchestration, or
  read-modify-write validation debt except where this schema change directly
  touches it.
- Rebuild the full unreleased migration history; that remains a later,
  separately verified stage after resource and database-access stabilization.
- Add WorkOS or change authentication behavior.
- Turn genuinely polymorphic graph identity, audit subject, or external
  reference identifiers into false Ash relationships.

## Decisions

### 1. Model every concrete foreign key as an Ash relationship

Every resource attribute backed by a concrete foreign key will have a
`belongs_to`; owning resources will add useful inverse `has_many` or `has_one`
relationships where the inverse has stable domain meaning. The normal
`belongs_to` form will define its `<name>_id` attribute, including nilability,
type, public visibility, and writability. `define_attribute? false` remains
only when the source attribute is deliberately shared, nonstandard, or
polymorphic and the exception is covered by the conformance inventory.

The structural test will compare Ash relationship metadata with the migration
foreign-key inventory rather than assuming every name ending in `_id` is a
foreign key. That avoids inventing relationships for polymorphic subject,
resource, target, and provider identifiers.

Alternative considered: add only the relationships needed by the next API
change. Rejected because the resource model would remain incomplete and future
generated API work would continue rediscovering missing ownership.

### 2. Normalize each map according to actual semantics

Typed columns are used when the current key set is stable and independently
meaningful. Unused placeholder maps are removed. Raw archive content remains
opaque because preserving the original provider payload is its explicit
purpose, but all product behavior and lookup keys move into typed envelope
columns. No current map is retained merely for convenience.

The outbound-action columns remain on the action row instead of creating two
new tables because the shapes are small, mutually exclusive, immutable command
inputs with the same lifecycle. Its create action validates the appropriate
columns for `review_reply` versus `check_update`.

Alternative considered: replace maps with embedded Ash resources. Rejected for
these eight fields: it would preserve JSONB storage for data whose current
shape is either simple enough for columns or unused. Embedded resources remain
appropriate for future structured, non-queryable values with real nested
validation needs.

### 3. Keep deletion state with the owning graph relationship

The Tombstones domain, resource, table, and `GraphRelationship.tombstone_id`
are removed. Graph relationships gain nullable `deleted_at`,
`deletion_operation_id`, `deleted_by_principal_id`, and `deletion_reason`
fields. The tombstone action atomically changes lifecycle and deletion fields;
restore clears them through the owning Ash action. Existing lifecycle and
validity fields continue to determine active-edge uniqueness and projection.

Richer deletion data in other contexts will use typed columns or a
domain-specific one-to-one resource with a real foreign key. A generic
`resource_type` / `resource_id` deletion table is prohibited.

Alternative considered: specialize the existing Tombstone row for graph
relationships. Rejected because a second row adds no lifecycle fact the graph
relationship cannot own directly and retains an unnecessary context.

### 4. Use database-generated UUIDv7 without hiding application defaults

Primary-key attributes will use UUID storage and be marked data-layer
generated, while remaining writable for explicit deterministic identifiers.
Ordinary create paths stop injecting `Ecto.UUID.generate/0`. The repository
minimum and Compose runtime move to PostgreSQL 18, and the migration default is
the native `uuidv7()` function, so inserts that omit an identifier receive a
UUIDv7 from PostgreSQL and Ash returns it.

The exact SQL-bearing default is the generated Ecto migration expression
`fragment("uuidv7()")` for UUID primary-key columns. This is the sole
repository-authored database exception added by the UUID migration and was
explicitly approved with the PostgreSQL 18 upgrade. No compatibility function,
handwritten UUID function, or MD5 construction is allowed.

UUIDv7 improves index locality and retains enough random bits for durable
global identity, but it is not treated as a sharding key. Future sharding will
still choose an explicit organization or workspace distribution key.

Alternative considered: Ash's `uuid_v7_primary_key` helper. Rejected because
its default is `Ash.UUIDv7.generate/0`, which generates the value in the
application and does not satisfy the database-generation requirement.

Alternative considered: retain PostgreSQL 17 and install AshPostgres'
compatibility `uuid_generate_v7()` function. Rejected after the PostgreSQL 18
upgrade was approved because the native function removes project-owned
procedural SQL and its retirement lifecycle.

### 5. Reorganize paths without renaming public modules

Crowded contexts will group files by responsibility, such as `resources/`,
`commands/`, `changes/`, `adapters/`, `workers/`, and `values/`. File movement
does not add namespace segments, delegation layers, or compatibility modules.
Small value-object modules may remain data-only when they are genuine passive
boundary DTOs; construction, normalization, or validation functions currently
scattered in consumers move into the owning value module.

Resource DSL sections will be ordered consistently: database configuration;
attributes grouped as identity/scope, lifecycle, domain data, and timestamps;
relationships; actions; identities; policies; API extensions. Grouping is
visual and semantic, not a macro abstraction.

Alternative considered: introduce a common resource macro and context facade
hierarchy. Rejected because it would obscure ordinary Ash DSL and create
abstraction without domain responsibility.

## Risks / Trade-offs

- [A relationship name may imply the wrong ownership semantics.] → Derive
  relationships from actual database foreign keys and existing domain
  vocabulary, then cover both directions with conformance tests.
- [Removing maps is API-breaking.] → Update internal callers and transport
  projections in the same slice and retain only behavior-backed fields.
- [Database-generated IDs can break code that needs an ID before insert.] →
  Keep explicit IDs writable for true preallocation/replay cases, remove
  generation only where the ID is not required before the create, and test
  both paths.
- [UUIDv7 timestamps expose coarse creation ordering.] → Treat identifiers as
  opaque externally and continue using authorization-scoped Relay IDs; do not
  encode tenant or business data in the UUID.
- [Moving many files can obscure semantic changes.] → Commit schema/behavior
  work separately from path-only moves and run the full gate after each
  checkpoint.
- [Existing local PostgreSQL 17 volumes are not reusable by a PostgreSQL 18
  container without a major-version upgrade.] → The repository is unreleased;
  document a volume reset for local state and make canonical verification use
  fresh isolated PostgreSQL 18 volumes.

## Migration Plan

1. Add failing structural tests for concrete relationships, implied
   `belongs_to` attributes, map elimination, tombstone elimination, UUID
   generation metadata, and module layout.
2. Normalize the eight fields and their callers, preserving typed replay and
   validation behavior.
3. Remove the Tombstones context and move graph relationship deletion state
   into `graph_relationships`.
4. Complete concrete Ash relationships and inverse relationships, then remove
   redundant manual foreign-key attributes.
5. Convert primary keys and ordinary create paths to database-generated
   UUIDv7, retaining explicit preallocation only where tests prove it is
   needed before insert.
6. Generate a forward AshPostgres migration for the resource delta, using
   PostgreSQL 18's native `uuidv7()`, and verify both upgrade and empty-database
   migration paths. The later rebaseline change will consolidate, not edit
   archived migration history.
7. Move files into responsibility-based subfolders in path-only commits.
8. Run focused resource/action/concurrency/API tests, strict architecture
   checks, strict OpenSpec validation, and the complete canonical gate.

Rollback is a normal code-and-migration revert while the product remains
unreleased. Any data rollback must reconstruct removed map values from their
typed columns; the forward migration therefore retains a reversible mapping
until the later unreleased-history rebaseline.

## Open Questions

None. The map classification, in-table deletion model, UUIDv7 direction,
relationship normalization, and physical grouping were approved as this
remediation stage.
