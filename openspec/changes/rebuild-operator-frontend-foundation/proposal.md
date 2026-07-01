## Why

The first operator console proved the vertical slice, but its frontend code now
mixes demo-era JSON compatibility, GraphQL transport details, view-model
normalization, domain derivation, and manual request orchestration in too few
modules. The next frontend work should start from a clean architecture
foundation before the operator surface becomes large enough that the demo shape
hardens into product debt.

## What Changes

- **BREAKING**: Replace the existing operator-workflow frontend module rather
  than preserving its temporary JSON adapter, demo component structure, or
  manual `useEffect` loading model.
- Rebuild the `/operator` React surface around a GraphQL-only product
  projection client and TanStack Query hooks.
- Split operator frontend code into focused boundaries for route composition,
  query hooks, GraphQL transport/query documents, response normalization,
  workflow view models, layout, panels, and pure presentation helpers.
- Keep Phoenix serving the `/operator` app shell, and keep backend operator
  workflow projection contracts authoritative.
- Keep frontend tests focused on architectural boundaries, query loading
  behavior, empty/error states, and the core operator workflow screen.
- Retire frontend tests whose only purpose is JSON/GraphQL adapter parity.

## Capabilities

### New Capabilities

- None.

### Modified Capabilities

- `frontend-architecture`: require the operator frontend reset to use
  GraphQL-only product reads, TanStack Query server-state ownership, and
  focused feature boundaries before additional operator behavior is added.
- `operator-console`: update the console contract so the product UI reads the
  operator workflow through GraphQL by default without preserving the demo JSON
  adapter as a frontend compatibility requirement.
- `ui-projection-contracts`: clarify that frontend projection clients hide
  GraphQL shape from components, while temporary JSON migration support is not
  required for product UI code once a GraphQL projection exists.

## Impact

- `assets/src/App.tsx` and `assets/src/main.tsx` will wire the operator route
  through a `QueryClientProvider`.
- `assets/src/operator-workflow/**` may be deleted and replaced with a new
  focused module layout.
- `assets/src/foundation/foundationStack.*` may be removed or simplified if it
  only exists as an early proof of TanStack Query wiring.
- Existing frontend tests under `assets/src/operator-workflow` will be replaced
  or rewritten around the new architecture.
- Phoenix app-shell behavior and backend operator workflow APIs should not need
  semantic changes.
