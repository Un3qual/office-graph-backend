## 1. Review And Acceptance

- [x] 1.1 Review `openspec/project.md` for scope, authorization, graph
  projection, operation correlation, audit, revision, and code-boundary
  project direction.
- [x] 1.2 Review `design-identity-and-authorization-schema` for typed scope
  rows, closure rows, inheritance modes, scope moves, principal/role/grant
  facts, sensitivity labels, policy bundles, and fact-version anchors.
- [x] 1.3 Review `design-revision-audit-soft-delete` for operation
  correlation, durable audit records, authorization decisions, typed
  revisions, concern separation, and idempotency.
- [x] 1.4 Review `design-code-organization-and-boundaries` for bounded-context
  ownership, Ash policy integration, direct SQL safeguards, shared operation
  contracts, and projection read-model ownership.
- [x] 1.5 Review accepted graph projection, UI projection, realtime, tenancy,
  graph item, and graph relationship specs for authorization-filtered
  projection and invalidation constraints.
- [x] 1.6 Confirm this change remains design-only and does not start Phoenix,
  Ash, Ecto, migration, GraphQL, JSON API, React, Oban, realtime, repair-job,
  or runtime implementation.

## 2. Capability Spec Review

- [x] 2.1 Add `scope-hierarchy-implementation-plan` requirements for
  authorization-owned scope hierarchy implementation, typed scope rows, closure
  rows, inheritance modes, and repair/rebuild planning.
- [x] 2.2 Add `scope-move-operation-plan` requirements for governed scope move
  commands, tenant/type/cycle/policy checks, idempotency, closure updates,
  operation correlation, audit, revisions, authorization decisions, and
  compensation.
- [x] 2.3 Add `scope-projection-invalidation-plan` requirements for
  authorization explanation invalidation, graph projection invalidation,
  derived context/render cache staleness, and realtime invalidation hints.

## 3. Planning Decisions Before Code Or Migrations

- [x] 3.1 Decide authorization owns scope truth while operation correlation
  owns command trace.
- [x] 3.2 Decide scope rows must remain typed and concrete enough for ownership
  rather than using unbounded local `resource_type` plus `resource_id`
  references.
- [x] 3.3 Decide closure rows are durable path facts for authorization checks,
  explanations, repair, and projection invalidation while direct parentage
  remains the hierarchy source of truth.
- [x] 3.4 Decide path inheritance and role/grant/sensitivity inheritance are
  separate facts interpreted together by policy.
- [x] 3.5 Decide scope moves are governed domain commands with tenant, type,
  cycle, lifecycle, policy, legal/retention, and idempotency validation.
- [x] 3.6 Decide scope moves write separate operation, audit, revision, and
  authorization decision records instead of one generic event payload.
- [x] 3.7 Decide closure rebuild and repair are controlled maintenance
  workflows with operation correlation, bounded diff summaries, and equivalent
  invalidation semantics.
- [x] 3.8 Decide scope hierarchy mutations must invalidate authorization
  explanations, graph projections, work packet/agent context, render caches,
  and realtime subscribers before stale derived state is reused.

## 4. Follow-On Planning Work

- [x] 4.1 Defer scope table migrations, closure-row indexes, move commands,
  repair jobs, projection invalidation events, API exposure, and tests to a
  later implementation change after this design change is accepted.
- [x] 4.2 Feed these planning requirements into future implementation work for
  `OfficeGraph.Authorization`, `OfficeGraph.Operations`, `OfficeGraph.Audit`,
  `OfficeGraph.Revisions`, `OfficeGraph.Projections`, work packet context,
  agent context, and realtime delivery.
- [x] 4.3 Keep existing active change directories unchanged except for marking
  the parent `design-identity-and-authorization-schema` task 3.2 complete after
  this change validates.

## 5. Validation

- [x] 5.1 Run `openspec validate design-scope-hierarchy-implementation
  --strict`.
- [x] 5.2 Run `openspec validate --changes --strict`.
- [x] 5.3 Fix any schema, delta, scenario-format, task-formatting, or
  validation issues reported by OpenSpec.
