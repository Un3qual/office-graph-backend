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

The first migration posture is to make native, high-value product history
first-class. Graph items, rich text documents and placements, conversations
and messages, review findings, evidence, and provider-neutral imported product
records should get bespoke typed revision tables or concrete revision modules
when their state needs domain-specific reconstruction. Simpler administrative
metadata, labels, non-URL display fields, and low-complexity settings can use
shared typed revision helper conventions as long as they keep concrete
foreign keys, typed changed-field names, operation correlation, and
record-family-specific reconstruction rules.

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

Authorization decision records are a separate typed record family and should
be written for every denied, redacted, escalated, approval-gated, and
sensitive-read decision. The first record shape should include organization,
scope, principal, delegator, service account or agent run when applicable,
requested action, target references, decision result, authority basis,
policy bundle and version, matched rule or obligation references, redaction or
projection outcome, operation correlation, request or trace identifier,
source/origin, reason when available, and timestamp. Audit records may point to
authorization decisions, and authorization decisions may point to redacted
graph projection references, but neither should copy the other's payload.

Alternatives considered:

- **Audit every authorization check:** Too costly and too noisy for graph
  projection and context assembly.
- **Audit only successful writes:** Misses denied attempts, escalations,
  sensitive reads, exports, and agent authority boundaries.

### 4. Model audit logs as envelope, targets, and versioned details

Enterprise customers expect audit logs to behave like a searchable,
exportable, streamable event surface. Internally, Office Graph should store
that surface as a typed relational envelope plus relational targets and
schema-versioned details, not as one opaque JSON blob.

The expected storage shape is:

- `audit_events` for the typed envelope: organization, optional
  workspace/initiative/workstream scope, action key, action category, result,
  actor, delegator, service account or agent when applicable, operation,
  authorization decision reference, policy bundle/version reference, request
  or trace identifiers, origin, IP/user-agent context where allowed,
  retention class, occurred timestamp, and append-only lifecycle state
- `audit_event_targets` for affected targets: principal, graph item,
  external reference, integration, credential metadata, policy bundle,
  approval, run, artifact, or other concrete target references with target role
  and a display/redaction snapshot
- `audit_event_details` for schema-versioned action-specific details, using
  constrained JSONB for non-authoritative metadata that differs by action
- raw archive or artifact references for large, sensitive, provider, model, or
  tool payloads

Queryable, security-sensitive, and export-critical fields belong in typed
columns or target rows. JSONB belongs only in the action-specific details layer
and must be tied to an action key and detail schema version. Details may carry
small structured facts such as changed setting names, previous/new enum labels,
reason text, provider error codes, or redacted request snippets. Details must
not become the only place to find actor, action, result, target, tenant,
operation, policy, retention, or timestamp.

Audit actions should be registered before use. An audit action registry should
define action key, category, allowed actor kinds, allowed target kinds, result
vocabulary, required detail schema version, default retention class, default
visibility, export/stream eligibility, and whether successful, denied, or
escalated attempts are durable-audit events by default.

Customer-facing audit APIs and exports should project the internal records into
a clean event document with action, actor, targets, result, occurred time,
context, details, and operation id. This projection can look document-shaped
for customers while the backend keeps the search and authorization surface
typed.

Audit events should be immutable from normal product code. Mistakes,
redactions, retention expiry, legal sealing, and correction workflows should
create correction/redaction/sealing events or lifecycle metadata rather than
rewriting the original event payload in place.

Alternatives considered:

- **Single JSON audit_events table:** Flexible, but weak for tenant filtering,
  SIEM/export guarantees, audit visibility, retention, and customer search.
- **Fully typed table per action:** Strong constraints, but too much schema
  churn for normal audit event evolution.
- **Editable audit rows:** Operationally convenient, but violates audit-trail
  expectations and makes corrections hard to trust.

### 5. Use operation correlation as the command trace

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

### 6. Use soft deletion plus tombstones for mutable product records

Mutable product records should leave normal use through a deleted/tombstoned
lifecycle state rather than hard deletion. Records should capture deletion
actor, operation, timestamp, reason, and restore/purge eligibility. The exact
columns may be `deleted_at`/`deleted_by` for simple records or a domain-specific
tombstone table when the resource needs richer metadata, redaction, legal-hold
state, or external-provider reconciliation.

The first tombstone shape should include organization and scope, resource kind,
concrete resource reference, deletion actor/source, operation, deletion time,
reason when available, lifecycle state, restore eligibility, purge eligibility,
retention class, legal-hold state, redaction state, and optional replacement or
restore-as-new linkage. Graph items and work containers can usually retain
soft-delete columns plus tombstone metadata when they carry URL handles,
children, or legal-hold state. Conversations and messages should preserve
thread/message deletion state separately enough to restore or redact a thread
without rewriting message history. Provider-neutral imported records should
include external source/object identifiers and reconciliation state. Artifacts
should preserve payload retention, digest, redaction, and storage-reference
state separately from product visibility.

Uniqueness should be explicit. Native URL-bearing slugs and handles are durable
reservations within their organization and scope and are not freed by soft
deletion. If an item with slug `foo` has ever existed, a new generated slug
that would otherwise be `foo` should become `foo-1`, then `foo-2`, and so on.
Deleted URLs must not resolve to a different new resource; they may show an
authorized tombstone, redirect to a restored/replaced resource, or return an
authorized not-found or gone response. Display names, labels, and other
non-URL user-facing identifiers may use active-record partial uniqueness when
reuse after deletion is allowed. Provider external identifiers should remain
reserved per organization, source, object type, and external identifier even
if the local product row is deleted.

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

### 7. Treat restore and purge as policy-controlled workflows

Restore is a domain action, not a blind `deleted_at = null` update. Restores
must check authorization, scope, classification, retention state, legal hold,
uniqueness conflicts, external-provider state, and revision/audit traceability.
Some records may restore in place; others may restore as a new active record
linked to the tombstone when uniqueness or external state has moved on.
The default for native records is restore-in-place when the original scope,
slug or handle reservation, and parent/container relationships are still valid.
Imported or provider-backed records, records with moved provider state, and
records whose active uniqueness constraints now conflict should restore as a
new linked active record or require an explicit rename/remap decision.

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

### 8. Apply retention, legal hold, export, and redaction by record family

Retention policy should apply by organization, workspace/initiative, resource
kind, classification, provider/source, and record family. Legal hold blocks
purge and retention expiry for affected records and must itself be audited.
Export must respect authorization, classification, redaction rules, secret
boundaries, model/tool payload controls, and audit visibility.

MVP retention should ship with default retention classes and behaviors while
remaining customer-configurable. Defaults should exist for product records,
revisions, audit records, authorization decisions, raw archives, model
payloads, tool-call payloads, external sync events, run events, derived
renders, and tombstones. Organization policy may override durations and
behaviors by scope, resource kind, classification, provider/source, and record
family, subject to legal hold and minimum compliance constraints.

Legal holds should target any combination of organization, workspace,
initiative, resource, actor, provider/source, classification, and record
family. Hold resolution should use the most restrictive matching hold and must
block purge, retention expiry, destructive redaction, and storage lifecycle
expiry for affected records until released through an audited workflow.

Export and redaction should produce a manifest that records included scopes,
record families, classifications, redaction decisions, excluded secrets,
payload references, digests, raw archive references, legal-hold interactions,
requesting principal, authorization basis, operation, and generated artifacts.
Secrets, credentials, prompts, model/tool payloads, raw archives, restricted
artifacts, and source-code-like content should export as references, digests,
or redacted summaries by default; full payload export requires explicit
authorization and classification approval.

The design should distinguish between product records, revisions, audit
records, authorization decisions, raw archives, model/tool payloads, external
sync events, run events, and derived renders because they have different
retention and redaction needs.

Alternatives considered:

- **One retention period per organization:** Easy to configure but too blunt
  for legal hold, secrets, prompts, raw payloads, and audit records.
- **Let storage lifecycle policies own retention alone:** Useful for blob
  expiration, but insufficient for domain authorization, export, and audit.

### 9. Plan audit/revision growth without overbuilding day one

Revision, audit, authorization decision, run event, sync event, and raw archive
tables should include organization, scope or resource references, actor/source,
action or record kind, operation, result/lifecycle, and event time indexes
where applicable. They should be partition-ready but do not need physical
partitioning before real customer volume or ingestion load proves the need.
For MVP, all revision, audit, authorization decision, retention, legal-hold,
export, raw archive, model/tool payload, run-event, and sync-event tables are
partition-ready only. No table requires day-one physical partitioning unless a
later implementation change introduces proven pre-customer volume or
compliance requirements that justify the operational complexity.

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

- Which low-risk reads beyond sensitive reads become durable audit records by
  default for the first customer profile?
