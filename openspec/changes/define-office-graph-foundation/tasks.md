# Tasks

## 1. Foundation Review

- [x] Review the proposal against `openspec/project.md` and
  `openspec/project-plan.md`.
- [x] Confirm that the generated PRD remains reference material only.
- [x] Confirm that the company-wide target, software proving workflow, React
  frontend, GraphQL plus JSON API, no LiveView, and internal agent runtime are
  locked.

## 2. Capability Specs

- [x] Review `foundation` requirements for product framing and platform
  constraints.
- [x] Review `work-graph` requirements for graph items, typed edges, proposed
  changes, work packets, questions, decisions, and micro-approvals.
- [x] Confirm `design-agent-runtime` owns embedded agents, automatic agents,
  structured output, tool separation, and run provenance.
- [x] Review `authorization` requirements for principals, hybrid policy,
  scoped visibility, agent permissions, relational permission data, and
  decision records.
- [x] Review `verification` requirements for checks, evidence, monitoring,
  waivers, and traceability.
- [x] Review `persistence` requirements for relational schemas, JSON
  avoidance, typed revisions, soft deletion, tenant scope, and large-table
  planning.
- [x] Review `backend-architecture` requirements for modular monolith,
  Boundary, Ash/Ecto boundaries, API layering, realtime, library extraction,
  and integration package boundaries.

## 3. Open Questions To Resolve Before Code

- [ ] Decide the first buyer, daily user, and flagship success metric.
- [x] Decide whether first intake is manual, GitHub, Sentry, CI, or another
  source.
- [x] Decide the first schema cut for generic graph records versus typed
  resources and extension tables.
- [x] Decide the initial tenancy scopes: organization, workspace, project,
  graph, repository, or a smaller subset.
- [x] Decide the first role, capability, and grant vocabulary.
- [x] Decide which authorization decisions must be durable records in v1.
- [x] Decide the first internal agent runtime scope for code review/fix versus
  conversation/review/proposed-change workflows in `design-agent-runtime`.
- [x] Decide where JSON storage is acceptable for raw payloads, model I/O, and
  archival data.
- [x] Decide the revision table pattern for the first aggregates.

### Plan Review Remediation

- [x] Resolve the concrete identity, authorization, credential, scope
  hierarchy, policy fact, sensitivity label, and external identity inventory in
  `design-identity-and-authorization-schema`.
- [x] Resolve authentication mechanics, session/token behavior, service
  account and agent credential issuance, external identity reconciliation, and
  first-org/first-admin bootstrap in
  `design-identity-and-authentication`.
- [x] Reconcile canonical capability ownership before promoting foundation
  requirements so this foundation change stays product framing rather than a
  duplicate durable source for authorization, persistence, work graph, audit,
  or code organization details.
- [x] Narrow the first backend target to the walking skeleton captured in
  `openspec/project-plan.md` and the persistence/work-graph changes.
- [x] Capture manual intake, ingestion normalization, idempotency, replay, and
  proposed graph change semantics in `design-ingestion-and-integrations` and
  `design-proposed-graph-changes` before backend code generation.
- [ ] Mark individual open questions above complete only after the downstream
  active change that owns the decision contains the accepted answer.

## 4. Follow-On OpenSpec Changes

- [x] Create `design-work-graph-core`.
- [x] Create `design-persistence-model`.
- [x] Create `design-revision-audit-soft-delete`.
- [x] Create `design-code-organization-and-boundaries`.
- [x] Create `design-ingestion-and-integrations`.
- [x] Create `design-agent-runtime`.
- [x] Create `design-proposed-graph-changes`.
- [x] Create `design-work-packets-and-readiness`.
- [ ] Create `design-runs-and-verification`.
- [x] Promote API, realtime, graph-projection, and UI-projection follow-on
  decisions into accepted durable specs.
- [x] Create `design-enterprise-governance`.

## 5. Validation

- [x] Run `openspec status --change define-office-graph-foundation`.
- [x] Run `openspec validate --changes --strict` once the OpenSpec CLI is
  available in the project environment.
- [x] Fix any schema or formatting issues reported by OpenSpec.
