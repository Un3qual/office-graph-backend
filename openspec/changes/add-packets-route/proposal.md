## Why

The frontend platform is now ready for a second product route, but the product
still exposes packet context only inside the operator console. A dedicated
packet workspace is the smallest route that proves the route-first React and
Relay architecture while advancing the packet-backed verified-completion
workflow.

## What Changes

- Add a Phoenix-served React Router `/packets` route with route-owned Relay
  data, loading, empty, error, selected-packet, and pagination states.
- Make the shared navigation rail route-aware so operators can move between
  the current `/operator` surface and the packet workspace without embedding
  packet vocabulary in shared UI.
- Present the existing generated `listWorkPackets` Relay connection as a dense
  packet list and selected-packet detail surface without adding a competing
  cache, JSON adapter, mutation flow, or new backend read contract.
- Add focused route, data, navigation, import-boundary, typecheck, Relay
  compiler, and app-shell verification coverage.

## Capabilities

### New Capabilities

- `packet-workspace`: Defines the first dedicated packet product route, its
  Relay-backed read states, selection behavior, and packet detail contract.

### Modified Capabilities

- `frontend-architecture`: Requires product navigation to use real route links
  for available destinations while shared navigation remains generic and
  route-owned modules retain product behavior.

## Impact

- Affects React Router configuration and route modules under `assets/app/`.
- Affects the generic navigation primitive under `assets/src/ui/` and the
  operator layout that supplies its route descriptors.
- Reuses the existing generated GraphQL `listWorkPackets` connection and Relay
  compiler path; no backend schema, database, or dependency changes are
  expected.
- Extends frontend verification and Phoenix app-shell route coverage for
  `/packets`.
