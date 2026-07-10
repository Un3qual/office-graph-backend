# Relay Suspense Hooks Design

date: 2026-07-10
status: approved direction, written review pending
openspec change: `adopt-relay-suspense-hooks`

## Outcome

Migrate the operator and packet product reads from direct Relay `fetchQuery`
subscriptions plus custom query-state objects to Relay render-time hooks under
explicit React Suspense and safe error boundaries. Product behavior remains
the same; Relay becomes the lifecycle owner as well as the normalized cache.

The canonical detailed design and requirements are:

- `openspec/changes/adopt-relay-suspense-hooks/design.md`
- `openspec/changes/adopt-relay-suspense-hooks/specs/frontend-architecture/spec.md`
- `openspec/changes/adopt-relay-suspense-hooks/specs/operator-console/spec.md`

## Architecture

- Add one shallow, product-neutral async boundary that accepts loading content,
  safe error content, and a reset key.
- Use `useLazyLoadQuery` for root and variable-driven reads.
- Use conditional query children or `useQueryLoader` plus `usePreloadedQuery`
  when a read begins from an operator event.
- Scope inbox and packet failures to the route; scope readiness and run-state
  failures to their inspector panels so valid operator context stays visible.
- Keep packet pagination page-replacing with local cursor history. Do not use
  `usePaginationFragment`, whose accumulated-edge semantics would change the
  current product contract.

## State And Data Flow

Relay owns request lifecycle, deduplication, cancellation, and GraphQL records.
React local state owns only cursor variables, cursor history, selected identity,
and whether an operator requested readiness validation. Page navigation clears
selection before changing variables so the new page selects its first row
without a derived-state synchronization effect.

Route mapping remains pure and generated Relay types stay explicit. Packet
mapping returns only rows, next-page availability, and next cursor.

## Error Handling

The generic boundary never renders or interprets caught errors. Routes and
panels provide safe product-specific fallback content. Reset keys are the page
cursor, selected identity, or validation request identity so old failures and
results cannot leak into new context.

## Testing

Implementation is TDD-first. Focused tests cover boundary suspension, safe
errors and reset, packet page replacement and selection, operator panel error
isolation, removal of custom query lifecycle, formatter reuse, and behavioral
navigation configuration. Final gates are Relay validation, typecheck, frontend
verification, strict validation of both active OpenSpec changes, `mix verify`,
and `git diff --check`.

## Scope Control

No backend schema, persistence, dependency, cache-policy, retry-UX, cumulative
pagination, mutation, realtime, or URL-state changes are included. The packet
route remains the baseline from `add-packets-route`; that change must be synced
or archived before `adopt-relay-suspense-hooks` is archived.
