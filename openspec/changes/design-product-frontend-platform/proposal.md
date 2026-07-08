## Why

The first React operator console proved the Phoenix-served product UI path, but
its current shape should not become the pattern for every future screen.
Before adding more product routes, Office Graph needs a small, route-first
frontend platform plan that fits React Router Framework Mode, the GraphQL-first
product path, and the project's ban on Tailwind and LiveView product UI.

## What Changes

- Establish React Router Framework Mode as the frontend routing direction for
  future product screens.
- Define a boring route-first file layout based on React Router conventions
  rather than adding premature `platform`, `domains`, or deep shared-design
  folder layers.
- Select Relay as the product GraphQL server-state model for implementation.
  The implementation MUST NOT add TanStack Query as a competing cache for the
  same product GraphQL data.
- Add the Absinthe Relay server package and establish Relay-compatible product
  GraphQL primitives: opaque Node IDs for stable product objects and
  connection-style pagination for lists that can grow.
- Clarify that shared UI stays shallow and generic until repeated real screens
  prove deeper boundaries are needed.
- Replace ambiguous "actions" language in frontend planning with product
  commands and UI affordances.
- Narrow frontend verification to concrete gates the project can actually run:
  typecheck, component tests, route smoke tests, Relay compiler checks,
  import-boundary checks, app-shell asset checks, and focused backend
  query-count tests where projection reads can grow.
- Land the initial backend Relay contract and React Router Framework Mode
  foundation while keeping the existing `/operator` Phoenix shell behavior
  intact until the operator route migration and app-shell handoff steps.

## Capabilities

### New Capabilities

- None.

### Modified Capabilities

- `frontend-architecture`: Adds route-first React Router Framework Mode
  requirements, shallow shared UI rules, and Relay as the product GraphQL
  client/cache model for implementation.
- `ui-projection-contracts`: Clarifies that backend projections provide
  commands and affordances, not generic frontend-inferred actions, and that UI
  data contracts must work with Relay.
- `ash-api-surface`: Clarifies that the product GraphQL surface must support
  frontend-owned Relay route operations with Node IDs and connections, without
  pushing the product UI back to JSON adapters or hand-written transport sprawl.

## Impact

- Affects future files under `assets/`, especially the eventual React Router
  Framework Mode entry files and route modules.
- Affects product GraphQL operation ownership, Relay setup, and frontend tests.
- Affects durable OpenSpec requirements for frontend architecture, UI
  projection contracts, and the GraphQL product API path.
- Adds a backend Absinthe Relay dependency, schema contract work, frontend
  Relay runtime wiring, and React Router Framework Mode foundation files, but
  does not migrate the existing operator console or change Phoenix routing in
  this change.
