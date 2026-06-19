## Context

Office Graph is an enterprise, company-wide work graph for human and agent
work. The accepted foundation defines a department-neutral graph of signals,
tasks, questions, decisions, requirements, checks, evidence, artifacts, runs,
work packets, conversations, and external references. The enterprise
governance design defines organization as the root tenant, workspace plus
initiative/project as default scopes, graph projections as filtered views, and
graph edges as context rather than access grants.

This design narrows the next problem: what the core work graph means before
the persistence schema, API shape, agent runtime, proposed graph change
application, revision history, and frontend projections are designed in full.
It should be concrete enough to guide those later changes without prematurely
committing to every table, Ash resource, or UI screen.

## Goals / Non-Goals

**Goals:**

- Define the first core work-container model: organization, workspace,
  initiative/project, and workstream.
- Define a department-neutral graph item taxonomy that works for engineering,
  design, marketing, social media, finance, operations, and leadership.
- Define how typed graph relationships behave, including direction, lifecycle,
  provenance, validation, traversal, and authorization expectations.
- Define graph projections as authorization-filtered views over scoped graph
  data, not tenants or access-granting containers.
- Define how domain-specific records and external references attach to the
  shared graph without forcing every department into one weak generic schema.
- Define how selected graph items can host node-scoped conversations and
  request context for embedded agents.
- Preserve clear boundaries for later persistence, revision/audit,
  agent-runtime, integration, proposed-change, work-packet, verification, and
  API/UI designs.

**Non-Goals:**

- No Phoenix, Ash, Ecto, migration, GraphQL, JSON API, React, or agent runtime
  implementation.
- No final table list or index strategy. The persistence model change owns the
  concrete relational schema.
- No full revision, audit, retention, legal-hold, restore, or deletion design.
- No full proposed graph change operation model or application transaction
  design.
- No full work packet schema, readiness scoring model, or run lifecycle.
- No final frontend interaction model or arbitrary graph-canvas design.

## Decisions

### 1. Use graph addressability as a shared contract, not as one generic data blob

Every meaningful work object should be addressable in the graph, but not every
object should be reduced to one generic `node` shape. The core graph should
provide a shared addressability contract: stable graph identity, type,
organization, workspace, optional initiative/project, optional workstream,
classification, lifecycle state, owner or source, provenance, and relationship
participation.

Type-specific meaning belongs in typed resources and domain actions. For
example, a question, decision, check, evidence item, run, work packet, review
finding, design annotation, campaign asset, finance exception, or PR review
comment may all be addressable graph items, but each can still have its own
typed fields, validations, state transitions, and policies.

Alternatives considered:

- **Single generic node table with JSON properties:** Flexible early, but
  conflicts with the project's relational design goals and makes policy,
  validation, revision history, and API contracts weak.
- **Every concept as a fully isolated resource with no shared graph contract:**
  Strong typing, but makes traversal, embedded conversations, projections, and
  cross-domain agent context brittle.

### 2. Treat initiatives/projects as bounded work containers, not teams or tasks

`Project` remains the customer-facing alias for an initiative: a bounded work
container around a business, product, operational, or cross-functional outcome.
Workstreams are execution lanes inside an initiative, such as backend
implementation, design review, security review, finance approval, launch, or
operations follow-up.

Teams, departments, org units, components, repositories, services, design
systems, campaigns, finance accounts, and external systems attach to work as
related scopes or resources. They can own, participate in, approve, block, or
be affected by work, but they are not projects by default.

Alternatives considered:

- **Team/component as project:** Familiar to some engineering teams, but
  breaks down for cross-functional and non-engineering work.
- **Task as project:** Makes small work heavyweight and hides true
  initiative-level context.
- **Graph as work container:** Too flexible and risks confusing graph
  projection membership with tenancy or access.

### 3. Define a small core taxonomy, then attach domain extensions

The core graph taxonomy should include graph items that are useful across
departments:

- signal
- requirement
- task
- question
- decision
- check
- evidence
- artifact
- run
- work packet
- conversation
- external reference
- document or plan section when a section needs its own discussion,
  provenance, task linkage, or agent context

Domain-specific concepts attach to this taxonomy. Software-specific records
such as pull requests, commits, review comments, CI checks, and Sentry events;
design records such as annotations and assets; marketing records such as
campaign briefs and approvals; social records such as posts and calendars; and
finance records such as exceptions and approvals should use provider-neutral
typed resources when they need durable behavior, not custom graph ontologies
per department.

Alternatives considered:

- **Large taxonomy from day one:** Captures more nuance, but makes the first
  schema and APIs unstable before real workflows prove which types deserve
  first-class treatment.
- **Only generic task/comment/artifact types:** Easier to build, but too weak
  for requirements, decisions, checks, evidence, runs, and agent governance.

### 4. Use type-specific statuses plus projection-level status families

Graph items should not share one universal status enum. A question, task,
check, evidence item, run, and work packet have different valid states and
transition rules. Each typed resource should own its specific lifecycle.

For cross-graph projection and filtering, the graph layer may expose normalized
status families such as new, open, blocked, waiting, in progress, done,
verified, failed, superseded, archived, or deleted. These families are
projection aids, not a replacement for type-specific lifecycle rules.

Alternatives considered:

- **One global status field:** Simple for UI filters, but becomes ambiguous
  and hard to validate.
- **Only type-specific statuses:** Correct locally, but makes inboxes,
  blockers, board views, and evidence chains harder to build consistently.

### 5. Keep relationships typed and narrow

Edges should have explicit semantics: direction, allowed source and target
types, lifecycle, provenance, authorization behavior, and cycle rules. Initial
relationship families should cover containment, decomposition, dependency,
blocking, provenance, requirement satisfaction, verification, evidence,
review, duplication, discussion, generated-from, produced-by, affected-scope,
and external-reference links.

Edges may carry narrow typed metadata such as state, confidence, source,
asserting principal, related run, and valid time window. They should not become
opaque payload stores. Larger explanations, artifacts, approvals, findings, or
proof should be represented as graph items and linked with typed edges.

Alternatives considered:

- **Unconstrained edge labels:** Easy to add, but impossible to validate or
  reason about safely.
- **Rich edge payloads for all relationship data:** Reduces node count, but
  hides evidence and revision-worthy facts inside relationship metadata.

### 6. Make graph projections filtered queries, not durable access scopes

A graph projection is a product view over scoped graph data. Examples include
inbox, question queue, focused node neighborhood, blocker view, dependency
view, workstream board, work packet context, review surface, and evidence
chain.

Every projection must filter nodes, edges, artifacts, conversations, external
references, revisions, summaries, and counts through authorization. If the
actor can see a relationship but not the target, the projection may hide the
target, show a restricted placeholder, or expose a policy-approved summary.

Alternatives considered:

- **Graph as a tenant or access boundary:** Flexible for ad hoc views, but
  contradicts the governance decision that graph edges and membership do not
  grant access.
- **Materialize every projection as its own durable object:** Useful later for
  performance, but premature before query patterns are proven.

### 7. Attach domain records through typed graph participation

Domain records should attach to the work graph when they need conversation,
review, provenance, relationships, evidence, or agent context. The attachment
must identify the graph item, domain resource type, owning scope, source
system when applicable, and provenance. External references should link Office
Graph records to provider records with provider, source identifier, URL, sync
state, and source provenance.

A concept deserves a dedicated typed resource when it has its own lifecycle,
business rules, authorization rules, query patterns, revision needs, or domain
actions. Otherwise it may remain an artifact, external reference, or typed
attachment until real usage justifies promotion.

Promotion is a product and schema evolution decision, not arbitrary runtime
schema creation by an end user. For example, imported provider review comments
may start as external references or attachments. If review comments become a
first-class Office Graph concept, the product should introduce a
provider-neutral typed resource such as review comments or review findings.
After that resource exists, a user or agent may convert or link an individual
imported comment into an instance of the existing resource type through an
explicit domain action.

This change defines the decision rule for external reference versus typed
resource. The concrete MVP inventory of provider-neutral resources, external
references, extension tables, and Ash resources belongs to
`design-persistence-model`.

Alternatives considered:

- **Provider-specific graph nodes for every imported object:** Fast for one
  integration, but would make the product ontology provider-driven.
- **Generic external artifact only:** Flexible, but loses important behavior
  for high-value records such as pull requests, review findings, design
  approvals, campaign approvals, or finance exceptions.

### 8. Model conversations as scoped graph participants

A conversation can attach to any addressable graph item, and a graph item may
have multiple conversations for different purposes or audiences. Node-scoped
conversations should assemble context from the selected item, authorized
neighbors, relevant decisions, requirements, checks, evidence, artifacts,
external references, and recent runs.

Embedded agents may draft answers, identify missing context, and propose graph
changes, but durable mutation must pass through the accepted proposed graph
change and domain-action safety model. Full run isolation, model routing, tool
permissions, and automatic agent lifecycle belong to the later agent-runtime
design.

Alternatives considered:

- **Global conversations with loose links:** Familiar, but it recreates the
  problem of decisions buried in chat.
- **Conversation per project only:** Too coarse; the product requires chatting
  with a selected task, requirement, check, evidence item, run, finding, or
  document section.

### 9. Keep this boundary semantic, with implementation choices delegated

This change defines the domain semantics and contracts. Later changes should
decide concrete database tables, Ash resource splits, revision storage,
auditable decision records, graph traversal query implementation, GraphQL/JSON
API shapes, and realtime behavior.

The expected implementation direction remains a modular monolith with explicit
bounded contexts. The work-graph context should expose domain actions and
query interfaces for graph identity, typed relationships, projections, and
addressability. It should consume authorization, tenancy, identity,
revision/audit, integration, and agent-runtime boundaries through declared
interfaces rather than embedding their internals.

Alternatives considered:

- **Lock table/resource shapes in this change:** Would make later persistence
  and code-organization work less useful.
- **Defer all semantics to persistence:** Risks letting schema convenience
  define the product ontology.

## Risks / Trade-offs

- [Risk] The graph item taxonomy becomes too generic to support real workflows
  well. -> Mitigation: promote concepts to dedicated typed resources when they
  have lifecycle, policy, query, or action needs.
- [Risk] The taxonomy grows too fast and becomes hard to explain. ->
  Mitigation: keep the core department-neutral set small and attach
  department-specific records through domain resources.
- [Risk] Normalized projection status families conflict with type-specific
  lifecycle rules. -> Mitigation: treat projection families as read models,
  not authoritative transition state.
- [Risk] Edge metadata becomes a hidden payload model. -> Mitigation: keep
  edge metadata narrow and represent substantive facts as graph items.
- [Risk] Node-scoped conversations could bypass graph mutation controls. ->
  Mitigation: conversations and embedded agents may propose changes, but
  domain actions decide what becomes true.
- [Risk] Full graph projections may be expensive. -> Mitigation: start with
  focused projections and defer arbitrary graph-canvas behavior until query
  requirements are proven.

## Migration Plan

There is no application-code migration for this design-only change. Follow-on
changes should consume these semantics in this order:

1. `design-persistence-model` defines relational tables, indexes, extension
   table rules, and graph traversal/read-model strategy.
2. `design-revision-audit-soft-delete` defines revision and deletion behavior
   for graph items, edges, conversations, and domain attachments.
3. `design-code-organization-and-boundaries` defines the concrete bounded
   contexts and dependency rules.
4. `design-proposed-graph-changes`, `design-work-packets-and-readiness`,
   `design-runs-and-verification`, `design-agent-runtime`, and
   `design-api-realtime-and-ui-projections` refine their respective areas
   without redefining the core graph semantics.

## Open Questions

- Which exact edge types belong in MVP versus the first follow-up release?
- Should document and plan sections be first-class core graph item types in
  MVP, or should they start as domain attachments that can become graph items
  when individually addressed?
- Which initial projections are required for the first customer-facing MVP:
  inbox, question queue, work packet context, focused node view, blocker view,
  workstream board, evidence chain, or review surface?
- Which graph item types require dedicated Ash resources immediately, which
  external concepts remain external references, and which provider-neutral
  resources belong in the MVP first schema cut? This inventory is deferred to
  `design-persistence-model`.
