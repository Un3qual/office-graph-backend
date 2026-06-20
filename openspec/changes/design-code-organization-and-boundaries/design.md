## Context

Office Graph has locked enough product and persistence direction to decide how
the backend should be organized before code generation begins. The accepted
foundation requires a large Elixir/Phoenix/Ash/Postgres backend, React from day
one, GraphQL plus JSON API, no LiveView, OpenSpec as workflow source of truth,
and clean DDD-style bounded contexts enforced with the Boundary library. The
work-graph design requires shared graph addressability with typed resources and
domain actions owning business meaning. The persistence design requires
provider-neutral relational base tables, explicit tenant/scope fields, limited
JSON use, normalized rich text, ordered placement, raw archives, and
partition-ready high-volume tables. The governance and revision/audit designs
require authorization as a core bounded context, durable operation correlation,
typed revision families, audit records, authorization decision records,
tombstones, retention, legal hold, and future extractability for reusable
domains.

This change defines the code-organization contract that later Phoenix, Ash,
Ecto, GraphQL, JSON API, Oban, integration, and agent-runtime implementation
must follow. It does not create application code or migrations.

## Goals / Non-Goals

**Goals:**

- Define the first modular-monolith shape and bounded-context dependency
  direction.
- Define where Ash domains and resources live and how callers use them.
- Define where direct Ecto and explicit SQL are allowed.
- Define Boundary rules for public/private modules and tests.
- Define cross-context operation contracts for tenant/scope/classification,
  authorization decisions, operation correlation, revisions, audit,
  tombstones, raw archives, sync events, run events, and domain events.
- Keep future library extraction practical without prematurely splitting the
  codebase into umbrella apps, Hex packages, or services.
- Define how Phoenix, Absinthe, JSON API, Oban, integration adapters, and agent
  runtime code enter domain boundaries.

**Non-Goals:**

- No Phoenix, Ash, Ecto, database migration, GraphQL, JSON API, React, Oban,
  integration-adapter, or agent-runtime implementation.
- No exact module tree for every future domain.
- No final table, column, index, migration, resolver, endpoint, worker, or
  schema shape.
- No umbrella application, microservice split, or separate Hex package split
  for MVP.
- No replacement for the dedicated persistence, governance, revision/audit,
  ingestion, agent-runtime, proposed-change, work-packet, runs/verification,
  or API/UI projection designs.

## Decisions

### 1. Start as one Phoenix application with strict internal boundaries

Office Graph should begin as a single Phoenix API application backed by a
modular monolith. The unit of isolation is the bounded context, not an umbrella
app, microservice, or Hex package. Contexts should live under one top-level
application namespace and expose narrow public modules, Ash domains, query
interfaces, and event contracts.

Initial logical contexts should include:

- identity and authentication
- tenancy and enterprise structure
- authorization and policy decisions
- audit and compliance
- operation correlation
- work containers
- work graph
- rich text and portable content
- ordered placement
- revisions and tombstones
- external references and raw archives
- integration primitives and provider adapters
- software proving records
- work packets and readiness
- runs and verification
- proposed graph changes
- agent runtime
- API and realtime entrypoints
- projection/read-model support

These are logical ownership areas. The first implementation plan may merge or
split module folders where it improves clarity, but each durable resource,
command, query, event, and policy must still have one clear owner.

Alternatives considered:

- **Umbrella app from day one:** Gives visible separation, but creates
  dependency and release-management overhead before context boundaries are
  proven.
- **Separate Hex packages immediately:** Supports extraction but freezes
  unstable APIs too early.
- **Microservices early:** Adds operational complexity and distributed
  consistency problems before the product has stable local boundaries.
- **One flat Phoenix context layer:** Faster to start, but too weak for the
  expected size, authorization complexity, and future extraction goals.

### 2. Use dependency direction, not shared utility sprawl, to keep contexts clean

Contexts should depend on narrower lower-level contracts, not on each other's
private modules. A practical dependency direction is:

1. foundation primitives: ids, time/value helpers, operation context structs,
   typed envelopes, and shared behaviours
2. identity, tenancy, authorization, and operation correlation
3. work containers, work graph, content, placement, revisions, audit,
   tombstones, external references, and raw archives
4. domain workflows such as software proving, work packets, proposed graph
   changes, runs/verification, integrations, and agent runtime
5. entrypoints such as controllers, Absinthe resolvers, JSON API handlers,
   Oban workers, channels, integration webhooks, and agent adapters

Shared modules must stay intentionally small and non-product-specific. A
module is not allowed to become shared merely because two callers want the
same database shortcut. When shared behavior has product meaning, it should
belong to a real context with an explicit public API.

Alternatives considered:

- **Large shared helpers namespace:** Convenient early, but becomes an
  unowned dependency dump.
- **Every context fully independent:** Too rigid for shared operation,
  authorization, audit, revision, and tenant contracts.

### 3. Let Ash own domain mutations, policies, and resource lifecycles

Ash should be the default boundary for typed domain resources, business
actions, validations, state transitions, and policy integration. Each bounded
context that owns durable product records should own its Ash domain modules and
resources. Resource modules should model local invariants and lifecycles, while
public context modules provide the stable command/query surface used by other
contexts and entrypoints.

Cross-context callers should not reach into another context's private Ash
resources or data-layer modules. They should call exported commands, exported
queries, or approved read-model interfaces. When a workflow mutates several
contexts, an orchestration module should create an operation context, call
public APIs, and preserve transaction, authorization, revision, and audit
semantics explicitly.

Ash policies should call the authorization boundary for policy decisions
rather than duplicating authorization logic in every resource. Ash changes,
preparations, and notifiers may attach operation correlation, revision, audit,
and domain-event behavior, but they must do so through shared contracts rather
than hidden side effects.

Alternatives considered:

- **Call Ash resources directly from every resolver/controller/worker:** Fast,
  but makes public contracts unclear and invites policy bypasses.
- **Wrap all Ash resources in hand-written context functions only:** Strong
  encapsulation, but can obscure useful Ash action semantics if overdone.
- **Use Ecto-only contexts:** Gives full control, but discards Ash policy and
  action value for the common domain paths.

### 4. Use Ecto and explicit SQL for approved escape hatches

Direct Ecto queries and explicit SQL are allowed when a path is a poor fit for
normal Ash actions, including graph traversal, projection read models,
authorization-filtered neighborhood queries, replay, analytics, raw archive
lookup, high-volume event scans, partition maintenance, backfills, and bulk
reconciliation. These paths must be owned by a bounded context and exposed as
named query/read-model modules or maintenance APIs.

Direct Ecto or SQL must not become a way to bypass policies, revisions, audit,
tombstones, soft-delete filters, or tenant/scope constraints. Query modules
must accept tenant, scope, actor, authorization, classification, and operation
context as needed. Mutating direct-SQL paths must be rare, context-owned,
operation-correlated, and covered by the same revision/audit/event expectations
as Ash actions.

Alternatives considered:

- **Force all database access through Ash:** Simpler policy surface, but
  awkward for graph traversal, projections, high-volume tables, and
  partition-aware operations.
- **Let any context use Repo freely:** Flexible, but weakens ownership,
  testing, and policy guarantees.

### 5. Treat operation correlation as the write spine

Every meaningful write, external sync, agent action, approval, denial,
revision, audit event, run event, domain event, tombstone, and raw archive
reference should be able to link back to an operation correlation record or an
operation context that creates one before durable records are written. The
operation context should carry the organization, relevant scopes, actor,
delegator, agent run or service account when applicable, command key,
idempotency key, request/trace identifiers, authority basis, reason, and
source/origin.

This operation contract is cross-context infrastructure, but it must not become
a generic event payload or polymorphic target model. Domain records still own
their typed data and concrete relationships.

Alternatives considered:

- **Store request ids on each record only:** Hard to query and easy to make
  inconsistent.
- **Make operation correlation the domain event store:** Reintroduces the
  rejected single-event-table model.

### 6. Keep revision, audit, authorization, tombstone, sync, run, and raw archive concerns separate

The code organization should mirror the data model's concern separation.
Revision modules reconstruct product state. Audit modules describe
security/compliance-sensitive actor behavior. Authorization decision modules
explain policy decisions and redaction. Tombstone modules describe deletion,
restore, purge, and URL reservation behavior. Raw archive modules preserve
provider, model, webhook, and tool payloads. Sync modules preserve ingestion
and provider reconciliation. Run-event modules preserve execution timelines.

Contexts may collaborate through shared operation ids and exported contracts,
but they should not write each other's private tables directly or use one
record family as a shortcut for another.

Alternatives considered:

- **One history/audit/event context owns everything:** Centralized, but hides
  the different semantics and retention/visibility rules.
- **Each product context rolls its own audit/revision code:** Local control,
  but inconsistent behavior and difficult extraction later.

### 7. Keep graph identity central, but typed resources own business behavior

The work graph context should own graph identity, graph relationships, graph
projection contracts, graph-addressable conversation anchors, and graph
attachment rules. Typed resources should own their business fields,
validations, lifecycles, and domain actions. A typed resource that participates
in the graph should acquire or reference graph identity through the graph
context's public contract, not by duplicating graph semantics locally.

Graph projection code may assemble data from multiple contexts through
approved read interfaces, but it must apply authorization and redaction through
the authorization boundary. Projection modules are read models, not owners of
domain mutation.

Alternatives considered:

- **Graph context owns every graph-addressable resource:** Simplifies
  traversal but turns graph identity into a generic product model.
- **Typed contexts own graph identity independently:** Makes addressability and
  projection behavior inconsistent.

### 8. Make library-ready boundaries boring before extracting them

Several domains should be designed so they can later become reusable libraries:
identity/authentication, authorization/policy decisions, integration
primitives, revision/audit primitives, agent runtime primitives, rich text, and
ordered placement. Library-ready code should avoid direct Phoenix controller
dependencies, UI assumptions, Office Graph-only naming in generic layers, and
hidden access to product contexts. It should receive dependencies through
behaviours, configuration, explicit data contracts, or callbacks.

Extraction should happen only after the public API stabilizes, tests prove the
boundary, and there is either another consumer or a clear operational reason to
split. Until then, library-ready domains remain internal Boundary contexts.

Alternatives considered:

- **Extract immediately:** Creates package churn before requirements settle.
- **Ignore extraction until much later:** Risks baking Office Graph product
  assumptions into reusable primitives.

### 9. Entry points call domains; they do not own domain rules

Phoenix controllers, Absinthe resolvers, JSON API handlers, channel handlers,
Oban workers, integration webhook handlers, provider adapters, agent-runtime
tools, and future UI projection endpoints should be thin entrypoints. They may
translate transport-specific input into operation context, authorize access,
call public domain commands/queries, and format output. They must not own
domain mutation rules, direct table writes, or special authorization shortcuts.

GraphQL and JSON API may expose different shapes, but both should call the same
domain contracts. Agent-runtime and integration entrypoints must use the same
authorization, operation, revision, audit, and proposed-change pathways as
human-driven requests.

Alternatives considered:

- **Resolver/controller owns use-case logic:** Common in small Phoenix apps,
  but too risky for an agent-native enterprise graph.
- **Separate service layer for every endpoint:** Can become boilerplate; use
  public domain commands and orchestration modules where they add clarity.

## Risks / Trade-offs

- **Risk: Too many contexts too early** -> Mitigation: treat the context map as
  ownership guidance and allow initial folder/module grouping where the public
  contracts remain clear.
- **Risk: Ash plus context wrappers become duplicated abstractions** ->
  Mitigation: expose Ash actions where useful, but require exported public
  modules for cross-context workflows and entrypoint use.
- **Risk: Direct SQL escape hatches bypass policy** -> Mitigation: require
  owning contexts, operation context inputs, authorization-filtered query
  modules, and tests for every direct-SQL path.
- **Risk: Boundary rules slow iteration** -> Mitigation: start with coarse
  boundaries and tighten exports as implementation proves the shape.
- **Risk: Library-ready design becomes premature library splitting** ->
  Mitigation: keep reusable domains internal until APIs and tests stabilize.
- **Risk: Operation context becomes noisy plumbing** -> Mitigation: provide a
  small shared struct/builder and make entrypoints create it once per request,
  job, webhook, sync, or agent action.

## Migration Plan

This change has no runtime migration because no application code exists yet.
For later implementation, the first plan should:

1. Generate the Phoenix API application and configure Boundary in the same
   application.
2. Define coarse Boundary contexts and public exports before adding domain
   resources.
3. Add shared operation-context and tenant/scope primitives.
4. Implement the first Ash domains and resources through their owning
   contexts.
5. Add Ecto/read-model modules only for paths that meet the approved escape
   hatch criteria.
6. Add CI checks for OpenSpec validation, Boundary checks, formatting,
   compilation, tests, and any generated API/schema checks.

Rollback for this planning change is normal OpenSpec revision: edit or replace
the artifacts before approval. Later code-generation changes must include
their own migration and rollback plans.

## Open Questions

- Which exact Elixir module names should be used for each context when the
  Phoenix application is generated?
- Should operation correlation live under a dedicated operations context or
  under a broader revision/audit primitives context in the first code cut?
- Should software proving records be a separate first implementation context
  or a provider-neutral integration subdomain until the first GitHub/Sentry
  spike proves the shape?
- Which graph projection queries need direct SQL in the first code cut versus
  Ash-backed query composition?
- How strict should initial Boundary exports be before the first working
  resource set exists?
