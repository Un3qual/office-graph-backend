## Context

Office Graph is expected to become a large Elixir/Phoenix/Ash/Postgres
backend. The accepted foundation and work-graph designs require a
department-neutral work graph, provider-neutral relational base tables, typed
domain resources, explicit tenant/scope fields, revision-ready records,
soft deletion, and limited JSON usage. The accepted governance design requires
organization-root tenancy, workspace and initiative/project scopes,
classification-aware access, explainable authorization, and audit/revision
separation.

This design defines the persistence posture before application code or
migrations are generated. It does not try to finalize every table column, but
it does establish the first schema/resource inventory and the rules later
Phoenix, Ash, Ecto, GraphQL, JSON API, Oban, integration, and agent-runtime
work should follow.

## Goals / Non-Goals

**Goals:**

- Define the MVP persistence inventory: first-class resources,
  external-reference-only records, provider-specific extension tables, raw
  archives, and likely Ash resource candidates.
- Define how graph identity, typed resources, domain attachments,
  conversations, external references, and projections map into relational
  persistence.
- Keep shared external concepts provider-neutral by default.
- Avoid JSON/JSONB for core queryable product data.
- Define when JSON storage is acceptable for raw payload, replay, debugging,
  and provenance.
- Define tenant and scope column rules for durable records.
- Define baseline indexing, uniqueness, and soft-delete-aware uniqueness
  expectations.
- Identify large-table growth and partitioning candidates without overbuilding
  the MVP.
- Preserve clean boundaries with revision/audit/soft-delete, code
  organization, ingestion/integrations, agent runtime, proposed graph changes,
  work packets/readiness, runs/verification, and API/UI projections.

**Non-Goals:**

- No Phoenix, Ash, Ecto, migration, GraphQL, JSON API, React, Oban, or agent
  runtime implementation.
- No final column list for every table.
- No final revision-table, audit-log, retention, legal-hold, or restore
  design.
- No final API schema, GraphQL schema, or UI read-model design.
- No dedicated enterprise deployment, schema-per-tenant, database-per-tenant,
  or RLS-first design.
- No full non-engineering workflow schema before a first non-engineering
  proving workflow is selected.

## Decisions

### 1. Use typed resources plus graph identity

Addressable work should have shared graph identity, but business meaning
belongs in typed resources. The persistence model should therefore use a
`graph_items`-style identity record for addressability, scope, classification,
projection, and relationship participation, with typed domain tables owning
their fields, validations, state, and actions.

The expected shape is:

- a graph identity record for addressable items
- typed domain resources with a required or optional unique graph identity
  reference when they participate in the work graph
- typed relationship records for graph edges
- typed attachments and external references for provider or domain context

Core persistence must not use polymorphic local references such as
`resource_type` plus `resource_id` for Office Graph-owned records. SQL-level
referential integrity should come from either a concrete foreign key to
`graph_items` for first-class graph-addressable resources, or a concrete
domain-table foreign key for typed embedded resources. External references may
store provider object type and external identifier because those point outside
the local relational model; that exception must not be used for internal
Office Graph resource links.

Alternatives considered:

- **Single generic node table with JSON properties:** Flexible, but too weak
  for authorization, validation, revision history, query performance, and API
  contracts.
- **Typed resources only with no graph identity:** Strong domain modeling, but
  makes cross-domain traversal, node-scoped conversations, graph projections,
  and agent context assembly much harder.

### 2. Make the MVP first-class inventory explicit

The MVP should include first-class relational resources for the shared product
loop and the software proving workflow. The first inventory should be treated
as a starting cut for design/spec work, not as final migration syntax.

First-class Office Graph resources:

- organizations
- workspaces
- initiatives/projects
- workstreams
- graph items
- graph relationships
- signals
- requirements
- tasks
- questions
- decisions
- checks
- evidence
- artifacts
- conversations
- conversation messages
- rich text documents and revision structures
- ordered collections, placements, and placement versions for graph-addressable
  ordered structures
- external references
- raw payload archives
- operation or command correlation records

First-class execution resources expected by nearby follow-on designs:

- work packets
- runs
- run events
- proposed graph changes
- context expansion requests

The exact fields and state machines for work packets, runs, proposed graph
changes, and revision/audit records belong to their dedicated changes, but the
persistence model should reserve them as typed relational concepts rather than
leaving them as generic attachments.

First-class software proving resources:

- integration installations or external sources
- repositories
- repository refs or branches
- commits
- pull requests
- review threads
- review comments
- review findings
- check runs
- issues
- observability issues
- observability events

External-reference-only or artifact-first for MVP until a workflow requires
promotion:

- design assets and design comments
- campaign assets
- social posts and social calendars
- finance records
- spreadsheets and spreadsheet rows
- external documents and document comments
- ticketing-provider records outside the selected proving workflow

Office Graph-authored documents and plan sections may become graph-addressable
through product work, but external document providers should start as external
references plus artifacts unless the first MVP scope requires native document
editing.

Office Graph-authored body fields should use a shared rich text persistence
subsystem rather than ad hoc text or editor payload columns on every table.
This applies to descriptions, discussion comments, conversation messages,
requirements, decisions, document sections, plan sections, and future native
comments.

Alternatives considered:

- **Only software tables in MVP:** Easier for the first proving workflow, but
  risks collapsing the product into engineering-only architecture.
- **First-class tables for every department immediately:** Demonstrates the
  long-term ambition, but creates schema churn before workflows are known.
- **Everything as external references first:** Simple ingestion, but leaves the
  native graph/runtime model too weak.

### 3. Use provider-neutral resources before provider-specific extension tables

When a concept exists across multiple providers or departments, the base table
should be provider-neutral. Provider-specific extension tables are justified
only when the source has fields, constraints, lifecycle, API behavior, or sync
semantics that do not fit the shared resource cleanly.

Examples:

- `pull_requests` should model provider, external source, repository, source
  and target refs, state, author, timestamps, merge state, and sync state.
- `github_pull_requests` should exist only for GitHub-specific fields or
  behavior that should not pollute the shared model.
- `review_comments` should model shared review-comment/thread behavior across
  GitHub, GitLab, CodeRabbit, Greptile, and future Office Graph-native review.
- `review_findings` should model actionable product findings separately from
  provider comments, because findings need status, severity, waiver, fix, and
  verification behavior.

Alternatives considered:

- **Provider-specific tables first:** Fast for GitHub/Sentry, but creates
  migrations and API churn when second providers arrive.
- **One huge provider-neutral table with many nullable columns:** Avoids joins
  early, but becomes unclear and brittle as providers diverge.

### 4. Keep external references distinct from typed resources

External references link Office Graph records to provider records. They are
not a substitute for first-class resources when Office Graph needs lifecycle,
authorization, validation, query, approval, revision, or domain-action
behavior.

An external reference should store provider, external source/account,
provider object type, external identifier, URL when available, sync state,
source provenance, owning organization, and related Office Graph resource.

Raw payload archives may keep original webhook/API/model payloads for replay,
debugging, provenance, or legal/compliance retention. Queryable fields must be
extracted into typed relational columns or tables.

Alternatives considered:

- **External reference as the only imported record:** Too weak for the native
  graph/runtime model.
- **Typed resource without source reference:** Loses replay, debugging,
  provenance, and provider reconciliation evidence.

### 5. Restrict JSON/JSONB to raw and unmodeled payload storage

Core product data used for authorization, graph traversal, workflow state,
revision history, filtering, reporting, integration reconciliation, agent
context assembly, or verification should use typed columns, lookup tables,
join tables, or extension tables.

JSON/JSONB is acceptable for:

- raw webhook payload archives
- raw provider API payload archives
- model prompt/input/output archives when governed by AI data controls
- tool-call request/response payload archives
- replay/debug snapshots that are not the normal query surface
- temporary unmodeled edge data only when paired with a promotion plan or
  explicit accepted exception

Any JSON archive row should carry typed envelope fields such as organization,
provider/source, received time, payload kind, payload digest, related resource
or event, retention classification, and replay/debug state.

Alternatives considered:

- **No JSON at all:** Clean, but impractical for external webhook/API replay
  and model/tool-call provenance.
- **JSON props on every graph item:** Flexible, but violates the core design
  goal and makes policy/query behavior vague.

### 6. Use explicit tenant and scope columns, with strict inheritance only when safe

Tenant-owned records should carry `organization_id` directly unless they are
strictly owned by a parent that cannot move across organizations. Workspace,
initiative/project, workstream, team, component, repository, integration,
external source, artifact, and resource scopes should be stored directly when
they are needed for authorization, filtering, indexing, export, or retention.

Scope inheritance is acceptable only when the ownership path is strict,
queryable, and safe for authorization. For high-volume child rows, denormalized
scope columns may be justified so authorization-filtered queries and exports
do not require deep joins.

The persistence model must not use graph membership as a tenant or permission
boundary. Graph projections remain filtered queries over scoped records.

Alternatives considered:

- **Only parent-derived scope:** Less duplication, but creates brittle and slow
  authorization/export queries.
- **All scope columns on every row:** Query-friendly, but can create
  consistency work when ownership changes. Use it where query/security needs
  justify it.

### 7. Use Ash for stable domain resources and Ecto/SQL for traversal, bulk, and high-volume paths

Ash should own stable resources, business actions, validations, policies, and
state transitions. This includes resources such as tasks, questions,
decisions, checks, evidence, work containers, and provider-neutral domain
records once their behavior is clear.

Explicit Ecto/SQL should be used where forcing work through Ash would weaken
the design:

- graph traversal and neighborhood queries
- projection read models
- bulk ingestion upserts
- idempotent external event replay
- high-volume append-only event writes
- maintenance jobs, backfills, and partition management

Ash resources and Ecto/SQL paths must share domain policy boundaries and
operation correlation rather than inventing separate authorization semantics.

Alternatives considered:

- **Ash everything:** Consistent but may be awkward for traversal and
  high-volume ingestion.
- **Ecto everything:** Flexible but would lose Ash's resource/action/policy
  benefits for stable domain behavior.

### 8. Define baseline indexes and uniqueness from expected query shapes

Every foreign key should have an index unless there is a clear reason not to.
Tenant-owned tables should usually index by organization plus their most common
scope and lifecycle/status filters. External records should have unique
constraints based on organization, provider/external source, provider object
type, and external identifier.

Baseline index families:

- foreign-key indexes
- organization plus workspace/initiative/workstream status indexes
- graph edge source/type and target/type indexes
- external source/object unique indexes
- partial unique indexes for active soft-deletable records when reuse is
  allowed
- time-range indexes for event-like tables
- indexes supporting idempotent ingestion and replay

Indexing should be designed from real query shapes, not broad speculative
coverage. Later design work may add read models for expensive graph
projections rather than over-indexing write-heavy truth tables.

Alternatives considered:

- **Minimal indexes only:** Faster writes early, but likely to make tenant and
  graph queries slow immediately.
- **Index every plausible column:** Wastes write throughput and makes
  migrations harder before access patterns are known.

### 9. Plan for soft deletion without finalizing restore and retention here

Mutable product records should include or inherit a soft-delete/tombstone
strategy from the beginning. The concrete restore, retention, legal hold, and
revision interaction rules belong to `design-revision-audit-soft-delete`, but
this persistence design must reserve columns and uniqueness behavior.

Default posture:

- mutable product rows should support `deleted_at`, `deleted_by`, deletion
  reason, or a domain-specific tombstone
- active-record uniqueness should generally use partial indexes that ignore
  deleted rows when names/slugs can be reused
- provider external identifiers should generally remain globally unique per
  organization/source/object type even if the local product row is deleted
- append-only raw archives, audit records, decision records, and event logs are
  not soft-deleted through normal product actions

Alternatives considered:

- **Hard delete until retention is designed:** Easier early, but incompatible
  with enterprise audit/revision needs.
- **One universal soft-delete policy:** Simple, but external references,
  append-only logs, and user-facing product records have different semantics.

### 10. Keep high-volume tables append-friendly and partition-ready

High-volume areas should be designed so partitioning can be added later
without redefining the product model. MVP does not need to partition every
table, but it should avoid schema choices that make time/tenant partitioning
impossible.

Likely high-volume candidates:

- raw payload archives
- source events and integration sync events
- run events
- audit logs and authorization decision records
- revision/history records
- model calls and tool-call logs
- conversation messages
- observability events
- check-run annotations or CI annotations

These tables should include organization, source/run/resource references,
created/received timestamps, and narrow typed envelope columns. Large payloads
should be stored or referenced through archive tables rather than duplicated
across every derived record.

Alternatives considered:

- **Partition from day one:** Premature operational complexity.
- **Ignore growth until it hurts:** Risks painful rewrites in exactly the
  tables that will be hardest to migrate later.

### 11. Use operation correlation as the shared write trace

Meaningful product actions should create or reference an operation/command
correlation record. Revisions, audit logs, run events, domain events, external
sync events, and proposed graph changes can all reference the same operation
without duplicating one another's payloads.

This design does not define the full revision or audit schema, but it reserves
the correlation concept so later changes can avoid giant duplicated event
records.

Alternatives considered:

- **One event table for every concern:** Simple early, but conflicts with typed
  revision/audit/run/sync separation.
- **No shared correlation record:** Makes it hard to trace a human or agent
  action across revisions, audit, runs, and provider sync.

### 12. Store rich text as normalized editor-independent document state

Rich text bodies should not use Lexical JSON as the durable source of truth.
Lexical is a likely React editor adapter, but Office Graph should persist an
Office Graph rich text model so future editor changes, native renderers, agent
serialization, and revision history do not depend on one frontend library.

The expected persistence shape is:

- `rich_text_documents` for the body/document aggregate and current revision
- `rich_text_document_revisions` as semantic commit records
- stable `rich_text_blocks` and versioned `rich_text_block_versions`
- stable `rich_text_inlines` and versioned `rich_text_inline_versions`
- `rich_text_mark_types` for supported marks such as bold, italic, underline,
  code, colors, highlights, or future semantic marks
- versioned `rich_text_inline_mark_versions` for mark applications
- typed reference tables for principal mentions, graph-item references,
  external links, artifacts, and future attachment references
- sidecar anchor, range, and quote-snapshot tables for references to whole
  resources, selected blocks, and selected inline spans
- derived render/cache tables for plain text, sanitized HTML, agent Markdown,
  Lexical JSON adapter output, or future editor adapter payloads

Rich text revisions should be copy-on-write, not full document snapshots. A
new document revision records the semantic edit, actor, operation, parent
revision, and change set. Only changed block, inline, mark, or reference
versions receive new rows. Unchanged blocks and inline nodes remain shared
across revisions through validity ranges or equivalent version membership.

Marks should be normalized rather than represented as boolean columns on text
rows. A mark type defines the mark key, value kind, compatibility/exclusivity
rules, introduction version, and deprecation state. Applying a mark to part of
a text run should split the run into stable inline nodes as needed, then apply
or close versioned mark rows on the affected inline nodes.

Mentions and references inside rich text are product facts, not only styling.
They should be stored in typed reference tables and linked to graph items,
principals, artifacts, external references, or URLs. Renderers can turn those
references into Lexical custom nodes, GraphQL/JSON API response shapes,
Markdown links for agents, or redacted placeholders when authorization
requires it.

Quotes and fine-grained references should be non-invasive sidecar records by
default. Creating a quote from another rich text document must not modify the
source document unless the user explicitly inserts a named source anchor or
bookmark. Pinned quotes should record the target document, target revision,
selected block or inline range, copied normalized snapshot fragment, hash, and
source authorization/classification context. Live references should resolve
against the latest authorized source state and carry resolution status such as
resolved, stale, deleted, ambiguous, or source-reordered.

Selections should preserve the user's intent. A text selection that crosses
multiple inline runs should store start and end anchors against stable inline
version identities plus offsets and, for pinned quotes, store the copied
fragment. Selecting several list items should be modeled as a block selection
set, not a loose boundary range; if the source list is later reordered, pinned
quotes preserve the original selected order while live excerpts must state
whether they render in original selection order or current source order.

The first rich text schema should stay intentionally narrow: paragraphs,
headings, lists, quotes, code blocks, text runs, basic marks, principal
mentions, graph-item references, external links, and artifact references.
Unsupported editor features should be rejected, flattened, or stored as
artifacts until a later accepted change promotes them into the portable schema.

Alternatives considered:

- **Store Lexical JSON as canonical content:** Fast to build, but ties durable
  data and revision history to one editor library and hides product references
  in JSON.
- **Store a full normalized snapshot per revision:** Simple to reconstruct,
  but wasteful when small edits touch one word or mark deep in a document.
- **Boolean mark columns on inline rows:** Easy for bold/italic/underline, but
  creates schema churn when new marks need values or compatibility rules.

### 13. Model ordering as an extensible placement contract with concrete FKs

Ordered structures should share semantics without forcing every ordered thing
through one polymorphic table. The reusable concept is an ordered placement
contract: stable collection identity, stable item membership, parent/child
placement when the structure is nested, fractional/manual position keys,
revision validity, lifecycle state, and derived dense ordinals for display.

For first-class graph-addressable resources, Office Graph may use generic
ordering tables with concrete graph foreign keys:

- `ordered_collections` with organization, collection kind, structure kind,
  ordering strategy, and `owner_graph_item_id`
- `ordered_placements` with collection, `item_graph_item_id`,
  `parent_placement_id`, and lifecycle state
- `ordered_placement_versions` with position key, validity revision or
  operation range, move/reorder metadata, and optional placement-state changes

For embedded or high-volume structures, Office Graph should use typed placement
tables that follow the same contract while preserving concrete foreign keys.
Examples include `rich_text_block_placements` with `document_id` and
`block_id`, or future `gallery_photo_placements` with `gallery_id` and
`gallery_photo_id`. Domain-specific placement details such as crop, focal
point, grid span, swimlane, or board column should live in typed extension
tables or typed placement-version tables, not in a generic JSON payload.

Manual reordering should update placement version state rather than content
state. Dense list numbers, card positions, slide numbers, or gallery display
indexes are derived from current placement order. A move of a document block,
task, or gallery photo should close or supersede the prior placement version
and create a new placement version with a new position key, without creating a
new content version for unchanged content.

Ordering strategies can grow over time. The first accepted strategy should be
fractional manual ordering, using sortable position keys so insertion and
reordering do not require renumbering sibling rows. Later strategies can add
append-only sequence, priority rank, grid placement, grouped/swimlane ordering,
or topological ordering without changing the identity and versioning contract.

Alternatives considered:

- **Polymorphic `owner_type`/`owner_id` and `item_type`/`item_id` tables:**
  Easy to generalize in diagrams, but weak for SQL constraints, Ash resources,
  authorization, migrations, and query planning.
- **Dense integer order columns on each table:** Simple initially, but
  expensive and fragile for frequent reordering, nested structures, and
  revision history.
- **One generic ordered placement table for everything:** Reuses code, but
  becomes a weak relational model for embedded or high-volume structures that
  need concrete foreign keys and domain-specific constraints.

## Risks / Trade-offs

- [Risk] The MVP inventory is still too broad. -> Mitigation: specs and tasks
  can split first-class resources into immediate, near-follow-up, and deferred
  cuts before implementation starts.
- [Risk] Provider-neutral tables become vague. -> Mitigation: require clear
  shared fields and extension-table escape hatches for provider-specific
  behavior.
- [Risk] JSON exceptions expand into a hidden product model. -> Mitigation:
  require typed envelope columns and normalized extraction for anything used
  in authorization, filtering, reporting, graph traversal, context assembly, or
  verification.
- [Risk] Graph traversal queries are slow on relational tables. -> Mitigation:
  begin with focused projections, maintain edge indexes, and add read models
  only when query patterns justify them.
- [Risk] Denormalized scope columns drift from parent ownership. ->
  Mitigation: allow denormalization only for query/security needs and require
  domain actions or maintenance checks to preserve consistency.
- [Risk] Ash and Ecto paths diverge in authorization behavior. -> Mitigation:
  require shared domain authorization and operation correlation for both.
- [Risk] Rich text normalization becomes too broad before product needs are
  known. -> Mitigation: keep the first portable schema narrow, require adapter
  support for accepted nodes/marks, and route unsupported content through
  artifacts or later schema promotion.
- [Risk] The ordered-placement contract becomes a generic schema escape hatch.
  -> Mitigation: allow reusable behavior, but require concrete graph-item
  foreign keys or typed domain foreign keys instead of polymorphic local
  references.

## Migration Plan

There is no application-code migration for this design-only change. Follow-on
work should consume the persistence model in this order:

1. Create persistence capability specs from this design and the accepted
   proposal.
2. Use `design-revision-audit-soft-delete` to finalize revision, audit,
   tombstone, retention, legal-hold, and restore behavior.
3. Use `design-code-organization-and-boundaries` to map these persistence
   responsibilities into Ash domains, Ecto modules, and boundary rules.
4. Use `design-ingestion-and-integrations` to refine raw payload archives,
   source events, idempotency, replay, and provider adapter contracts.
5. Use `design-agent-runtime`, `design-runs-and-verification`, and
   `design-api-realtime-and-ui-projections` to refine high-volume event,
   context, run, and projection read patterns.
6. Use a future rich text implementation design to refine editor adapters,
   copy-on-write reconstruction, anchor resolution, quote snapshots, ordering
   tables, rendering caches, search indexing, and collaboration/session
   behavior.

## Open Questions

- Which first-class MVP resources are immediate implementation scope versus
  near-follow-up scaffolding?
- Should review comments and review findings both ship in the first software
  proving workflow, or should review findings be native first while provider
  comments remain external references until imported examples require them?
- Should observability issues/events be provider-neutral from day one, or
  should Sentry start as an external source with normalized issue/event
  records added after the first integration spike?
- Which graph projection queries need read models in MVP, if any?
- Which high-volume tables should be partition-ready only, and which need
  partitioning before first customer data?
- Which rich text node and mark types are in the first portable schema, and
  which unsupported editor features should be flattened, rejected, or stored
  as artifacts?
- Should rich text reconstruction use validity ranges, explicit revision
  membership rows, periodic materialized snapshots, or a hybrid once document
  sizes and edit patterns are better understood?
- Which ordered structures should use graph-addressable ordered placement
  tables in MVP, and which should use typed embedded placement tables from the
  start?
