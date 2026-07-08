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
- Require the platform design to choose one GraphQL server-state model before
  implementation: Relay, or TanStack Query plus generated GraphQL operation
  types. The implementation MUST NOT run both as competing caches for the same
  product GraphQL data.
- Clarify that shared UI stays shallow and generic until repeated real screens
  prove deeper boundaries are needed.
- Replace ambiguous "actions" language in frontend planning with product
  commands and UI affordances.
- Narrow frontend verification to concrete gates the project can actually run:
  typecheck, component tests, route smoke tests, GraphQL compiler or codegen
  checks, import-boundary checks, app-shell asset checks, and focused backend
  query-count tests where projection reads can grow.
- Keep this change design-first. It does not add new product routes, migrate
  the existing operator console, add Relay, add React Router Framework Mode, or
  change Phoenix routing by itself.

## Capabilities

### New Capabilities

- None.

### Modified Capabilities

- `frontend-architecture`: Adds route-first React Router Framework Mode
  requirements, shallow shared UI rules, and a required GraphQL client/cache
  decision before implementation.
- `ui-projection-contracts`: Clarifies that backend projections provide
  commands and affordances, not generic frontend-inferred actions, and that UI
  data contracts must work with the selected GraphQL client model.
- `ash-api-surface`: Clarifies that the product GraphQL surface must support
  frontend-owned route operations without pushing the product UI back to JSON
  adapters or hand-written transport sprawl.

## Impact

- Affects future files under `assets/`, especially the eventual React Router
  Framework Mode entry files and route modules.
- Affects product GraphQL operation ownership, Relay or GraphQL-codegen setup,
  and frontend tests.
- Affects durable OpenSpec requirements for frontend architecture, UI
  projection contracts, and the GraphQL product API path.
- Does not change backend behavior, Phoenix routes, frontend runtime code, or
  package dependencies in this design change.
