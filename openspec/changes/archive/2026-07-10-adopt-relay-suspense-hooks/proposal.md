# Adopt Relay Suspense Hooks

## Why

The operator and packet routes currently wrap Relay `fetchQuery` subscriptions
in duplicated, boolean-heavy query-state machines. Moving route reads to
Relay's render-time hooks and React Suspense removes that parallel state layer,
keeps loading and errors at explicit UI boundaries, and makes Relay the actual
owner of product GraphQL read state.

## What Changes

- Replace route-owned imperative `fetchQuery` subscriptions for operator and
  packet reads with Relay render-time hooks such as `useLazyLoadQuery`,
  `useQueryLoader`, and `usePreloadedQuery`.
- Add product-specific Suspense fallbacks and safe error boundaries at route or
  panel scope so initial, pagination, validation, and dependent-read failures
  preserve the approved operator and packet UX without exposing transport or
  authorization details.
- Keep packet pagination page-replacing and cursor-history-based; do not adopt
  `usePaginationFragment` until the product chooses cumulative connection
  rendering.
- Remove the duplicated query-state types and transition helpers, update local
  selection at navigation events instead of mirroring derived state in an
  effect, and trim unused packet connection fields.
- Consolidate packet presentation formatting and replace source-spelling tests
  with module or rendered-behavior assertions.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `frontend-architecture`: Require Relay product reads to use render-time Relay
  hooks with explicit Suspense and safe error boundaries rather than parallel
  custom query-state machines.
- `operator-console`: Preserve operator context and panel-specific loading and
  error behavior while dependent Relay reads move behind Suspense boundaries.

## Impact

- Affects Relay data orchestration under `assets/app/routes/operator/` and
  `assets/app/routes/packets/`.
- Adds route-owned loading and error boundary components and updates Relay
  documents or generated artifacts as required by hook ownership.
- Removes duplicated frontend query-state types and helpers; no backend schema,
  API, database, or dependency changes are expected.
- Depends on the packet workspace introduced by the unarchived
  `add-packets-route` change; that baseline must be synchronized or archived
  before this change is archived.
