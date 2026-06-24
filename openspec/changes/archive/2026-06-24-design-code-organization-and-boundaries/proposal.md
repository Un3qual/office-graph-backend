## Why

Office Graph is about to move from architecture/persistence decisions into
backend shape decisions. The project needs a code-organization contract before
Phoenix, Ash, Ecto, Oban, API, integration, and agent-runtime implementation
begins, so the modular monolith does not grow through lateral coupling, generic
helper modules, or table-driven shortcuts that are difficult to authorize,
revise, test, and later extract.

## What Changes

- Define the first bounded-context map for graph identity, work containers,
  governance, authorization, persistence primitives, revision/audit,
  integrations, agent runtime, runs, work packets, APIs, and UI projections.
- Define how Ash domains, resources, actions, policies, validations,
  notifiers, and public interfaces should be organized for typed resources,
  graph items, provider-neutral records, rich text, ordered placement, raw
  archives, operation correlation, and soft-deletable records.
- Define when code should use Ash, when it should use Ecto directly, and when
  explicit SQL/read-model modules are allowed for traversal, bulk operations,
  projections, replay, analytics, or partition-aware high-volume paths.
- Define Boundary dependency rules, public API ownership, test placement, and
  module naming expectations that keep bounded contexts isolated in a large
  Elixir codebase.
- Define shared operation contracts for tenant/scope/classification fields,
  operation correlation, authorization decision records, revisions, audit
  records, tombstones, raw archives, run events, and external sync events.
- Define extractability requirements for future reusable libraries such as
  identity/authentication, authorization, integration primitives,
  revision/audit primitives, agent runtime, rich text, and ordered placement.
- Define how Phoenix controllers, Absinthe resolvers, JSON API endpoints, Oban
  workers, integration adapters, and agent-runtime code call domain boundaries
  without bypassing authorization, revision, audit, validation, or graph-action
  rules.
- Keep the work design-only. This change does not start Phoenix, Ash, Ecto,
  migration, API, frontend, Oban, integration, or agent-runtime
  implementation.

## Capabilities

### New Capabilities

- `bounded-context-architecture`: Defines the initial modular-monolith domain
  map, context ownership rules, context-to-context dependencies, and public
  interface expectations.
- `ash-domain-boundaries`: Defines how Ash domains, resources, actions,
  policies, validations, changes, preparations, and notifiers are organized
  without leaking domain internals.
- `ecto-sql-boundaries`: Defines the allowed direct Ecto and explicit SQL
  paths for graph traversal, projections, replay, analytics, high-volume
  tables, and bulk operations that should not be forced through Ash actions.
- `boundary-enforcement`: Defines Boundary library usage, module naming,
  dependency rules, test boundaries, and enforcement expectations for the
  modular monolith.
- `shared-operation-contracts`: Defines the cross-context contracts for
  tenant/scope/classification, operation correlation, authorization decisions,
  revisions, audit, tombstones, raw archives, sync events, run events, and
  domain events.
- `extractable-library-boundaries`: Defines which domains should be kept
  library-ready, what dependencies they may accept, and what product-specific
  assumptions they must avoid.
- `entrypoint-boundary-contracts`: Defines how controllers, GraphQL resolvers,
  JSON API handlers, Oban workers, integration adapters, and agent runtime
  code enter domain boundaries without bypassing policy or mutation rules.

### Modified Capabilities

- None. No durable specs exist yet under `openspec/specs/`; this change builds
  on active foundation, work-graph, governance, persistence, and
  revision/audit planning changes.

## Impact

- Affects OpenSpec planning artifacts for Elixir application structure, Ash
  resource organization, Ecto/schema ownership, SQL/read-model ownership,
  Boundary rules, public context APIs, test layout, API resolver/controller
  layering, Oban worker layering, integration adapter boundaries, and
  agent-runtime entrypoints.
- Provides source requirements for later Phoenix, Ash, Ecto migration,
  Absinthe GraphQL, JSON API, Oban, integration, agent-runtime, and frontend
  projection implementation.
- Does not implement application code, migrations, Ash resources, API
  endpoints, frontend screens, workers, adapters, or agent behavior.
