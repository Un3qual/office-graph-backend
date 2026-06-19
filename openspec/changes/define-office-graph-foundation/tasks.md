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
- [x] Review `agent-runtime` requirements for embedded agents, automatic
  agents, structured output, tool separation, and run provenance.
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
- [ ] Decide whether first intake is manual, GitHub, Sentry, CI, or another
  source.
- [ ] Decide the first schema cut for generic graph records versus typed
  resources and extension tables.
- [ ] Decide the initial tenancy scopes: organization, workspace, project,
  graph, repository, or a smaller subset.
- [ ] Decide the first role, capability, and grant vocabulary.
- [ ] Decide which authorization decisions must be durable records in v1.
- [ ] Decide the first internal agent runtime scope for code review/fix versus
  conversation/review/proposed-change workflows.
- [ ] Decide where JSON storage is acceptable for raw payloads, model I/O, and
  archival data.
- [ ] Decide the revision table pattern for the first aggregates.

## 4. Follow-On OpenSpec Changes

- [ ] Create `design-work-graph-core`.
- [ ] Create `design-persistence-model`.
- [ ] Create `design-revision-audit-soft-delete`.
- [ ] Create `design-code-organization-and-boundaries`.
- [ ] Create `design-ingestion-and-integrations`.
- [ ] Create `design-agent-runtime`.
- [ ] Create `design-proposed-graph-changes`.
- [ ] Create `design-work-packets-and-readiness`.
- [ ] Create `design-runs-and-verification`.
- [ ] Create `design-api-realtime-and-ui-projections`.
- [ ] Create `design-enterprise-governance`.

## 5. Validation

- [x] Run `openspec status --change define-office-graph-foundation`.
- [x] Run `openspec validate --changes --strict` once the OpenSpec CLI is
  available in the project environment.
- [x] Fix any schema or formatting issues reported by OpenSpec.
