## Why

Office Graph's Ash resources currently expose incomplete relationship models,
eight generic map attributes that carry typed product behavior, a cross-domain
polymorphic tombstone table, application-generated UUIDs, and crowded physical
module layouts. These inconsistencies make Ash less effective as the canonical
domain boundary and increase the cost and risk of the API and database-access
cleanup that follows.

## What Changes

- Complete each resource's Ash relationship declarations and let
  `belongs_to` relationships own their generated foreign-key attributes unless
  a concrete exception requires an explicit attribute.
- Replace all eight current generic `:map` attributes with typed embedded
  resources, typed relational data, or explicit raw-archive payloads according
  to how the data is used.
- **BREAKING** Remove the generic polymorphic tombstone resource and store
  common soft-deletion state on each mutable owning table, using
  domain-specific related records only when richer deletion state is required.
- Make PostgreSQL generate UUIDv7 primary keys by default while preserving
  supplied identifiers for deterministic tests, imports, and replay.
- Upgrade the repository-managed development and verification database to
  PostgreSQL 18 and use its native `uuidv7()` implementation.
- Group resource attributes and related declarations by responsibility, move
  behavior next to the structs it owns, and split crowded context folders into
  navigable responsibility-based subfolders without changing public module
  names.
- Add architecture checks and behavior tests that keep these resource
  conventions from regressing.

## Capabilities

### New Capabilities

- `ash-resource-conventions`: Defines complete relationship modeling,
  foreign-key ownership, declaration grouping, database-generated UUIDv7
  identifiers, and behavior-owning module placement for Ash resources.

### Modified Capabilities

- `json-storage-policy`: Classify and replace the eight current generic map
  fields according to typed-domain versus opaque-archive usage.
- `soft-delete-tombstones`: Replace the generic polymorphic tombstone table
  with in-table soft-deletion state and domain-specific deletion metadata.
- `bounded-context-architecture`: Require responsibility-based physical
  grouping inside crowded contexts while preserving public context and module
  ownership.
- `persistence`: Establish PostgreSQL-generated UUIDv7 as the durable primary
  key default.

## Impact

This change affects Ash resources and domains throughout `lib/office_graph`,
their tests and architecture inventories, GraphQL/JSON projections that expose
tombstone state, and the unreleased Postgres schema. It may add typed embedded
resources or relational resources, removes the Tombstones context, and changes
identifier defaults and the repository-managed PostgreSQL major version. It
does not yet perform the subsequent Relay/API
migration, database-access debt removal, final migration-chain rebaseline, or
WorkOS integration.
