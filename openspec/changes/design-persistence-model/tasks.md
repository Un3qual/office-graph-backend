## 1. Review And Acceptance

- [x] 1.1 Confirm this change defines persistence architecture only and does
  not start Phoenix, Ash, Ecto, database migration, API, frontend, Oban, or
  agent-runtime implementation.
- [x] 1.2 Confirm Office Graph uses shared graph identity for addressability
  while business fields, validations, lifecycle, and actions remain in typed
  resources.
- [x] 1.3 Confirm core local persistence avoids polymorphic `type` plus `id`
  references and uses concrete foreign keys to graph identity or typed domain
  tables.
- [x] 1.4 Confirm provider-neutral base resources are preferred before
  provider-specific extension tables.
- [x] 1.5 Confirm external references, raw payload archives, and typed product
  resources are separate persistence concepts.
- [x] 1.6 Confirm JSON/JSONB is limited to raw, replay, debugging, model,
  tool-call, and explicitly accepted temporary unmodeled payloads.
- [x] 1.7 Confirm tenant and scope columns are explicit when needed for
  authorization, filtering, indexing, export, retention, or deletion.
- [x] 1.8 Confirm rich text bodies use normalized Office Graph document state
  instead of Lexical JSON or another editor payload as canonical storage.
- [x] 1.9 Confirm rich text revisions use whole-document semantic revisions in
  v1 with stable identities, pinned exact-span quote snapshots, and selection
  segments while allowing later copy-on-write inline versions, live anchors,
  render caches, and collaboration state to attach without replacing the v1
  model.
- [x] 1.10 Confirm ordered structures use domain-owned ordering in v1 with
  concrete foreign keys, sortable position keys, lifecycle state, operation
  correlation, and compatibility with later shared placement behavior.
- [x] 1.11 Confirm high-volume tables are partition-ready and linked by
  operation correlation instead of duplicated large payloads.

## 2. Capability Spec Review

- [x] 2.1 Review `mvp-persistence-inventory` requirements for first-class
  product resources, reserved execution resources, software proving resources,
  and external-reference-only deferred domains.
- [x] 2.2 Review `graph-storage-contract` requirements for graph identity,
  typed relationships, no polymorphic local references, and authorization-
  filtered graph projections.
- [x] 2.3 Review `provider-neutral-resources` requirements for shared external
  concepts, explicit provider identity, and native Office Graph records using
  the same base model where appropriate.
- [x] 2.4 Review `extension-table-rules` requirements for extension-table
  justification, preserved base identity, and promotion when provider-specific
  behavior becomes shared behavior.
- [x] 2.5 Review `external-reference-model` requirements for external
  reference identity, promotion to typed resources, and separate raw payload
  archives.
- [x] 2.6 Review `json-storage-policy` requirements for JSON boundaries,
  typed archive envelopes, and promotion paths for temporary unmodeled data.
- [x] 2.7 Review `tenant-scope-indexing` requirements for explicit tenant and
  scope columns, baseline index families, and soft-delete-aware uniqueness.
- [x] 2.8 Review `large-table-growth` requirements for partition-ready high-
  volume tables, archive references, and operation correlation.
- [x] 2.9 Review `portable-rich-text-persistence` requirements for editor-
  independent rich text, stable extension identities, whole-document semantic
  revisions, normalized marks, typed references, pinned quote snapshots,
  selection segments, deferred live quote/reconstruction behavior, and derived
  plain text.
- [x] 2.10 Review `ordered-placement-model` requirements for domain-owned v1
  ordering, concrete references, sortable position keys, lifecycle state,
  operation correlation, and future shared ordering strategies.

## 3. Open Decisions Before Migrations

- [x] 3.1 Split the first-class persistence inventory into immediate MVP
  migration scope, near-follow-up scaffolding, and deferred external-reference-
  only domains.
- [x] 3.2 Decide whether review comments and review findings both ship in the
  first software proving workflow or whether one starts as external reference
  context.
- [x] 3.3 Decide whether observability issues and events are provider-neutral
  from day one or begin with Sentry-focused normalized records after an
  integration spike.
- [x] 3.4 Decide which graph projection queries need dedicated read models in
  MVP, if any.
- [x] 3.5 Decide which high-volume tables are only partition-ready in MVP and
  which, if any, need day-one partitioning.
- [x] 3.6 Decide the first portable rich text node, mark, and reference types
  and the handling for unsupported editor features.
- [x] 3.7 Decide that v1 uses whole-document semantic revisions while keeping
  stable identities for future validity ranges, explicit revision membership
  rows, periodic materialized snapshots, or a hybrid.
- [x] 3.8 Decide which MVP ordered structures use explicit domain-owned fields
  or typed placement tables while preserving compatibility with future shared
  placement behavior.
- [x] 3.9 Decide the first sortable position-key implementation, rebalance
  policy, and conflict behavior for concurrent reorders.
- [x] 3.10 Decide the first operation-correlation record shape shared by
  revisions, audit records, run events, sync events, change proposals,
  and domain events.

## 4. Follow-On Planning Work

- [x] 4.1 Create or continue `design-revision-audit-soft-delete` to finalize
  revision records, audit logs, tombstones, retention, legal hold, restore
  behavior, and how operation correlation links them without duplicating data.
- [x] 4.2 Create or continue `design-code-organization-and-boundaries` to map
  graph identity, typed resources, provider-neutral records, rich text,
  ordered placement, raw archives, and high-volume SQL paths into Ash domains,
  Ecto modules, Boundary rules, and extractable library boundaries.
- [x] 4.3 Create or continue `design-ingestion-and-integrations` to refine
  external sources, raw payload archives, provider adapters, idempotency,
  replay, sync state, extension packages, and provider-specific extension
  tables.
- [x] 4.4 Create or continue `design-agent-runtime` to consume graph identity,
  rich text references, external references, raw archives, operation
  correlation, and cross-scope context expansion safely.
- [ ] 4.5 Create or continue `design-runs-and-verification` to refine runs,
  run events, checks, evidence, review findings, verification state, and
  high-volume event persistence.
- [x] 4.6 Create or continue `design-proposed-graph-changes` to define how
  agents and humans propose typed persistence changes without bypassing graph,
  authorization, revision, and approval rules.
- [x] 4.7 Create or continue `design-work-packets-and-readiness` to define
  work packets, execution packages, readiness checks, approval gates, and
  agent-executable block constraints.
- [x] 4.8 Retarget accepted API, realtime, render-cache, agent Markdown, and
  projection follow-up work to durable specs:
  `openspec/specs/ash-api-surface/spec.md`,
  `openspec/specs/realtime-delivery/spec.md`,
  `openspec/specs/graph-projections/spec.md`, and
  `openspec/specs/ui-projection-contracts/spec.md`.
- [x] 4.9 Resolve the rich text implementation direction before schema
  migrations: v1 includes pinned exact-span quote snapshots, selection
  segments, source freshness, and current-permission reauthorization, while
  live quote updating, automatic re-anchoring, render caches, and
  collaboration/session behavior remain deferred.
- [ ] 4.10 Create a future ordered placement implementation design before
  building reusable placement APIs, typed placement migrations, position-key
  libraries, rebalance jobs, derived ordinal projections, or strategy-specific
  extension tables.
- [x] 4.11 Reference `design-identity-and-authorization-schema` as the owning
  companion inventory for principals, external identities, authorization
  scopes, roles, capabilities, grants, policy facts, sensitivity labels, and
  credential metadata before first migrations.
- [x] 4.12 Define the first walking skeleton persistence scope and pull
  skeletal work packets, runs, run events, change proposals, and
  verification results forward only as needed to prove the loop.
- [x] 4.13 Narrow rich text v1 to normalized documents, current blocks, stable
  text-run or inline-span identities, basic marks/references, pinned
  exact-span quote snapshots, selection segments, whole-document semantic
  revisions, source freshness state, and derived plain text.
- [x] 4.14 Narrow ordered placement v1 to explicit task-list ordering and rich
  text block ordering with concrete references.
- [x] 4.15 Add the graph identity plus typed resource same-transaction
  invariant.
- [x] 4.16 Lock schema-facing scope language to `initiative` and cross-link
  audit JSON details as a controlled JSON exception.
- [x] 4.17 Add rich text and ordering extension invariants so MVP narrowing
  does not force a later redesign when deferred features are promoted.

## 5. Validation

- [x] 5.1 Run `openspec status --change design-persistence-model`.
- [x] 5.2 Run `openspec validate design-persistence-model --strict`.
- [x] 5.3 Fix any schema, delta, task-formatting, or validation issues
  reported by OpenSpec.
