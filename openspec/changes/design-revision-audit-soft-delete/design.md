## Context

Office Graph already requires a department-neutral work graph, provider-neutral
relational persistence, explicit tenant/scope fields, limited JSON usage,
explainable authorization, and separate audit/revision concepts. The
foundation design requires typed, aggregate-aware revision history and soft
deletion from the beginning. The governance design requires durable audit
records for security/compliance-sensitive behavior and operation correlation
to link related records without duplicating payloads. The persistence design
reserves operation correlation, soft-delete-aware uniqueness, high-volume
growth planning, and follow-on revision/audit/tombstone details.

This change finalizes the revision, audit, soft-delete, retention, legal-hold,
restore, and export posture before code or migrations are generated.

## Goals / Non-Goals

**Goals:**

- Define typed revision history for reconstructable product state changes.
- Keep audit records distinct from revisions, domain events, run events,
  external sync events, authorization decisions, and raw payload archives.
- Define operation correlation records as the shared command trace.
- Define soft deletion, tombstones, restore eligibility, purge blocking, and
  soft-delete-aware uniqueness.
- Define retention, legal hold, export, and redaction boundaries.
- Identify high-volume growth and indexing needs for revision/audit records.

**Non-Goals:**

- No Phoenix, Ash, Ecto, database migration, Oban, GraphQL, JSON API, React, or
  agent-runtime implementation.
- No final column list for every table.
- No SIEM adapter, object-storage tiering, purge worker, or export pipeline
  implementation.
- No replacement for the enterprise governance design's authorization policy
  model.
- No generic event-sourcing architecture for every product record.

## Decisions

### 1. Separate revisions, audit, events, sync, runs, and raw archives

Office Graph should not use one event table for every historical concern.
Each record family answers a different question:

- revisions reconstruct meaningful state changes to product records
- audit records explain security/compliance-sensitive actor behavior
- authorization decision records explain policy decisions and redaction
- domain events notify other domains about business facts
- run events preserve agent/runtime execution timelines
- external sync events preserve ingestion, idempotency, replay, and provider
  reconciliation state
- raw archives preserve original provider, webhook, model, or tool payloads

All of these records may reference one operation correlation record when they
come from the same meaningful action. They should not duplicate each other's
large payloads or pretend to be interchangeable.

Alternatives considered:

- **One append-only event stream:** Simple to start, but it hides distinct
  retention, visibility, reconstruction, and export requirements.
- **Use audit logs as history:** Satisfies compliance traceability but does not
  reconstruct product state.
- **Use revisions as audit:** Reconstructs state but misses denied actions,
  credential use, exports, and sensitive reads.

### 2. Use aggregate-aware typed revisions

Mutable product aggregates should define typed revision/history records close
to the aggregate they reconstruct. A revision should record the changed
aggregate, actor/source, operation, timestamp, reason when available, parent or
superseded revision, affected fields or child components, and enough typed
before/after values or references to reconstruct meaningful state.

The default pattern is not one universal JSON `versions` table. A task,
decision, requirement, evidence item, conversation message, rich text document,
ordered placement, review finding, or provider-neutral imported product record
may each need a revision shape that matches its domain. Shared helper tables or
library modules are acceptable when they preserve typed semantics and concrete
foreign keys.

Large or sensitive payloads should be referenced, not copied. Revisions can
point to rich text revision records, artifacts, raw archives, derived renders,
or external references when those records already own the payload.

Alternatives considered:

- **Opaque snapshot JSON:** Easy to implement but weak for policy, query,
  redaction, and schema evolution.
- **Full row copy for every edit:** Simple reconstruction but expensive and
  noisy for rich text, ordered placements, and large artifacts.
- **No revision until audit exists:** Leaves product changes unreconstructable
  and makes restore behavior ambiguous.

### 3. Write durable audit records for policy-sensitive behavior

Audit records should be append-only from normal product code and should focus
on actor behavior, authority basis, policy result, resource/scope, and
investigation context. They should be written when policy requires durable
traceability, including:

- role, grant, membership, custom-role, and policy changes
- credential access, rotation, revocation, and secret-use requests
- sensitive artifact, audit-log, prompt/context, and cross-scope summary reads
- context expansion, temporary grant, approval gate, and waiver decisions
- external writes, exports, destructive actions, restores, purges, retention
  changes, and legal-hold changes
- denied or escalated policy-sensitive attempts
- sensitive agent tool use or autonomous actions

Normal low-risk reads can remain operational logs unless organization policy,
classification, resource kind, or customer configuration requires durable read
audit.

Alternatives considered:

- **Audit every authorization check:** Too costly and too noisy for graph
  projection and context assembly.
- **Audit only successful writes:** Misses denied attempts, escalations,
  sensitive reads, exports, and agent authority boundaries.

### 4. Use operation correlation as the command trace

An operation correlation record should represent one meaningful command or
externally observed action. It should include organization, optional
workspace/initiative/workstream scope, actor principal, delegator, agent run,
service account, external source, command key, idempotency key when available,
request/trace identifiers, policy bundle or authorization context version when
applicable, origin, reason, and timestamps.

Related revisions, audit records, authorization decisions, approvals, run
events, external sync events, proposed graph changes, and domain events should
reference the operation. The operation may reference a primary graph item or
external reference when one exists, but it must not introduce a polymorphic
local target model.

Alternatives considered:

- **Store correlation fields on every record only:** Hard to query and easy to
  drift.
- **Make the operation record the event payload:** Recreates the generic event
  table problem and duplicates domain data.

### 5. Use soft deletion plus tombstones for mutable product records

Mutable product records should leave normal use through a deleted/tombstoned
lifecycle state rather than hard deletion. Records should capture deletion
actor, operation, timestamp, reason, and restore/purge eligibility. The exact
columns may be `deleted_at`/`deleted_by` for simple records or a domain-specific
tombstone table when the resource needs richer metadata, redaction, legal-hold
state, or external-provider reconciliation.

Uniqueness should be explicit. User-facing names and slugs can usually use
active-record partial uniqueness when reuse after deletion is allowed. Provider
external identifiers should usually remain reserved per organization, source,
object type, and external identifier even if the local product row is deleted.

Append-only records such as audit logs, authorization decisions, raw archives,
run events, external sync events, and immutable revision rows are not
soft-deleted by normal product actions. They may become retention-expired,
redacted, sealed, exported, or purged only through policy-controlled retention
workflows.

Alternatives considered:

- **Hard delete first:** Faster early but incompatible with enterprise restore,
  audit, legal hold, and provider reconciliation.
- **One universal tombstone table for everything:** Consistent in diagrams but
  weak for domain-specific restore and uniqueness rules.

### 6. Treat restore and purge as policy-controlled workflows

Restore is a domain action, not a blind `deleted_at = null` update. Restores
must check authorization, scope, classification, retention state, legal hold,
uniqueness conflicts, external-provider state, and revision/audit traceability.
Some records may restore in place; others may restore as a new active record
linked to the tombstone when uniqueness or external state has moved on.

Purge is more restrictive than deletion. Purge must honor legal hold,
retention policy, audit requirements, export obligations, external-provider
contracts, and raw archive retention. Purge may delete payload bodies while
keeping minimal tombstones, digests, external identifiers, or audit metadata
when policy requires traceability.

Alternatives considered:

- **Restore always recreates the old row:** Simple but fails on uniqueness and
  external-provider drift.
- **Purge deletes every trace:** Incompatible with audit, legal hold, and
  compliance obligations.

### 7. Apply retention, legal hold, export, and redaction by record family

Retention policy should apply by organization, workspace/initiative, resource
kind, classification, provider/source, and record family. Legal hold blocks
purge and retention expiry for affected records and must itself be audited.
Export must respect authorization, classification, redaction rules, secret
boundaries, model/tool payload controls, and audit visibility.

The design should distinguish between product records, revisions, audit
records, authorization decisions, raw archives, model/tool payloads, external
sync events, run events, and derived renders because they have different
retention and redaction needs.

Alternatives considered:

- **One retention period per organization:** Easy to configure but too blunt
  for legal hold, secrets, prompts, raw payloads, and audit records.
- **Let storage lifecycle policies own retention alone:** Useful for blob
  expiration, but insufficient for domain authorization, export, and audit.

### 8. Plan audit/revision growth without overbuilding day one

Revision, audit, authorization decision, run event, sync event, and raw archive
tables should include organization, scope or resource references, actor/source,
action or record kind, operation, result/lifecycle, and event time indexes
where applicable. They should be partition-ready but do not need physical
partitioning before real customer volume or ingestion load proves the need.

Alternatives considered:

- **Partition all history tables immediately:** Adds operational complexity
  before query and retention patterns are proven.
- **Ignore growth until later:** Risks painful rewrites in the highest-volume
  tables.

## Risks / Trade-offs

- [Risk] Typed revisions create more tables than a generic versions table. ->
  Mitigation: share helper libraries and conventions while keeping domain
  storage typed.
- [Risk] Audit logging can become noisy. -> Mitigation: durable audit triggers
  are policy-sensitive by default, with normal low-risk reads left to
  operational logs unless configured otherwise.
- [Risk] Restore semantics vary by resource. -> Mitigation: require each
  mutable aggregate to declare restore behavior before migration.
- [Risk] Retention and legal hold can conflict with product deletion. ->
  Mitigation: treat delete, restore, purge, and retention expiry as separate
  policy-controlled workflows.
- [Risk] Operation correlation becomes a dumping ground. -> Mitigation: keep
  operation records narrow and require typed records to own their payloads.

## Migration Plan

There is no application-code migration for this design-only change. Follow-on
implementation should proceed in this order:

1. Use this change to define table/resource conventions for revisions, audit
   records, authorization decisions, operation correlations, tombstones,
   retention state, legal holds, and exports.
2. Feed those conventions into `design-code-organization-and-boundaries` for
   Ash domains, Ecto modules, Boundary rules, and library extraction posture.
3. Feed audit, authorization decision, approval, and credential-use records
   into governance and agent-runtime implementation.
4. Feed run-event, sync-event, and proposed-graph-change references into their
   dedicated follow-on designs.
5. Add physical partitioning, SIEM export, object-storage lifecycle, purge
   workers, and export pipelines only when implementation designs define real
   query, volume, or compliance requirements.

## Open Questions

- Which exact aggregates get bespoke revision tables versus shared typed
  revision helper tables in the first migration batch?
- Which low-risk reads become durable audit records by default for the first
  customer profile beyond the governance defaults?
- Which records require restore-in-place versus restore-as-new semantics once
  concrete table shapes are selected?
