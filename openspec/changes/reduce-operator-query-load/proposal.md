## Why

One captured `/operator` page load issued 162 SQL queries across the inbox,
selected item, and packet-readiness requests. The current behavior repeats
local owner bootstrap, authorization, and projection assembly work per request,
and it also exposes an older console contract that still treats the JSON API as
the frontend path even though the current API direction says GraphQL is the
normal product API.

## What Changes

- Make the operator console default to the GraphQL projection client while
  preserving the existing JSON adapter as a temporary compatibility bridge and
  parity target.
- Require operator workflow projections to have a bounded, batched query shape
  for inbox, item detail, packet readiness, run state, and verification outcome
  reads.
- Remove duplicated selected-row work where the inbox response already contains
  enough item detail for the initial selection.
- Cache or carry request/session authorization facts so local bootstrap and
  read authorization do not re-query the same organization, workspace,
  principal, capability, role, and session rows for every console subrequest.
- Add query-count regression coverage or telemetry-backed assertions for the
  operator page workflow so future rows or linked resources do not reintroduce
  N+1 projection reads.

## Capabilities

### New Capabilities

- None.

### Modified Capabilities

- `operator-console`: change the product UI's normal projection transport from
  the temporary JSON bridge to GraphQL, while keeping component-facing view
  models stable.
- `operator-workflow`: require projection reads to batch related records and
  keep query counts bounded as inbox rows, graph links, runs, and readiness
  inputs grow.

## Impact

- `assets/src/operator-workflow/projectionClient.ts` and
  `assets/src/operator-workflow/OperatorConsole.tsx` default adapter selection.
- `assets/src/operator-workflow/useOperatorWorkflow.ts` selected-row loading
  behavior and any follow-on cache/query layer.
- `lib/office_graph/api_support.ex`, `lib/office_graph/foundation.ex`,
  `lib/office_graph/authorization.ex`, and `lib/office_graph/identity.ex`
  context-loading and authorization validation paths.
- `lib/office_graph/projections.ex` and `lib/office_graph/runs.ex` batched
  projection assembly.
- `lib/office_graph_web/graphql/operator_workflow/*` and
  `lib/office_graph_web/json_api/operator_workflow/*` transport parity tests.
- Operator workflow API, frontend projection, and query-count regression tests.
