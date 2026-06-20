## Why

Office Graph needs a concrete revision, audit, soft-delete, retention, and
legal-hold design before backend migrations begin. The persistence,
governance, and work-graph designs already reserve these concepts; this change
turns them into an implementation-ready contract without collapsing revisions,
audit logs, domain events, run events, and raw archives into one generic event
store.

## What Changes

- Define typed, reconstructable revision history for mutable product records,
  graph items, rich text, ordered placements, conversations, evidence, and
  integration-derived product records.
- Define durable audit boundaries for security/compliance-sensitive behavior,
  including reads, denied actions, escalations, approvals, waivers,
  credentials, external writes, exports, retention changes, legal hold, and
  restore/purge actions.
- Define the audit log storage contract: typed audit event envelope,
  relational event targets, schema-versioned action-specific details, action
  registry, customer-facing event projection, export/streaming posture, and
  append-only correction semantics.
- Define operation correlation as the shared command trace that links
  revisions, audit records, authorization decisions, run events, sync events,
  domain events, and proposed graph changes without duplicating payloads.
- Define soft deletion and tombstones for mutable product records, including
  deletion actor, reason, lifecycle state, URL slug/handle reservation,
  display-identifier uniqueness behavior, restore eligibility, and purge
  constraints.
- Define retention, legal-hold, export, redaction, and purge boundaries for
  product records, revisions, audit records, raw archives, model/tool payloads,
  and provider-derived records.
- Define which details remain in follow-on implementation work, such as exact
  Ecto migration syntax, Ash resource modules, GraphQL/JSON API shapes,
  background purge jobs, SIEM export adapters, and storage-tier mechanics.

## Capabilities

### New Capabilities

- `typed-revision-history`: Defines reconstructable, aggregate-aware revision
  records for meaningful product state changes without a universal JSON
  versions table.
- `audit-record-boundaries`: Defines when durable audit records and
  authorization decision records are required, what they identify, how audit
  events are shaped, how event-specific detail is versioned, and how audit
  visibility differs from normal product visibility.
- `operation-correlation`: Defines shared operation or command correlation
  records that revisions, audit records, run events, sync events, and proposed
  graph changes can reference.
- `soft-delete-tombstones`: Defines soft-deleted state, tombstone records,
  active uniqueness, restore eligibility, and purge blocking rules for mutable
  product records.
- `retention-legal-hold-export`: Defines retention policy application, legal
  hold behavior, purge/export boundaries, redaction requirements, and
  high-volume growth expectations for retained records.

### Modified Capabilities

- None. No durable specs exist yet under `openspec/specs/`; this change builds
  on active foundation, work-graph, governance, and persistence planning
  changes.

## Impact

- Affects OpenSpec planning artifacts for revision tables, audit logs,
  authorization decision records, operation correlation records, tombstones,
  retention policy application, legal holds, export/redaction, and purge jobs.
- Feeds later Phoenix, Ash, Ecto migration, GraphQL, JSON API, Oban,
  integration, agent-runtime, SIEM export, and storage-retention
  implementation.
- Does not implement application code, database migrations, Ash resources, API
  endpoints, frontend screens, background jobs, SIEM adapters, or storage
  infrastructure.
