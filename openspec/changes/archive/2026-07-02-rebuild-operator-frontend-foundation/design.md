## Context

The first operator console was intentionally small and proved that Phoenix can
serve a React product surface backed by the operator workflow projections. It
then grew into a mixed demo module: `projectionClient.ts` contains transport
setup, GraphQL query strings, JSON bridge code, normalization, and workflow
derivation, while `useOperatorWorkflow.ts` manually coordinates several
server-state reads even though the frontend stack already includes TanStack
Query.

The product direction is now clearer than the demo direction. React remains the
product UI, Phoenix remains the app-shell host, and GraphQL is the normal
product frontend API. The user explicitly does not require compatibility with
the demo operator console or its JSON adapter.

## Goals / Non-Goals

**Goals:**

- Replace the operator frontend implementation with a clean module layout that
  can grow into a large product UI.
- Make GraphQL the only product frontend transport for the operator console.
- Put server state behind TanStack Query hooks with stable query keys, loading,
  error, empty, and stale/refetch behavior.
- Keep React components unaware of GraphQL response shape, query documents,
  fetch details, JSON envelopes, and backend field casing.
- Keep the visible `/operator` route usable as a workbench for inbox,
  selected item, packet readiness, run state, and verification state.
- Keep shared UI primitives and design tokens separate from operator workflow
  mapping.

**Non-Goals:**

- Preserving the old `assets/src/operator-workflow` file layout.
- Preserving the frontend JSON adapter, JSON parity frontend tests, or the
  injected demo API prop as a product requirement.
- Changing backend operator workflow projection semantics.
- Adding a new GraphQL library, code generator, Relay, Apollo, or route
  framework in this change.
- Redesigning the broader Office Graph navigation, graph canvas, rich text,
  workflow builder, mobile UI, or agent runtime UI.

## Decisions

### Rebuild The Feature Module Rather Than Refactor In Place

The existing demo code is small enough to replace directly. Keeping it would
force the new architecture to preserve names, tests, and adapter seams that
exist only because the first console started as a quick vertical slice.

Target feature layout:

```text
assets/src/operator/
  OperatorRoute.tsx
  OperatorWorkspace.tsx
  workflowTypes.ts
  workflowQueries.ts
  workflowGraphql.ts
  workflowMappers.ts
  workflowDerived.ts
  useOperatorWorkflow.ts
  components/
    OperatorLayout.tsx
    InboxList.tsx
    ItemSummary.tsx
    ReadinessPanel.tsx
    RunPanel.tsx
    VerificationPanel.tsx
```

Shared primitives remain under `assets/src/ui`, design tokens remain under
`assets/src/design`, and generic component examples must not absorb workflow
logic.

Alternative considered: split the current `operator-workflow` directory
incrementally. That reduces diff size but leaves the new foundation shaped by
temporary compatibility code.

### Use GraphQL-Only Frontend Reads

The product frontend will use a small GraphQL HTTP transport and feature-owned
query documents. JSON API routes may continue to exist for backend parity or
customer/integration surfaces, but the frontend will not keep a JSON adapter or
frontend parity tests for it.

Alternative considered: keep the JSON bridge as a test path. That made sense
while migrating transport, but it now increases surface area without serving
the product frontend.

### Use TanStack Query For Server State

Operator workflow reads will be represented as query hooks:

- `useOperatorInboxQuery`
- `useOperatorItemQuery`
- `usePacketReadinessQuery`
- `useOperatorRunStateQuery`

The route-level hook can compose these reads and derive the verification panel
from run state when the loaded run projection already includes the needed
verification data. Selected row id remains local React state until URL-backed
selection is designed.

Alternative considered: keep manual `useEffect` loading. That is acceptable for
a demo but becomes brittle as cancellation, deduplication, refetching,
invalidation, and background refresh behavior grows.

### Keep View Models Stable And Product-Oriented

GraphQL mappers should normalize camelCase response fields into product view
models consumed by components. Components should render named view-model fields
and helper output, not inspect GraphQL response shape or infer domain meaning
from raw transport records.

Alternative considered: pass GraphQL response objects directly to components.
That lowers mapper code in the short term but couples the UI tree to transport
shape and makes future projection or realtime changes harder.

### Test Architecture Boundaries, Not Demo Compatibility

Frontend tests should prove:

- `/operator` route composition provides a QueryClient and renders the
  workbench from GraphQL data.
- Query hooks call the expected GraphQL operation and normalize the response.
- Components handle loading, empty, error, selected, readiness, run, and
  verification states.
- No production operator component imports JSON API client code.

Old tests that only prove JSON and GraphQL adapters return the same frontend
shape should be removed with the old adapter.

Alternative considered: keep all old tests and rewrite around the new module.
That would continue testing compatibility decisions the product no longer
needs.

## Risks / Trade-offs

- [Risk] Replacing the module in one pass can drop a visible state from the
  demo UI. -> Mitigation: keep tests around the core workflow states before
  deleting the old module and verify the final `/operator` rendering path.
- [Risk] GraphQL response mapping remains hand-written. -> Mitigation: keep
  query documents and mappers isolated so code generation can replace them
  later without touching components.
- [Risk] Query keys or derived states become ad hoc again. -> Mitigation:
  centralize query keys and derived workflow helpers in feature-owned modules.
- [Risk] Removing JSON frontend compatibility might hide backend transport
  drift. -> Mitigation: keep backend GraphQL/JSON parity tests in backend API
  suites; do not make the product frontend own that compatibility.
- [Risk] TanStack Query tests can leak cache state across cases. -> Mitigation:
  create a fresh `QueryClient` per component test with retries disabled.

## Migration Plan

1. Add failing frontend tests for the new GraphQL-only operator route, query
   hook behavior, and the absence of JSON imports from production operator UI.
2. Create the new `assets/src/operator` module with query keys, GraphQL
   transport, query hooks, mappers, derived helpers, route composition, and
   focused components.
3. Repoint `App.tsx` and `main.tsx` to the new route and `QueryClientProvider`.
4. Delete obsolete `assets/src/operator-workflow` code and demo-only tests.
5. Remove or simplify `assets/src/foundation/foundationStack.*` if it is only a
   TanStack proof after the operator route uses the real pattern.
6. Run frontend verification, Phoenix app-shell tests, OpenSpec validation,
   formatting, and compile checks.

Rollback is a git revert of this change. Backend projection contracts and
Phoenix app-shell routing remain intact.

## Open Questions

- Whether selected operator item state should later move into the URL. This
  change keeps it local because there is only one implemented operator route.
- Whether a future schema/codegen tool should generate GraphQL types. This
  change keeps hand-written response types because the current frontend surface
  is still small and the priority is architecture boundaries.
