## Why

Office Graph needs a persistence model before backend code generation so the
large Elixir/Ash/Postgres codebase does not start with generic JSON blobs,
provider-specific one-off tables, or graph storage that is hard to authorize,
query, revise, and extend. The accepted work-graph design defines the semantic
model; this change defines how those semantics should map into relational,
provider-neutral, tenant-scoped persistence decisions for the MVP.

## What Changes

- Define the concrete MVP persistence inventory: first-class provider-neutral
  resources, external-reference-only records, provider-specific extension
  tables, raw payload archives, and initial Ash resource candidates.
- Define the relational graph storage contract for graph item identity, typed
  relationships, conversations, domain attachments, external references, and
  projection-supporting read patterns.
- Define provider-neutral base-table rules for shared external concepts such
  as repositories, branches, commits, pull requests, review comments, checks,
  documents, design assets, campaign assets, finance records, social posts, and
  source events.
- Define when provider-specific extension tables are justified and how they
  relate back to provider-neutral base records.
- Define where JSON/JSONB is acceptable, limited primarily to raw external
  payload archives, replay/debugging data, and model/tool payload retention,
  while keeping queryable product data typed and relational.
- Define editor-independent rich text persistence for descriptions, discussion
  bodies, comments, document sections, and plan sections, including normalized
  blocks, inline nodes, mark applications, references, revision history, and
  agent Markdown serialization.
- Define an extensible ordered-placement persistence contract for ordered
  document blocks, list items, plan sections, tasks, galleries, boards, and
  future ordered structures without using polymorphic local foreign keys.
- Define explicit tenant, workspace, initiative/project, workstream, team,
  component, repository, integration, external-source, and artifact scope rules
  for durable records.
- Define baseline indexing and uniqueness rules, including external-id
  uniqueness, tenant/status composites, foreign-key indexes, soft-delete
  partial indexes, and event time-range indexes.
- Identify high-volume table candidates and future partitioning paths for raw
  events, sync events, run events, audit/decision records, revisions, model
  calls, and tool-call logs.
- Define boundaries with follow-on revision/audit/soft-delete, code
  organization, integration ingestion, agent runtime, API, and UI projection
  designs.

## Capabilities

### New Capabilities

- `mvp-persistence-inventory`: Defines the first schema/resource cut for MVP,
  including first-class resources, external-reference-only records,
  provider-specific extensions, raw archives, and initial Ash resource
  candidates.
- `graph-storage-contract`: Defines relational persistence expectations for
  graph identities, typed relationships, graph item participation, domain
  attachments, conversations, and projection support.
- `provider-neutral-resources`: Defines base-table rules for shared concepts
  that appear across providers, departments, and integrations.
- `extension-table-rules`: Defines when source-specific, provider-specific, or
  department-specific extension tables are justified and how they link to base
  records.
- `external-reference-model`: Defines external reference identity, provenance,
  sync state, provider object linkage, and raw payload archive boundaries.
- `json-storage-policy`: Defines where JSON/JSONB is allowed and how typed
  relational extraction is required for queryable product data.
- `portable-rich-text-persistence`: Defines normalized, editor-independent rich
  text storage, revision history, mark/reference extraction, and derived
  serialization for Lexical, Markdown, and future editor adapters.
- `ordered-placement-model`: Defines reusable ordered-collection semantics,
  versioned placements, fractional/manual ordering, graph-addressable ordering,
  typed embedded ordering, and SQL-safe foreign-key rules.
- `tenant-scope-indexing`: Defines tenant/scope columns, baseline indexes,
  external-id uniqueness, soft-delete-aware uniqueness, and query-shape
  requirements.
- `large-table-growth`: Defines high-volume table candidates, retention hooks,
  partitioning readiness, and operational growth assumptions.

### Modified Capabilities

- None. No durable specs exist yet under `openspec/specs/`; this change builds
  on active foundation, enterprise-governance, and work-graph-core changes
  without modifying an accepted capability spec.

## Impact

- Affects OpenSpec planning artifacts for Postgres schema design, Ash resource
  boundaries, Ecto/query usage, graph traversal/read models, integration
  ingestion, raw payload storage, and future API/query surfaces.
- Provides source requirements for later Phoenix, Ash, Ecto migration,
  GraphQL, JSON API, Oban, integration adapter, and agent-runtime
  implementation.
- Feeds follow-on changes for revision/audit/soft-delete, code organization,
  ingestion/integrations, agent runtime, change proposals, work packets,
  runs/verification, and API/UI projections.
- Does not implement application code, database migrations, Ash resources,
  API endpoints, frontend screens, integration adapters, or agent runtime
  behavior.
