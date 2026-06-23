## 1. Review And Acceptance

- [x] 1.1 Confirm `proposal.md` scopes this change to core work-graph
  semantics and not Phoenix, Ash, database, API, frontend, or agent-runtime
  implementation.
- [x] 1.2 Confirm `design.md` keeps graph addressability as a shared contract
  while preserving typed resources and domain actions for business meaning.
- [x] 1.3 Confirm initiatives/projects are bounded work containers and that
  teams, departments, org units, components, repositories, services, campaigns,
  finance accounts, design systems, and external systems attach as related
  scopes or resources rather than becoming projects by default.
- [x] 1.4 Confirm graph projections are filtered views over scoped graph data
  and do not create tenant, access, or permission boundaries.
- [x] 1.5 Confirm domain attachment promotion is a product/schema evolution
  decision, not arbitrary per-record runtime schema creation by users.
- [x] 1.6 Confirm the concrete MVP inventory of provider-neutral resources,
  external-reference-only records, provider-specific extension tables, and
  initial Ash resources is deferred to `design-persistence-model`.

## 2. Capability Spec Review

- [x] 2.1 Review `work-containers` requirements for initiative/project
  containers, workstreams, non-project related resources, small work items, and
  explicit container scope.
- [x] 2.2 Review `graph-items` requirements for addressability, department-
  neutral item types, typed-resource ownership of business meaning,
  type-specific lifecycles, projection status families, and provenance.
- [x] 2.3 Review `graph-relationships` requirements for typed edge
  definitions, initial relationship families, access-control implications,
  narrow metadata, lifecycle, and provenance.
- [x] 2.4 Review `graph-projections` requirements for authorization-filtered
  views, restricted placeholders, summary leakage controls, initial projection
  families, projection status families, and explainability.
- [x] 2.5 Review `domain-attachments` requirements for typed attachments,
  provider-neutral base concepts, external references, product-level promotion
  to dedicated resources, and attachment boundaries.
- [x] 2.6 Review `node-conversations` requirements for conversations attached
  to addressable graph items, context assembly, embedded-agent boundaries,
  conversation provenance, and graph-action routing.

## 3. Open Work Graph Questions

- [x] 3.1 Decide which exact edge types belong in MVP versus the first
  follow-up release.
- [x] 3.2 Decide whether document and plan sections are first-class core graph
  item types in MVP or start as domain attachments that become graph items
  when individually addressed.
- [x] 3.3 Decide which initial projections are required for the first
  customer-facing MVP: inbox, question queue, work packet context, focused
  node view, blocker view, workstream board, evidence chain, review surface,
  or another projection.
- [x] 3.4 Decide which graph item types require dedicated Ash resources
  immediately and which can wait until the persistence model is designed.
- [x] 3.5 Decide the first normalized projection status families after the
  MVP item lifecycles are known.

## 4. Follow-On Planning Work

- [x] 4.1 Feed work-container, graph-item, relationship, projection,
  attachment, and node-conversation semantics into `design-persistence-model`.
- [x] 4.2 In `design-persistence-model`, define the concrete MVP inventory of
  provider-neutral resources, external-reference-only records,
  provider-specific extension tables, and initial Ash resources.
- [x] 4.3 Feed graph item, edge, projection, domain attachment, conversation,
  and product-level promotion semantics into `design-revision-audit-soft-delete`.
- [x] 4.4 Feed graph addressability, typed-resource boundaries, domain actions,
  and projection/query interfaces into `design-code-organization-and-boundaries`.
- [x] 4.5 Feed node-conversation context assembly, context expansion needs, and
  embedded-agent mutation boundaries into `design-agent-runtime`.
- [x] 4.6 Feed external references, provider-neutral domain attachments, and
  source provenance rules into `design-ingestion-and-integrations`.
- [x] 4.7 Feed explicit graph-action routing and attachment-to-resource
  conversion rules into `design-proposed-graph-changes`.
- [x] 4.8 Record that work-container scope, addressable graph items, checks,
  evidence, and projection context are available to
  `design-work-packets-and-readiness` and `design-runs-and-verification`, but
  the detailed packet/run handoff remains deferred until those designs
  stabilize.
- [x] 4.9 Feed initial projection families and authorization-filtered graph
  context into `design-api-realtime-and-ui-projections`.
- [x] 4.10 Feed the first executable walking skeleton graph slice into
  `design-persistence-model` and the project remediation plan.
- [x] 4.11 Lock schema-facing work-container language to `initiative` and add
  graph relationship restore eligibility rules.

## 5. Validation

- [x] 5.1 Run `openspec status --change design-work-graph-core`.
- [x] 5.2 Run `openspec validate --changes --strict`.
- [x] 5.3 Fix any schema, delta, task-formatting, or validation issues reported
  by OpenSpec.
