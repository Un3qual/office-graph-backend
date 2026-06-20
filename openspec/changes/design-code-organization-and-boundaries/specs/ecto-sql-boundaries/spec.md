## ADDED Requirements

### Requirement: Approved Direct SQL Paths
Direct Ecto queries and explicit SQL SHALL be allowed only for context-owned
paths that are poor fits for normal Ash actions, including graph traversal,
projection read models, authorization-filtered neighborhoods, replay,
analytics, raw archive lookup, high-volume event scans, partition maintenance,
backfills, and bulk reconciliation.

#### Scenario: A graph projection query is planned
- **WHEN** a projection requires traversal or aggregation that is awkward for
  normal Ash actions
- **THEN** the owning context may define a direct Ecto or SQL read-model module
  for that query

#### Scenario: A simple domain mutation is planned
- **WHEN** a mutation can be expressed as an Ash action on the owning resource
- **THEN** it does not use direct SQL as the primary mutation path

### Requirement: Direct Query Authorization Inputs
Direct Ecto and SQL read paths MUST accept tenant, scope, actor, authorization,
classification, soft-delete, and operation context inputs as required by the
records they read.

#### Scenario: A direct query returns graph data
- **WHEN** a direct SQL path returns graph nodes, edges, artifacts,
  conversations, summaries, counts, or revisions
- **THEN** it applies authorization filtering or returns enough target
  references for an approved authorization-filtering stage before data reaches
  the caller

#### Scenario: A query reads soft-deletable records
- **WHEN** a direct query reads mutable product records that support soft
  deletion
- **THEN** it applies active/tombstone filtering consistent with the owning
  context's lifecycle rules

### Requirement: Direct Mutation Safeguards
Direct Ecto and SQL mutation paths MUST be rare, context-owned,
operation-correlated, tested, and subject to the same authorization, revision,
audit, tombstone, sync-event, and domain-event expectations as Ash mutations.

#### Scenario: A bulk reconciliation writes imported records
- **WHEN** a provider sync path performs a bulk direct-SQL mutation
- **THEN** it records operation correlation, idempotency, sync-event state, and
  any required revisions or audit records

#### Scenario: A maintenance job rewrites derived data
- **WHEN** a maintenance job uses direct SQL for derived ordinals, projection
  cache refresh, or partition maintenance
- **THEN** the job is owned by the relevant context and documents why an Ash
  action path is inappropriate

### Requirement: Read Model Ownership
Read models and query modules SHALL have explicit owning contexts and SHALL
return typed result shapes rather than leaking arbitrary row maps across the
codebase.

#### Scenario: A projection read model is introduced
- **WHEN** a read model combines graph, authorization, content, evidence,
  external-reference, and run data
- **THEN** the projection context owns the query module and publishes a typed
  result contract

#### Scenario: A caller needs private columns
- **WHEN** an entrypoint requests fields from another context's private tables
- **THEN** the owning context exposes an approved query shape rather than
  allowing private table access
