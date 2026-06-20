# Design: Office Graph Foundation

## Context

Office Graph is an enterprise, company-wide work graph where humans and agents
plan, execute, review, and verify work together. The first deep proving
workflow is software review/fix/verification because it has concrete signals
and evidence, but the product foundation must serve design, marketing, social
media, finance, operations, leadership, and other departments.

The backend stack is Elixir, Phoenix, Ash, and Postgres. The frontend will be
React from day one. Phoenix LiveView is forbidden for product UI. Both GraphQL
and JSON API are required.

## Design Goals

- Keep the product ontology department-neutral.
- Make the internal agent runtime a core graph capability, not a later bolt-on.
- Make enterprise authorization, auditability, revision history, and soft
  deletion foundational.
- Prefer provider-neutral relational schemas and typed extension tables over
  JSON property bags.
- Use a modular monolith with enforceable boundaries so the backend can grow
  without becoming tangled.
- Preserve future extraction paths for identity/authentication,
  authorization, agent runtime, integrations, and revision/audit primitives.

## Product Foundation

The locked product direction is an agent-governed company work graph.

The core loop is:

```text
signal
  -> graph item
  -> question
  -> decision
  -> work packet
  -> human, agent, or integration run
  -> evidence
  -> verification or monitoring
  -> reusable organizational context
```

The first proving workflow is:

```text
feature/task/bug
  -> PR and external review comments
  -> imported review findings
  -> internal Office Graph agents propose fixes or follow-up work
  -> human review and modification
  -> pushed changes and PR comments
  -> linked commits, checks, Sentry events, decisions, and evidence
```

Long term, Office Graph should run native review agents that work entirely over
the graph. Parent-level agents must be able to catch conflicts that child-level
reviews miss.

Integrations are the starting point for adoption, not the intended long-term
defense. Office Graph should accept signals from existing tools and write back
where useful, but the most valuable workflows should mature into native
Office Graph experiences that are better because they use cross-tool graph
context, internal agents, permissions, revision history, and verification
evidence. The product should avoid remaining a thin feature layer that an
integrated vendor can copy into its own product.

## Capability Boundaries

This foundation change owns product framing, vocabulary, locked platform
choices, and the first proving workflow. Granular follow-on changes own
canonical durable requirements for identity, authentication, authorization,
scope hierarchy, work-graph relationships, persistence, revision/audit,
operation correlation, code organization, ingestion, proposed changes, runs,
verification, and API/UI behavior.

### Foundation

Owns product framing, locked platform decisions, OpenSpec scope, first proving
workflow, non-goals, and reference-material precedence.

### Work Graph

Owns graph items, typed edges, questions, decisions, work packets, graph
projections, proposed graph changes, and addressable node conversations.

### Agent Runtime

Owns embedded agents, automatic agents, run orchestration, model/tool
separation, tool approvals, run events, findings, proposed changes, and agent
provenance.

### Authorization

Owns principals, roles, memberships, capabilities, grants, policy context,
agent effective permissions, tool permissions, integration scopes, and
authorization decision records.

### Verification

Owns checks, evidence, monitoring, verification state, waivers, and
traceability from future failures back to prior work.

### Persistence

Owns schema design rules: provider-neutral relational base tables, extension
tables, JSON avoidance, tenant/scope columns, typed revisions, audit/event
distinctions, soft deletion, indexing, and large-table growth paths.

### Backend Architecture

Owns the modular monolith shape, Boundary rules, Ash/Ecto split, API layering,
realtime/async boundaries, integration package contracts, and library-ready
internal domains.

## Backend Architecture Posture

Start with a modular monolith, not microservices. Use Phoenix for HTTP/API,
Absinthe for GraphQL, JSON API controllers for required REST-like access, Ash
for stable domain resources/actions/policies, Ecto/SQL for graph traversal and
bulk operations when Ash would be the wrong abstraction, Oban for durable
async jobs, and Phoenix PubSub/Channels/Absinthe subscriptions for realtime.

Phoenix controllers, GraphQL resolvers, webhooks, Oban jobs, integration
adapters, and agent runtime modules must call domain actions or services. They
must not own business logic.

Candidate bounded contexts:

- Accounts and Identity
- Organizations and Tenancy
- Authorization
- Work Graph
- Questions and Decisions
- Work Packets
- Agent Runtime
- Runs
- Verification
- Integrations
- External Artifacts
- Persistence/Revisions/Audit
- API and Realtime adapters

Use Boundary rules so contexts expose public APIs intentionally and internal
modules remain private. This should be enforced early, before the codebase is
large.

## Persistence Design Rules

Base schemas should be relational and provider-neutral when concepts are
shared across systems. A `pull_requests` table, for example, should model
provider, source account, external identifier, repository, source and target
branches, author, state, timestamps, merge metadata, sync status, and linked
external references. A `github_pull_requests` table should exist only for
GitHub-specific fields or behavior that do not belong in the shared model.

Avoid JSON/JSONB for core queryable domain data. JSON is acceptable for raw
external payload archives, replay/debug data, and unmodeled edge payloads that
are not the normal product query surface. Normalize fields needed for
authorization, graph traversal, filtering, reporting, context assembly, and
verification.

Revision history should be typed and aggregate-aware. Do not use one giant
`versions` table with opaque snapshots as the primary design. Separate:

- revision history: reconstructable meaningful changes to product records
- audit logs: security/compliance records of who did what
- domain events: business events used by other domains
- run events: durable execution timelines
- external sync events: provider ingestion and replay state
- raw payload archives: original provider/model/webhook data

Soft deletion is required from the beginning. Tables must define
`deleted_at`/`deleted_by` or a domain-specific tombstone strategy, restore
rules, retention implications, and uniqueness behavior for active versus
deleted records.

## Authorization Design

Use a hybrid enterprise model:

```text
RBAC roles
  + ABAC policy facts
  + relationship checks
  + capability permissions
  + explicit grants
```

Principals include humans, agents, service accounts, integrations, webhook
sources, and system jobs. Agent effective permissions are the intersection of
delegator permissions, agent capabilities, work packet autonomy policy, tool
or integration scope, and organization policy.

Graph edges never grant access by themselves. Context assembly for graph
projections, embedded agents, work packets, API responses, and agent runs must
filter every included record through authorization.

## Agent Runtime Design

The runtime should support:

- node-scoped embedded conversations
- automatic agents attached to graph items and trigger states
- parent-level review agents
- structured output from lower-trust models
- trusted runtime components for tool execution
- explicit tool permissions and approvals
- durable runs, events, findings, prompt/model provenance, outputs, and
  proposed changes

The first implementation should be scoped carefully. It should not try to
replace IDEs, CI, or every external automation tool. It should make Office
Graph the governed context and provenance layer for agent work.

## API And Realtime Design

GraphQL and JSON API must share domain actions and authorization semantics.
GraphQL should serve graph-shaped product reads, client mutations, and
subscriptions. JSON API should serve integration-friendly access, webhooks
where appropriate, exports, and endpoints where GraphQL is not the right fit.

Realtime updates should use Phoenix PubSub with Absinthe subscriptions or
Phoenix Channels. Postgres remains durable state, not the application realtime
bus.

## Tradeoffs

- A generic graph is flexible but can become vague. The design uses typed graph
  primitives plus relational support tables and extension tables.
- Ash gives strong action/policy structure but should not absorb every graph
  traversal or bulk workflow. Use Ash for stable business operations and
  explicit Ecto/SQL behind domain boundaries where needed.
- Internal agent runtime is core, but unrestricted coding-agent scope would
  explode the MVP. Start with graph-aware conversations, automatic reviews,
  proposed changes, and approved tool actions.
- Department packs are important, but broad workflow templates are deferred
  until the shared ontology proves itself through a deep workflow.

## Follow-On Changes

This foundation should be followed by narrower design changes:

- `design-work-graph-core`
- `design-persistence-model`
- `design-revision-audit-soft-delete`
- `design-code-organization-and-boundaries`
- `design-ingestion-and-integrations`
- `design-agent-runtime`
- `design-proposed-graph-changes`
- `design-work-packets-and-readiness`
- `design-runs-and-verification`
- `design-api-realtime-and-ui-projections`
- `design-enterprise-governance`
