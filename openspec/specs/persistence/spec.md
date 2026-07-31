# persistence Specification

## Purpose
Define provider-neutral relational persistence as the base for shared domain concepts.
## Requirements
### Requirement: Provider-Neutral Relational Base Tables

Office Graph SHALL prefer provider-neutral relational base tables for concepts
shared across integrations.

#### Scenario: Shared external concept is modeled

- **WHEN** a concept such as repository, branch, commit, pull request, issue,
  review comment, check run, design asset, campaign asset, document, social
  post, finance record, or external artifact is needed across providers
- **THEN** the base table must model the shared concept with typed relational
  columns before provider-specific extension tables are introduced

#### Scenario: Provider-specific behavior is required

- **WHEN** GitHub, GitLab, Sentry, Figma, Slack, finance tools, or another
  provider requires fields or behavior that do not belong in the shared model
- **THEN** source-specific extension tables may be added with a clear reason
  and foreign key back to the provider-neutral base record

### Requirement: JSON Avoidance For Core Domain Data

Core Office Graph domain data SHALL avoid JSON or JSONB columns wherever a
typed relational model is practical.

#### Scenario: New schema stores queryable product data

- **WHEN** a table stores data used for authorization, graph traversal,
  workflow state, revision history, filtering, reporting, integrations, agent
  context assembly, or verification
- **THEN** the data must use typed columns, lookup tables, join tables, or
  extension tables rather than generic JSON properties

#### Scenario: Raw external payload is stored

- **WHEN** raw webhook, API, or model payloads need archival for replay,
  debugging, or provenance
- **THEN** JSON storage may be used for the raw payload archive, but normalized
  queryable fields must be extracted into typed tables or columns

### Requirement: Typed Revision History

Office Graph SHALL support edit and revision history without relying on one
giant JSON-backed versions table.

#### Scenario: Meaningful record changes

- **WHEN** a graph item, work packet, decision, requirement, check, evidence,
  conversation, run, integration-derived artifact, or sensitive domain record
  changes
- **THEN** the system must preserve typed revision or history records with
  actor, source, timestamp, reason when available, affected fields,
  supersession relationship, request or trace identifier when available, and
  related agent run or approval when applicable

#### Scenario: Revision design is chosen

- **WHEN** revision storage is designed for a domain
- **THEN** the design must distinguish reconstructable revision history from
  audit logs, domain events, run events, external sync events, and raw payload
  archives

### Requirement: Soft Deletion From The Beginning

Office Graph SHALL support soft deletion for mutable product records from the
beginning.

#### Scenario: Record is removed from normal use

- **WHEN** a graph item or mutable product record is deleted
- **THEN** it must retain a tombstone or soft-deleted state with deletion actor,
  deletion time, reason when available, and restore/retention behavior
  according to policy

#### Scenario: Unique constraints are designed

- **WHEN** uniqueness rules are added to soft-deletable records
- **THEN** the design must specify whether uniqueness ignores deleted rows
  through partial indexes or remains globally reserved forever

### Requirement: Tenant And Scope Columns

Durable Office Graph records SHALL carry explicit tenant and scope information.

#### Scenario: Table is designed

- **WHEN** a durable product table is introduced
- **THEN** the table must define the applicable organization, workspace,
  project, graph, integration, or external source scope needed for
  authorization, isolation, indexing, and future export

### Requirement: Large Table Growth Planning

High-volume persistence areas SHALL identify indexing and partitioning paths
before implementation.

#### Scenario: Event-like table is designed

- **WHEN** schemas are planned for raw events, run events, audit logs,
  revisions, integration sync events, model calls, or tool-call logs
- **THEN** the design must include baseline indexes and identify whether later
  partitioning is likely

### Requirement: Durable identifiers are database-generated UUIDv7
Ordinary durable Office Graph records SHALL receive UUIDv7 primary keys from
PostgreSQL, while explicit caller-supplied identifiers SHALL remain available
only for deterministic replay, imports, fixtures, or workflows that prove the
identifier is required before insertion.

#### Scenario: Ordinary Ash create omits an identifier
- **WHEN** an Ash create action inserts a durable record without an explicit primary key
- **THEN** PostgreSQL MUST generate a valid UUIDv7 and return it to the action

#### Scenario: Deterministic identifier is required
- **WHEN** replay, import, a fixture, or a multi-record workflow requires a stable identifier before insert
- **THEN** the owning private action MAY accept an explicit valid UUID while preserving uniqueness and authorization invariants

#### Scenario: Application UUID default is proposed
- **WHEN** a resource primary key or ordinary create path proposes `Ecto.UUID.generate`, `Ash.UUID.generate`, `Ash.UUIDv7.generate`, or another application default
- **THEN** architecture verification MUST reject it unless the exact pre-insert requirement is documented and tested

#### Scenario: Sharding is introduced later
- **WHEN** Office Graph partitions data across database shards
- **THEN** UUIDv7 MUST remain an opaque durable identifier and the design MUST choose an explicit tenant or scope distribution key rather than assuming UUID ordering determines shard placement

### Requirement: Repository-managed PostgreSQL supports native UUIDv7
The repository-managed development and canonical verification databases SHALL
run PostgreSQL 18 or newer and SHALL use the native `uuidv7()` function for
durable identifier defaults.

#### Scenario: Canonical verification starts PostgreSQL
- **WHEN** `bin/verify` starts its isolated Compose database
- **THEN** the ready container's PostgreSQL server binary MUST report major version 18 before migrations and tests run

#### Scenario: Local PostgreSQL 17 state exists
- **WHEN** a developer upgrades the repository-managed container from PostgreSQL 17
- **THEN** setup documentation MUST require a volume reset or an explicit external major-version upgrade instead of starting PostgreSQL 18 against the PostgreSQL 17 data directory
