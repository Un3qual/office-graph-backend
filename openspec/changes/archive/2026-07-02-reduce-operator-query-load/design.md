## Context

The captured `/operator` page load issued 162 SQL queries:

- `GET /api/operator-workflow/inbox`: 55 queries
- `GET /api/operator-workflow/items/:id`: 55 queries
- `POST /api/operator-workflow/packet-readiness`: 52 queries

The Phoenix `/operator` app shell itself does not query the database. At the
time of the captured page load, the React app defaulted to a JSON adapter that
called `/api/operator-workflow/*` routes. That choice matched the first minimal
console implementation, but the current product direction is simpler: the
product frontend reads operator workflow data through GraphQL. JSON routes may
remain only for current backend callers or integration contracts.

Changing the frontend transport alone will not solve the query count. The JSON
controllers and GraphQL resolvers both call `OfficeGraph.ApiSupport`, which
loads a session context and delegates to `OfficeGraph.Projections`. The biggest
query buckets are repeated local owner bootstrap and authorization checks, plus
projection assembly that builds each inbox row independently.

## Goals / Non-Goals

**Goals:**

- Make GraphQL the operator-console product data path.
- Keep `OperatorWorkflowProjectionClient` as the frontend boundary so panels
  consume stable view models rather than transport response shapes.
- Reduce one page load by eliminating duplicate selected-item work and repeated
  session/bootstrap work.
- Make operator workflow projection reads batch related records across inbox
  rows and linked resources.
- Add query-count regression coverage that fails when row count or graph-link
  count causes linear query growth.

**Non-Goals:**

- Removing the JSON operator workflow routes.
- Replacing the hand-written GraphQL projection adapter with code generation or
  Relay/Apollo in this change.
- Redesigning the visual console, adding broad product routes, or changing the
  operator workflow projection payload semantics beyond transport and
  performance behavior.
- Reworking the full authorization model. This change may carry
  already-established request capability facts, but it does not replace
  RBAC/ABAC policy semantics or introduce VM-lifetime session caches.

## Decisions

### Use GraphQL For The Product UI

The operator frontend should call GraphQL through the current feature-owned
data client or hooks. A frontend JSON adapter is not a product fallback. Backend
JSON routes may remain only when a current backend caller, integration contract,
or verification need is named.

Alternative considered: leave JSON as the UI transport and only optimize the
backend. That would reduce query count but keep the console out of alignment
with the API direction that product reads use GraphQL as the normal transport.

### Keep Components Off Raw API Shapes

The GraphQL adapter already maps camelCase GraphQL fields into the same
snake_case frontend view model consumed by the current components. The
implementation should keep panels, layout, and presentation helpers unaware of
GraphQL response shapes.

Alternative considered: let components call GraphQL directly. That would make
the migration faster locally but violate the frontend architecture requirement
and make future socket/cache invalidation harder.

### Remove Request Fanout Before Adding More API Shapes

The inbox currently returns full item projections, then the UI immediately
fetches `/items/:id` for the first row and repeats the same expensive detail
assembly. The UI should reuse the selected inbox row as the initial detail. If
later payload size becomes a problem, a separate change can split inbox summary
rows from item detail deliberately.

Run state already includes verification results and missing evidence. The UI
should avoid calling a separate verification outcome read when the selected run
state provides enough data for the current verification panel. A composite
GraphQL selection query can be considered later if the projection contract
needs a dedicated read shape.

Alternative considered: introduce a new composite endpoint immediately. That
would reduce page-load round trips but adds another API shape before the shared
backend read and batching problems are fixed.

### Carry Trusted Session Context Instead of Bootstrapping Per Read

The log shows local owner bootstrap dominates the page-load query count. Each
operator workflow read calls `ApiSupport.read_session_context/1`, which
bootstraps the local owner when no trusted session context is provided. The
hand-written JSON API should get the same server-side local owner plug pattern
used by GraphQL and generated JSON API routes, or otherwise pass a trusted
session context from the controller into `ApiSupport`.

`Authorization.authorize/3` should also avoid re-querying session, principal,
capability, role, and role-assignment tables when the session context already
contains validated capabilities for the current request. Any shortcut must
still reject revoked sessions or stale principals where the request boundary
has not established freshness.

The local development owner bootstrap should remain request scoped. A
VM-lifetime bootstrap cache would reduce a few local setup reads, but it also
creates auth-shaped state that can outlive identity, tenancy, or policy row
changes. That trade-off is not worth carrying in the shared API support path.

Alternative considered: memoize local bootstrap globally. That helps local dev
but can hide revocation/session freshness behavior and is less representative
of real authenticated request handling.

### Batch Backend Read Assembly

`operator_inbox/1` should assemble rows through a batched builder that also
serves `operator_workflow_item/2` with a one-event input. The builder should:

- read proposed changes for all event ids with `normalized_event_id in ^ids`
- derive applied operation ids once and read audit records and revisions with
  `operation_id in ^operation_ids`
- group graph resource ids by resource type and fetch each resource type with
  `id in ^ids`
- read graph relationships once for all involved graph item ids
- read packet required-check links, source references, and runs once for all
  involved graph links
- group the loaded records in memory to preserve the existing row projection
  semantics

`Runs.get_summary/2` can stay simple for single-run reads in this change, but
the duplicated verification outcome path should not force a second summary read
when the frontend already has run state.

Alternative considered: rely on GraphQL dataloaders. The current GraphQL fields
are coarse workflow reads rather than nested resource resolvers. Batching
belongs in the shared backend read first so any current API path benefits.

### Add Query-Count Regression Coverage

Use Ecto telemetry in tests to count SQL queries for operator projection reads.
The important assertion is not an exact permanent number; it is bounded growth:
adding more inbox rows, graph links, and applied operations must not add one
query per row/resource in known hotspots.

The test fixture should cover pending and applied intakes because applied rows
exercise audit, revision, graph link, relationship, packet-source/check, and run
link projection paths.

## Risks / Trade-offs

- GraphQL product reads reveal frontend data bugs that the old JSON path hid.
  Mitigation: keep focused frontend data tests and route tests around the
  current GraphQL path.
- Query-count tests can become brittle when legitimate fixed-cost reads are
  added. Mitigation: assert upper bounds and scaling behavior separately, and
  keep the threshold documented in the test.
- Reusing inbox row detail can serve stale detail after a later user action.
  Mitigation: reuse only for initial selection/load, then explicitly refresh
  after commands or source watermark changes.
- Skipping repeated authorization queries can weaken revocation behavior if it
  trusts unvalidated client input. Mitigation: only trust server-installed
  `%SessionContext{}` values and preserve rejection of client-supplied
  `session_context` maps.
- Batching in `OfficeGraph.Projections` will add in-memory grouping code.
  Mitigation: keep existing row-builder helpers as formatting functions and add
  tests for current API behavior after the batching change.

## Migration Plan

1. Add query-count helpers and a failing regression test that captures current
   operator projection growth.
2. Switch the frontend to the current GraphQL data path and remove old frontend
   JSON adapter tests unless a current caller is named.
3. Reuse selected inbox row detail and avoid redundant verification-outcome
   reads when run state is sufficient.
4. Install/carry trusted session context for operator workflow reads and avoid
   repeated local bootstrap and authorization table reads in the same request.
5. Replace per-row projection assembly with the batched builder.
6. Run OpenSpec validation, focused backend/frontend tests, query-count tests,
   and the existing frontend verification command.

Rollback is a git revert or a focused fix to the GraphQL path. JSON is not a
product UI fallback unless a current caller or data-safety reason is named.

## Open Questions

- What steady-state query budget should gate the final page-load path after
  local bootstrap is removed: a strict absolute ceiling, or separate ceilings
  for frontend fanout, auth/session, and projection assembly?
- Should the final UI use a single GraphQL selection query for inbox plus
  selected detail/readiness/run state, or keep separate projection-client
  methods and rely on caching/deduplication?
- Should local dev bootstrap eventually move to startup/seed-time setup rather
  than request-time ensure calls?
