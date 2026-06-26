## Context

Office Graph is past the point where the walking skeleton can safely keep
absorbing feature work. The accepted specs already set the direction:
AshGraphql and AshJsonApi are the default API posture, bounded contexts own
domain behavior, React is the product UI, LiveView is forbidden, and UI
surfaces should read through explicit projection contracts.

The implementation does not yet match that posture. The live GraphQL API is a
single hand-written `OfficeGraphWeb.Schema`; JSON endpoints are Phoenix
controllers and serializers under `/api`; `OfficeGraph.ApiSupport` owns request
validation, local owner context loading, orchestration transactions, idempotency
digesting, and projection reads; large public context modules contain many
manual Ash calls and direct transaction boundaries; and the first React console
has started without a durable routing, data-fetching, component, or design
system foundation.

The conceptual model has also become too broad for the first product spine.
The stable MVP loop is simple: messy signal, change proposal, work item, work
packet, run, check, evidence, verification, reusable context. Backend
infrastructure such as graph identity, operation correlation, raw archives,
execution observations, evidence candidates, audit records, revisions, and
policy bundles remains valuable, but it should not automatically become
operator-facing API or UI vocabulary.

This change is planning and governance work. It intentionally does not rewrite
runtime behavior. It defines the sequence and gates that later implementation
changes must follow.

## Goals / Non-Goals

**Goals:**

- Stop new product work from copying the current manual transport and
  single-component frontend patterns.
- Define a staged migration from hand-written GraphQL/JSON surfaces toward
  AshGraphql/AshJsonApi resource surfaces plus narrow custom command/projection
  exceptions.
- Define how domain/resource cleanup should reduce direct Ecto, manual
  `authorize?: false` paths, and transport-adjacent orchestration without
  exposing unsafe generated writes.
- Define a frontend architecture foundation before more operator surfaces,
  packet views, run views, graph projections, or verification screens are
  added.
- Define the canonical MVP product vocabulary and classify non-spine concepts
  as backend infrastructure unless a workflow requires operator action.
- Add verification gates that make architectural drift visible.

**Non-Goals:**

- Do not perform the API, domain, persistence, or frontend refactors in this
  planning change.
- Do not expose all Ash resource creates or updates through generated APIs.
  Private lifecycle actions must stay private unless a later spec explicitly
  makes them safe public actions.
- Do not remove the existing walking-skeleton or operator-console endpoints
  until compatibility tests and replacement clients exist.
- Do not split the application into microservices or separate frontend/backend
  deployables.
- Do not implement full identity provider flows, SCIM UI, rich text quote
  models, graph canvas behavior, native agent execution, or realtime client
  state management here.

## Decisions

### 1. Stabilize In Four Tracks

The remediation work should be split into four coordinated tracks:

1. API surface migration.
2. Ash/domain ownership cleanup.
3. Frontend architecture foundation.
4. Product concept simplification.

These tracks can be planned together, but implementation should land in small
changes with one dominant risk area at a time. The first implementation change
should add gates and documentation, not a broad rewrite.

Alternative considered: one large cleanup branch. Rejected because it would
mix API behavior, domain lifecycle, UI structure, and vocabulary migration in a
way that would be hard to review and likely to break the existing smoke value.

### 2. Keep A Small User-Facing Product Spine

The MVP product spine is:

```text
Signal
  -> Change Proposal
  -> Work Item
  -> Work Packet
  -> Run
  -> Check
  -> Evidence
  -> Verification
```

`Work Packet` is the user-facing execution contract. `Run` is the user-facing
attempt to execute that contract. `Evidence` is user-facing with explicit
states such as suggested, accepted, rejected, and stale. `Verification` is the
decision over checks and evidence. `Change Proposal` is the only accepted
product term for proposed domain mutations.

Infrastructure concepts can still exist in storage and audit paths, but they
should be hidden behind projection contracts by default. This means
`EvidenceCandidate`, `ExecutionObservation`, `OperationCorrelation`,
`GraphItem`, `GraphRelationship`, `VerificationResult`, `RawArchive`, and
`PolicyBundle` are not automatically product API nouns.

Alternative considered: expose every typed backend record as a product concept
because the storage model is typed. Rejected because it makes the operator
experience and API contracts reflect implementation mechanics instead of the
work loop.

### 3. Migrate APIs By Compatibility, Not Big Bang

API cleanup should proceed in stages:

1. Add guard tests and exception ledgers for manual GraphQL root fields,
   Phoenix JSON resource endpoints, and custom command/projection routes.
2. Modularize the existing GraphQL schema and JSON API code into separate
   transport namespaces without changing routes or behavior.
3. Mount/read from AshGraphql and AshJsonApi for safe read-only or simple
   resource surfaces on WorkGraph, WorkPackets, and Runs.
4. Promote composite command behavior out of `OfficeGraph.ApiSupport` into an
   owning domain command module.
5. Migrate clients/tests from compatibility routes to generated or explicitly
   documented command/projection APIs.
6. Retire compatibility endpoints after parity and client migration.

Custom transport code remains valid for commands and projections that span
domains or need a non-resource envelope. It must stay thin: context loading,
calling public domain commands, and transport-specific error presentation.

GraphQL and JSON API code should remain transport-separated under
`OfficeGraphWeb`, not promoted to independent root application namespaces. The
locked organization rule is transport first, capability second, purpose third:

```text
lib/office_graph_web/
  graphql/
    schema.ex
    root_query.ex
    root_mutation.ex
    common/
      errors.ex
      scalars.ex
    work_graph/
      types.ex
      queries.ex
      mutations.ex
      resolvers.ex
    work_packets/
      types.ex
      queries.ex
      mutations.ex
      resolvers.ex
    runs/
      types.ex
      queries.ex
      mutations.ex
      resolvers.ex
    verification/
      types.ex
      queries.ex
      mutations.ex
      resolvers.ex
    operator_workflow/
      types.ex
      queries.ex
      resolvers.ex
    packet_run_verification/
      types.ex
      mutations.ex
      resolvers.ex
    compatibility/

  json_api/
    common/
      errors.ex
      params.ex
    work_graph/
      controller.ex
      serializer.ex
    work_packets/
      controller.ex
      serializer.ex
    runs/
      controller.ex
      serializer.ex
    verification/
      controller.ex
      serializer.ex
    operator_workflow/
      controller.ex
      serializer.ex
    packet_run_verification/
      controller.ex
      serializer.ex
    compatibility/
```

The matching module roots are `OfficeGraphWeb.GraphQL.*` and
`OfficeGraphWeb.JsonApi.*`. Capability folders may represent a bounded domain
such as WorkPackets or Runs, or a durable custom command/projection surface
such as OperatorWorkflow or PacketRunVerification. Transport-shared helpers
belong under that transport's `common` namespace. Domain behavior, command
ownership, and projection contracts belong under `OfficeGraph.*`, not under a
generic `OfficeGraphWeb.Api` namespace.

Alternative considered: immediately replace `/graphql` and `/api` with
generated Ash APIs. Rejected because current commands span multiple domains,
some resource actions are intentionally private, and compatibility tests still
provide useful smoke coverage.

Alternative considered: create top-level API roots such as `OfficeGraphGQL` or
`OfficeGraphRestApi`. Rejected because these APIs are presentation/transport
concerns inside the Phoenix web boundary, not separate bounded contexts or OTP
apps. If the APIs later become independently packaged applications, that can
be revisited.

### 4. Treat Exception Ledgers As Burn-Down Lists

The direct Ecto exception ledger is not the target architecture. It is a
visible debt register. New direct Ecto, raw SQL, broad `authorize?: false`, or
manual Ash orchestration paths must either use an existing ledger entry or add
a narrow entry with owner, reason, allowed operation type, approving spec, and
retirement condition.

Implementation changes should retire ledger entries by moving stable lifecycle,
authorization, validation, operation correlation, idempotency, and audit/revision
behavior into owning Ash actions or public domain commands. Some explicit
transaction boundaries may remain when Ash does not yet express a safe atomic
workflow, but those boundaries must be owned by a domain, not by a controller or
transport helper.

Alternative considered: ban all direct Ecto immediately. Rejected because some
current transaction/idempotency paths are real safety mechanisms and need
careful replacement.

### 5. Build A Lightweight But Real Frontend Foundation

The React app should move toward this structure:

```text
Phoenix app shell
  -> React routes
    -> feature route/container
      -> projection hooks
        -> query cache
          -> JSON adapter now
          -> GraphQL adapter when stable
shared tokens -> shared UI primitives -> feature components
```

The first frontend implementation change should:

- promote concept tokens to CSS custom properties;
- create generic shared primitives such as badge, button, panel, pane header,
  nav rail, text field, and empty state;
- split the 500-line operator console into route/container, query hooks,
  workbench layout, inbox, detail, readiness, run, and verification panels;
- introduce a projection-client interface so JSON and future GraphQL adapters
  return the same frontend view model;
- add a query cache for server state once more than one route or realtime
  invalidation exists;
- make app-shell verification fail when built assets are missing.

Routing should stay minimal until a second real product route exists. Inert
nav items should not imply implemented product surfaces. Local UI state can
remain in React or URL parameters; a global client store is deferred until
there is real cross-route client-only workflow state.

Alternative considered: add Relay/Apollo, a global store, and a full design
system package now. Rejected because backend API contracts are still in motion
and the current UI needs a small rescue, not a platform rebuild.

### 6. Verification Gates Come Before Refactors

Before large code movement, add gates that catch new drift:

- OpenSpec strict validation for this change and all specs.
- API architecture tests that reject new manual resource endpoints/root fields
  unless documented as exceptions.
- Domain architecture tests that reject new direct database exceptions or broad
  `authorize?: false` paths without ledger coverage.
- Frontend verification that uses project-local dependencies and catches a
  missing built app shell.
- Parity tests that keep existing GraphQL and JSON compatibility surfaces
  aligned while generated Ash surfaces are introduced.

Alternative considered: refactor first and backfill tests. Rejected because
the current problem is uncontrolled drift; gates are the cheapest way to stop
the drift while cleanup happens incrementally.

## Risks / Trade-offs

- API migration could expose unsafe lifecycle writes through generated Ash
  APIs -> Keep generated public surfaces read-only/simple first and require
  explicit specs before public creates/updates.
- Compatibility endpoints could live forever -> Require retirement conditions,
  client migration tasks, and tests proving replacement parity before archive.
- Domain cleanup could remove important transaction/idempotency safety -> Treat
  exception retirement as behavior-preserving refactors with regression tests
  for replay, concurrency, authorization, and partial-commit prevention.
- Frontend architecture could become overbuilt -> Add only primitives,
  adapters, and query/cache tools when they solve current operator-console
  pressure or the next real route.
- Vocabulary simplification could hide useful audit details -> Keep
  infrastructure details available in debug/audit surfaces, but do not make
  them the default product model.
- OpenSpec artifacts could become another layer of stale documentation -> Pair
  every stabilization requirement with a verification gate or implementation
  task so drift is caught by commands, not memory.

## Migration Plan

1. Land this OpenSpec change with proposal, design, spec deltas, and tasks.
2. First implementation change: add stabilization guard tests and update
   exception ledgers for current manual API, domain, and frontend gaps.
3. Second implementation change: modularize existing API schema/error
   presentation without route or behavior changes.
4. Third implementation change: establish frontend foundation and reliable
   frontend verification without adding new product screens.
5. Fourth implementation change: introduce safe generated Ash read surfaces and
   adapter tests while retaining compatibility routes.
6. Later implementation changes: move composite command ownership out of
   `OfficeGraph.ApiSupport`, burn down domain exception entries, migrate
   clients, and retire compatibility endpoints.

Rollback is straightforward for the planning artifact: revert this change. For
later implementation, each stage must keep current tests passing and avoid
removing compatibility endpoints until replacements are proven.

## Open Questions

- Which URL should host strict AshJsonApi during migration: existing `/api`, a
  new `/api/v1`, or a temporary `/jsonapi` mount?
- Should the operator console keep JSON as the default adapter until projection
  contracts stabilize, or should GraphQL become the dogfood path as soon as a
  generated schema is available?
- Which domain owns the cross-cutting packet-run-verification command:
  WorkPackets, Runs, Verification, a new WorkExecution context, or an
  OperatorWorkflow command boundary?
- Should packet readiness become a backend-projected command affordance instead
  of a frontend-assembled POST input?
- How aggressive should the first vocabulary migration be for
  `proposed_graph_changes`: code/database rename now, or API/UI rename first
  with storage rename later?
