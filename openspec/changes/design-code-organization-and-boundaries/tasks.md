## 1. Review And Acceptance

- [x] 1.1 Review `proposal.md` against `openspec/project.md`,
  `openspec/project-plan.md`, and the accepted foundation direction.
- [x] 1.2 Confirm this change remains design-only and does not start Phoenix,
  Ash, Ecto, database migration, GraphQL, JSON API, React, Oban, integration,
  or agent-runtime implementation.
- [x] 1.3 Confirm the backend starts as one Phoenix API application with
  Boundary-enforced internal contexts rather than an umbrella app,
  microservice split, or separate Hex packages.
- [x] 1.4 Confirm the initial context map covers identity, tenancy,
  authorization, audit, operation correlation, work containers, work graph,
  content, ordered placement, revisions, tombstones, external references, raw
  archives, integrations, software proving records, work packets, runs,
  verification, proposed graph changes, agent runtime, entrypoints, and
  projections.
- [x] 1.5 Confirm Ash owns normal domain mutations, validations, lifecycle
  rules, and policy integration for typed resources.
- [x] 1.6 Confirm direct Ecto and explicit SQL are limited to context-owned
  traversal, projection, replay, analytics, high-volume, partition,
  maintenance, backfill, and bulk reconciliation paths.
- [x] 1.7 Confirm operation correlation is the shared write spine without
  becoming a generic event payload or polymorphic target model.
- [x] 1.8 Confirm revisions, audit records, authorization decisions,
  tombstones, raw archives, external sync events, run events, and domain events
  remain separate typed record families.
- [x] 1.9 Confirm library-ready domains stay internal until their APIs, tests,
  configuration, and data contracts are stable enough for extraction.
- [x] 1.10 Confirm controllers, resolvers, JSON API handlers, Oban workers,
  integration adapters, and agent runtime tools enter through public domain
  contracts.

## 2. Capability Spec Review

- [x] 2.1 Review `bounded-context-architecture` requirements for the modular
  monolith baseline, context ownership, dependency direction, and initial
  context map.
- [x] 2.2 Review `ash-domain-boundaries` requirements for Ash domain ownership,
  public Ash access, authorization integration, and shared side-effect
  contracts.
- [x] 2.3 Review `ecto-sql-boundaries` requirements for approved direct SQL
  paths, authorization inputs, mutation safeguards, and read-model ownership.
- [x] 2.4 Review `boundary-enforcement` requirements for Boundary definitions,
  private module protection, CI verification, and test discipline.
- [x] 2.5 Review `shared-operation-contracts` requirements for operation
  context propagation, concern separation, concrete references, and shared
  contract ownership.
- [x] 2.6 Review `extractable-library-boundaries` requirements for candidate
  identification, extraction gates, product-assumption isolation, and
  extraction-readiness tests.
- [x] 2.7 Review `entrypoint-boundary-contracts` requirements for thin
  entrypoints, shared policy/mutation paths, API surface reuse, and projection
  entrypoint behavior.

## 3. Open Decisions Before Code Generation

- [x] 3.1 Decide exact Elixir module names and folder layout for the first
  Phoenix code cut.
- [x] 3.2 Decide whether operation correlation starts as a dedicated context or
  under a broader revision/audit primitives context.
- [x] 3.3 Decide whether software proving records begin as a separate context or
  as a provider-neutral integration subdomain.
- [x] 3.4 Decide which first graph projection queries require direct SQL versus
  Ash-backed query composition.
- [x] 3.5 Decide how strict initial Boundary exports should be before the first
  working resource set exists.
- [x] 3.6 Decide which library-candidate domains need behaviours or callback
  seams in the first code cut.

## 4. Follow-On Planning Work

- [x] 4.1 Feed the context map, Boundary rules, and Ash/Ecto ownership rules
  into the first backend app-generation change.
- [x] 4.2 Feed entrypoint and projection rules into
  `design-api-realtime-and-ui-projections`.
- [ ] 4.3 Feed provider adapter, raw archive, sync event, and
  provider-neutral ownership rules into `design-ingestion-and-integrations`.
- [x] 4.4 Feed agent entrypoint, operation context, authorization, and
  extractability rules into `design-agent-runtime`.
- [ ] 4.5 Feed shared operation, revision, audit, and validation rules into
  `design-proposed-graph-changes`.
- [ ] 4.6 Feed work packet, run, verification, evidence, and read-model
  ownership rules into `design-work-packets-and-readiness` and
  `design-runs-and-verification`.
- [x] 4.7 Create a future implementation plan before generating Phoenix, Ash,
  Ecto, Boundary, API, Oban, integration, or agent-runtime code.
- [x] 4.8 Add the cross-change backend implementation-readiness gate and name
  `first-backend-walking-skeleton` as the next app-generation change after the
  gate is satisfied and approved.

## 5. Validation

- [x] 5.1 Run `openspec status --change design-code-organization-and-boundaries`.
- [x] 5.2 Run `openspec validate design-code-organization-and-boundaries --strict`.
- [x] 5.3 Run `openspec validate --changes --strict`.
- [x] 5.4 Fix any schema, delta, scenario-format, task-formatting, or
  validation issues reported by OpenSpec.
