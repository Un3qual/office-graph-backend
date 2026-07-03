## Why

One captured `/operator` page load issued 162 SQL queries across the inbox,
selected item, and packet-readiness requests. The current behavior repeats
local owner bootstrap, authorization, and projection assembly work per request,
and it also exposes an older console contract that still treats the JSON API as
the frontend path even though the current API direction says GraphQL is the
normal product API.

## What Changes

- Make the operator console use GraphQL for product reads. Keep JSON routes only
  for current backend callers or integration contracts; do not keep a frontend
  JSON adapter or parity target for its own sake.
- Require operator workflow projections to have a bounded, batched query shape
  for inbox, item detail, packet readiness, run state, and verification outcome
  reads.
- Remove duplicated selected-row work where the inbox response already contains
  enough item detail for the initial selection.
- Carry server-installed request/session authorization facts so local bootstrap
  and read authorization do not re-query the same capability and role rows for
  every console subrequest, without introducing VM-lifetime identity or session
  caches.
- Add query-count regression coverage or telemetry-backed assertions for the
  operator page workflow so future rows or linked resources do not reintroduce
  N+1 projection reads.

## Capabilities

### New Capabilities

- None.

### Modified Capabilities

- `operator-console`: change the product UI's normal data path from the
  temporary JSON bridge to GraphQL, while keeping component-facing view models
  stable.
- `operator-workflow`: require projection reads to batch related records and
  keep query counts bounded as inbox rows, graph links, runs, and readiness
  inputs grow.

## Impact

- The operator frontend data client, route, and selected-row loading behavior.
- `lib/office_graph/api_support.ex`, `lib/office_graph/foundation.ex`,
  `lib/office_graph/authorization.ex`, and `lib/office_graph/identity.ex`
  context-loading and authorization validation paths.
- `lib/office_graph/projections.ex` and `lib/office_graph/runs.ex` batched
  projection assembly.
- `lib/office_graph_web/graphql/operator_workflow/*` plus any current JSON API
  routes that remain for backend or integration use.
- Operator workflow API, frontend data, and query-count regression tests.
