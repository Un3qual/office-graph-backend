## 1. Review And Acceptance

- [x] 1.1 Confirm this change defines revision, audit, soft-delete,
  tombstone, retention, legal-hold, restore, purge, and export design only and
  does not start Phoenix, Ash, Ecto, migration, API, frontend, Oban, SIEM, or
  storage-tier implementation.
- [x] 1.2 Confirm revisions, audit records, authorization decisions, domain
  events, run events, external sync events, and raw archives remain separate
  typed record families.
- [x] 1.3 Confirm operation correlation is a narrow command trace rather than a
  generic event payload or polymorphic target model.
- [x] 1.4 Confirm mutable product records use soft deletion or tombstones from
  the beginning while append-only records use retention/redaction/purge
  workflows instead of normal product deletion.
- [x] 1.5 Confirm retention, legal hold, export, and redaction rules are applied
  by organization, scope, resource kind, classification, provider/source, and
  record family.

## 2. Capability Spec Review

- [x] 2.1 Review `typed-revision-history` requirements for aggregate-aware
  typed revisions, reconstructable state, rich text/placement references, and
  concern separation.
- [x] 2.2 Review `audit-record-boundaries` requirements for durable audit
  triggers, denied/escalated attempts, audit record shape, sensitive payload
  references, and audit visibility.
- [x] 2.3 Review `operation-correlation` requirements for operation shape,
  correlated record references, idempotency, and causation.
- [x] 2.4 Review `soft-delete-tombstones` requirements for deleted lifecycle
  state, tombstone metadata, uniqueness, restore, and purge.
- [x] 2.5 Review `retention-legal-hold-export` requirements for retention
  policy, legal hold, export/redaction, and growth planning.

## 3. Open Decisions Before Migrations

- [x] 3.1 Decide which first migration aggregates need bespoke revision tables
  and which can share typed revision helper tables or conventions.
- [x] 3.2 Decide the first audit action taxonomy and result vocabulary for
  writes, reads, denials, escalations, approvals, waivers, exports, external
  writes, and agent tool use.
- [x] 3.3 Decide the first authorization decision record shape and how it links
  to audit records, policy bundle versions, operation correlation, and redacted
  graph projections.
- [x] 3.4 Decide the first tombstone shapes for graph items, work containers,
  conversations/messages, provider-neutral imported records, and artifacts.
- [x] 3.5 Decide restore-in-place versus restore-as-new behavior for each first
  mutable aggregate class.
- [x] 3.6 Decide active-record uniqueness and provider-identifier retention
  rules for deleted local and imported records.
- [x] 3.7 Decide the first retention classification fields and default retention
  behaviors for product records, revisions, audit records, raw archives,
  model/tool payloads, and derived renders.
- [x] 3.8 Decide the first legal-hold target model and how hold scope is
  resolved across organization, workspace, initiative, resource, actor,
  provider/source, classification, and record family.
- [x] 3.9 Decide the first export/redaction manifest shape for product records,
  audit records, revisions, raw archives, secrets, prompts, and restricted
  artifacts.
- [x] 3.10 Decide which revision/audit/retention tables are only
  partition-ready in MVP and which, if any, need day-one partitioning.

## 4. Follow-On Planning Work

- [x] 4.1 Feed revision, audit, tombstone, and retention boundaries into
  `design-code-organization-and-boundaries`.
- [ ] 4.2 Feed operation correlation, authorization decision, audit, approval,
  and credential-use records into `design-agent-runtime` and
  `design-runs-and-verification`.
- [x] 4.3 Feed raw archive retention, external sync event, idempotency, and
  provider reconciliation rules into `design-ingestion-and-integrations`.
- [x] 4.4 Feed revision, audit, tombstone, and proposed mutation traceability
  rules into `design-proposed-graph-changes`.
- [ ] 4.5 Feed export, redaction, audit visibility, and projection staleness
  constraints into `design-api-realtime-and-ui-projections`.
- [x] 4.6 Add audit JSON exception cross-link and edge tombstone/restore
  cascade rules.

## 5. Validation

- [x] 5.1 Run `openspec status --change design-revision-audit-soft-delete`.
- [x] 5.2 Run `openspec validate design-revision-audit-soft-delete --strict`.
- [x] 5.3 Fix any schema, delta, task-formatting, or validation issues reported
  by OpenSpec.
