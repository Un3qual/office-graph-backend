## Why

Operators can inspect an individual run only after reaching it through an
existing packet or operator workflow. They need a dedicated, authorized index
that makes current work runs discoverable and lets them move safely into the
existing packet and operator workspaces without creating another command path.

## What Changes

- Add an authorized, organization- and workspace-scoped, newest-first work-run
  index projection and forward Relay connection with stable keyset cursors and
  a bounded query shape.
- Add a read-only `/runs` product route for list, URL-owned selection, run
  detail, bounded activity, recovery states, and links to packet and operator
  workspaces.
- Enable `All Runs` in product navigation while keeping deferred destinations
  disabled.
- Add explicit `packetId` URL selection to the existing packet workspace for
  packet deep links; preserve its present data and command ownership.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `work-runs`: add the authorized, scoped, stable, bounded run-index
  projection without changing detailed run or command ownership.
- `operator-console`: add the read-only `/runs` list/detail/activity route and
  enabled product navigation.
- `packet-workspace`: add explicit `packetId` URL selection without adding a
  second packet projection or a new command owner.

## Impact

The implementation will add a focused `OfficeGraph.Projections` run-index
read, an `operatorRuns` GraphQL Relay connection, and a route-owned React
package under `assets/app/routes/runs/`. It will extend app-shell routing and
navigation, and narrowly adapt the existing packet route's selection behavior.
The route reuses `operatorRunState` and its activity connection for detail;
it adds no mutation, persistence, migration, external write, identity, or
governance administration behavior.
