## Context

Office Graph has two Phoenix-served React Router product routes. Both routes
read through Relay, but their orchestration currently calls `fetchQuery`
directly, subscribes in effects, and mirrors request lifecycle into local
`QueryState` objects. The packet route copied the operator route's lifecycle
helpers, which created duplicated state transitions and boolean combinations
that Relay and Suspense can own instead.

Relay 21 in the project exposes `useLazyLoadQuery`, `useQueryLoader`,
`usePreloadedQuery`, and `usePaginationFragment`. The generated packet field
supports forward and backward connection arguments. The current packet product
UX, however, replaces one cursor page with another; Relay pagination fragments
accumulate edges and therefore do not match the approved page-replacement
semantics.

Constraints:

- Relay remains the only product GraphQL server-state cache.
- React Router Framework Mode remains the route owner and Phoenix remains the
  SPA host.
- Loading, empty, safe error, selection, pagination, readiness, run, and
  verification behavior must remain explicit.
- Product-specific fallback and error copy stays in route folders; shared UI
  remains generic and product-vocabulary-free.
- Tailwind, LiveView product UI, new frontend dependencies, backend schema
  changes, and cumulative-list UX are out of scope.

## Goals / Non-Goals

**Goals:**

- Remove route-owned `fetchQuery` subscription effects and custom query-state
  machines for operator and packet reads.
- Use Relay render-time hooks under explicit Suspense and safe error
  boundaries.
- Preserve page-replacing cursor navigation and route-local selection.
- Preserve operator context when readiness or run-state reads suspend or fail.
- Keep data mapping pure and generated Relay types explicit at route boundaries.
- Resolve the packet quality findings without introducing a replacement
  abstraction layer.

**Non-Goals:**

- Do not change GraphQL operations, authorization, persistence, or backend
  projection behavior except for Relay directives required by compilation.
- Do not convert packet pagination into infinite or cumulative scrolling.
- Do not add URL-owned selection, retry controls, mutations, realtime updates,
  or optimistic product commands.
- Do not create a generic application data framework around Relay hooks.
- Do not migrate unrelated React effects or presentation code.

## Decisions

### 1. Use render-time Relay hooks instead of a shared query-state wrapper

Initial and variable-driven route reads will use `useLazyLoadQuery` inside a
component that is already wrapped by a Suspense and error boundary. Conditional
or user-triggered reads will live in conditionally rendered children that call
`useLazyLoadQuery`, or use `useQueryLoader` plus `usePreloadedQuery` when the
request must begin in an event handler.

This is preferred over a shared `QueryState` utility because it lets Relay own
request deduplication, cancellation, store reads, and render suspension without
copying lifecycle booleans into React state. The route still owns product
variables, selection, cursor history, mapping, fallback copy, and error copy.

Direct `fetchQuery(...).subscribe(...)` remains available for non-rendering
imperative workflows only. The migrated product reads will not use it.

### 2. Add one shallow generic async boundary

A product-neutral shared boundary will combine React Suspense with a class
error boundary. It will accept fallback nodes, an error fallback node, and a
reset key. It will not inspect or render the caught error, which prevents raw
transport or authorization details from leaking through generic UI.

Routes and panels provide their own loading and error content. Route-level
boundaries cover initial and cursor-page reads. Panel-level boundaries cover
operator readiness validation and run-state reads so an isolated failure does
not discard the inbox, selected item, or other inspector panels.

The boundary resets only when its explicit key changes. This makes recovery
deterministic and avoids hidden retry behavior.

### 3. Keep packet pagination as page replacement

The packet route will keep `{first, after}` and previous-cursor history as
local navigation state. A data child calls `useLazyLoadQuery` with the current
page variables and maps only the consumed view data: rows, next-page
availability, and next cursor.

Next and Previous handlers clear local selection before changing page
variables. When the new page renders, the effective selection is the first row
unless the operator selects another row on that page. This removes the effect
that copied derived selection back into state while preserving the approved
rehome-on-pagination behavior.

`usePaginationFragment` is rejected for this change because its append/prepend
connection semantics would change what a page represents and would require a
different selection and Previous-button contract.

### 4. Split operator reads by visible UI boundary

The operator inbox query becomes the route-level `useLazyLoadQuery` read. The
loaded inbox component owns cursor history and local selection and maps Relay
data into the existing panels.

Packet-readiness validation remains event-triggered. The validation event
stores request variables or a preloaded query reference, then renders the
validated result under a readiness-panel Suspense/error boundary. Until a
validation request exists, the panel continues to use readiness derived from
the selected inbox row.

Run state is rendered by a child only when the selected item has a run id. The
child calls `useLazyLoadQuery` and renders both run and verification content
under one panel-level boundary. Selecting another item changes the boundary
key and discards the prior dependent read.

This decomposition avoids conditional hooks and prevents dependent query
failures from replacing the entire operator workspace.

### 5. Make loaded, loading, and error component inputs explicit

Presentational components will no longer receive the inferred return type of a
large workflow hook or a generic query-state object. Route composition will
pass explicit rows, selected data, pagination flags, callbacks, and dedicated
loading or error nodes.

The packet connection mapping will drop fields not consumed by production
code. Packet lifecycle-state formatting will move into the existing route
formatter module. Navigation tests will import the destination constant and
assert values and rendered behavior rather than exact source spelling.

### 6. Keep tests behavioral and boundary-focused

TDD will introduce failing tests for Suspense loading, safe route errors,
panel-level operator error isolation, page-replacement selection, lean packet
mapping, shared packet formatting, and direct navigation configuration.

Architecture checks may inspect import specifiers to prevent migrated route
code from importing `fetchQuery`; tests will not assert quote style, exact
import statements, or JSX source spelling.

## Risks / Trade-offs

- **Suspense changes render timing** -> Preserve the existing visible fallback
  copy and test initial, pagination, validation, and dependent-read timing with
  deferred Relay networks.
- **A route error could replace too much UI** -> Use route boundaries only for
  root reads and panel boundaries for readiness and run-state reads.
- **Error boundaries can become stuck** -> Key each boundary to page variables,
  selected identity, or validation request identity and test reset behavior.
- **Operator migration is larger than packet-only cleanup** -> Commit packet,
  shared boundary, and operator slices separately with focused verification at
  each step.
- **`network-only` does not maximize cache reuse** -> Retain the current fetch
  policy during the architecture migration; cache-policy changes require their
  own product behavior decision.
- **Parallel OpenSpec changes have archive ordering** -> Synchronize or archive
  `add-packets-route` before archiving this change so the packet capability
  baseline exists first.

## Migration Plan

1. Add and verify the generic async boundary.
2. Convert the packet route to `useLazyLoadQuery`, remove packet query-state
   code, and complete its formatter, mapping, and test cleanup.
3. Convert the operator inbox root read, then readiness and run-state dependent
   reads, preserving panel isolation.
4. Remove now-unused operator query-state helpers and direct product-read
   `fetchQuery` imports.
5. Run focused Relay, route, typecheck, and boundary tests after each slice;
   finish with strict OpenSpec validation and `mix verify`.

Rollback can revert the migration commits independently and restore the
existing `fetchQuery` workflows without backend or persisted-data changes.

## Open Questions

None. Cache-policy improvements, cumulative connection rendering, retry UX,
and React Router data-loader preloading remain separate future decisions.
