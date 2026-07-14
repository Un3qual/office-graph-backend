## Context

`graph_relationships` currently contains only source item, target item, and a
free-form `relationship_type`. WorkGraph and Verification write
`produced_task`, `has_review_finding`, `requires_verification`, `has_evidence`,
and `references_artifact`, while the canonical `graph-relationships`
specification requires a narrow typed vocabulary, endpoint rules, scope,
lifecycle, provenance, and cycle behavior. The product is unreleased, so the
stored vocabulary can be migrated instead of supported by a compatibility
layer.

This change is the parent for GitHub integration and AgentRuntime. Both
consumers need to create or propose graph context without owning relationship
validation or gaining access through an edge.

## Goals / Non-Goals

**Goals:**

- Install the accepted MVP relationship vocabulary through migrations.
- Validate endpoint kinds, organization/scope, lifecycle, provenance,
  uniqueness, and cycle policy transactionally.
- Preserve relationship lifecycle and provenance without putting substantive
  facts in edge metadata.
- Migrate existing unreleased relationship rows to canonical definitions.
- Keep traversal authorization-filtered and query-bounded.

**Non-Goals:**

- No customer-defined relationship builder or registry administration UI.
- No broad graph editor or generic edge mutation API.
- No access inheritance through graph edges.
- No duplicate, merge, split, approval, waiver, saved-view, or workflow
  configuration relationship families beyond the accepted MVP vocabulary.
- No GitHub- or agent-specific relationship definitions in this change.

## Decisions

### 1. Definitions and endpoint rules are relational and migration-owned

Add `relationship_definitions` and `relationship_endpoint_rules` resources in
WorkGraph. Definitions store stable key, family, direction, meaning, lifecycle,
provenance, authorization, cycle, and specialization posture. Endpoint rules
store concrete source and target graph-item kinds.

This keeps the vocabulary queryable and extensible without hiding core rules in
JSON or requiring seeds. A hard-coded enum was rejected because future packages
need registered specializations. A user-editable registry was rejected because
governance and safe migration semantics are not in scope.

### 2. Relationship rows reference definitions and own explicit scope/lifecycle

`graph_relationships` retains concrete graph-item foreign keys and gains a
definition foreign key, organization, optional governing workspace, lifecycle,
asserting principal, operation, validity timestamps, and optional run,
integration event, supersession, and tombstone references. The old string is
removed after backfill.

Duplicating the canonical key on every edge was rejected because it permits
definition drift. Keeping only endpoint-derived scope was rejected because
cross-workspace policy and historical interpretation require an explicit
governing scope.

### 3. Named WorkGraph commands own all relationship mutations

Public functions create, supersede, archive, and restore relationships through
one WorkGraph transaction boundary. Proposal application, providers, and agents
call those commands or create proposals; they do not use the resource create
action directly.

A generic CRUD mutation was rejected because relationship types have different
endpoint, cycle, provenance, and lifecycle rules.

### 4. Cycle policy is definition-specific and concurrency-safe

Only definitions that prohibit cycles perform a bounded recursive traversal.
The command locks a stable organization/definition guard before validating and
inserting so two concurrent edges cannot each pass against stale graph state and
commit a cycle.

Checking all relationship families was rejected as unnecessary cost. An
unlocked preflight was rejected because it is race-prone.

### 5. Traversal never turns an edge into an access grant

Relationship reads first authorize the relationship scope and then authorize or
redact each endpoint through existing projection policy. Cross-workspace writes
require a separate capability and named command.

Filtering only at the relationship row was rejected because it could reveal an
otherwise restricted endpoint through adjacency.

### 6. Existing vocabulary is rewritten, not aliased

Backfill maps `produced_task` to `generated_from` and reverses signal-to-task
endpoints, maps `has_review_finding` to `review_finding_for` and reverses
task-to-finding endpoints, and maps `requires_verification` to `requires_check`
without reversal. It maps `has_evidence` to `evidenced_by` without reversal and
maps `references_artifact` to `generated_from` without reversal for
evidence-item-to-artifact endpoints. Unknown values abort with a count and value
list bounded for operator safety.

Compatibility aliases were rejected under the unreleased-development policy.

## Risks / Trade-offs

- Recursive cycle validation can become expensive → limit it to definitions
  that forbid cycles, add cardinality/query-count tests, and index definition
  plus endpoints.
- A definition guard can serialize hot edge families → scope locking to
  organization and definition and measure contention in concurrency tests.
- Backfill can reverse an edge incorrectly → assert legacy endpoint kinds before
  swapping and abort on mismatches.
- Explicit provenance increases row width → keep optional references nullable
  and store explanations/evidence in owning records.
- Cross-workspace scope can be ambiguous → require a governing workspace or an
  explicit organization-scoped command and record both endpoint scopes.

## Migration Plan

1. Create definition and endpoint-rule tables and install the MVP vocabulary.
2. Add nullable definition, scope, lifecycle, and provenance columns plus
   indexes to `graph_relationships`.
3. Validate all legacy values and endpoint kinds, backfill canonical definition
   references, and reverse `produced_task` and `has_review_finding` endpoints.
4. Add non-null and foreign-key constraints required for current rows.
5. switch WorkGraph commands, projections, and APIs to definition-backed reads.
6. Remove the legacy string column and regenerate schemas/artifacts.

Rollback recreates the legacy string column from canonical keys, restores the
five known legacy names and directions, removes new constraints/columns, and
drops registry tables only after proving no post-change relationship type or
lifecycle state would be lost.

## Open Questions

None. The accepted MVP vocabulary, identity deferral, and dependency ordering
are fixed by the approved program design.
