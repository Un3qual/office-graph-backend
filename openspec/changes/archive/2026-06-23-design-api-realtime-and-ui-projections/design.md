## Context

The current walking skeleton exposes equivalent GraphQL and JSON behavior
through a hand-written Absinthe schema, Phoenix controller, serializer, and a
shared smoke-test support module. That proved the end-to-end loop, but it is
not the intended product API architecture.

Office Graph is already modeled around Ash domains and resources, and the
application includes AshGraphql and AshJsonApi. Future API work needs to keep
resource actions, validation, authorization, revision, audit, operation
correlation, and lifecycle semantics in the owning Ash resource/domain or
public context contract. Transport code should compose those contracts rather
than becoming a second business-rule layer.

The API decision also affects realtime delivery and frontend projection design.
Initial product views such as inboxes, question queues, work packet context,
focused node views, blocker views, review surfaces, evidence chains,
verification views, and agent runtime status need stable projection contracts.
Those projections must line up with GraphQL, JSON API, and realtime updates so
the frontend does not infer product semantics from transport-specific shapes.

This change is design-only. It records the guardrails before implementation
starts and before the temporary walking-skeleton transport pattern spreads.

## Goals / Non-Goals

**Goals:**

- Make AshGraphql and AshJsonApi the default implementation path for
  Ash-owned resource and action API surfaces.
- Quarantine the existing manual walking-skeleton GraphQL schema and JSON
  controller as temporary smoke-test transport code.
- Define when custom Absinthe or Phoenix transport code is acceptable.
- Keep GraphQL schema growth modular by domain, capability, generated Ash
  schema contribution, or explicit projection module.
- Define realtime delivery around domain events, projection invalidations,
  authorization filtering, and read-after-connect recovery.
- Define frontend projection contracts before product UI implementation.
- Carry export, redaction, audit visibility, sensitivity labels, and projection
  staleness constraints into API, realtime, and render-cache design.

**Non-Goals:**

- Implement Phoenix routes, Absinthe modules, AshGraphql declarations,
  AshJsonApi routes, realtime subscriptions, Channels, React UI, or migrations.
- Delete the walking-skeleton smoke endpoints immediately.
- Choose every first product query, mutation, projection, or subscription.
- Replace Ash-generated APIs with a custom schema framework.
- Define final visual design or component layout for the frontend.

## Decisions

### 1. Ash APIs Are The Default

Ash-owned resource reads, relationships, create/update/delete actions,
filters, sorting, pagination, and resource action exposure should be planned
through AshGraphql and AshJsonApi first.

Rationale: Ash is the domain and policy boundary for resource semantics. Using
the Ash API packages keeps authorization, validation, lifecycle, revision,
audit, and operation metadata attached to the resource action instead of
duplicating those rules in controllers or resolvers.

Alternative considered: Continue with a manually maintained Absinthe schema
and Phoenix JSON controllers. That keeps the smoke path simple, but it creates
two places to encode domain behavior and makes it easy for later frontend work
to copy the wrong pattern.

### 2. Manual Walking-Skeleton API Code Is Quarantined

The current hand-written schema, controller, serializer, and support module may
remain only as temporary smoke-test compatibility code until equivalent product
surfaces exist. New API work must not grow those modules as the default
architecture.

Rationale: The walking skeleton was useful evidence, not a durable API
pattern. Explicit quarantine lets smoke tests continue while preventing the
temporary path from setting code-quality precedent.

Alternative considered: Delete the manual endpoints immediately. That is too
early because the smoke tests still document a working system loop and the Ash
replacement has not been designed in implementation detail.

### 3. Custom Transport Code Is Exception-Based

Custom Absinthe or Phoenix code is allowed for orchestration commands,
projection endpoints, transport-specific envelopes, external integration
commands, exports, webhooks, and workflows that do not map cleanly to a single
Ash resource/action API. The custom layer must stay thin: build or receive
operation context, call public domain commands, map errors, and return
transport shapes.

Rationale: Some Office Graph workflows coordinate multiple domains, such as
intake, proposed changes, verification, work packets, runs, agent runtime
activity, and exports. Those workflows need explicit entrypoints, but the
entrypoints should not own business rules.

Alternative considered: Force every API through generated resource endpoints.
That would make orchestration and projection flows awkward and would encourage
clients to reconstruct workflows from low-level resource operations.

### 4. GraphQL Is Modular And Composed

The root GraphQL schema should compose generated Ash schema contributions and
domain-owned or capability-owned modules. It should not keep accumulating
inline object trees, mutations, subscriptions, interfaces, and resolver logic in
one monolithic file.

Rationale: Office Graph expects many resource families and shared capability
interfaces. Keeping schema ownership close to the owning domain gives each
capability a clear home and makes authorization-aware interface behavior
reviewable.

Alternative considered: Keep a single root schema file for simplicity. That is
acceptable only for the walking-skeleton smoke path; it does not scale to
product graph, projection, realtime, and agent-runtime surfaces.

### 5. Product UI Reads Through Projection Contracts

Frontend product surfaces should read authorization-filtered projection
contracts rather than ad hoc controller or resolver joins. Each projection
contract should define owner, inputs, included graph items, related typed
records, status fields, redaction behavior, empty states, API exposure, and
realtime behavior.

Rationale: Product views mix graph items, domain records, generated content,
evidence, verification status, review state, and runtime state. A projection
contract gives the UI a stable shape without pushing business inference into
React components.

Alternative considered: Let each screen request raw resources and infer state
client-side. That would fragment authorization, redaction, status vocabulary,
and realtime reconciliation across screens.

### 6. Realtime Uses Domain And Projection Events

Realtime delivery should be sourced from typed domain events, approved runtime
events, and projection invalidations after durable authorization-relevant state
is committed. Absinthe subscriptions and Channels may expose different
transport shapes, but both must derive from the same event contract.

Rationale: API controllers and database notifications are not the application
event bus. Domain events make ownership, authorization, replay, projection
staleness, and read-after-connect recovery explicit.

Alternative considered: Publish from controllers or rely on database
notifications. That is simpler at first, but it misses maintenance/backfill
events, makes authorization filtering harder, and couples delivery to the
current transport path.

### 7. Realtime Payloads Are Hints, Not Authoritative State

Realtime payloads should include identity, version, stale-marker, or
invalidation information that lets clients reconcile through the authorized
projection or resource API. They should not be treated as complete durable
state replacements.

Rationale: Subscribers can miss events, reconnect, cross authorization
boundaries, or observe stale render caches. Read-after-connect and refetch
paths keep clients correct.

Alternative considered: Send full projection rows in every event. That can be
useful for selected low-risk updates, but as a default it increases leakage
risk and duplicates projection read semantics in the realtime layer.

### 8. Render Caches Are Derived And Policy-Scoped

Render caches, rich text renders, Markdown renders, graph neighborhoods, count
rollups, review surfaces, and agent-context render outputs are derived state.
They must identify source records, cache keys, invalidation events,
authorization inputs, sensitivity labels, staleness behavior, and rebuild
paths.

Rationale: Derived content can include sensitive graph context, external
provider snippets, agent-generated text, tool observations, and raw archive
references. Caches must either be scoped to the authorized viewer/policy
context or contain only safe metadata.

Alternative considered: Cache rendered content globally by source content hash.
That is unsafe when redaction, policy, tenant scope, temporary grants, legal
hold, export visibility, or generated content status changes affect rendering.

## Risks / Trade-offs

- Ash package fit may be imperfect for some orchestration or projection
  endpoints. Mitigation: require a documented custom-transport exception with
  shared domain-command semantics and focused tests.
- The walking-skeleton manual API may linger. Mitigation: label it as
  temporary in this design and require migration or cleanup tasks when future
  API work touches it.
- Generated GraphQL and custom capability interfaces may require glue code.
  Mitigation: keep glue domain-owned and root-composed instead of inline in the
  root schema.
- Realtime authorization can drift from read authorization. Mitigation: require
  realtime owners, authorization filters, and reauthorization behavior when
  access changes.
- Projection contracts can become too broad. Mitigation: define owners and
  first-screen contracts explicitly, and keep raw resources available through
  Ash APIs for resource-level operations.
- Derived render caches can leak redacted content. Mitigation: include policy
  context, sensitivity labels, staleness, export/redaction, and rebuild paths in
  every render-cache design.

## Migration Plan

1. Keep the existing walking-skeleton manual endpoints as smoke-test
   compatibility only.
2. Audit the existing Ash resources/domains and identify the first GraphQL and
   JSON API surfaces that should move to AshGraphql and AshJsonApi.
3. Define the root GraphQL composition pattern for generated Ash schema
   contributions plus domain/capability modules.
4. Select the first projection-backed product surface and define its contract,
   API transport exposure, realtime invalidation behavior, cache posture, and
   redaction behavior.
5. Replace or retire each walking-skeleton manual endpoint after equivalent
   Ash-backed or documented thin command endpoints exist.
6. Add focused tests that prevent new product API work from copying the manual
   schema/controller/serializer pattern.
7. Roll back implementation changes by routing clients back to the temporary
   smoke endpoints only while keeping domain-resource behavior unchanged.

## Open Questions

- Which walking-skeleton endpoint or resource action should be migrated first?
- What exact Absinthe/AshGraphql composition pattern should the Phoenix root
  schema use?
- Which product projection should be the first implementation target: inbox,
  question queue, focused node view, verification view, or agent runtime
  status?
- Should the first realtime implementation expose Absinthe subscriptions,
  Phoenix Channels, or both?
- Which JSON API custom exceptions are required up front for webhooks, exports,
  external integrations, or orchestration commands?
